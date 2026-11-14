# Package status update notification and frontend cache invalidation

**Status:** ⏳ investigation opened — awaiting notification shape and cache-invalidation design review

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md), [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md), [2026-11-14-log-monitoring-phases-2-3.md](2026-11-14-log-monitoring-phases-2-3.md), [2026-11-13-FIXED-package-updates.md](done/2026-11-13-FIXED-package-updates.md), [2026-11-13-FIXED-controller-package-load-performance.md](done/2026-11-13-FIXED-controller-package-load-performance.md)

---

## Problem

- 🔷 When package status or installed package data updates on the server (e.g. `PackageUpdates`, `DebPackages`, `RpmPackages`, `Programs` via `OSQuery.sync`), the server must notify the controller frontend so it clears its cached package state and refreshes visible views.
- 🔷 Logged-in users (`Users` tab / `LoggedInUsers`) should **not** be cached in `Machine.Detail`: refresh `Users` every time the user switches to that tab, while the other tabs (`General`, package tabs, `Interfaces`) keep caching until invalidated by server notifications. CPU inventory loads with **General** via `Store.MachineGeneral` ([done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md)).
- 🔷 Currently, the frontend holds cached per-machine tab flags (`users_loaded`, `general_loaded`, `debian_loaded`, etc.) and in-memory store lists with no server push notification to invalidate or reload them when an agent reports new data.

---

## Evidence

✔️ Current server and controller behavior in the tree:

### 1. Server sends no notification on `OSQuery.sync` (`server/OSQuery.vala`)

- ✔️ `server/OSQuery.vala` (`sync()`) writes the incoming snapshot (`model.sync(this.app.db, connection.user.id, rows)`), calls `this.app.db.backupDB()`, triggers `this.app.os_update.check.begin()` for `"OsVersion"`, and replies `"ok"`.
- 🚫 `server/OSQuery.vala` never calls `this.app.broadcast(...)` after `PackageUpdates`, `DebPackages`, `RpmPackages`, `Programs`, `OsVersion`, or `LoggedInUsers` syncs.
- ✔️ `server/Application.vala` (`broadcast(OLLMrpc.Notification)`) already broadcasts `event.agent` (`server/Net/SslListen.vala`, `server/Net/SslConnection.vala`) and `event.pair` (`server/Agent.vala`) to connected clients; `agent/Application.vala` ignores unrecognized notification methods.
- ℹ️ `agent/linux/PackageMonitor.vala` already posts `DebPackages` / `RpmPackages` on lock-free dpkg/rpm changes and `PackageUpdates` via `send_pending()` on startup and every 12 hours (plus post-upgrade rescans planned in [2026-11-13-machines-package-update.md](2026-11-13-machines-package-update.md)); `agent/Win32/PackageMonitor.vala` posts `Programs` on `MsiInstaller` events.
- ℹ️ `LoggedInUsers` can update after startup via [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md); `SystemInfo`, `CpuInfo`, and `InterfaceAddresses` still startup-only until [2026-11-14-log-monitoring-phases-2-3.md](2026-11-14-log-monitoring-phases-2-3.md) phase 2.

### 2. Machine detail pane caches per-tab load state (`controller/tab/Asset/Machine/Detail.vala`)

- ✔️ `Detail` keeps per-tab booleans (`general_loaded`, `debian_loaded`, `rpm_loaded`, `windows_loaded`, `interfaces_loaded`) for `current_agent_id` (`Users` reloads every visit; no separate CPUs tab).
- ✔️ `show_machine(machine)` and `clear()` are the only places that reset `*_loaded = false`; switching back and forth between tabs on the same `current_agent_id` skips `load(this.current_agent_id)` once `*_loaded` is `true` — including `users`.
- ✔️ `Store.LoggedInUsers.load(agent_id)` (`controller/store/LoggedInUsers.vala`) already keeps existing rows visible (`refreshing = true` on the tab toggle spinner) when reloading the same `loaded_agent`, and drops duplicate calls if already `busy` for that agent.
- 🚫 `Detail` does not listen to `window.app.rpc.notification`, so neither its cached `*_loaded` flags nor the currently visible package tab ever invalidate or reload when package status changes on the server.

### 3. Software and Machines tabs only reload on `map` (`controller/tab/Asset/*.vala`, `controller/store/*.vala`)

- ✔️ `controller/tab/Asset/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`, and `SystemInfo.vala` only call `this.store.load(...)` inside `this.map.connect(...)`.
- ✔️ `controller/store/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`, `SystemInfo.vala`, `InterfaceAddresses.vala`, and `MachineGeneral.vala` retain cached rows in memory across unmap/remap until a later `load()` reply replaces them.
- 🚫 Unlike `controller/tab/Agent.vala` (which connects `this.window.app.rpc.notification` to reload on `event.agent` and `event.pair`), none of the Asset tabs or stores subscribe to server notifications.
- ℹ️ `SystemInfo.list(true)` (`shared/OSQuery/SystemInfo.vala`) does not select `os_version.pkgs_updated` / `os_version.pkgs_status` yet (noted in [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md)), though `SystemInfo` and `Machine.Detail` still need notification-driven cache invalidation once those or `PackageUpdates` change.

---

## Root cause

- ✔️ `server/OSQuery.vala` (`sync()`) does not broadcast a notification when package or osquery state changes, and the controller (`Machine.Detail`, `Tab.Asset.*`, and `Store.*`) has no notification listener to invalidate `*_loaded` flags / cached store items and reload visible views.

---

## Proposed direction (rough sketch)

### 1. Server broadcast notification on `OSQuery.sync` (`server/OSQuery.vala`, `docs/rpc-commands.md`)

- 💩 Broadcast a notification from `server/OSQuery.vala` (`sync()`) after `model.sync(...)` succeeds for tables that update dynamically (at minimum `PackageUpdates`, `DebPackages`, `RpmPackages`, `Programs`, `LoggedInUsers`, and — once phase 2 lands — `OsVersion` / `InterfaceAddresses`; see [2026-11-14-log-monitoring-phases-2-3.md](2026-11-14-log-monitoring-phases-2-3.md)):
  - 💩 Option A: single `event.osquery` notification with `action = name` (e.g. `"PackageUpdates"`, `"DebPackages"`, `"RpmPackages"`, `"Programs"`, `"LoggedInUsers"`) and `args = OLLMrpc.args("i", (int) connection.user.id)` (or `"is"` with `agent_id` and `name`) so the controller knows both **which table** and **which `agent_id`** changed.
  - 💩 Option B: dedicated `event.packages` (for `PackageUpdates` / `DebPackages` / `RpmPackages` / `Programs`) alongside `event.agent` / `event.task`.
- 💩 Also consider whether `OSQuery.sync` should only broadcast when rows actually changed (or always on `PackageUpdates` / package syncs) to avoid redundant controller reloads during agent startup bursts.
- 🔷 Document the new notification in `docs/rpc-commands.md` in the same change.

### 2. `Machine.Detail` (`Users` tab — no caching) (`controller/tab/Asset/Machine/Detail.vala`)

- 🔷 Drop `users_loaded` from `controller/tab/Asset/Machine/Detail.vala` so `this.users.load(...)` runs every time `"users"` becomes active (`Store.LoggedInUsers.load` already keeps existing rows visible with the tab's `refreshing` spinner when reloading the same `loaded_agent`).

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private bool general_loaded = false;
		private bool users_loaded = false;
		private bool debian_loaded = false;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private bool general_loaded = false;
		private bool debian_loaded = false;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`, `notify["active-name"]`)

```vala
					case "users":
						if (this.users_loaded) {
							break;
						}
						this.users_loaded = true;
						this.users.load(this.current_agent_id);
						break;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`, `notify["active-name"]`)

```vala
					case "users":
						this.users.load(this.current_agent_id);
						break;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`, `clear()` and `show_machine()`)

```vala
			this.general_loaded = false;
			this.users_loaded = false;
			this.debian_loaded = false;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`, both occurrences)

```vala
			this.general_loaded = false;
			this.debian_loaded = false;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`, `show_machine()`)

```vala
				case "users":
					if (this.users_loaded) {
						break;
					}
					this.users_loaded = true;
					this.users.load(agent_id);
					break;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`, `show_machine()`)

```vala
				case "users":
					this.users.load(agent_id);
					break;
```

### 3. Frontend notification invalidation and reload (`controller/tab/Asset/`, `controller/store/`)

- 🔷 On receiving the package-status / table-update notification, clear cached state on the controller so stale rows are not shown:
  - 💩 **`Machine.Detail` (`controller/tab/Asset/Machine/Detail.vala`):**
    - Connect to `window.app.rpc.notification`.
    - When `agent_id == this.current_agent_id` (or `agent_id <= 0`), reset the matching `*_loaded` flag (`general_loaded`, `debian_loaded`, `rpm_loaded`, `windows_loaded`, `interfaces_loaded`) to `false` (and clear the child store if unmapped / inactive), and immediately call `load(this.current_agent_id)` if that sub-tab is currently visible. Resetting `general_loaded` also refreshes CPU blocks on **General**.
  - 💩 **Software tabs (`Tab.Asset.DebPackages`, `RpmPackages`, `Programs`) & Machines tab (`Tab.Asset.SystemInfo`):**
    - Listen for matching notifications (`PackageUpdates` / `DebPackages` / `RpmPackages` / `Programs`, and `OsVersion` / `PackageUpdates` for `SystemInfo`).
    - If the widget is currently mapped (`this.get_mapped()`), trigger `this.store.load(...)` (debounced if needed for startup bursts); if unmapped, mark/clear the store's cached state so it does not flash stale rows before the next `map` reload completes.

---

## Next

- ⏳ 🔷 Approve section 2 (`controller/tab/Asset/Machine/Detail.vala` — drop `users_loaded` so `Users` refreshes on every visit).
- ⏳ 🔷 Confirm notification shape (`event.osquery` with `name` + `agent_id` vs `event.packages`) and whether `OSQuery.sync` should suppress notifications during unchanged snapshots / debounce startup bursts.
- ⏳ 🔷 Confirm whether unmapped tabs should clear their in-memory `Store` items immediately on notification (showing the loading spinner on next open) or keep existing rows with the tab spinner while reloading on `map`.
- ⏳ 💩 Once confirmed, add verbatim `Remove` / `Replace with` / `Add` hunks and `docs/rpc-commands.md` updates for sections 1 and 3.
