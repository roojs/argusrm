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

## Assumption

- 🔷 Managed **Linux agents** include **LXC guests on SysV init** (no systemd inside the guest). See `docs/setup.md` (SysV agent service in container). Design phase 1 for that path first; systemd/logind hosts are optional extras.

## Plan

Startup unchanged (`Execute.send_startup()`). New agent monitor(s) debounce like `PackageMonitor` (~60s) and call existing sync (`LoggedInUsers.send()` on Linux, `sync_table` on Windows; `OSQuery.sync("Users")` when built).

🚫 **Phase 1 must not watch `/var/log/auth.log` or an unfiltered auth journal.** Volume (SSH failures, `sudo`, cron PAM) would constantly arm resync. Auth belongs in phase 3 with server-side filters (`docs/plans/1.1-implementation.md`), not as the driver for table refresh.

ℹ️ Linux **read** path is `agent/OSQuery/LoggedInUsers.vala`: osquery `logged_in_users` (**utmp** — normal in LXC/SysV), then cgroup `session-*.scope` fallback only on **systemd** hosts without utmp ([done/2026-11-14-FIXED-logged-in-users-empty-linux.md](done/2026-11-14-FIXED-logged-in-users-empty-linux.md)). Phase 1 **triggers** must match the read path per host class, not logind-only.

### Phase 1 — session and local accounts

| Piece | Linux | Windows |
|-------|-------|---------|
| Class | New `UserSessionMonitor` (or split Linux/Win32 like `PackageMonitor`) | same |
| Sessions → `logged_in_users` | **LXC / SysV (required):** `GLib.FileMonitor` on live **utmp** — try `/var/run/utmp`, `/run/utmp`, `/var/adm/utmp` (first present). SSH/console login/logout updates utmp → debounced `LoggedInUsers.send()`. | `Win32.EvtSubscribe` Security: `4624`, `4634`, `4647` |
| | **systemd host (optional):** if system D-Bus has `org.freedesktop.login1`, also (or instead) `SessionNew` / `SessionRemoved`. | |
| | 🚫 No logind inside typical LXC SysV guest — do not rely on it there. Cgroup fallback in `send()` does not apply without systemd slices. | |
| logind vs SSH (systemd only) | ℹ️ On systemd desktops/servers, interactive SSH with `pam_systemd` can use logind signals; **not** the LXC SysV baseline. | |
| Local accounts → `users` | `GLib.FileMonitor` on `/etc/passwd`, `/etc/group` | Security: `4720`, `4726`, `4738` (if `users` in cut) |
| Action | Debounce → `LoggedInUsers.send()` / `sync_table("logged_in_users", …)` | same |
| | Debounce → `OSQuery.sync("Users")` (and `Groups` / `UserGroups` if in cut) | same |
| RPC | None if only existing `OSQuery.sync` / `LoggedInUsers` RPCs | same |
| Periodic poll | 🚫 No timer for `logged_in_users` — unlike `PackageUpdates`, a 12h (or daily) resync would not catch short logon/logoff windows and would not fix “who was on the box for five minutes” after the fact. Refresh is **startup + session events only** (debounced). | |

**Decisions (pick one per row):**

| # | Question | A (recommended) | B |
|---|----------|-----------------|---|
| 1 | Phase 1 tables | `logged_in_users` only | + `users` (± `groups`, `user_groups`) |
| 2 | Linux session trigger | **utmp** `FileMonitor` + optional logind if present | utmp only (never logind) |
| 4 | Windows Security IDs | logon/logoff first | include account IDs in same debouncer |

### Phase 2 — slow-changing host state

- Daily timer (or separate debounced network trigger later): `os_version`, `interface_addresses`.
- Out of phase 1 unless explicitly folded in.

### Phase 3 — security / log events

- Filtered journal or Windows Security IDs; may ship events to server, not only `OSQuery.sync`.
- Not tied to refreshing `logged_in_users` / `users`.

---

## Next

- ⏳ 🔷 User: decisions 1, 2, 4 in phase 1 table.
- ⏳ 💩 After decisions: verbatim code in this file (`UserSessionMonitor`, wire from `Application` / `meson.build`), server cache notification for `LoggedInUsers` if not done ([2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md)).
- ⏳ 💩 New RPCs or event posts → `docs/rpc-commands.md`.
