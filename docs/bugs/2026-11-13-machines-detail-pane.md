# Machines tab detail pane and per-machine data tabs

**Status:** ⏳ rough sketch — awaiting review of layout, tabs, and available machine fields before writing code proposals

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, `docs/rpc-commands.md`

---

## Problem

- 🔷 The Machines tab (`controller/tab/Asset/SystemInfo.vala`) needs a horizontal split on the right pane (`Gtk.Paned` with `Gtk.Orientation.VERTICAL`, top grid / bottom detail) with an adjustable splitter.
- 🔷 When no machine is selected, the bottom area is hidden and the Machines grid uses the full height.
- 🔷 When a machine is selected, the bottom area opens at a 50% vertical split.
- 🔷 The lower half contains a tabbed area:
  - 🔷 **General** — vertical left-right key/value display of joined machine information (`system_info`, `os_version`, `os_releases`, etc.).
  - 🔷 **Column-based tabs** — per-machine tables such as **CPUs**, **Users**, **Interfaces**, and **Packages**.
  - 🔷 **Packages** — generate three tabs for the three package types (**Debian packages**, **RPM packages**, **Windows programs**) and hide the two that are not relevant for the selected machine.
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

### 5. Other per-machine tables in DB (scripts and tasks)

- ✔️ `script_agent` (`shared/SQT/ScriptAgent.vala`) — scripts enabled on `agent_id`.
- ✔️ `task_target` (`shared/SQT/TaskTarget.vala`) — tasks scheduled/executed on `agent_id` (`task_id`, `scheduled`, `started`, `ended`, `success`, `is_cancelled`).
- ℹ️ No per-machine RPC filters `script_agent` or `task_target` by `agent_id` yet.

### 6. Not collected yet

- ℹ️ `users` (local OS accounts), `uptime`, power state, storage/mounts, and listening ports/processes (`docs/plans/5.8-assets-page.md`, `docs/plans/1.1-implementation.md`).

---

## Root cause

- ✔️ `controller/tab/Asset/SystemInfo.vala` currently appends only the `Gtk.ScrolledWindow` holding `this.grid` directly to itself, with no `Gtk.Paned` or selection listener.
- ✔️ `CpuInfo`, `LoggedInUsers`, and `InterfaceAddresses` have no `list(int agent_id)` RPCs, and the existing package CSVs (`deb_packages.csv`, `rpm_packages.csv`, `programs.csv`) use aggregated columns rather than per-machine columns.

---

## Proposed fix (rough sketch)

### 1. Split pane and selection behaviour (`controller/tab/Asset/SystemInfo.vala`)

- 🔷 Wrap the Machines grid (`ScrolledWindow`) and the detail pane inside a `Gtk.Paned(Gtk.Orientation.VERTICAL)`:
  - Top child: existing `ScrolledWindow` containing `this.grid`.
  - Bottom child: detail container, `visible = false` when no machine is selected.
- 🔷 When a machine is selected, show the bottom child and set `paned.position` to 50% of the paned height (`get_allocated_height() / 2`) if it was previously hidden (💩 preserve the user's dragged splitter position while switching between machines once open).
- 💩 Selection model is currently `Gtk.MultiSelection` (`this.column_grid(rows, true)`):
  - Show the detail pane when `selection.get_selection().get_size() == 1` (or show the focused/first selected machine when `>= 1`? Confirm which behaviour is wanted).
  - Clear/hide the detail pane when `0` rows are selected or the selected row disappears on reload/filter.

### 2. Lower tabbed area layout

- 💩 Reuse the `Adw.ToggleGroup` + `Adw.ViewStack` pattern from `controller/tab/Asset/Software.vala` (inline tab bar across the top of the bottom pane, no controls in the window header bar).
- 💩 Tab list (left to right):
  1. **General** (key/value list)
  2. **CPUs** (column grid — `cpu_info`)
  3. **Users** (column grid — `logged_in_users`)
  4. **Interfaces** (column grid — `interface_addresses`)
  5. **Debian packages** (column grid — `deb_packages`, visible only when `PackageManager.APT`)
  6. **RPM packages** (column grid — `rpm_packages`, visible only when `PackageManager.DNF`)
  7. **Windows programs** (column grid — `programs`, visible only when `PackageManager.WIN`)
  8. 💩 Optional later tabs: **Tasks** (`task_target`) / **Scripts** (`script_agent`).
- 🔷 All three package tabs are constructed upfront; on machine selection, `OsVersion.package_manager()` logic (`platform_like`, then `platform`) decides which one of the three package tabs stays visible and hides the other two.
- 💩 If the currently active tab is a package tab that becomes hidden on switching to a machine with a different OS, switch back to **General** (or the newly visible package tab).

### 3. **General** tab — vertical left/right key-value view

- 🔷 Vertical scrolled list (`Gtk.ScrolledWindow` + `Gtk.Grid` or `Adw.PreferencesGroup` / `Adw.ActionRow` with `.property` / selectable labels) displaying grouped key/value pairs:
  - 💩 **System & Identity**: Hostname, Computer name, Local hostname, UUID, Logged-in users
  - 💩 **Operating System**: Operating system (`name` + `version`), Platform / Platform like, Codename, Arch, Build, OS status (dot/label), OS checked (`os_updated`), Package status (`pkgs_status` / `pkgs_updated` once joined), Reboot required (`reboot_required` when set)
  - 💩 **Hardware**: Hardware vendor, Hardware model, Hardware version, Hardware serial, Physical memory (formatted size), Board vendor/model/version/serial
  - 💩 **CPU Summary**: CPU brand, Type / Subtype, Physical cores, Logical cores, Microcode
  - 💩 **Agent / Connection** (if joined from `agent`): IP address, Connected, Last connected, Registered on
- 💩 Omit blank rows (e.g. `computer_name` on Linux or `board_*` when empty) or show `—`?

### 4. Column-based detail tabs and RPCs needed

- 💩 Reuse `Tab.Base` (`column_grid` + column CSVs) for each column-based tab so sorting, column visibility menu, and `bytes`/`date`/`status` formatting work consistently:
  - 💩 **CPUs** (`cpu_info_machine.csv`, new `CpuInfo.list(int agent_id)` RPC):
    - Device ID, Model, Manufacturer, Cores (`number_of_cores`), Logical (`logical_processors`), Current MHz, Max MHz, Socket (`socket_designation`), Address width, Type, Status.
  - 💩 **Users** (`logged_in_users_machine.csv`, new `LoggedInUsers.list(int agent_id)` RPC):
    - User, TTY, Host, Time (`date` or `recent-date`), Type (`ctype`), PID.
  - 💩 **Interfaces** (`interface_addresses_machine.csv`, new `InterfaceAddresses.list(int agent_id)` RPC):
    - Interface (`interface`), Address, Mask, Broadcast, Point-to-point, Type (`ctype`).
  - 💩 **Debian packages** (`deb_packages_machine.csv`, existing `DebPackages.list(agent_id, 0)` RPC):
    - Name, Version, Revision, Arch, Section, Priority, Size (`bytes`), Update waiting (`update_since` date/dot), Source (off), Maintainer (off), Status (off).
  - 💩 **RPM packages** (`rpm_packages_machine.csv`, existing `RpmPackages.list(agent_id, 0)` RPC):
    - Name, Epoch, Version, Release, Arch, Package group, Size (`bytes`), Install time (`date`), Update waiting (`update_since`), Source (off), Vendor (off).
  - 💩 **Windows programs** (`programs_machine.csv`, existing `Programs.list(agent_id, 0)` RPC):
    - Name, Version, Publisher, Install date, Language (off), Identifying number (off), Install location (off), Install source (off), Uninstall string (off).
- 💩 Lazy loading: load a detail tab's RPC only when a machine is selected and that tab is visible (or reload visible tab on selection change, and load newly switched-to tab for the current `agent_id`), rather than firing 4–6 RPCs on every row click.

---

## Next

- ⏳ 🔷 Confirm the tab list (**General**, **CPUs**, **Users**, **Interfaces**, **Debian** / **RPM** / **Windows**, and whether **Tasks** / **Scripts** belong here now or later).
- ⏳ 🔷 Confirm `MultiSelection` behaviour for the detail pane (show only when 1 row selected vs show active/first row) and whether `SystemInfo.list(true)` should also join `agent` (`ip`, `connected`, `last_connected`, `created`) and `os_version.pkgs_updated` / `pkgs_status`.
- ⏳ 🔷 Confirm whether blank key/value rows in **General** are hidden or shown empty, and whether column-based detail tabs should lazy-load when visible.
- ⏳ 💩 Once confirmed, write verbatim `Remove` / `Replace with` / `Add` code proposals (`docs/rpc-commands.md`, `shared/OSQuery/*.vala`, `controller/resources/columns/*.csv`, `controller/tab/Asset/*.vala`, `controller/store/*.vala`).
