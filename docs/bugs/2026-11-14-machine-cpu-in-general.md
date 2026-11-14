# Machine detail: fold CPU inventory into General, drop CPUs tab

**Status:** ✔️ applied 2026-11-14 — CPUs tab removed; `MachineGeneral` loads `CpuInfo.list`; awaiting live UI verification

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md), [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md)

---

## Problem

- 🔷 Machine **General** shows coarse CPU fields from `system_info` (`cpu-brand`, `cpu-type`, `cpu-physical-cores`, `cpu-logical-cores`, etc.) but not the per-socket **`cpu_info`** inventory that the dedicated **CPUs** tab loads via `CpuInfo.list`.
- 🔷 **CPUs** is a full lazy-loaded tab (`controller/tab/Asset/Machine/CpuInfo.vala`) with a data grid driven by `cpu_info_machine.csv`. On typical workstations and servers there is **one** `cpu_info` row, so an extra tab is mostly an extra click for the same information.
- 🔷 **Expected (confirmed):**
  - Append **`cpu_info`** detail at the **bottom** of the **General** key-value view (after **OS release**).
  - **Loop** all `CpuInfo.list` rows for the machine: one row in the list → one block of CPU fields; more than one → **additional rows** (repeat the same field set per processor, distinguished by device/socket/model as needed).
  - **Remove** the **CPUs** tab from `Machine.Detail` (toggle, view-stack page, `cpus_loaded`, and lazy-load wiring).
- 🔷 **Actual:** CPU inventory is isolated on the **CPUs** tab; `Store.MachineGeneral` never calls `CpuInfo.list`.

---

## Evidence

✔️ Current tree:

### 1. General store only uses the first row per RPC section (`controller/store/MachineGeneral.vala`)

- `load()` calls `SystemInfo.list`, `OsVersion.list`, and `OsReleases.list` only.
- `load_section()` iterates `machine_general.csv` columns for a `source` and always formats **`rows.get(0)`** — no multi-row loop today.

### 2. Column layout (`controller/resources/columns/machine_general.csv`)

- Sections: **System info** → **OS version** → **OS release** (no `cpu_info` `Source` column).
- System info already includes summary CPU fields from osquery `system_info` (lines 17–22).

### 3. CPUs tab (`controller/tab/Asset/Machine/Detail.vala`, `CpuInfo.vala`)

- `Detail` registers `cpus` page + toggle, `cpus_loaded`, and `cpus.load(agent_id)` on first visit.
- Tab uses `Store.CpuInfo` + `CpuInfo.list` and grid columns from `cpu_info_machine.csv` (model, cores, logical, MHz, etc.).

### 4. Data model unchanged

- `shared/OSQuery/CpuInfo.vala`: one `cpu_info` row per processor; `CpuInfo.list` orders by `device_id`.
- Agent still syncs `cpu_info` at startup (`agent/OSQuery/Execute.vala`); no new RPC required for this UI change.

---

## Design (approved)

### Placement

- New **`cpu_info`** section in **`machine_general.csv`** at the **end** (after `os_releases` rows).
- Visible fields: align with what operators care about on the old grid (at minimum **Model**, **Cores**, **Logical**, **Current MHz**; include **Device ID** / **Socket** when multiple rows exist so blocks are distinguishable). Reuse formats from `cpu_info_machine.csv` where they exist (`mhz`, `number`, `text`).

### Multiple processors

- For each element returned by `CpuInfo.list(agent_id)`:
  - Emit the section’s field rows (same column schema, values from that row).
- **One CPU:** single block at the bottom (optional single **CPU** expander row, or flat indent-1 rows — match existing General section style).
- **More than one:** repeat the block; prefix or sub-label keys when needed (e.g. expander title **CPU** vs **CPU (socket 1)** / **CPU 2**, or leading **Device ID** row per block) so additional rows are not ambiguous.

### Overlap with `system_info` CPU fields

- Keep existing **System info** summary CPU fields for now unless a follow-up bug removes redundancy after General shows `cpu_info` at the bottom.
- Do not remove `cpu_info` sync or `CpuInfo.list` — only change where the controller displays it.

### Remove CPUs tab

- Drop **CPUs** from `Detail` (toggle group, `ViewStack`, `cpus_loaded`, refresh spinner binding).
- Remove or retire `controller/tab/Asset/Machine/CpuInfo.vala` if nothing else references it; **`Store.CpuInfo`** may move into `MachineGeneral.load` or stay as a small helper.
- Update `controller/tab/Asset/Machine/namespace.vala`, `controller/meson.build`, `docs/meson.build`, and doc comments that list **CPUs** as a detail tab.
- Update [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md) (and any plan text) that treats **CPUs** as a separate cached tab — after this change, CPU data loads with **General** (`general_loaded` only).

---

## Proposed fix (verbatim — review before apply)

### Apply order

1. `ColumnSchema.vala` — add `mhz` format for General key-value rows.
2. `machine_general.csv` — append `cpu_info` field rows.
3. `MachineGeneral.vala` — `CpuInfo.list` + `load_cpu_section` (one expander per processor).
4. `Detail.vala` — remove **CPUs** tab.
5. Remove `CpuInfo` tab/store + `cpu_info_machine.csv`; update meson, gresource, `namespace.vala`.
6. `docs/rpc-commands.md` + [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md) (drop `cpus_loaded` references).
7. Build / smoke.

---

### 1. `controller/store/ColumnSchema.vala` — `mhz` format

`Tab.Base` already formats megahertz for grids; General uses `ColumnSchema.display_value` only.

#### Add (inside `switch (this.format)`, before `case "status":`)

```vala
				case "mhz":
					var mhz = (int64) 0;
					if (prop.value_type == GLib.Type.INT64) {
						mhz = value.get_int64();
					}
					if (prop.value_type == GLib.Type.INT) {
						mhz = (int64) value.get_int();
					}
					if (mhz > 0) {
						ret.val = mhz.to_string("%'" + int64.FORMAT) + " MHz";
					}
					return ret;
```

#### Update class docstring `format` list

Mention `mhz` alongside `bytes`, `date`, `status`, `expander`.

---

### 2. `controller/resources/columns/machine_general.csv` — append after OS release rows

Field rows only (`Source` = `cpu_info`). Code emits the expander title per processor; do not add an `expander` row here.

```
1,Model,model,ON,0,text,off,cpu_info
1,Cores,number-of-cores,ON,0,number,off,cpu_info
1,Logical,logical-processors,ON,0,number,off,cpu_info
1,Current MHz,current-clock-speed,ON,0,mhz,off,cpu_info
1,Max MHz,max-clock-speed,ON,0,mhz,off,cpu_info
1,Manufacturer,manufacturer,ON,0,text,off,cpu_info
1,Socket,socket-designation,ON,0,text,off,cpu_info
```

---

### 3. `controller/store/MachineGeneral.vala`

#### Update class docstring

- `load` fetches `SystemInfo.list`, `OsVersion.list`, `OsReleases.list`, and **`CpuInfo.list`**.

#### Add to `load()` after `os_releases` section (before `this.items = this.built`)

```vala
			if (!yield this.load_cpu_section(agent_id)) {
				return;
			}
```

#### Add method

```vala
		/**
		 * Call ''CpuInfo.list'' and append one expander block per
		 * processor onto {@link built}.
		 *
		 * @param agent_id selected machine agent id
		 * @return false when superseded or failed
		 */
		private async bool load_cpu_section(int agent_id)
		{
			var epoch = this.epoch;
			OLLMrpc.Response response;
			try {
				response = yield this.app.rpc.call(new OLLMrpc.Request() {
					method = "CpuInfo.list",
					args = OLLMrpc.args("i", agent_id)
				});
			} catch (GLib.Error e) {
				if (epoch == this.epoch) {
					this.busy = false;
					this.failed("Could not load CpuInfo.list", e.message);
				}
				return false;
			}
			if (epoch != this.epoch) {
				return false;
			}
			if (response.error != null) {
				this.busy = false;
				this.failed("Could not load CpuInfo.list", response.error.message);
				return false;
			}
			if (!response.retval.type().is_a(typeof(Gee.ArrayList))) {
				return true;
			}
			var rows = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			if (rows.size == 0) {
				return true;
			}
			for (var i = 0; i < rows.size; i++) {
				var row = rows.get(i);
				var title = "CPU";
				if (rows.size > 1) {
					title = @"CPU $(i + 1)";
				}
				this.built.add(new KeyValue() {
					key = title,
					expander = true,
					expanded = true
				});
				foreach (var col in this.cols) {
					if (!col.visible || col.source != "cpu_info") {
						continue;
					}
					this.built.add(col.display_value(row));
				}
			}
			return true;
		}
```

`General.vala` — **no code change** (existing expander + indent rendering).

---

### 4. `controller/tab/Asset/Machine/Detail.vala` — drop **CPUs** tab

#### Update class docstring

Remove `{@link CpuInfo}` from the tab list.

#### Remove fields

```vala
		private Adw.Toggle cpus_toggle;
```

```vala
		private CpuInfo cpus;
```

```vala
		private bool cpus_loaded = false;
```

#### Remove constructor block (CPUs page + toggle + spinner bind)

From `this.cpus = new CpuInfo(window);` through `this.cpus.bind_property("refreshing", cpus_spin, "visible", GLib.BindingFlags.SYNC_CREATE);` (lines ~225–247 in current tree).

#### Remove (`notify["active-name"]` switch)

```vala
					case "cpus":
						if (this.cpus_loaded) {
							break;
						}
						this.cpus_loaded = true;
						this.cpus.load(this.current_agent_id);
						break;
```

#### Remove (`clear()` and `show_machine()` reset blocks)

Every `this.cpus_loaded = false;` line.

#### Remove (`show_machine()`, toggle group rebuild)

```vala
				this.group.add(this.cpus_toggle);
```

#### Remove (`show_machine()`, `previous` switch case)

```vala
					case "cpus":
```

#### Remove (`show_machine()`, active-tab switch)

```vala
				case "cpus":
					if (this.cpus_loaded) {
						break;
					}
					this.cpus_loaded = true;
					this.cpus.load(agent_id);
					break;
```

---

### 5. Remove files

- `controller/tab/Asset/Machine/CpuInfo.vala`
- `controller/store/CpuInfo.vala`
- `controller/resources/columns/cpu_info_machine.csv`

---

### 6. Build lists and gresource

#### `controller/meson.build` — Remove

```vala
	'store/CpuInfo.vala',
```

```vala
	'tab/Asset/Machine/CpuInfo.vala',
```

#### `docs/meson.build` — Remove

```vala
  '../controller/store/CpuInfo.vala',
```

```vala
  '../controller/tab/Asset/Machine/CpuInfo.vala',
```

#### `controller/resources/argusrm.gresource.xml` — Remove

```xml
    <file>columns/cpu_info_machine.csv</file>
```

#### `controller/tab/Asset/Machine/namespace.vala` — Replace doc list

Remove `and {@link CpuInfo}` from the namespace doc comment.

---

### 7. `docs/rpc-commands.md`

#### Replace (`CpuInfo.list` caller note)

```markdown
- ℹ️ The method is `shared/OSQuery/CpuInfo.vala`. `Store.CpuInfo` calls it.
```

With:

```markdown
- ℹ️ The method is `shared/OSQuery/CpuInfo.vala`. `Store.MachineGeneral` calls it for the per-machine **General** tab (one key-value block per processor).
```

---

### 8. Related doc touch-up

#### [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md)

- Problem bullet: drop **CPUs** from the cached-tab list (`General` + package tabs + `Interfaces` only).
- Evidence §2: remove `cpus_loaded` from the boolean list and from notification invalidation sketch (`general_loaded` covers CPU inventory after this change).
- Evidence §3: remove `CpuInfo.vala` from the store cache list (or note only sync/RPC remains on server).

---

### 9. Verification

- `meson compile -C build`, `meson test -C build`.
- Controller: select a machine → **General** scrolls to **CPU** expander(s) at the bottom with model/cores/MHz.
- Multi-socket fixture: `CpuInfo.list` returns `size > 1` → **CPU 1**, **CPU 2**, … expanders each with the same field set.
- Detail bar has no **CPUs** toggle; `general_loaded` still gates repeat `MachineGeneral.load`.

---

## Resolved decisions (was open questions)

- ✔️ **Multi-CPU layout:** one **Gtk.Expander** per `CpuInfo.list` row — title **CPU** when `rows.size == 1`, else **CPU 1**, **CPU 2**, … (ordered by `device_id`).
- ✔️ **`system_info` CPU summary:** keep existing **System info** `cpu-brand` / cores fields for now; dedupe in a follow-up if redundant.

---

## Conclusions

- ✔️ Root issue is **UX placement**, not missing data: `cpu_info` is synced and listed; the separate tab rarely earns its cost.
- ✔️ Implementation is mostly **controller**: CSV + `MachineGeneral` multi-row append + **Detail** tab removal; **no** server/RPC schema change.