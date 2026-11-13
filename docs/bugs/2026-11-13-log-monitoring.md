# Agent log monitoring and periodic table refresh

**Status:** ⏳ investigation opened — inventory of current monitors and open design questions

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/5.9.1-DONE-assets-software-data.md`, `docs/plans/1.1-implementation.md`

---

## Problem

- 🔷 `logged_in_users` and other startup osquery tables are currently posted only once when the agent starts (`Execute.send_startup()`).
- 🔷 Later logins, logouts, account changes, and system/security log events do not reach the server after startup.
- 🔷 Need a clear design for startup tables plus log monitoring (rather than startup-only or daily-only polling) and where log monitoring currently stands.

---

## Evidence

✔️ Inventory of what currently runs on the agent (`agent/`):

### 1. Startup snapshot only (`agent/OSQuery/Execute.vala`)

- ✔️ `Execute.send_startup()` runs once when the agent starts with an existing certificate or after registration:
  - `system_info` (`SystemInfo`)
  - `cpu_info` (`CpuInfo`)
  - `logged_in_users` (`LoggedInUsers`)
  - `interface_addresses` (`InterfaceAddresses`)
  - `os_version` (`OsVersion`)
  - One package table (`send_packages()`): `DebPackages`, `RpmPackages`, or `Programs`
- ✔️ None of `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, or `os_version` are re-queried on a timer or on OS events after startup.

### 2. Existing monitors (`agent/linux/PackageMonitor.vala`, `agent/Win32/PackageMonitor.vala`)

- ✔️ **Linux (`agent/linux/PackageMonitor.vala`):**
  - Watches `/var/lib/dpkg` (`APT`) or `/var/lib/rpm` (`DNF`) using `GLib.FileMonitor` (inotify), waits 60s + fcntl lock check, and calls `osquery.send_packages()`.
  - Calls `send_pending()` (`UpdatesAvailable.check` -> `OSQuery.sync("PackageUpdates")`) at start and every 12 hours (`GLib.Timeout.add_seconds(12 * 60 * 60, ...)`).
- ✔️ **Windows (`agent/Win32/PackageMonitor.vala`):**
  - Subscribes to the Windows `Application` event log via `Win32.EvtSubscribe` (`MsiInstaller` events `1033`, `11707`, `1034`, `11724`), waits 60s, and calls `osquery.send_packages()`.
  - No other event log channels (`Security`, `System`) or periodic timers are subscribed.

### 3. Planned but not built

- ℹ️ `docs/plans/5.8-assets-page.md` explicitly left `logged_in_users` refresh after startup out of Phase 1 ("That refresh is not designed") and noted `users` (local OS accounts) and `uptime` are not synced.
- ℹ️ `docs/plans/1.1-implementation.md` ("Later — security") and `docs/plans/5.5-controller-user-interface.md` ("Monitoring") describe agent event monitoring for new executables and listening sockets with a server-replicated filter database.
- 🚫 No generic log-monitoring class, journald/auth-log reader, utmp/login watcher, or Windows `Security`/`System` event monitor exists in the tree yet.

---

## Root cause

- ✔️ Agent monitoring currently handles only package-database directory changes (Linux) and `MsiInstaller` events (Windows), plus a 12-hour `PackageUpdates` timer on Linux.
- ✔️ No mechanism watches login/auth logs, Windows `Security`/`System` event logs, or refreshes startup tables after boot.

---

## Proposed direction (rough sketch)

### 1. Startup + log monitoring for dynamic tables (`logged_in_users`, `users`)

- 🔷 Run `send_startup()` at boot/connect, then rely on log/event monitoring to detect changes without heavy polling.
- 💩 **Linux login / user changes:**
  - Watch login/session sources (e.g. `/run/utmp` or `systemd-logind` D-Bus / `journald` / `/var/log/auth.log`) and `/etc/passwd` + `/etc/group` (for local `users`) using the same debounced resync pattern as `PackageMonitor` (`OSQuery.sync("LoggedInUsers")` / `OSQuery.sync("Users")`).
- 💩 **Windows login / user changes:**
  - Subscribe via `Win32.EvtSubscribe` to `Security` log events (e.g. logon `4624`, logoff `4634`/`4647`, account create/delete/change `4720`/`4726`/`4738`) and debounce `OSQuery.sync("LoggedInUsers")` / `OSQuery.sync("Users")`.

### 2. Optional periodic (daily) sync for slow-changing host state

- 💩 Re-sync `os_version` (picks up `reboot_required` on Windows or OS point-release upgrades) and `interface_addresses` (picks up DHCP/VPN IP changes) on a daily timer (or on network/log triggers).

### 3. General log / security event monitoring (later)

- 💩 Decide whether log monitoring only triggers `OSQuery.sync` of existing tables or also ships filtered log/security events (new executables, unexpected sockets, failed logins) to the server as sketched in `docs/plans/1.1-implementation.md`.

---

## Next

- ⏳ 🔷 Confirm which tables and events belong in the first cut of log monitoring (`logged_in_users`, local `users`, `os_version` / `reboot_required`, `interface_addresses`, or auth/security log alerts).
- ⏳ 🔷 Confirm whether Linux log monitoring should use `GLib.FileMonitor` (e.g. `/run/utmp`, `/etc/passwd`, `/var/log/auth.log`) / `systemd-logind` D-Bus or `sd-journal`, and whether Windows uses `Win32.EvtSubscribe` on `Security`.
- ⏳ 💩 Once confirmed, add verbatim code proposals and update `docs/rpc-commands.md` if any new tables or event RPCs are added.
