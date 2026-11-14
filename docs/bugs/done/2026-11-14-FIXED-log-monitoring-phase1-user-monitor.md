# Agent UserMonitor — logins and local accounts (phase 1)

**Status:** ✅ closed 2026-11-14. `UserMonitor` on Linux and Windows is in the tree. Phases 2–3 → [2026-11-14-log-monitoring-phases-2-3.md](../2026-11-14-log-monitoring-phases-2-3.md).

**Pointer:** `docs/bug-fix-process.md`, `agent/linux/UserMonitor.vala`, `agent/Win32/UserMonitor.vala`, `agent/Application.vala`, `agent/Win32/Service.vala`, [2026-11-14-log-monitoring-phases-2-3.md](../2026-11-14-log-monitoring-phases-2-3.md), [2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)

---

## Problem

- 🔷 `logged_in_users` and local account tables (`users`, `groups`, `user_groups`) were posted only once at agent startup (`Execute.send_startup()`).
- 🔷 Later logins, logouts, and account changes did not reach the server.

---

## Root cause

- ✔️ Only `PackageMonitor` existed; no session or passwd/group watch on Linux, no Security log subscription for logon/account events on Windows.

---

## Fix (landed)

- ✔️ **`agent/linux/UserMonitor.vala`:** utmp or `/run/systemd/sessions/` for sessions; `/etc/passwd` and `/etc/group` for accounts; 60s debounce; `LoggedInUsers.send()` and `sync_table` for `users` / `groups` / `user_groups`.
- ✔️ **`agent/Win32/UserMonitor.vala`:** Security **4624** / **4634** / **4647** → `logged_in_users`; **4720** / **4726** / **4738** → account tables.
- ✔️ Wired from `Application.vala` and `Win32/Service.vala` after `PackageMonitor.start()`.

Design constraints kept from the original plan:

- 🚫 No `/var/log/auth.log` or unfiltered auth journal (phase 3 + server filters).
- 🚫 No periodic timer for `logged_in_users` — startup + session events only.

---

## Next

- ⏳ Verify on LXC/SysV (utmp) and systemd host (`/run/systemd/sessions/`).
- ⏳ Controller cache notification for `LoggedInUsers` / `Users` ([2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)).