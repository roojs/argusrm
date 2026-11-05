# Linux service never sends osquery rows after registration

**Status:** ✔️ FIXED — Linux service reads `AGENT_DATA_DIR`; live `osquery 0`

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala must follow `docs/coding-standards.md`.

ℹ️ Related: `../2026-11-04-elevation-dialog-and-pin-used.md` does **not** fix this.
ℹ️ `docs/plans/2.1.2-root-registration-ui.md`, `docs/plans/3.0-server.md` Phase 3.

---

## Problem

- 🔷 After a Linux machine registers, osquery rows do not reach the server.
- 🔷 Boot-up: when the agent service starts with a certificate, it always sends the osquery snapshot.
  - First registration and a later `argus-agent` run use the same path.
  - The interactive process does not post the rows. The `--service` process does.
- ℹ️ The server can still have downloaded the osquery *installers* at startup.
  - That is `Initialize.fetch_osquery` into the package store.
  - It is not `OSQuery.sync` from the agent.

---

## Evidence

- ✔️ Linux registration writes `client.pem`, `server`, `download`, and `download-path` under `Argus.AGENT_DATA_DIR`.
  - `agent/linux/Application.vala` `registration` sets `RegisterWindow.data_dir` / `Register.data_dir`.
  - Success only calls `service.restart()`.
  - That process never calls `OSQuery.Initialize`.
- ✔️ The restarted `--service` process uses `Application.command_line`.
  - It looks for `client.pem` under `GLib.Environment.get_user_data_dir()` / `argus`.
  - As root that is `/root/.local/share/argus`, not `AGENT_DATA_DIR`.
  - No file there, so `OSQuery.Initialize` is not started.
- ✔️ The same user-data path is used by:
  - `Application.open_link`
  - `OSQuery.Initialize.run` (`download-path`)
  - `Download.fetch` (`download` and the client certificate)
- ℹ️ `OSQuery.sync` is a normal `TlsClient.call`.
  - It does not need `live_handles`.
  - Controller `live_handles` in the other bug does not send these rows.

---

## Root cause

- ✔️ Registration and the long-running service disagree on the data directory.
  - Registration writes the system agent directory.
  - The service reads the root user’s `argus` directory.
  - The snapshot is never queried or posted.

---

## Proposed fix

- 🔷 On Linux, the service reads the same `Argus.AGENT_DATA_DIR` that registration wrote.
- 🔷 A registered `--service` start always runs `OSQuery.Initialize` after `open_link`.
  - That is the boot-up send. No extra registration-window call.
- 🚫 Do not start `OSQuery.Initialize` from the registration window.
  - The service already starts it when it finds `client.pem`.
- 🚫 Do not change Windows or Android paths in this log.
- ℹ️ An already-registered desktop run calls `setup()` and skips the PIN.
  - `setup()` starts the service only when it is down.
  - The running dialog with `Close` / `Restart` is `../2026-11-04-elevation-dialog-and-pin-used.md`.

### `agent/Application.vala` — `open_link`: Linux uses `AGENT_DATA_DIR`

**Why:** The TLS client must load `server` and `client.pem` from the directory registration wrote.

**Where:** `open_link`, the `dir` assignment.

**Depends on:** none.

#### Remove

```vala
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
```

#### Replace with

```vala
#if LINUX
			var dir = Argus.AGENT_DATA_DIR;
#else
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
#endif
```

### `agent/Application.vala` — `command_line`: Linux service finds the system certificate

**Why:** `--service` only starts osquery when this file exists.

**Where:** the registered-process `client.pem` test at the end of `command_line`, not the Android window path.

**Depends on:** `open_link` above.

#### Remove

```vala
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
```

#### Replace with

```vala
#if LINUX
			var cert = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
#else
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
#endif
```

### `agent/OSQuery/Initialize.vala` — `run`: Linux `download-path`

**Why:** The installer URL path is next to the certificate.

**Where:** `run`, the `get_contents` for `download-path`.

**Depends on:** none.

#### Remove

```vala
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "download-path"),
						out url_path);
```

#### Replace with

```vala
#if LINUX
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						Argus.AGENT_DATA_DIR, "download-path"),
						out url_path);
#else
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "download-path"),
						out url_path);
#endif
```

### `agent/Download.vala` — `fetch`: Linux `download` file

**Why:** The download socket is stored in the same directory.

**Where:** `fetch`, the `dir` assignment.

**Depends on:** none.

#### Remove

```vala
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
```

#### Replace with

```vala
#if LINUX
			var dir = Argus.AGENT_DATA_DIR;
#else
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
#endif
```

---

## Attempts / changelog

- 🔷 Boot-up contract: service start with a cert always posts the osquery tables.
- ✔️ Fences applied. `meson compile -C build` succeeded.

---

## Next

- 🔷 `✔️` Fences applied in `agent/Application.vala`, `agent/OSQuery/Initialize.vala`, `agent/Download.vala`.
- ✔️ Live service posted osquery after the path fix. Empty tables are `2026-11-04-FIXED-osquery-sync-kills-agent.md`.
