# Package status update notification and frontend cache invalidation

**Status:** ⏳ investigation opened — awaiting notification shape and cache-invalidation design review

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md), [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md), [2026-11-13-FIXED-package-updates.md](done/2026-11-13-FIXED-package-updates.md), [2026-11-13-FIXED-controller-package-load-performance.md](done/2026-11-13-FIXED-controller-package-load-performance.md)

---

## Problem

- 🔷 When package status or installed package data updates on the server (e.g. `PackageUpdates`, `DebPackages`, `RpmPackages`, `Programs` via `OSQuery.sync`), the server must notify the controller frontend so it clears its cached package state and refreshes visible views.
- 🔷 The same pattern applies to logged-in users (`LoggedInUsers` / `users_loaded`), although there is no agent-side update process for `logged_in_users` yet (tracked in [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md)).
- 🔷 Currently, the frontend holds cached per-machine tab flags and in-memory store lists with no server push notification to invalidate or reload them when an agent reports new package status.

---

## Evidence

✔️ Current server and controller behavior in the tree:

### 1. Server sends no notification on `OSQuery.sync` (`server/OSQuery.vala`)

- ✔️ `server/OSQuery.vala` (`sync()`) writes the incoming snapshot (`model.sync(this.app.db, connection.user.id, rows)`), calls `this.app.db.backupDB()`, triggers `this.app.os_update.check.begin()` for `"OsVersion"`, and replies `"ok"`.
- 🚫 `server/OSQuery.vala` never calls `this.app.broadcast(...)` after `PackageUpdates`, `DebPackages`, `RpmPackages`, `Programs`, `OsVersion`, or `LoggedInUsers` syncs.
- ✔️ `server/Application.vala` (`broadcast(OLLMrpc.Notification)`) already broadcasts `event.agent` (`server/Net/SslListen.vala`, `server/Net/SslConnection.vala`) and `event.pair` (`server/Agent.vala`) to connected clients; `agent/Application.vala` ignores unrecognized notification methods.
- ℹ️ `agent/linux/PackageMonitor.vala` already posts `DebPackages` / `RpmPackages` on lock-free dpkg/rpm changes and `PackageUpdates` via `send_pending()` on startup and every 12 hours (plus post-upgrade rescans planned in [2026-11-13-machines-package-update.md](2026-11-13-machines-package-update.md)); `agent/Win32/PackageMonitor.vala` posts `Programs` on `MsiInstaller` events.
- ℹ️ `LoggedInUsers` (and `SystemInfo`, `CpuInfo`, `InterfaceAddresses`) currently only sync once at agent startup (`agent/OSQuery/Execute.vala`), with log-driven updates deferred to [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md).

### 2. Machine detail pane caches per-tab load state (`controller/tab/Asset/Machine/Detail.vala`)

- ✔️ `Detail` keeps per-tab booleans (`users_loaded`, `debian_loaded`, `rpm_loaded`, `windows_loaded`, `interfaces_loaded`, `cpus_loaded`) for `current_agent_id`.
- ✔️ `show_machine(machine)` and `clear()` are the only places that reset `*_loaded = false`; switching back and forth between tabs on the same `current_agent_id` skips `load(this.current_agent_id)` once `*_loaded` is `true`.
- 🚫 `Detail` does not listen to `window.app.rpc.notification`, so neither its cached `*_loaded` flags nor the currently visible package tab ever invalidate or reload when package status changes on the server.

### 3. Software and Machines tabs only reload on `map` (`controller/tab/Asset/*.vala`, `controller/store/*.vala`)

- ✔️ `controller/tab/Asset/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`, and `SystemInfo.vala` only call `this.store.load(...)` inside `this.map.connect(...)`.
- ✔️ `controller/store/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`, `SystemInfo.vala`, `LoggedInUsers.vala`, `InterfaceAddresses.vala`, and `CpuInfo.vala` retain `items_store` in memory across unmap/remap until a later `load()` reply replaces `this.items`.
- 🚫 Unlike `controller/tab/Agent.vala` (which connects `this.window.app.rpc.notification` to reload on `event.agent` and `event.pair`), none of the Asset tabs or stores subscribe to server notifications.
- ℹ️ `SystemInfo.list(true)` (`shared/OSQuery/SystemInfo.vala`) does not select `os_version.pkgs_updated` / `os_version.pkgs_status` yet (noted in [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md)), though `SystemInfo` and `Machine.Detail` still need notification-driven cache invalidation once those or `PackageUpdates` change.

---

## Root cause

- ✔️ `server/OSQuery.vala` (`sync()`) does not broadcast a notification when package or osquery state changes, and the controller (`Machine.Detail`, `Tab.Asset.*`, and `Store.*`) has no notification listener to invalidate `*_loaded` flags / cached store items and reload visible views.

---

## Proposed direction (rough sketch)

### 1. Server broadcast notification on `OSQuery.sync` (`server/OSQuery.vala`, `docs/rpc-commands.md`)

- 💩 Broadcast a notification from `server/OSQuery.vala` (`sync()`) after `model.sync(...)` succeeds for tables that update dynamically (at minimum `PackageUpdates`, `DebPackages`, `RpmPackages`, `Programs`, and `OsVersion`, plus `LoggedInUsers` once [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md) adds live updates):
  - 💩 Option A: single `event.osquery` notification with `action = name` (e.g. `"PackageUpdates"`, `"DebPackages"`, `"RpmPackages"`, `"Programs"`, `"LoggedInUsers"`) and `args = OLLMrpc.args("i", (int) connection.user.id)` (or `"is"` with `agent_id` and `name`) so the controller knows both **which table** and **which `agent_id`** changed.
  - 💩 Option B: dedicated `event.packages` (for `PackageUpdates` / `DebPackages` / `RpmPackages` / `Programs`) alongside `event.agent` / `event.task`.
- 💩 Also consider whether `OSQuery.sync` should only broadcast when rows actually changed (or always on `PackageUpdates` / package syncs) to avoid redundant controller reloads during agent startup bursts.
- 🔷 Document the new notification in `docs/rpc-commands.md` in the same change.

### 2. Frontend cache invalidation and reload (`controller/tab/Asset/`, `controller/store/`)

- 🔷 On receiving the package-status / table-update notification, clear cached state on the controller so stale rows are not shown:
  - 💩 **`Machine.Detail` (`controller/tab/Asset/Machine/Detail.vala`):**
    - Connect to `window.app.rpc.notification`.
    - When `agent_id == this.current_agent_id` (or `agent_id <= 0`), reset the matching `*_loaded` flag (`debian_loaded`, `rpm_loaded`, `windows_loaded`, and later `users_loaded`) to `false` (and clear the child store if unmapped / inactive), and immediately call `load(this.current_agent_id)` if that sub-tab is currently visible.
  - 💩 **Software tabs (`Tab.Asset.DebPackages`, `RpmPackages`, `Programs`) & Machines tab (`Tab.Asset.SystemInfo`):**
    - Listen for matching notifications (`PackageUpdates` / `DebPackages` / `RpmPackages` / `Programs`, and `OsVersion` / `PackageUpdates` for `SystemInfo`).
    - If the widget is currently mapped (`this.get_mapped()`), trigger `this.store.load(...)` (debounced if needed for startup bursts); if unmapped, mark/clear the store's cached state so it does not flash stale rows before the next `map` reload completes.
- ℹ️ Keep `LoggedInUsers` (`users_loaded`) aligned with the same notification/invalidation hook so [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md) can plug into it without a separate mechanism once agent-side user updates exist.

---

## Next

- ⏳ 🔷 Confirm notification shape (`event.osquery` with `name` + `agent_id` vs `event.packages`) and whether `OSQuery.sync` should suppress notifications during unchanged snapshots / debounce startup bursts.
- ⏳ 🔷 Confirm whether unmapped tabs should clear their in-memory `Store` items immediately on notification (showing the loading spinner on next open) or keep existing rows with the tab spinner while reloading on `map`.
- ⏳ 💩 Once confirmed, add verbatim `Remove` / `Replace with` / `Add` hunks and `docs/rpc-commands.md` updates.
