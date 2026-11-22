# Windows agent — fleet upgrade via `argus-updater.exe`

**Status:** ⏳ opened

**Pointer:** `docs/bug-fix-process.md`, [2026-11-17-windows-exe-distribution.md](2026-11-17-windows-exe-distribution.md), [`packaging/windows/argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi), [`server/SQT/Task.vala`](../../server/SQT/Task.vala), [`agent/Download.vala`](../../agent/Download.vala)

---

## Problem

- 🔷 **Expected:** From the controller, queue an upgrade of the **Argus RM Agent** on Windows machines. The agent downloads the released `ArgusAgent-{version}-Setup.exe`, applies it **in place**, and comes back registered — no manual reinstall visits.
- 🚫 **Actual:** [`argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi) already upgrades when setup runs. Tasks store `dist_version_id` but dispatch only the shell line (`"setup-filename.exe" /S`) with **no download**. There is **no** `argus-updater.exe` handoff when the installer stops the service.
- 🚫 **Rejected:** Spawning `Setup.exe` detached from the service and calling the task “done”.

---

## Phase W0 — Download installer before run

The server already validates `dist_version_id` on `Task.submit`. The scheduler sends `Argus.Command` with `command` only. W0 adds one wire field with the HTTPS path, and the agent fetches before spawn (same socket as osquery).

### Design

- 🔷 New property on **`Argus.Command`**: `dist_url_path` `s`. Empty when `task.dist_version_id` is 0. Otherwise `"/" + distributable_version.path` (e.g. `/distributables/{sha256}.exe`).
- 🔷 Agent: if `dist_url_path` is non-empty, `Download.fetch`, then replace `command` with a line that points at the temp file. Distributable tasks today use `"filename.exe" /S`; after fetch use `"C:\Users\…\Temp\{sha256}.exe" /S` (reuse [`Download.path`](../../agent/Download.vala)).
- ℹ️ W1 reuses the same fetch; [`agent/Win32/Command.vala`](../../agent/Win32/Command.vala) then launches `argus-updater.exe` with that path instead of spawning setup directly when the handoff applies.

### `docs/rpc-commands.md` — `Argus.Command`

#### Replace

```
- 💩 Properties on both: `identifier` `i`, `command` `s`, `environment` `as`, `cwd` `s`.
```

#### With

```
- 💩 Properties on both: `identifier` `i`, `command` `s`, `environment` `as`, `cwd` `s`, `dist_url_path` `s`.
- 💩 `dist_url_path` is empty when the task has no installer. Otherwise an HTTPS GET path on the download socket, such as `/distributables/{sha256}.exe`. The agent fetches it before running `command`.
```

### `server/Command.vala`

#### Add — after `cwd`

```vala
		/**
		 * HTTPS path on the download socket, or empty.
		 *
		 * Set from ''task.dist_version_id'' when a distributable
		 * is queued. The agent fetches this before {@link command}.
		 */
		public string dist_url_path { get; set; default = ""; }
```

### `agent/linux/Command.vala`, `agent/Win32/Command.vala`, `agent/android/Command.vala`

#### Add — same property and doc as server (agent namespace)

```vala
		public string dist_url_path { get; set; default = ""; }
```

### `agent/InstallDownload.vala` (new file)

#### Add

```vala
namespace Argus.Agent
{
	/**
	 * Fetch a task installer and point ''command'' at the temp file.
	 */
	public class InstallDownload : GLib.Object
	{
		/**
		 * @param order command about to spawn
		 * @param error message when fetch fails
		 * @return false when ''dist_url_path'' was set and fetch failed
		 */
		public static bool prepare(Command order, out string error)
		{
			error = "";
			var path = order.dist_url_path.strip();
			if (path == "") {
				return true;
			}
			if (!path.has_prefix("/")) {
				path = "/" + path;
			}
			var download = new Download();
			var code = download.fetch(path);
			if (code != 0) {
				error = "could not download the installer";
				return false;
			}
#if WINDOWS
			if (download.path.has_suffix(".msi")) {
				order.command = "msiexec.exe /i \"" + download.path + "\" /qn";
				return true;
			}
#endif
			order.command = "\"" + download.path + "\" /S";
			return true;
		}
	}
}
```

### `agent/meson.build`

#### Add — to agent sources (all platforms)

```
	'InstallDownload.vala',
```

### `server/SQT/Task.vala` — method `run`

#### Add — after `var line = this.command_text(...)` and before the `foreach (var target in targets)` loop

Load the URL path once per task:

```vala
			var dist_url_path = "";
			if (tasks.get(0).dist_version_id > 0) {
				var versions = new Gee.ArrayList<Argus.Shared.SQT.DistributableVersion>();
				var version_binds = new Gee.HashMap<string, int>();
				version_binds.set("id", (int) tasks.get(0).dist_version_id);
				Argus.Shared.SQT.DistributableVersion.query(this.app.db).selectWhere(
					"WHERE id = $id AND deleted_dt = 0", version_binds, null, versions);
				if (versions.size == 0) {
					foreach (var target in targets) {
						this.fail_target(target, 1, "unknown distributable version");
					}
					return;
				}
				var rel = versions.get(0).path.strip();
				if (rel != "") {
					dist_url_path = rel.has_prefix("/") ? rel : "/" + rel;
				}
			}
```

#### Replace — inside the loop, `var order = new Argus.Server.Command() { … }`

```vala
				var order = new Argus.Server.Command() {
					command = line,
					dist_url_path = dist_url_path
				};
```

### `agent/linux/Command.vala` — method `run`

#### Add — immediately after `this.connection = connection;` and before building `argv`

```vala
			var prepare_error = "";
			if (!InstallDownload.prepare(this, out prepare_error)) {
				this.report("Command.stderr", prepare_error + "\n");
				this.stdout_done = true;
				this.stderr_done = true;
				this.child_done = true;
				this.finish(127);
				return;
			}
```

### `agent/Win32/Command.vala` — method `spawn`

#### Add — at the start of `spawn`, before `GLib.Shell.parse_argv`

```vala
			var prepare_error = "";
			if (!InstallDownload.prepare(this, out prepare_error)) {
				// same Command.stderr + Command.ended 127 pattern as parse_argv failure
				return;
			}
```

(After W1 lands, insert the updater handoff **here**, when the distributable is Argus RM Agent, instead of `parse_argv` on the setup line.)

### `agent/android/Command.vala` — method `run`

#### Add — if `dist_url_path != ""`, stderr + ended 127 with “not supported” (no distributable installs on Android yet).

### `docs/meson.build`

#### Add — valadoc input for `agent/InstallDownload.vala` when other agent paths are listed.

---

## Phase W1 — `argus-updater.exe` (approved direction)

Ship a small **windows-subsystem** binary beside `argus-agent.exe`, refreshed every NSIS run (like `argus-tray.exe`).

### Flow

1. W0 leaves `command` as the local setup path (or W1 skips rewriting to `/S` and passes path only to the updater).
2. Service starts `argus-updater.exe` **detached** with setup path + task metadata. Task step completes as “updater launched”, not “install finished”.
3. Updater waits until `argus-agent` service is gone (`sc query`, timeout).
4. Updater runs `"<setup>" /S`, waits for exit, records exit code for the new agent / task log.
5. NSIS drops fresh `argus-updater.exe` each release.

### Installer metadata (`packaging/windows/argusrm-agent.nsi`)

#### Add — after `PRODUCT_VERSION` defines, before `Name`

```nsis
!define VI_PRODUCT_VERSION "${PRODUCT_VERSION}.0"
VIProductVersion "${VI_PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "${PRODUCT_VERSION}"
```

(Optionally set `VIAddVersionKey` on the staged setup via `makensis` / `argus-agent.exe` version resource — confirm one canonical version string.)

### Packaging (W1)

- 🔷 New Meson target → `argus-updater.exe`; [`scripts/ci/windows-package-nsis.sh`](../../scripts/ci/windows-package-nsis.sh) stages it under `dist-windows/Argus`.

---

## Success criteria

- 🔷 Distributable task on Windows: agent logs fetch, runs installer from `%TEMP%`, exit code on task (via updater once W1 is done).
- 🔷 Argus RM Agent fleet upgrade: registration under `%LOCALAPPDATA%\argus\` survives; `programs.version` updates after sync.

---

## Next

- ⏳ Implement W0 (small, no new RPC methods).
- ⏳ Implement W1 updater + `Win32/Command` handoff after `InstallDownload.prepare`.
- ⏳ Lab test: upload setup, queue from Distributables, verify version bump without re-registration.

---

## LLM log

- ✔️ 2026-11-22 — Initial investigation; trim to updater-only direction.
- ✔️ 2026-11-22 — Proposed W0 code: `dist_url_path` on `Argus.Command`, `InstallDownload`, server `Task.run`, agent `Command` hooks.