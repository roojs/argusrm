# Machine detail: fold CPU inventory into General, drop CPUs tab

**Status:** ⏳ opened — design approved in conversation; implementation not started

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

## Proposed fix (sketch — review before apply)

1. **`machine_general.csv`:** add `cpu_info` `Source` section at the bottom; field list per design above.
2. **`MachineGeneral.vala`:** `yield` `CpuInfo.list` for `agent_id`; add `load_cpu_section` (or extend `load_section`) to loop **all** rows and append `ColumnSchema.display_value` for each.
3. **`General.vala`:** no layout change expected if store emits the right `KeyValue` sequence (existing expander + indent rendering).
4. **`Detail.vala`:** remove CPUs tab and related state; **General** load already runs on first General visit — ensure `MachineGeneral.load` includes CPU RPC in that path.
5. **Cleanup:** drop unused `CpuInfo` tab from meson/gresource if the grid tab is deleted; keep `cpu_info_machine.csv` only if still referenced (else remove from gresource).
6. **Build / smoke:** open machine detail → **General** shows CPU block(s) at bottom; multi-socket test agent (or DB fixture) shows multiple blocks; **CPUs** tab gone.

---

## Open questions

- 💩 Single expander **CPU** with flat children vs one expander per socket when `rows.size > 1`.
- 💩 Whether to hide redundant `system_info` CPU summary fields once `cpu_info` is always shown at the bottom.

---

## Conclusions

- ✔️ Root issue is **UX placement**, not missing data: `cpu_info` is synced and listed; the separate tab rarely earns its cost.
- ✔️ Implementation is mostly **controller**: CSV + `MachineGeneral` multi-row append + **Detail** tab removal; **no** server/RPC schema change.