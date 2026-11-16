# Machine Users tab shows only logged-in sessions instead of all system users

**Status:** ✅ closed 2026-11-14. Users/Groups split tab, sync, list RPCs, filters, and live UI verified on this host.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-machines-detail-pane.md](2026-11-13-FIXED-machines-detail-pane.md), [2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md), [2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md)

---

## Problem

- 🔷 Per-machine **Users** tab listed only `logged_in_users` sessions, with no groups pane or non-system filter.
- 🔷 Expected: all osquery `users`, groups split, login tick, Added/Modified, default `uid >= 1000` (hide `nobody`), `SystemInfo.list` live logins only.

---

## Summary of changes

### Shared / agent / server

- ✔️ `shared/OSQuery/Users.vala`, `Groups.vala`, `UserGroups.vala` — sync + `Users.list` / `Groups.list`; joined `gid_groupname`, `logged_in_users_time`, `groups_groupnames`; `member_count` and `users_uid_ge_1000_member_count` on groups.
- ✔️ `shared/OSQuery/namespace.vala`, `agent/OSQuery/Execute.vala` — startup sync for `users`, `groups`, `user_groups`.
- ✔️ `shared/OSQuery/SystemInfo.vala` — `logged_in_users.deleted_dt = 0` on Machines grid subquery.
- ✔️ `server/OSQuery.rpc_register()` — **must** call `Users`/`Groups`/`UserGroups.rpc_register()` (not only `Request.register` in `Application.vala`).
- ✔️ `docs/rpc-commands.md` — `Users.list`, `Groups.list`, sync wire aliases.

### Controller

- ✔️ Replaced `LoggedInUsers` machine tab with `Machine.Users` (split pane) + `Machine.Groups`; `users.csv` / `groups.csv`.
- ✔️ `Store.Users`, `Store.Groups`, `Filters.Users`, `Filters.Groups`.
- ✔️ `Tab.Base` — `tick`, `GLib.Type.BOOLEAN`, date tooltips.
- ✔️ `Machine.Detail` — removed `users_loaded` (reload Users tab whenever active).
- ✔️ Show system users: users grid `uid >= 1000 && uid != 65534`; groups list hides `gid < 1000` unless `users_uid_ge_1000_member_count > 0`.
- ✔️ Groups pane width (`width_request` 320, paned position 340).

### Removed

- 🚫 `controller/tab/Asset/Machine/LoggedInUsers.vala`, `controller/store/LoggedInUsers.vala`, `logged_in_users_machine.csv` (shared `LoggedInUsers` kept for sync and joins).

### Tests

- ✔️ `server/tests/packages.vala` — insert + list for users/groups/user_groups.

---

## Rollout fixes (same change)

| Issue | Cause | Fix |
| --- | --- | --- |
| Could not list users/groups | `add_class` / `Bin.register` missing on server | `server/OSQuery.vala` `rpc_register` |
| Empty grids after connect | List before agent sync; `users_loaded` cached empty | Drop `users_loaded` |
| Groups too narrow / filter | UI + no shared show-system rule | Paned width; `Filters.Groups` + list field |

---

## Verification

- ✔️ `meson compile -C build`, `meson test -C build` (6/6).
- ✔️ Live: agent sync 69 users / 102 groups / 95 memberships; controller lists populate after tab revisit; show-system filters both panes.

---

## Next

- ℹ️ Periodic `users` / `groups` refresh after startup remains [2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md).
- ℹ️ Optional: `event.osquery` notification to invalidate other machine tabs ([2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)); Users tab intentionally uncached.