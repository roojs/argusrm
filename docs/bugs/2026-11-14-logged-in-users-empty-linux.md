# Logged-in users empty on systemd 256+ Linux hosts

**Status:** ✔️ implemented (`agent/OSQuery/LoggedInUsers.vala`, `Execute.vala`, `meson.build`; `ninja` build and 6/6 `meson test` pass); awaiting install + live service verification

**Pointer:** `docs/bug-fix-process.md`, `agent/OSQuery/Execute.vala`, `agent/OSQuery/Package.vala`, `agent/OSQuery/DebPackages.vala`, `shared/OSQuery/LoggedInUsers.vala`, [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md), [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md)

---

## Problem

- 🔷 On this Linux host (`fastboy`), **Users** (`logged_in_users` in both the Machines grid column and the per-machine `Users` detail tab) is missing / empty.
- 🔷 Expected: active logged-in sessions on Linux are reported by `agent` and shown in `Logged in users` and the `Users` detail tab.
- 🔷 Actual: `osqueryi --json "SELECT * FROM logged_in_users"` returns `[]` (0 rows) on this host because `/run/utmp` does not exist.

---

## Evidence

- ✔️ `/var/log/argusrm/agent.log` (`09:45:59.474082`): `Execute.vala:183: SELECT * FROM logged_in_users 0 rows`, followed by `logged_in_users sent`.
- ✔️ `/home/alan/.cache/argusrm/controller.log` (`09:46:10.745704`) & `/var/log/argusrm/server.log` (`09:46:10.746696`): `LoggedInUsers.list` returns an empty list (`type id '0' is invalid`).
- ✔️ On this host (Ubuntu 25.04, `osqueryi` 5.24.0), `/run/utmp` and `/var/run/utmp` do not exist (removed in glibc/systemd 256+ for Y2038), so `osqueryi --json "SELECT * FROM logged_in_users"` returns `[]`.
- ✔️ Tested pure `osqueryi` fallback queries on this host:
  - **Shell/sshd process query** (`SELECT DISTINCT u.username, p.pid, p.name, p.cmdline FROM processes p JOIN users u ON p.uid = u.uid WHERE p.name IN ('bash', 'zsh', 'sh', 'sshd') AND u.uid >= 1000`):
    - Returned 22 `bash` rows for `alan` (including terminal tabs, IDE subshells, and background scripts).
    - Missed `alan2` completely (active Wayland desktop session `session-598.scope` has `gnome-session-binary` / `gnome-shell` / `systemd --user` with no interactive `bash` process), and `u.uid >= 1000` excludes `root` (`uid = 0`) logins.
  - **`processes.cgroup_path` session-scope query** (`SELECT 'user' AS type, u.username AS user, '' AS tty, '' AS host, MIN(p.start_time) AS time, MIN(p.pid) AS pid FROM processes p JOIN users u ON p.cgroup_path LIKE '/user.slice/user-' || u.uid || '.slice/%' WHERE p.cgroup_path LIKE '/user.slice/user-%.slice/session-%.scope' GROUP BY p.cgroup_path, u.username`):
    - Returned the exact 3 active login sessions in ~527 ms using `osqueryi` alone:
      - `user=alan`, `pid=1697978` (`login -- alan`), `time=1794269964` (`session-596.scope`)
      - `user=alan`, `pid=5096` (`gdm-session-worker`), `time=1792826779` (`session-9.scope`)
      - `user=alan2`, `pid=1705223` (`gdm-session-worker`), `time=1794270223` (`session-598.scope`)
    - Also catches `root` logins (`/user.slice/user-0.slice/session-*.scope`) and excludes `systemd --user` manager scopes and background subshells (`tty` and `host` remain `""`).
- ✔️ Temporary probe `/tmp/argus-logind-probe.vala` verified `LoggedInUsers.sync` + SQLite select round-trip (`sync=true stored=3`).
  - ℹ️ Caveat discovered in probe: `OLLMchat/libocsqlite/Query.vala` maps SQLite column `type` -> GObject property `ctype` only on `SELECT` (`setObjectProperty`), not on `INSERT` / `UPDATE` (`insert`, `updateOld`, `updateImp`). As a result, `logged_in_users.type` in SQLite stays `""` for every `LoggedInUsers` row until `libocsqlite` handles `ctype` on writes (separate library issue). `user`, `tty`, `host`, `time`, and `pid` persist and load cleanly.

---

## Root cause

- ✔️ `agent/OSQuery/Execute.vala` (`sync_table()`) queries `SELECT * FROM logged_in_users` generically, which reads `/run/utmp` on Linux and returns 0 rows on systemd 256+ distributions (Ubuntu 24.04+, 25.04, Debian 13, Fedora 41+) where `utmp` has been removed.
- ✔️ Unlike packages (`agent/OSQuery/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`, `Package.vala`), `logged_in_users` has no agent-side `LoggedInUsers` class with a `send()` method to handle the Linux fallback without modifying `Execute.sync_table()`.

---

## Ruled out

- 🚫 `org.freedesktop.login1` D-Bus implementation in `Execute.vala` — rejected by user.
- 🚫 Table-specific `if (table == "logged_in_users")` fallback logic inside `Execute.sync_table()` — rejected by user; `Execute.sync_table()` stays unchanged.
- 🚫 Refactoring `Execute.sync_table()` into a separate `sync_rows()` method — unnecessary; when `rows.size > 0` (or when fallback is also empty), `LoggedInUsers.send()` can call `application.osquery.sync_table(...)` directly.

---

## Proposed fix

- 🔷 Add `agent/OSQuery/LoggedInUsers.vala` (`Argus.Agent.OSQuery.LoggedInUsers : Argus.Shared.OSQuery.LoggedInUsers`) as a Linux-only class, matching the pattern of `agent/OSQuery/DebPackages.vala`, `RpmPackages.vala`, and `Programs.vala`.
- 🔷 In `LoggedInUsers.send(Application application)`:
  - Query `SELECT * FROM logged_in_users` via `application.osquery.select(...)`.
  - If `rows.size > 0`, call `return application.osquery.sync_table(this.table_name(), this.rpc_name());` directly (normal `utmp` path).
  - Run the `osqueryi` `processes.cgroup_path` + `users` fallback query into `rows` (with comment explaining the systemd 256+ `/run/utmp` / osquery workaround).
  - If `rows.size == 0` after fallback, call `return application.osquery.sync_table(this.table_name(), this.rpc_name());` (so an empty snapshot still clears stale sessions).
  - Otherwise post the fallback `rows` via `OSQuery.sync` (`this.rpc_name()` = `"LoggedInUsers"`).
- 🔷 In `agent/OSQuery/Execute.vala`:
  - Leave `sync_table()` implementation untouched — only change its visibility from `private` to `internal` so `LoggedInUsers` can call `application.osquery.sync_table(...)`.
  - In `send_startup()`, wrap `LoggedInUsers` in `#if LINUX` (`new LoggedInUsers().send(this.application)`) with `#else` keeping `this.sync_table("logged_in_users", "LoggedInUsers")` for Windows.

### 1. `agent/OSQuery/LoggedInUsers.vala` — Linux-only `LoggedInUsers` with `send()` fallback

**Why:** Encapsulate the Linux cgroup fallback on `Argus.Agent.OSQuery.LoggedInUsers` while calling `Execute.sync_table()` directly whenever `logged_in_users` has rows (or when fallback is also empty).

**Where:** new file `agent/OSQuery/LoggedInUsers.vala`, registered in `agent/meson.build` (Linux `argusrm-agent-gtk` and `argusrm-agent` only) and `docs/meson.build`.

**Depends on:** item 2 (`internal int sync_table`).

#### Add — `agent/OSQuery/LoggedInUsers.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Agent.OSQuery
{
	/**
	 * Agent ''logged_in_users'' row.
	 *
	 * Extends {@link Argus.Shared.OSQuery.LoggedInUsers} and posts
	 * the session snapshot with a Linux cgroup fallback when
	 * ''utmp'' is absent.
	 */
	public class LoggedInUsers : Argus.Shared.OSQuery.LoggedInUsers
	{
		/**
		 * Query ''logged_in_users'' and post the snapshot.
		 *
		 * Calls {@link Execute.sync_table} directly when
		 * ''logged_in_users'' returns rows. Otherwise falls back to
		 * active systemd session scopes in ''processes'' on Linux.
		 *
		 * @param application agent whose server connection is open
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public int send(Application application)
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return 0;
			}
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(this.rpc_name());
			application.osquery.select(row_type, "SELECT * FROM " + this.table_name(), rows);
			if (rows.size > 0) {
				return application.osquery.sync_table(this.table_name(), this.rpc_name());
			}
			/* Workaround for systemd 256+ removing /run/utmp and
			 * osquery's logged_in_users table still relying on utmp
			 * (causing it to return 0 rows on modern Linux distros).
			 */
			application.osquery.select(row_type,
				"SELECT 'user' AS type, u.username AS user, '' AS tty, '' AS host, " +
				"MIN(p.start_time) AS time, MIN(p.pid) AS pid " +
				"FROM processes p " +
				"JOIN users u ON p.cgroup_path LIKE '/user.slice/user-' || u.uid || '.slice/%' " +
				"WHERE p.cgroup_path LIKE '/user.slice/user-%.slice/session-%.scope' " +
				"GROUP BY p.cgroup_path, u.username",
				rows);
			if (rows.size == 0) {
				return application.osquery.sync_table(this.table_name(), this.rpc_name());
			}
			GLib.debug("SELECT * FROM %s %d rows", this.table_name(), rows.size);
			var connection = application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Response response;
			try {
				response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", this.rpc_name(), rows)
				});
			} catch (GLib.Error e) {
				Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", this.table_name(), response.error.message);
				return response.error.code;
			}
			GLib.debug("%s sent", this.table_name());
			return 0;
		}
	}
}
```

### 2. `agent/OSQuery/Execute.vala` — `#if LINUX` `LoggedInUsers.send()` and `internal sync_table`

**Why:** Use `LoggedInUsers.send()` on Linux while keeping Windows on `sync_table("logged_in_users", "LoggedInUsers")` and leaving `sync_table()`'s implementation unmodified.

**Where:** `send_startup()` and `sync_table()` signature in `agent/OSQuery/Execute.vala`.

**Depends on:** item 1.

#### Remove (`agent/OSQuery/Execute.vala`)

```vala
			code += this.sync_table("system_info", "SystemInfo");
			code += this.sync_table("cpu_info", "CpuInfo");
			code += this.sync_table("logged_in_users", "LoggedInUsers");
			code += this.sync_table("interface_addresses", "InterfaceAddresses");
```

#### Replace with (`agent/OSQuery/Execute.vala`)

```vala
			code += this.sync_table("system_info", "SystemInfo");
			code += this.sync_table("cpu_info", "CpuInfo");
#if LINUX
			code += new LoggedInUsers().send(this.application);
#else
			code += this.sync_table("logged_in_users", "LoggedInUsers");
#endif
			code += this.sync_table("interface_addresses", "InterfaceAddresses");
```

#### Remove (`agent/OSQuery/Execute.vala`)

```vala
		private int sync_table(string table, string class_name)
```

#### Replace with (`agent/OSQuery/Execute.vala`)

```vala
		internal int sync_table(string table, string class_name)
```

### 3. `agent/meson.build` & `docs/meson.build` — add `OSQuery/LoggedInUsers.vala`

**Why:** Include `agent/OSQuery/LoggedInUsers.vala` in all agent builds and valadoc inputs.

**Where:** `agent/meson.build` (lines 38, 68, 125) and `docs/meson.build` (line 86).

**Depends on:** item 1.

#### Remove (`agent/meson.build` — three source lists)

```meson
		'OSQuery/Initialize.vala',
		'OSQuery/Execute.vala',
		'OSQuery/Package.vala',
```

#### Replace with (`agent/meson.build` — all three occurrences)

```meson
		'OSQuery/Initialize.vala',
		'OSQuery/Execute.vala',
		'OSQuery/LoggedInUsers.vala',
		'OSQuery/Package.vala',
```

#### Remove (`docs/meson.build`)

```meson
  '../agent/OSQuery/Initialize.vala',
  '../agent/OSQuery/Execute.vala',
  '../agent/OSQuery/Package.vala',
```

#### Replace with (`docs/meson.build`)

```meson
  '../agent/OSQuery/Initialize.vala',
  '../agent/OSQuery/Execute.vala',
  '../agent/OSQuery/LoggedInUsers.vala',
  '../agent/OSQuery/Package.vala',
```

---

## Attempts / changelog

- ✔️ Checked `/var/log/argusrm/agent.log`, `/var/log/argusrm/server.log`, `~/.cache/argusrm/controller.log`, `/run/utmp`, `osqueryi`, `who`, and `org.freedesktop.login1`.
- ✔️ Tested both `processes` + `users` shell/sshd query and `processes.cgroup_path` session-scope query in `osqueryi` on this host.
- ✔️ Proved `LoggedInUsers.sync` -> SQLite round-trip in `/tmp/argus-logind-probe.vala`.
- 🚫 Rejected `org.freedesktop.login1` D-Bus approach, table-specific `Execute.sync_table()` branching, and refactoring `sync_table()` into `sync_rows()`; updated proposal to call `application.osquery.sync_table(...)` directly when `rows.size > 0` (and keep `sync_table()` untouched apart from `internal`).
- ✔️ Added `agent/OSQuery/LoggedInUsers.vala`, updated `agent/OSQuery/Execute.vala`, `agent/meson.build`, and `docs/meson.build`; `ninja -C build` and `meson test -C build` (`6/6`) passed.

## Next

- ⏳ 🔷 Install the rebuilt agent (`sudo ninja -C build install`) and restart `argusrm-agent` to verify live `logged_in_users` sync on this host.
