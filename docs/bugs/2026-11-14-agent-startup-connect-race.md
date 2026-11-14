# Agent skips startup osquery and package sync when server is not yet reachable

**Status:** ✔️ approved fix implemented in `agent/Application.vala` (`ninja` build and 6/6 `meson test` pass); awaiting install + live service verification

**Pointer:** `docs/bug-fix-process.md`, `agent/Application.vala`, `agent/OSQuery/Execute.vala`, `agent/linux/PackageMonitor.vala`

---

## Problem

- 🔷 On this machine (`fastboy`), `argusrm-agent` connects to `argusrm-server` and receives `event.agent`, yet does not send up the package list (`deb_packages` / `PackageUpdates`) or startup osquery tables.
- 🔷 Expected: when `argusrm-agent` starts before `argusrm-server` is listening, it waits on a timeout (logging debug output while waiting) until the connection is ready, then runs `OSQuery.Initialize`, `send_startup()`, and `PackageMonitor`.
- 🔷 Actual: when `argusrm-agent` starts before `argusrm-server` is listening, the first `attach_connection()` fails (`this.connection == null`), `command_line()` skips `OSQuery.Initialize`, `send_startup()`, and `PackageMonitor`, and the 30-second retry later connects without ever running startup inventory.

---

## Evidence

- ✔️ `/var/log/argusrm/agent.log` and `/var/log/argusrm/server.log` across two consecutive service restarts (`09:23:18` and `09:29:13` on 2026-11-14):
  - `09:29:13.055650`: `Application.vala:205: Could not connect to 192.168.122.1: Connection refused` (agent tries to connect before server binds port 817).
  - `09:29:13.493384`: `SslListen.vala:212: SSL listening on 0.0.0.0:817` (server opens socket 438 ms later).
  - `09:29:43.821752`: `Application.vala:268: watching the server connection` (30-second retry in `attach_connection()` succeeds).
  - `09:29:43.872107`: `Application.vala:521: event.agent` (server notifies connected agent).
  - No `SELECT * FROM system_info`, `os_version`, `deb_packages`, or `PackageUpdates` calls appear in `agent.log`.
- ✔️ `/var/log/argusrm/server.log` and `~/.cache/argusrm/controller.log` confirm `DebPackages.list` returns 0 rows (`type id '0' is invalid` on empty `ArrayList` reply).
- ✔️ `osqueryi --json "SELECT COUNT(*) AS cnt FROM deb_packages"` on this host returns `5570` rows, and `osqueryi --json "SELECT * FROM os_version"` returns `"platform":"ubuntu"`, `"platform_like":"debian"`.
- ✔️ Temporary probe `/tmp/argus-pkg-probe.vala` verified that querying all 5,570 `deb_packages` rows (`343 ms`), sending them over `OLLMrpc.Transport.TlsClient` with `timeout = 5` and `watch()` (`405 ms` parse), and running `DebPackages.sync` + `db.backupDB()` (`156 ms`) succeeds end-to-end (`561 ms` total).

---

## Root cause

- ✔️ In `agent/Application.vala` (`command_line()`, `#if LINUX`), `OSQuery.Initialize`, `this.osquery.send_startup()`, and `PackageMonitor` only run inside `if (this.connection != null)` immediately after the first `this.attach_connection()` call.
- ✔️ When that first `this.attach_connection()` fails (`this.connection == null`), `attach_connection()` schedules the 30-second retry timer (`connection_check_id`) and returns, so startup inventory and `PackageMonitor` are never run once the retry connects.

---

## Ruled out

- 🚫 Adding a `GLib.Thread` on Linux (`osquery-init` / `state_changed` thread refactor) — rejected by user as an unnecessary threading change.

---

## Proposed fix

### `agent/Application.vala` — wait on a timeout with debug logging until connection is ready

- 🔷 In `command_line()` (`#if LINUX`), after `this.attach_connection()`:
  - If `this.connection != null && !Application.connection_down`, run `OSQuery.Initialize`, `this.osquery.send_startup()`, and `PackageMonitor` immediately as before.
  - Otherwise, log `GLib.debug("waiting for connection");` and start a `GLib.Timeout.add_seconds(5, ...)` timer that logs `GLib.debug("waiting for connection");` while `this.connection == null || Application.connection_down`, and once ready runs `OSQuery.Initialize`, `this.osquery.send_startup()`, and `PackageMonitor`, then returns `false`.
- 💩 Interval choice: `5` seconds checks shortly after the 30-second `attach_connection()` retry succeeds without log spam (`5`s / `10`s / `30`s are easy to adjust if preferred).

#### Remove (`agent/Application.vala`)

```vala
#if LINUX
			var cert = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.attach_connection();
				if (this.connection != null) {
					new OSQuery.Initialize(this).start();
					this.osquery.send_startup();
					this.monitor = new PackageMonitor(this);
					this.monitor.start();
				}
			}
#else
```

#### Replace with (`agent/Application.vala`)

```vala
#if LINUX
			var cert = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.attach_connection();
				if (this.connection != null && !Application.connection_down) {
					new OSQuery.Initialize(this).start();
					this.osquery.send_startup();
					this.monitor = new PackageMonitor(this);
					this.monitor.start();
				}
				if (this.connection == null || Application.connection_down) {
					GLib.debug("waiting for connection");
					GLib.Timeout.add_seconds(5, () => {
						if (this.connection == null || Application.connection_down) {
							GLib.debug("waiting for connection");
							return true;
						}
						new OSQuery.Initialize(this).start();
						this.osquery.send_startup();
						this.monitor = new PackageMonitor(this);
						this.monitor.start();
						return false;
					});
				}
			}
#else
```

---

## Attempts / changelog

- ✔️ Inspected `/var/log/argusrm/agent.log`, `/var/log/argusrm/server.log`, and `~/.cache/argusrm/controller.log`.
- ✔️ Proved `DebPackages` serialization and `OSQuery.sync` work in `/tmp/argus-pkg-probe.vala`.
- 🚫 Threading + `state_changed` approach rejected by user; reverted `agent/Application.vala` to pre-edit state and replaced proposal with `GLib.Timeout.add_seconds` + `GLib.debug("waiting for connection")`.
- ✔️ Applied approved `GLib.Timeout.add_seconds(5, ...)` edit in `agent/Application.vala`; `ninja -C build agent/argusrm-agent agent/argusrm-agent-gtk` succeeded and `meson test -C build` passed (6/6).

## Next

- ⏳ 🔷 Install the rebuilt agent (`sudo ninja -C build install`) and restart `argusrm-agent` to verify live sync on this host.
