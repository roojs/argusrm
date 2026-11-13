# Machines tab detail pane and per-machine data tabs

**Status:** ✔️ Phase 1 implemented (`Gtk.Paned` split + `Machine/Detail` + per-machine package tabs; compiled & tests pass, awaiting live UI check); Phase 2 (CPUs/Users/Interfaces) and Phase 3 (General) next

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, `docs/rpc-commands.md`

---

## Problem

- 🔷 The Machines tab (`controller/tab/Asset/SystemInfo.vala`) needs a horizontal split on the right pane (`Gtk.Paned` with `Gtk.Orientation.VERTICAL`, top grid / bottom detail) with an adjustable splitter.
- 🔷 When no machine is selected, the bottom area is hidden and the Machines grid uses the full height.
- 🔷 When a machine is selected, the bottom area opens at a 50% vertical split.
- 🔷 The lower half contains a tabbed area:
  - 🔷 **Column-based tabs** — per-machine tables such as **CPUs**, **Users**, **Interfaces**, and **Packages**.
  - 🔷 **Packages** — generate three tabs for the three package types (**Debian packages**, **RPM packages**, **Windows programs**) and hide the two that are not relevant for the selected machine.
  - 🔷 **General** — vertical dump of the horizontal Machines table (`system_info.csv`) with nothing hidden, grouped with expanders, built generically from data and multiple queries (CSV-driven) with its own vertical-list CSS style.
- 🔷 **Tab location** — put the per-machine tab classes in a dedicated subdirectory (`controller/tab/Asset/Machine/`) rather than flat in `controller/tab/` or `controller/tab/Asset/`.
- 🔷 **Phasing** — build the column-based tabs first and leave the **General** tab for a later phase.
- ℹ️ Android design is deferred for now; on Android, selecting a machine will open a separate window with the tabbed content.

---

## Evidence

✔️ Inventory of all per-machine data currently collected or stored in the tree (`shared/OSQuery/`, `shared/Agent.vala`, `shared/OsReleases.vala`, `shared/SQT/`, `docs/rpc-commands.md`):

### 1. Single-row machine data (already returned by `SystemInfo.list(true)`)

- ✔️ `system_info` (`shared/OSQuery/SystemInfo.vala`, 1 row per `agent_id`):
  - Identity: `hostname`, `local_hostname`, `computer_name`, `uuid`
  - Hardware: `hardware_vendor`, `hardware_model`, `hardware_version`, `hardware_serial`
  - Board: `board_vendor`, `board_model`, `board_version`, `board_serial`
  - Memory: `physical_memory` (`int64`, bytes)
  - CPU summary: `cpu_type`, `cpu_subtype`, `cpu_brand`, `cpu_physical_cores`, `cpu_logical_cores`, `cpu_microcode`
- ✔️ `os_version` + `os_releases` (already joined in `SystemInfo.list(true)`):
  - OS strings: `operating_system` (`name` + `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`
  - OS update status: `os_updated` (unix time from `os_releases`), `os_status` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked/unmatched)
  - Restart flag: `reboot_required` (`os_version.reboot_required`, `1` when waiting on Windows)
- ✔️ `logged_in_users` summary (already joined in `SystemInfo.list(true)`):
  - `logged_in_users` (`GROUP_CONCAT(DISTINCT user)`)
- ✔️ Audit timestamps exist on `SystemInfo` via `Row` (`added_dt`, `updated_dt`, `deleted_dt`), though `added_dt` / `updated_dt` currently show the `system_info` row sync time.

### 2. Single-row machine data in DB **not** yet on `SystemInfo.list(true)`

- ✔️ `os_version.pkgs_updated` and `os_version.pkgs_status` exist in `shared/OSQuery/OsVersion.vala` and are listed in `controller/resources/columns/system_info.csv`, but `SystemInfo.list(true)` does not select them onto `SystemInfo` yet.
- ✔️ `os_releases` (`shared/OsReleases.vala`) also stores `released`, `eol`, `is_lts`, and `name` for the matched release row.
- ✔️ `agent` (`shared/Agent.vala`, matched by `system_info.agent_id = agent.id`):
  - `ip` (peer address), `created` (registered unix time), `last_connected` (latest app-socket unix time), `connected` (live connection boolean), `requester`, `username`, `hostname`, `is_controller`, `status`
  - ℹ️ `Agent.list` exists (`server/Agent.vala`) with `LIMIT 20` and no `agent_id` filter; `SystemInfo.list(true)` does not join `agent` columns.

### 3. Many-row osquery tables (synced at startup by `agent/OSQuery/Execute.vala`)

- ✔️ `cpu_info` (`shared/OSQuery/CpuInfo.vala`, 1 row per processor):
  - `device_id`, `model`, `manufacturer`, `processor_type`, `cpu_status`, `number_of_cores`, `logical_processors`, `address_width`, `current_clock_speed` (MHz), `max_clock_speed` (MHz), `socket_designation`
  - 🚫 No `CpuInfo.list` RPC exists yet.
- ✔️ `logged_in_users` (`shared/OSQuery/LoggedInUsers.vala`, 1 row per session):
  - `user`, `tty`, `host`, `time` (unix timestamp), `ctype` (DB column `type`), `pid`
  - 🚫 No `LoggedInUsers.list` RPC exists yet.
- ✔️ `interface_addresses` (`shared/OSQuery/InterfaceAddresses.vala`, 1 row per address):
  - `@interface` (DB column `interface`), `address`, `mask`, `broadcast`, `point_to_point`, `ctype` (DB column `type`)
  - 🚫 No `InterfaceAddresses.list` RPC exists yet.

### 4. Package / program tables (per-agent RPC already exists)

- ✔️ `deb_packages` + `package_updates` (`shared/OSQuery/DebPackages.vala`):
  - `DebPackages.list(agent_id, 0)` with `agent_id > 0` already returns that machine's rows (`deleted_dt = 0`) joined with `package_updates`:
  - Columns: `name`, `version`, `revision`, `arch`, `section`, `priority`, `size` (`int64`, bytes), `source`, `maintainer`, `status`, `update_since` (`int`, unix time from `package_updates`, `0` when up to date)
  - ℹ️ `controller/resources/columns/deb_packages.csv` is currently written for the aggregated Software grid (`min-version`, `max-version`, `max-size`, `installed`, `remove`), not per-machine columns (`version`, `revision`, `size`, `status`, `update-since`).
- ✔️ `rpm_packages` + `package_updates` (`shared/OSQuery/RpmPackages.vala`):
  - `RpmPackages.list(agent_id, 0)` with `agent_id > 0` already returns that machine's rows (`deleted_dt = 0`) joined with `package_updates`:
  - Columns: `name`, `epoch`, `version`, `release`, `arch`, `package_group`, `size` (`int64`, bytes), `source`, `vendor`, `sha1`, `install_time` (`int64`, unix time), `update_since` (`int`, unix time from `package_updates`, `0` when up to date)
  - ℹ️ `controller/resources/columns/rpm_packages.csv` is currently aggregated (`min-version`, `max-version`, `max-size`, `installed`), not per-machine (`version`, `release`, `epoch`, `size`, `install-time`, `update-since`).
- ✔️ `programs` (`shared/OSQuery/Programs.vala`):
  - `Programs.list(agent_id, 0)` with `agent_id > 0` already returns that machine's rows (`deleted_dt = 0`):
  - Columns: `name`, `version`, `publisher`, `language`, `identifying_number`, `install_date` (text), `install_location`, `install_source`, `uninstall_string`
  - ℹ️ `controller/resources/columns/programs.csv` is currently aggregated (`min-version`, `max-version`, `installed`, `uninstall-count`).
- ✔️ **Feasibility of reusing existing package stores and tabs (`controller/store/`, `controller/tab/Asset/`):**
  - ✔️ `Store.DebPackages`, `Store.RpmPackages`, and `Store.Programs` are directly reusable as-is (`load(int agent_id)` already calls `*.list(agent_id, 0)`). Note: their `if (this.busy) return;` guard should be checked if switching machines rapidly while a previous load is in flight.
  - ℹ️ Reusing `Tab.Asset.DebPackages`, `RpmPackages`, and `Programs` widget classes is feasible (parameterize `table` CSV and `agent_id`, skip `map -> load(0)`, and hide `Versions differ` / `spread` in `DebPackages` when `agent_id > 0`), **but not essential**:
    - `RpmPackages` and `Programs` tabs are ~99 lines each, and Software tabs will later add Software-specific filters, bulk update, sign-off, and machine drill-down (`5.9.2`, `5.9.3`, `5.5`).
    - Thin per-machine tabs in `controller/tab/Asset/Machine/` reusing `Tab.Base` (`column_grid`) and the existing `Store.*` classes keep Software and Machine detail cleanly separated.

### 5. Other per-machine tables in DB (scripts and tasks)

- ✔️ `script_agent` (`shared/SQT/ScriptAgent.vala`) — scripts enabled on `agent_id`.
- ✔️ `task_target` (`shared/SQT/TaskTarget.vala`) — tasks scheduled/executed on `agent_id` (`task_id`, `scheduled`, `started`, `ended`, `success`, `is_cancelled`).
- ℹ️ No per-machine RPC filters `script_agent` or `task_target` by `agent_id` yet.

### 6. Not collected yet

- ℹ️ `users` (local OS accounts), `uptime`, storage/mounts, listening ports/processes, power state (`docs/plans/5.8-assets-page.md`, `docs/plans/1.1-implementation.md`).
- ℹ️ Startup + log monitoring refresh (`logged_in_users`, logins, system/security events) is tracked separately in `docs/bugs/2026-11-13-log-monitoring.md`.

---

## Root cause

- ✔️ `controller/tab/Asset/SystemInfo.vala` currently appends only the `Gtk.ScrolledWindow` holding `this.grid` directly to itself, with no `Gtk.Paned` or selection listener.
- ✔️ `CpuInfo`, `LoggedInUsers`, and `InterfaceAddresses` have no `list(int agent_id)` RPCs, and the existing package CSVs (`deb_packages.csv`, `rpm_packages.csv`, `programs.csv`) use aggregated columns rather than per-machine columns.

---

## Proposed fix (rough sketch, phased)

### Phase 1 — Split pane, `Machine/` tab container, and Package tabs (existing RPCs) ✔️

- 🔷 ✔️ **Split pane (`controller/tab/Asset/SystemInfo.vala`):**
  - Wrapped the Machines grid (`ScrolledWindow`) and `Machine.Detail` inside a `Gtk.Paned(Gtk.Orientation.VERTICAL)`:
    - Top child: existing `ScrolledWindow` containing `this.grid`.
    - Bottom child: `Machine.Detail`, `visible = false` when `selected.get_size() != 1`.
  - When a single machine is selected and the detail pane was hidden, shows `detail`, sets `paned.position = paned.get_height() / 2`, and preserves the dragged splitter position while switching between single machines.
- 🔷 ✔️ **Subdirectory & container (`controller/tab/Asset/Machine/`):**
  - Added `controller/tab/Asset/Machine/namespace.vala`, `Detail.vala`, `DebPackages.vala`, `RpmPackages.vala`, `Programs.vala` (`namespace Argus.Controller.Tab.Asset.Machine`), plus `controller/meson.build` and `docs/meson.build`.
  - `Detail` uses `Adw.ToggleGroup` + `Adw.ViewStack` matching `controller/tab/Asset/Software.vala`, with lazy loading on visible tab selection.
- 🔷 ✔️ **Package tabs (`DebPackages`, `RpmPackages`, `Programs`) & stores (`controller/store/*.vala`):**
  - Reused existing `DebPackages.list(agent_id, 0)`, `RpmPackages.list(agent_id, 0)`, and `Programs.list(agent_id, 0)` RPCs and existing `Store.DebPackages`, `Store.RpmPackages`, and `Store.Programs` (updated `loaded_agent` check in `Store.*.load` so switching machines supersedes an in-flight load for a different machine and clears stale rows).
  - Constructed all three package tabs upfront; on `show_machine(machine)`, `machine.package_manager()` decides which one stays visible and hides the other two (showing an `Adw.StatusPage` when `UNKNOWN`).
  - Added `controller/resources/columns/deb_packages_machine.csv`, `rpm_packages_machine.csv`, and `programs_machine.csv` to `controller/resources/argusrm.gresource.xml`.

### Phase 2 — Remaining column-based tabs: CPUs, Users, Interfaces (new RPCs)

- 🔷 Reuse `Tab.Base` (`column_grid` + column CSVs) inside `controller/tab/Asset/Machine/` for the remaining many-row osquery tables:
  - 💩 **CPUs** (`cpu_info_machine.csv`, new `CpuInfo.list(int agent_id)` RPC + `Store.CpuInfo`):
    - Device ID, Model, Manufacturer, Cores (`number_of_cores`), Logical (`logical_processors`), Current MHz, Max MHz, Socket (`socket_designation`), Address width, Type, Status.
  - 💩 **Users** (`logged_in_users_machine.csv`, new `LoggedInUsers.list(int agent_id)` RPC + `Store.LoggedInUsers`):
    - User, TTY, Host, Time (`date`), Type (`ctype`), PID.
  - 💩 **Interfaces** (`interface_addresses_machine.csv`, new `InterfaceAddresses.list(int agent_id)` RPC + `Store.InterfaceAddresses`):
    - Interface (`interface`), Address, Mask, Broadcast, Point-to-point, Type (`ctype`).

### Phase 3 — **General** tab (vertical dump with expanders, multi-query generic builder)

- 🔷 Just a vertical dump of the horizontal Machines table (`system_info.csv` fields) with **nothing hidden** (rows that start `off` in the horizontal `ColumnView` are included here).
- 🔷 Group categories into **expanders** (`Gtk.Expander` or `Adw.ExpanderRow`, matching the blank-line-separated category groups in `system_info.csv`).
- 🔷 Add a dedicated CSS style for vertical lists in `controller/resources/style.css` (distinct from `ColumnView` horizontal row styling).
- 🔷 Build it generically from data and **multiple queries** rather than stuffing extra joins onto the horizontal `SystemInfo.list(true)` query:
  - 💩 Generic vertical-list builder (e.g. on `Tab.Base` or `Machine.General`) driven by **CSV files** (reusing `system_info.csv` plus optional additional source CSVs such as `Agent` / `OsVersion` / `OsReleases` rows) that maps each CSV row to a GObject property on the corresponding query result and formats values with the existing `Tab.Base` formatters (`text`, `number`, `bytes`, `date`, `status`).
  - 💩 Decide tab order once General lands (e.g. **General**, **CPUs**, **Users**, **Interfaces**, **Debian** / **RPM** / **Windows**).

### Phase 4 — Optional later tabs

- 💩 **Tasks** (`task_target`) and **Scripts** (`script_agent`) tabs once per-agent list RPCs exist.

---

## Next

- ⏳ 🔷 Verify Phase 1 split pane and package tabs in the running `argusrm-controller` UI.
- ⏳ 💩 Prepare Phase 2 (`CpuInfo.list`, `LoggedInUsers.list`, `InterfaceAddresses.list` + `Machine/CpuInfo`, `LoggedInUsers`, `InterfaceAddresses` tabs) and Phase 3 (`General` vertical expander view).
