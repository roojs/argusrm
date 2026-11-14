# Machine Users tab shows only logged-in sessions instead of all system users

**Status:** ⏳ diagnosed; fix direction and open design choices documented — await approval

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, `docs/rpc-commands.md`, [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md), [2026-11-14-logged-in-users-empty-linux.md](2026-11-14-logged-in-users-empty-linux.md), [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md)

---

## Problem

- 🔷 The per-machine `Users` tab in the Machines detail pane (`controller/tab/Asset/Machine/Detail.vala`) currently lists only `logged_in_users` sessions instead of all user accounts on the system.
- 🔷 Expected:
  - 🔷 Show all users on the machine (from osquery `users`), not only users with an active login session.
  - 🔷 Show flag(s) indicating whether each user is currently logged in.
  - 🔷 Default the grid filter to non-system users (e.g. hiding system accounts with `uid < 1000` by default).
  - 🔷 Include a filter bar on the `Users` tab with a search entry and a control to show or hide all/system users.
- 🔷 Actual:
  - ✔️ `agent/OSQuery/Execute.vala` syncs only `logged_in_users` and never queries or syncs osquery's `users` table.
  - ✔️ `Machine.Detail` wires the `"users"` tab to `Tab.Asset.Machine.LoggedInUsers`, which has no filter bar and displays only `logged_in_users` rows.

---

## Evidence

- ✔️ **Current `Users` tab implementation (`controller/tab/Asset/Machine/`):**
  - ✔️ `Detail.vala` instantiates `this.users = new LoggedInUsers(window)` for toggle/page `"users"` (`"Users"`).
  - ✔️ `controller/tab/Asset/Machine/LoggedInUsers.vala` loads `Store.LoggedInUsers` (`LoggedInUsers.list(agent_id)`) using `controller/resources/columns/logged_in_users_machine.csv` (`User`, `TTY`, `Host`, `Logged in`, `Type`, `PID`) with no filter bar.
- ✔️ **Missing `users` table sync and RPC (`shared/OSQuery/`, `agent/OSQuery/`, `server/`):**
  - ✔️ `agent/OSQuery/Execute.vala` (`send_startup()`) syncs `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, `os_version`, and packages — no `users` sync exists.
  - ✔️ No `shared/OSQuery/Users.vala`, `users` SQLite table, or `Users.list` RPC exists (`docs/plans/5.8-assets-page.md` noted `Osquery users is the account list. It is not synced.`).
- ✔️ **Live `osqueryi` `users` schema and counts on this host (`fastboy`, Ubuntu 25.04, `osqueryi` 5.24.0):**
  - ✔️ `PRAGMA table_info(users)` columns:
    - `uid` (`BIGINT`, PK)
    - `gid` (`BIGINT`)
    - `uid_signed` (`BIGINT`)
    - `gid_signed` (`BIGINT`)
    - `username` (`TEXT`, PK)
    - `description` (`TEXT`)
    - `directory` (`TEXT`)
    - `shell` (`TEXT`)
    - `uuid` (`TEXT`, PK)
  - ✔️ Row counts in `SELECT * FROM users` on this host:
    - `69` total accounts.
    - `64` accounts with `uid < 1000` (includes `root` at `uid = 0`, `daemon`, system service users).
    - `5` accounts with `uid >= 1000`:
      - `alan` (`uid = 1000`, `shell = /bin/bash`, `directory = /home/alan`)
      - `guest` (`uid = 1001`, `shell = /bin/bash`, `directory = /home/guest`)
      - `alan2` (`uid = 1002`, `shell = /bin/bash`, `directory = /home/alan2`)
      - `libvirt-qemu` (`uid = 64055`, `shell = /usr/sbin/nologin`, `directory = /var/lib/libvirt`)
      - `nobody` (`uid = 65534`, `shell = /usr/sbin/nologin`, `directory = /nonexistent`)
- ✔️ **Existing `tick` / `status` cell rendering (`controller/tab/Base.vala`):**
  - ✔️ `column_factory` creates a `Gtk.Image` for `format == "tick"`, but `factory.bind` currently has an empty `case "tick": break;` (lines 584–585) so `tick` cells never render an icon.
  - ✔️ `status` format (`1` green `.status-ok`, `2` amber `.status-warn`, `0` red `.status-bad`, `-1` hidden) is already implemented with optional `tooltip-<name>` support.
- ✔️ **Existing filter-bar pattern (`controller/tab/Asset/SystemInfo.vala`, `DebPackages.vala`, `controller/tab/Tasks.vala`):**
  - ✔️ Pages wrap `store` in `Gtk.FilterListModel(this.store, this.filter)` with a `Argus.Controller.Filters.*` subclass of `Gtk.Filter`, paired with a `.machines-filter` `Gtk.Box` holding `Gtk.SearchEntry` and toggle/dropdown controls.
- ℹ️ **Related `deleted_dt` note (`shared/OSQuery/SystemInfo.vala`):**
  - ✔️ `SystemInfo.list(agent_id, true)` subquery for `logged_in_users` (lines 193–198) currently omits `AND logged_in_users.deleted_dt = 0`, so logged-out historical rows in `logged_in_users` can still appear in the Machines grid `Logged in users` cell.

---

## Root cause

- ✔️ The per-machine `Users` tab was wired directly to `logged_in_users` (active sessions only) while osquery's `users` account table has never been modelled, synced from agents, or exposed over RPC.
- ✔️ Neither a `Filters.Users` filter nor a `.machines-filter` bar exists on the per-machine `Users` tab to search accounts or toggle system users vs non-system users.

---

## Proposed design

### 1. Keep `logged_in_users` and add `users` sync (`Shared.OSQuery.Users` + agent)

- 🔷 Keep syncing `logged_in_users` (used by `SystemInfo.list` and for determining active login state).
- 🔷 Add `Argus.Shared.OSQuery.Users : Row` (`shared/OSQuery/Users.vala`) matching osquery's `users` schema:
  - 💩 Stored columns: `uid` (`int64`), `gid` (`int64`), `uid_signed` (`int64`), `gid_signed` (`int64`), `username` (`string`), `description` (`string`), `directory` (`string`), `shell` (`string`), `uuid` (`string`).
  - 💩 Key columns for `sync_rows<Users>`: `{ "uid", "username", "uuid" }` (matches osquery's `users` primary key across Linux and Windows SIDs).
  - 💩 Non-stored joined fields populated by `Users.list(int agent_id)`:
    - 🔷 `logged_in` flag (e.g. `int` or `bool`) derived from active `logged_in_users` rows (`deleted_dt = 0` matching `agent_id` and `logged_in_users.user = users.username`).
    - 💩 Optional joined session summary columns (`tty`, `host`, `login_time` / `MAX(time)`) from active `logged_in_users` so session context is not lost when replacing the `LoggedInUsers` tab.
- 🔷 Sync `this.sync_table("users", "Users")` in `agent/OSQuery/Execute.vala` (`send_startup()`).
- ℹ️ Periodic / event-driven refresh of both `users` and `logged_in_users` after startup remains tracked in [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md).
- 💩 Register `Users` in `shared/OSQuery/namespace.vala`, `server/OSQuery.vala`, `server/Application.vala`, `controller/Application.vala`, `shared/meson.build`, `docs/meson.build`, and `docs/rpc-commands.md`.

### 2. Per-machine `Users` tab, store, columns, and filter bar (`controller/`)

- 🔷 Replace (or rename/update) the `"users"` page in `controller/tab/Asset/Machine/Detail.vala` to display `Store.Users` wrapped in `Gtk.FilterListModel` with `Filters.Users`.
- 🔷 Add a `.machines-filter` bar above the grid on the `Users` tab:
  - 🔷 `Gtk.SearchEntry` to search across visible text columns (e.g. `username`, `description`, `directory`, `shell`, `tty`, `host`).
  - 🔷 Toggle control (e.g. `Gtk.CheckButton` `"Show system users"` or `"Show all users"`, unchecked by default) to switch between non-system users and all users.
- 💩 **Column layout (`controller/resources/columns/users_machine.csv`):**
  - 💩 `User` (`username`, `ON`, `text`, row header)
  - 💩 `Logged in` (`logged-in`, `ON`, `tick` or `status` — see open decisions below)
  - 💩 `UID` (`uid`, `ON`, `number`)
  - 💩 `Description` (`description`, `ON`, `text`)
  - 💩 `Home` (`directory`, `ON`, `text`)
  - 💩 `Shell` (`shell`, `ON`, `text`)
  - 💩 `Last login` / `Logged in since` (`login-time`, `ON` or `off`, `elapsed`)
  - 💩 `TTY` (`tty`, `off`, `text`), `Host` (`host`, `off`, `text`), `GID` (`gid`, `off`, `number`), `UUID` (`uuid`, `off`, `text`)
- 💩 Also implement `case "tick":` in `controller/tab/Base.vala` (`column_factory` `bind`) if `tick` is used for `Logged in`, or use `status` (`1` green / `-1` hidden or `0` grey/red).

### 3. Open decisions to confirm before writing code proposals

- ⏳ 💩 **Non-system user filter rule (`Filters.Users`):**
  - 🔷 Baseline requested: filter out system users such as `uid < 1000` by default.
  - 💩 Edge cases observed on Linux (`osqueryi` on `fastboy`):
    - `nobody` has `uid = 65534` and `libvirt-qemu` has `uid = 64055` (`uid >= 1000`, `shell = /usr/sbin/nologin`); should the default non-system filter be purely `uid >= 1000` (or `uid >= 1000 && uid < 65534`), or also filter `nologin`/`false` shells on Linux, and should any currently `logged_in` user (e.g. `root` `uid = 0`) stay visible even when system users are hidden?
  - 💩 Windows `osquery` `users` behaviour: on Windows, `uid` is the SID RID (e.g. `500` Administrator, `501` Guest, `1000+` local users, `18`/`19`/`20` built-in service accounts) and `shell` is `""`. Confirm whether Windows should use the same `uid >= 1000` rule (or also keep `uid == 500` / `logged_in` users, or check `uuid` SID prefix `S-1-5-21-`).
- ⏳ 💩 **Logged-in column presentation:**
  - 💩 Implement `tick` in `Tab.Base` (showing a checkmark icon when logged in, blank otherwise) vs `status` dot (`status-ok` green when logged in, hidden or `status-bad` when not) vs text.
- ⏳ 💩 **`LoggedInUsers` controller files (`Store.LoggedInUsers`, `Tab.Asset.Machine.LoggedInUsers`, `logged_in_users_machine.csv`):**
  - 💩 Confirm whether to replace `Tab.Asset.Machine.LoggedInUsers` with `Users` (and drop the unused `LoggedInUsers` tab/store/CSV or keep `LoggedInUsers.list` RPC if anything else needs raw sessions).
- ⏳ 💩 **`SystemInfo.list` `deleted_dt = 0` fix:**
  - 💩 Confirm adding `AND logged_in_users.deleted_dt = 0` to `shared/OSQuery/SystemInfo.vala` line 197 so logged-out sessions stop appearing in the Machines grid `Logged in users` column.

---

## Attempts / changelog

- ✔️ Inspected `controller/tab/Asset/Machine/Detail.vala`, `controller/tab/Asset/Machine/LoggedInUsers.vala`, `controller/store/LoggedInUsers.vala`, `shared/OSQuery/LoggedInUsers.vala`, `agent/OSQuery/Execute.vala`, `agent/OSQuery/LoggedInUsers.vala`, `controller/tab/Base.vala`, and `controller/tab/Asset/SystemInfo.vala`.
- ✔️ Verified `osqueryi` `users` schema and account distribution on `fastboy` (`69` rows: `64` with `uid < 1000`, `5` with `uid >= 1000`).

## Next

- ⏳ 🔷 Confirm the open design choices above (non-system user rule on Linux/Windows, `tick` vs `status` for logged-in flag, replacing `Machine.LoggedInUsers`, and `deleted_dt = 0` in `SystemInfo.list`).
- ⏳ 💩 Once confirmed, add verbatim `Remove` / `Replace with` / `Add` code proposals to this bug log and implement after approval.
