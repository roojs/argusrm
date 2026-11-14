# Agent skips startup osquery and package sync when server is not yet reachable

**Status:** ✔️ fix implemented in `agent/Application.vala` (`ninja` build and 6/6 `meson test` pass); awaiting install + live service verification

**Pointer:** `docs/bug-fix-process.md`, `agent/Application.vala`, `agent/OSQuery/Execute.vala`, `agent/linux/PackageMonitor.vala`

---

## Problem

- 🔷 On this machine (`fastboy`), `argusrm-agent` is connected to `argusrm-server` and receives `event.agent`, yet does not send up the package list (`deb_packages` / `PackageUpdates`) or startup osquery tables.
- 🔷 Expected: once `argusrm-agent` connects to `argusrm-server` (whether on initial startup or on a 30-second retry / reconnect), it runs `OSQuery.Initialize`, sends startup osquery tables and packages (`send_startup()`), and starts `PackageMonitor`.
- 🔷 Actual: when `argusrm-agent` starts before `argusrm-server` is listening (or when the server is unreachable at agent startup), `attach_connection()` connects 30 seconds later on retry, emits `state_changed()`, and never runs `OSQuery.Initialize`, `send_startup()`, or `PackageMonitor`.

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
- ✔️ Temporary probe `/tmp/argus-startup-race-probe.vala` reproduced the 450 ms server startup race:
  - `broken` mode (current `if (this.connection != null)` check only at `command_line()`): `[result] fixed=false connected=true deb_rows=0 monitor_started=false`.
  - `fixed` mode (`state_changed` handler running `osquery-init` + `send_startup()` + `PackageMonitor`): `[result] fixed=true connected=true deb_rows=5570 monitor_started=true`.

---

## Root cause

- ✔️ In `agent/Application.vala` (`command_line()`, `#if LINUX`), `OSQuery.Initialize`, `this.osquery.send_startup()`, and `PackageMonitor` are only started inside `if (this.connection != null)` immediately after the first `this.attach_connection()` call.
- ✔️ When that first `this.attach_connection()` fails (`this.connection == null`), `attach_connection()` schedules the 30-second retry timer, which later opens the connection and emits `this.state_changed()`, but nothing listens to `this.state_changed()` on Linux to initialize osquery, send startup tables/packages, or start `PackageMonitor`.

---

## Proposed fix

### `agent/Application.vala` — trigger Linux inventory and `PackageMonitor` on `state_changed`

- 🔷 Connect `this.state_changed` in the `#if LINUX` registered branch before `this.attach_connection()`, matching the Windows `#else` pattern (`GLib.Thread` for `OSQuery.Initialize`, then `GLib.Idle.add` for `this.osquery.send_startup()` and `PackageMonitor`), guarded by a local `osquery_starting` flag and `this.monitor == null` so reconnects refresh inventory without creating duplicate `PackageMonitor` instances.

#### Remove

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

#### Replace with

```vala
#if LINUX
			var cert = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				var osquery_starting = false;
				this.state_changed.connect(() => {
					if (this.connection == null || Application.connection_down || osquery_starting) {
						return;
					}
					osquery_starting = true;
					new GLib.Thread<int>("osquery-init", () => {
						var code = new OSQuery.Initialize(this).run();
						GLib.Idle.add(() => {
							osquery_starting = false;
							if (code == 0 && this.connection != null && !Application.connection_down) {
								this.osquery.send_startup();
								if (this.monitor == null &&
									this.os_version.package_manager() !=
										Argus.Shared.OSQuery.PackageManager.UNKNOWN) {
									this.monitor = new PackageMonitor(this);
									this.monitor.start();
								} else if (this.monitor != null) {
									this.monitor.send_pending();
								}
							}
							return false;
						});
						return 0;
					});
				});
				this.attach_connection();
			}
#else
```

---

## Attempts / changelog

- ✔️ Inspected `/var/log/argusrm/agent.log`, `/var/log/argusrm/server.log`, and `~/.cache/argusrm/controller.log`.
- ✔️ Proved `DebPackages` serialization and `OSQuery.sync` work in `/tmp/argus-pkg-probe.vala`.
- ✔️ Reproduced failure and verified fix in `/tmp/argus-startup-race-probe.vala`.

- ✔️ Applied replacement in `agent/Application.vala`; `ninja -C build agent/argusrm-agent agent/argusrm-agent-gtk` succeeded and `meson test -C build` passed (6/6).

## Next

- ⏳ 🔷 Install the rebuilt agent (`sudo ninja -C build install`) and restart `argusrm-agent` to verify live `deb_packages` sync on this host.
