# Machine detail: fold CPU inventory into General, drop CPUs tab

**Status:** ✅ closed 2026-11-14. `MachineGeneral` loads `CpuInfo.list` into General expander blocks; CPUs tab removed; `meson test` 6/6; build verified.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-machines-detail-pane.md](2026-11-13-FIXED-machines-detail-pane.md), [2026-11-14-FIXED-machine-general-store.md](2026-11-14-FIXED-machine-general-store.md), [2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)

---

## Problem

- 🔷 Per-machine **CPUs** tab duplicated rarely needed `cpu_info` grid UI when most hosts have one processor row.
- 🔷 Expected: show `cpu_info` at the bottom of **General** (one expander per `CpuInfo.list` row); remove the **CPUs** tab.

---

## Summary of changes

### Controller

- ✔️ `controller/resources/columns/machine_general.csv` — `cpu_info` source rows (model, cores, logical, MHz, manufacturer, socket).
- ✔️ `controller/store/ColumnSchema.vala` — `mhz` format for General key-value rows.
- ✔️ `controller/store/MachineGeneral.vala` — `load_cpu_section()` after OS release; title **CPU** or **CPU 1**, **CPU 2**, … when `rows.size > 1`.
- ✔️ `controller/tab/Asset/Machine/Detail.vala` — removed **CPUs** page, toggle, and `cpus_loaded`.
- ✔️ `controller/tab/Asset/Machine/namespace.vala` — doc list updated.

### Removed

- 🚫 `controller/tab/Asset/Machine/CpuInfo.vala`, `controller/store/CpuInfo.vala`, `controller/resources/columns/cpu_info_machine.csv` (shared `shared/OSQuery/CpuInfo.vala` and `CpuInfo.list` unchanged).

### Build / docs

- ✔️ `controller/meson.build`, `docs/meson.build`, `controller/resources/argusrm.gresource.xml`.
- ✔️ `docs/rpc-commands.md` — `Store.MachineGeneral` caller for `CpuInfo.list`.
- ✔️ [2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md) — no `cpus_loaded`; CPU cache tied to `general_loaded`.

---

## Resolved decisions

- ✔️ One **Gtk.Expander** per processor; ordered by `device_id`.
- ✔️ Keep **System info** summary CPU fields for now (dedupe optional follow-up).

---

## Verification

- ✔️ `meson compile -C build`, `meson test -C build` (6/6).

---

## Next

- ℹ️ Optional: hide redundant `system_info` CPU summary after General `cpu_info` blocks are sufficient.
- ℹ️ `event.osquery` invalidation should reset `general_loaded` to refresh CPU data ([2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)).