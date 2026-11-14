# Machines tab detail pane and per-machine data tabs

**Status:** ✅ closed 2026-11-14. Phase 1, Phase 2, Phase 3 RPCs, and Phase 4 General tab verified fixed (`Users`, `Interfaces`, `CPUs`, `SystemInfo.list(agent_id, join)`, `OsVersion.list`, `OsReleases.list`, `MachineGeneral`, `Machine.General`) — see [2026-11-14-FIXED-machine-general-store.md](2026-11-14-FIXED-machine-general-store.md).

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

- ✔️ `cpu_info` (`shared/OSQuery/CpuInfo.vala`, 1 row per processor socket):
  - `device_id`, `model`, `manufacturer`, `processor_type`, `cpu_status`, `number_of_cores`, `logical_processors`, `address_width`, `current_clock_speed` (MHz), `max_clock_speed` (MHz), `socket_designation`
  - 🚫 No `CpuInfo.list` RPC exists yet.
  - ✔️ **Sample stored row (`/var/lib/argusrm/argus.sqlite`, agent 16 `fastboy`):**
    ```
    device_id            model                           manufacturer          processor_type  cpu_status  number_of_cores  logical_processors  address_width  current_clock_speed  max_clock_speed  socket_designation
    CPU0                 Intel(R) Core(TM) Ultra 7 165U  Intel(R) Corporation  3               65          12               14                  64             4455                 4900             U3E1
    ```
  - ℹ️ `processor_type` (`3` = Central Processor) and `cpu_status` (`65` = `0x41`, Socket Populated + Enabled) are raw SMBIOS codes. On a multi-socket server there is one row per socket (`CPU0`, `CPU1`).
- ✔️ `logged_in_users` (`shared/OSQuery/LoggedInUsers.vala`, 1 row per session):
  - `user`, `tty`, `host`, `time` (unix timestamp), `ctype` (DB column `type`), `pid`
  - 🚫 No `LoggedInUsers.list` RPC exists yet.
  - ✔️ **Sample status on this host (`/var/lib/argusrm/argus.sqlite` & local `osqueryi`):** `0` rows because `/run/utmp` does not exist on systemd 256+ / Mint 22 / Ubuntu 24.04 (`who` still reports active sessions from `systemd-logind`, and `osqueryi` `last` reports `wtmp` rows); Windows (`WTS`) and older Debian/EL populate `logged_in_users`:
    ```
    type    user   tty      host          time        pid
    user    alan   pts/0    192.168.0.5   1739009760  2885
    user    alan   seat0    login screen  1739069561  2390
    active  alan   Console                1763020800  -1     (Windows)
    ```
- ✔️ `interface_addresses` (`shared/OSQuery/InterfaceAddresses.vala`, 1 row per address):
  - `@interface` (DB column `interface`), `address`, `mask`, `broadcast`, `point_to_point`, `ctype` (DB column `type`)
  - 🚫 No `InterfaceAddresses.list` RPC exists yet.
  - ✔️ **Sample stored rows (`/var/lib/argusrm/argus.sqlite`, agent 16 `fastboy`; local `osqueryi` sets `type` = `"unknown"` on every Linux row):**
    ```
    interface  address                              mask                                     broadcast        point_to_point  type
    lo         127.0.0.1                            255.0.0.0                                                 127.0.0.1       unknown
    wlp0s20f3  192.168.0.6                          255.255.252.0                            192.168.3.255                    unknown
    lxcbr0     10.0.3.1                             255.255.255.0                            10.0.3.255                       unknown
    docker0    172.17.0.1                           255.255.0.0                              172.17.255.255                   unknown
    tun3       10.9.188.16                          255.255.255.0                                             10.9.188.16     unknown
    virbr0     192.168.122.1                        255.255.255.0                            192.168.122.255                  unknown
    lo         ::1                                  ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff                                   unknown
    wlp0s20f3  fe80::d079:79cb:7ea7:8cdd%wlp0s20f3  ffff:ffff:ffff:ffff::                                                     unknown
    lxcbr0     fc42:5009:ba4b:5ab0::1               ffff:ffff:ffff:ffff::                                                     unknown
    tun3       fe80::153e:f0c0:be2b:42bf%tun3       ffff:ffff:ffff:ffff::                                                     unknown
    vnet0      fe80::fc54:ff:fe00:1f86%vnet0        ffff:ffff:ffff:ffff::                                                     unknown
    ```
  - ✔️ **What osquery has for default route and interface type (not synced by agent yet, inspected via `osqueryi`):**
    - `routes` (identifies default/outbound gateway and VPN/tunnel routes):
      ```
      destination   netmask  gateway        source       interface  metric  type
      0.0.0.0       0        192.168.0.251  192.168.0.12 wlp0s20f3  600     gateway
      10.0.3.0      24                      10.0.3.1     lxcbr0     0       gateway
      10.9.188.0    24                      10.9.188.16  tun3       0       gateway
      45.33.34.46   0        10.9.188.1                  tun3       0       gateway
      ```
    - `interface_details` (has `mac`, `type` integer e.g. `1` Ethernet / `4` Loopback / `254` Tunnel, `mtu`, `link_speed`, `flags`):
      ```
      interface  mac                type  mtu    link_speed  flags
      lo         00:00:00:00:00:00  4     65536  0           65609
      wlp0s20f3  c8:58:b3:d0:7a:1e  1     1500   0           69699
      lxcbr0     00:16:3e:00:00:00  1     1500   0           4099
      docker0    c6:b1:92:54:9a:a9  1     1500   0           4099
      tun3       00:00:00:00:00:00  254   1500   10000       69841
      virbr0     52:54:00:c5:91:71  1     1500   10000       69699
      vnet0      fe:54:00:00:1f:86  1     1500   10000       70467
      ```

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
    - `RpmPackages` and `Programs` tabs are ~99 lines each, and Software tabs will later add Software-specific filters, bulk update, sign-off, and machine drill-down (`docs/bugs/`, `5.5`).
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
- ✔️ **Detail pane tabs disappeared / did not appear (`shared/OSQuery/Row.vala` & `controller/tab/Asset/Machine/Detail.vala`):**
  - `Row.bin_write_prop` omitted `"agent-id"` and `Row.bin_read_prop` reset `this.agent_id = 0` on the wire, so `SystemInfo.list` always delivered `machine.agent_id == 0` to `Machine.Detail.show_machine()`, which returned early before adding any toggles to `this.group` or loading any tab. (`sync_rows`, `sync_packages`, `OsVersion.sync`, and `PackageUpdates.sync` already overwrite `agent_id` from `connection.user.id`, so only `id` and `since` belong in the wire omit/zero list.)
  - `Detail.show_machine()` called `this.group.remove_all()` when switching between machines with different `package_manager()` values; in libadwaita 1.7.0 `adw_toggle_group_remove_all()` leaves `toggle->group != NULL`, causing subsequent `this.group.add(...)` calls to fail with `adw_toggle_group_add: assertion 'toggle->group == NULL' failed` and drop the tabs. Removing toggles individually with `this.group.remove(toggle)` clears `toggle->group` cleanly.
- ✔️ **Detail lists hung & timed out (`server/Application.vala`):**
  - `server/Application.vala` called `OLLMrpc.Request.register(...)` for `SystemInfo`, `DebPackages`, `RpmPackages`, and `Programs`, but omitted `CpuInfo`, `LoggedInUsers`, and `InterfaceAddresses`.
  - `/var/log/argusrm/server.log` logged `Ffi.vala:277: RPC dispatch: no handler instance for LoggedInUsers.list` (and `InterfaceAddresses.list`, `CpuInfo.list`) with no reply, so `OLLMrpc.Client` queued every subsequent click (`DebPackages.list`, etc.) behind 120-second call timeouts (`~/.cache/argusrm/controller.log`).
  - Added `OLLMrpc.Request.register(...)` for `"CpuInfo"`, `"LoggedInUsers"`, and `"InterfaceAddresses"` in `server/Application.vala`.
- ✔️ **Spinner rendered broken `image-missing` icon (`controller/`):**
  - `Gtk.Spinner` resolves `process-working-symbolic` via CSS; under the `Adwaita` icon theme on this host, `Gtk.IconTheme.lookup_icon("process-working-symbolic", ...)` falls back to `image-missing.svg`.
  - Replaced `Gtk.Spinner` across `controller/` (`Machine/*`, `Software`, `DebPackages`, `RpmPackages`, `Programs`, `Agent`, `Repository`, `Tasks`) with `Adw.Spinner` (which renders programmatically via `Adw.SpinnerPaintable` without icon-theme lookup), and updated `.package-wait` in `controller/resources/style.css` so it matches `Adw.Spinner` (`image.spinner`).

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

### Phase 2 — Remaining column-based tabs: Users, Interfaces, CPUs (new RPCs) ✔️

- 🔷 Reuse `Tab.Base` (`column_grid` + column CSVs) inside `controller/tab/Asset/Machine/` for the remaining many-row osquery tables.
- 🔷 **Approved tab order in `Machine/Detail.vala`:** **Users**, **Debian packages** / **RPM packages** / **Windows programs**, **Interfaces**, **CPUs**.
- ℹ️ Column visibility legend (matching [5.8](../../plans/5.8-assets-page.md) and [5.9](../../plans/done/5.9-DONE-assets-software.md)):
  - ✅ starts visible (`ON` in CSV).
  - hidden starts off (`off` in CSV), and can be turned on from the header menu.

#### Users (`logged_in_users`, `LoggedInUsers.list(int agent_id)` -> `logged_in_users_machine.csv`)

- ✅ `user` — **User** (`text`, 160px, row header). The login name (`alan`).
- ✅ `tty` — **TTY** (`text`, 110px). Terminal or console (`pts/0`, `seat0`, `Console`).
- ✅ `host` — **Host** (`text`, 160px). Remote host or display (`192.168.0.5`, `login screen`).
- ✅ `time` — **Logged in** (`elapsed` format in `Tab.Base`, 100px). Relative time since login (`45s`, `12m`, `3h`, `4d`), with mouseover tooltip showing the formatted local date/time (`%Y-%m-%d %H:%M:%S`).
- ✅ `ctype` (`type` in DB) — **Type** (`text`, 100px). Session type (`user`, `active`, `disconnected`).
- hidden `pid` — **PID** (`number`, 80px). Session process ID (`2885`).

#### Interfaces (`interface_addresses`, `InterfaceAddresses.list(int agent_id)` -> `interface_addresses_machine.csv`)

- 🔷 Keep Phase 2 on `interface_addresses` only (no `routes`/`interface_details` sync yet).
- ✅ `interface` — **Interface** (`text`, 120px, row header). Device name (`wlp0s20f3`, `lxcbr0`, `tun3`, `docker0`, `lo`).
- ✅ `address` — **Address** (`cidr` format in `Tab.Base` combining `address` + `mask` as `address/prefix`, 240px, e.g. `192.168.0.6/22`, `10.0.3.1/24`, `fe80::.../64`).
- ✅ `point_to_point` — **Point-to-point** (`text`, 160px). Peer address (`10.9.188.16`, `127.0.0.1`).
- hidden `mask` — **Mask** (`text`, 220px). Raw netmask (`255.255.252.0`).
- hidden `broadcast` — **Broadcast** (`text`, 160px). Broadcast address (`192.168.3.255`).
- hidden `ctype` (`type` in DB) — **Type** (`text`, 100px). Raw osquery `type` (`unknown` on Linux).

#### CPUs (`cpu_info`, `CpuInfo.list(int agent_id)` -> `cpu_info_machine.csv`)

- 🔷 No bold row-header styling on CPUs (`bold_header: false` on `Tab.Base`).
- ✅ `device_id` — **Device ID** (`text`, 90px). e.g. `CPU0`.
- ✅ `model` — **Model** (`text`, 260px). e.g. `Intel(R) Core(TM) Ultra 7 165U`.
- ✅ `number_of_cores` — **Cores** (`number`, 80px). e.g. `12`.
- ✅ `logical_processors` — **Logical** (`number`, 80px). e.g. `14`.
- ✅ `current_clock_speed` — **Current MHz** (`mhz` format in `Tab.Base`, right-aligned, comma-formatted + ` MHz`, 110px). e.g. `4,455 MHz`.
- 🚫 `max_clock_speed` removed.
- hidden `manufacturer` — **Manufacturer** (`text`, 140px). e.g. `Intel(R) Corporation`.
- hidden `socket_designation` — **Socket** (`text`, 120px). e.g. `U3E1`.
- hidden `address_width` — **Address width** (`number`, 110px). e.g. `64`.
- hidden `processor_type` — **Type** (`text`, 110px). Raw SMBIOS code (`3`).
- hidden `cpu_status` — **Status** (`number`, 80px). Raw SMBIOS code (`65`).

### Phase 3 — **General** tab RPCs (store & UI split out) ✔️

- 🔷 Vertical dump of the machine row from **three subqueries** matching the three tables `SystemInfo` joins (`system_info`, `os_version`, `os_releases`), with each subquery going onto an expander entry.
- 🔷 Use plain `.list` RPCs (no `read` RPCs, no `logged_in_users` coalesce, no enriched joins, and no `agent` table).
- 🔷 Reuse the existing `controller/resources/columns/system_info.csv` for field labels and data types/formats (no extra resource CSV files).
- ℹ️ The `Store.Base` CSV interface, `Store.KeyValue`, `Store.MachineGeneral`, `Tab.Asset.Machine.General`, `Detail.vala`, and `.vertical-list` CSS are broken out into [2026-11-14-FIXED-machine-general-store.md](2026-11-14-FIXED-machine-general-store.md).
- ✔️ Three plain `list` RPCs implemented (`SystemInfo.list(agent_id, join)`, `OsVersion.list(agent_id)`, `OsReleases.list(agent_id)`) and registered in `server/Application.vala`, `controller/Application.vala`, `docs/rpc-commands.md`, and `server/tests/packages.vala`.

---

#### 1. `shared/OSQuery/SystemInfo.vala` & `controller/store/SystemInfo.vala` — `SystemInfo.list(agent_id, join)`

**Why:** Reuse `SystemInfo.list` with `agent_id > 0` and `!join` to fetch one machine's plain `system_info` row without a new `read` method or `logged_in_users` coalesce.

**Where:** `rpc_register()` and `list()` in `shared/OSQuery/SystemInfo.vala`; `load()` in `controller/store/SystemInfo.vala`.

**Depends on:** none.

##### Remove (`shared/OSQuery/SystemInfo.vala`)

```vala
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("SystemInfo", typeof(SystemInfo));
			OLLMrpc.Request.add_class(
				"SystemInfo", typeof(SystemInfo),
				"list", "b"
			);
		}

		/**
		 * List every stored row.
		 *
		 * A controller calls this. An agent with no row is absent.
		 * A row whose ''agent_id'' is not in ''agent'' is absent.
		 * Joined ''os_version'' and logins follow that same rule.
		 * A caller that is not a controller is refused.
		 * ''join'' adds that host's ''os_version'' onto the row.
		 * The same flag adds the distinct logged-in users.
		 * Those values are not stored on ''system_info''.
		 *
		 * @param request inbound RPC from a controller
		 * @param join true adds ''os_version'' and the logins
		 */
		public void list(OLLMrpc.Request request, bool join)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<SystemInfo>();
			var query = SystemInfo.query(SystemInfo.db);
			if (!join) {
				query.select("WHERE agent_id IN (SELECT id FROM agent)", rows);
			}
			if (join) {
```

##### Replace with (`shared/OSQuery/SystemInfo.vala`)

```vala
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("SystemInfo", typeof(SystemInfo));
			OLLMrpc.Request.add_class(
				"SystemInfo", typeof(SystemInfo),
				"list", "ib"
			);
		}

		/**
		 * List stored rows, or one agent's row.
		 *
		 * A controller calls this. An agent with no row is absent.
		 * A row whose ''agent_id'' is not in ''agent'' is absent.
		 * Joined ''os_version'' and logins follow that same rule.
		 * A caller that is not a controller is refused.
		 * When ''agent_id'' is greater than zero, only that host is
		 * returned.
		 * ''join'' adds that host's ''os_version'' onto the row.
		 * The same flag adds the distinct logged-in users.
		 * Those values are not stored on ''system_info''.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id, or zero for all
		 * @param join true adds ''os_version'' and the logins
		 */
		public void list(OLLMrpc.Request request, int agent_id, bool join)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<SystemInfo>();
			var query = SystemInfo.query(SystemInfo.db);
			if (!join) {
				var where = "WHERE agent_id = " + agent_id.to_string();
				if (agent_id < 1) {
					where = "WHERE agent_id IN (SELECT id FROM agent)";
				}
				query.select(where, rows);
			}
			if (join) {
```

##### Remove (`shared/OSQuery/SystemInfo.vala`, `columns` and `WHERE` clause inside `if (join)`)

```vala
			if (join) {
				var columns = string.joinv(", ", query.getColsExcept(null, "system_info."));
				query.selectQuery(@"
```

and at the bottom of `query.selectQuery`:

```vala
					WHERE
						system_info.agent_id IN (SELECT id FROM agent)
					", rows);
```

##### Replace with (`shared/OSQuery/SystemInfo.vala`)

```vala
			if (join) {
				var where = "system_info.agent_id = " + agent_id.to_string();
				if (agent_id < 1) {
					where = "system_info.agent_id IN (SELECT id FROM agent)";
				}
				var columns = string.joinv(", ", query.getColsExcept(null, "system_info."));
				query.selectQuery(@"
```

and at the bottom of `query.selectQuery`:

```vala
					WHERE
						$(where)
					", rows);
```

##### Remove (`controller/store/SystemInfo.vala`)

```vala
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "SystemInfo.list",
				args = OLLMrpc.args("b", true)
			}, (obj, res) => {
```

##### Replace with (`controller/store/SystemInfo.vala`)

```vala
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "SystemInfo.list",
				args = OLLMrpc.args("ib", 0, true)
			}, (obj, res) => {
```

---

#### 2. `shared/OSQuery/OsVersion.vala` — `OsVersion.list(agent_id)`

**Why:** Expose the plain `os_version` row for one machine (`name`, `version`, `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `pkgs_updated`, `pkgs_status`, `reboot_required`).

**Where:** `shared/OSQuery/OsVersion.vala` (`db` field, `init_db`, `rpc_register`, `list()`).

**Depends on:** none.

##### Add — store `db` reference on `OsVersion`

In `public class OsVersion : Row`, above `sync`:

```vala
		private static SQ.Database db;
```

In `init_db(SQ.Database db)`, before `string errmsg;`:

```vala
			OsVersion.db = db;
```

##### Remove (`shared/OSQuery/OsVersion.vala`)

```vala
		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("OsVersion", typeof(OsVersion));
		}
```

##### Replace with (`shared/OSQuery/OsVersion.vala`)

```vala
		/**
		 * Register this row and ''OsVersion.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("OsVersion", typeof(OsVersion));
			OLLMrpc.Request.add_class(
				"OsVersion", typeof(OsVersion),
				"list", "i"
			);
		}

		/**
		 * Stored ''os_version'' row for one agent.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''deleted_dt'' is set is absent. A
		 * caller that is not a controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<OsVersion>();
			if (agent_id > 0) {
				var query = new SQ.Query<OsVersion>(OsVersion.db, "os_version");
				query.select(@"
					WHERE
						agent_id = $(agent_id)
					AND
						deleted_dt = 0
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
```

---

#### 3. `shared/OsReleases.vala`, `server/Application.vala`, & `controller/Application.vala` — `OsReleases.list(agent_id)`

**Why:** Expose the plain `os_releases` row matching one machine's `os_version` `(platform, major, minor)` over RPC, and register `OsVersion` + `OsReleases` in both `server/Application.vala` and `controller/Application.vala`.

**Where:** `shared/OsReleases.vala` (interfaces, `db` field, `init_db`, `rpc_register`, `list()`), `server/Application.vala` (`command_line()`), `controller/Application.vala` (`command_line()`).

**Depends on:** item 2.

##### Remove (`shared/OsReleases.vala`)

```vala
	public class OsReleases : GLib.Object, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
```

##### Replace with (`shared/OsReleases.vala`)

```vala
	public class OsReleases : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		private static SQ.Database db;

		public int64 id { get; set; default = 0; }
```

##### Add — store `db` in `OsReleases.init_db()`

In `init_db(SQ.Database db)`, before `var errmsg = "";`:

```vala
			OsReleases.db = db;
```

##### Add — `rpc_register()` and `list()` below `query()` in `shared/OsReleases.vala`

```vala
		/**
		 * Register this row and ''OsReleases.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("OsReleases", typeof(OsReleases));
			OLLMrpc.Request.add_class(
				"OsReleases", typeof(OsReleases),
				"list", "i"
			);
		}

		/**
		 * Stored ''os_releases'' row matching one agent's ''os_version''.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A caller that is not a controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<OsReleases>();
			if (agent_id > 0) {
				var query = OsReleases.query(OsReleases.db);
				var columns = string.joinv(", ", query.getColsExcept(null, "os_releases."));
				query.selectQuery(@"
					SELECT
						$(columns)
					FROM
						os_releases
					JOIN
						os_version
					ON
						os_version.platform = os_releases.platform
						AND os_version.major = os_releases.major
						AND os_version.minor = os_releases.minor
					WHERE
						os_version.agent_id = $(agent_id)
						AND os_version.deleted_dt = 0
					LIMIT 1
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
```

##### Add — wire/handler registration in `server/Application.vala`

In `command_line()`, directly after `Argus.Shared.Agent.rpc_register();`:

```vala
			Argus.Shared.OsReleases.rpc_register();
```

In `command_line()`, directly after `OLLMrpc.Request.register("SystemInfo", new Argus.Shared.OSQuery.SystemInfo());`:

```vala
			OLLMrpc.Request.register("OsVersion", new Argus.Shared.OSQuery.OsVersion());
			OLLMrpc.Request.register("OsReleases", new Argus.Shared.OsReleases());
```

##### Add — wire registration in `controller/Application.vala`

In `command_line()`, directly after `Argus.Shared.OSQuery.SystemInfo.rpc_register();`:

```vala
			Argus.Shared.OSQuery.OsVersion.rpc_register();
			Argus.Shared.OsReleases.rpc_register();
```

---

#### 4. `docs/rpc-commands.md` — update `SystemInfo.list` and add `OsVersion.list`, `OsReleases.list`

**Why:** `.cursor/rules/rpc-commands.mdc` requires documenting new or changed RPC methods in the same change.

**Where:** `docs/rpc-commands.md` under `SystemInfo.list`.

**Depends on:** items 1, 2, 3.

##### Remove (`docs/rpc-commands.md`)

```markdown
### `SystemInfo.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `b`: true includes that host's `os_version` and the distinct logged-in users on the row. false is `system_info` only.
- Reply `retval` `o`: an array of `SystemInfo` rows. One row per host that has sent `system_info` and whose `agent_id` is still in `agent`.
- `os_version` and `logged_in_users` in that reply are included only when their `agent_id` is in `agent`.
- Startup deletes `system_info` rows whose `agent_id` is not in `agent`.
- With the flag, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `os_updated`, `os_status`, and `reboot_required`. `os_updated` and `os_status` come from `os_releases` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked or unmatched). `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
- `logged-in-users` is not a column of `system_info`. The list reads rows already stored. It does not ask the agent.
- `major`, `minor`, and `patch` are text here, so a missing row stays blank. They are not columns of `system_info`.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/SystemInfo.vala`. `Store.SystemInfo` calls it. [5.8](plans/5.8-assets-page.md).
```

##### Replace with (`docs/rpc-commands.md`)

```markdown
### `SystemInfo.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `ib`: `agent_id` and `join`. When `agent_id` is greater than zero, only that host is returned. `join` true includes that host's `os_version` and the distinct logged-in users on the row; false is `system_info` only.
- Reply `retval` `o`: an array of `SystemInfo` rows. One row per host that has sent `system_info` (and whose `agent_id` is still in `agent` when `agent_id` is zero).
- `os_version` and `logged_in_users` in that reply are included only when their `agent_id` is in `agent`.
- Startup deletes `system_info` rows whose `agent_id` is not in `agent`.
- With `join` true, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `os_updated`, `os_status`, and `reboot_required`. `os_updated` and `os_status` come from `os_releases` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked or unmatched). `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
- `logged-in-users` is not a column of `system_info`. The list reads rows already stored. It does not ask the agent.
- `major`, `minor`, and `patch` are text here, so a missing row stays blank. They are not columns of `system_info`.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/SystemInfo.vala`. `Store.SystemInfo` calls `SystemInfo.list(0, true)` and `Store.MachineGeneral` calls `SystemInfo.list(agent_id, false)`. [5.8](plans/5.8-assets-page.md).

### `OsVersion.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent_id`.
- Reply `retval` `o`: an array of `OsVersion` rows (`deleted_dt = 0`) for that `agent_id`. An `agent_id` less than one returns an empty array.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/OsVersion.vala`. `Store.MachineGeneral` calls it.

### `OsReleases.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent_id`.
- Reply `retval` `o`: an array containing zero or one `OsReleases` row matching that host's `os_version` (`platform`, `major`, `minor`, with `os_version.deleted_dt = 0`). An `agent_id` less than one returns an empty array.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OsReleases.vala`. `Store.MachineGeneral` calls it.
```

### Phase 4 — Optional later tabs

- 💩 **Tasks** (`task_target`) and **Scripts** (`script_agent`) tabs once per-agent list RPCs exist.

---

## Next

- ✅ Closed 2026-11-14. Phase 1–3 and the **General** tab verified in the running controller UI (see [2026-11-14-FIXED-machine-general-store.md](2026-11-14-FIXED-machine-general-store.md)).
