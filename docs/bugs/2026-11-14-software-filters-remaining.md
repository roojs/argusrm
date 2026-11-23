# Software Assets: remaining filter and bar work

**Status:** ⏳ opened — Debian phase-1 bar shipped; items below are separate small tasks

**Pointer:** `docs/bug-fix-process.md`, [../plans/done/5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [5.9.2.1-DONE-debian-filters-phase1.md](../plans/done/5.9.2.1-DONE-debian-filters-phase1.md), [2026-11-14-debian-package-change-filter.md](2026-11-14-debian-package-change-filter.md), [../plans/done/5.10-DONE-data-enrichment.md](../plans/done/5.10-DONE-data-enrichment.md), [1.2-aim-debian-update.md](../plans/1.2-aim-debian-update.md)

---

## Problem

- 🔷 Software phase 1 (three aggregate grids) is in the tree. Debian, RPM, and Windows each have a filter bar on the software page and on the machine page. Several filter behaviours drawn in [5.5](../plans/5.5-controller-user-interface.md) and [1.2](../plans/1.2-aim-debian-update.md) are not implemented on Software.
- 🔷 Track remaining UI in this file and linked bugs (no separate filter plan).

---

## Inventory

| Item | Platform | State |
| --- | --- | --- |
| Search + section + Versions differ + remove column | Debian | ✔️ shipped |
| **Change / Recent changes** | Debian | ⏳ [2026-11-14-debian-package-change-filter.md](2026-11-14-debian-package-change-filter.md) |
| Rubbish bin **click** → Remove task | Debian | ⏳ icon only; [5.5](../plans/5.5-controller-user-interface.md) / tasks |
| Hide secondary binaries of one source package | Debian | ⏳ not started |
| Search + Update pending + Versions differ | RPM | ✔️ software and machine bars |
| Search + Can uninstall + Versions differ | Windows | ✔️ software and machine bars |
| **Which rows are “installed program”** (`programs.source` on fleet grid; snapshot unions services/startup) | Windows | ⏳ spec not written — [5.9.2](../plans/5.9.2-assets-software-filters.md); symptom [2026-11-23-ISSUE-programs-windows-installed-vs-noise.md](2026-11-23-ISSUE-programs-windows-installed-vs-noise.md); Debian analogue: **Hide secondary binaries** (below) |
| **Needs updating** (`update_since` > 0 on aggregate row) | Debian/RPM | ⏳ data on RPC; no column/filter on Software grid |
| Saved filters replace temp bar | All | ⏳ [5.7](../plans/5.7-list-filters.md) |

---

## Evidence

✔️ Debian: `controller/tab/Asset/DebPackages.vala`, `controller/filter/DebPackages.vala`.

✔️ RPM: `controller/filter/RpmPackages.vala`, `controller/tab/Asset/RpmPackages.vala`, `controller/tab/Asset/Machine/RpmPackages.vala`. Search matches the package name. Filters is Update pending (`update_since` > 0), off by default. Software also has Versions differ.

✔️ Windows: `controller/filter/Programs.vala`, `controller/tab/Asset/Programs.vala`, `controller/tab/Asset/Machine/Programs.vala`. Search matches the program name and the publisher. Filters is Can uninstall, off by default. Software also has Versions differ.

✔️ `update_since` on `DebPackages` / `RpmPackages` from `package_updates` ([2026-11-13-FIXED-package-updates.md](done/2026-11-13-FIXED-package-updates.md)); not in `controller/resources/columns/deb_packages.csv`.

ℹ️ **Versions differ** is machine version spread, not package-manager pending updates ([5.10](../plans/done/5.10-DONE-data-enrichment.md)).

⏳ **Windows fleet scope (2026-11-23):** [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala) stores multiple `source` values in one table; the grid aggregates all of them. Example counts on a fleet DB copy: `service` 641, `programs` 233, `appx` 127, `startup` 12 — see [2026-11-23-ISSUE-programs-windows-installed-vs-noise.md](2026-11-23-ISSUE-programs-windows-installed-vs-noise.md). Product intent for the Windows sub-tab is still [5.9](../plans/done/5.9-DONE-assets-software.md) (“one installed program”). Executable hash lookup is [2026-11-21-processes-exe-enrichment.md](2026-11-21-processes-exe-enrichment.md), not this grid.

---

## Proposed fix (by task — implement as separate commits)

1. **RPM / Windows bars** — ✔️ search plus a Filters menu on the software page and the machine page. Software also has Versions differ. RPM's tick is Update pending. Windows' tick is Can uninstall. Both ticks start off.
2. **Needs updating** — visible column and/or bar toggle on Debian and RPM; wire `Filters.*.match` to `update_since`.
3. **Secondary packages** — Debian-only filter rule (source/namesake); do not suffix-heuristic hide `-dev` (per old plan LLM notes).
4. **Windows `programs.source` scope** — write fields in [5.9.2](../plans/5.9.2-assets-software-filters.md), then implement in `controller/filter/Programs.vala` (and SQL/list only if the spec says so). Symptom and counts: [2026-11-23-ISSUE-programs-windows-installed-vs-noise.md](2026-11-23-ISSUE-programs-windows-installed-vs-noise.md).
5. **Bin click** — depends on task UI / signing; link [done/2026-11-15-FIXED-machines-package-update-phase4-ui.md](done/2026-11-15-FIXED-machines-package-update-phase4-ui.md) when Remove exists.

---

## Next

- ⏳ Pick next slice: **needs updating** column vs **secondary packages** vs **Windows source scope** (write 5.9.2 Windows section first). RPM and Windows phase-1 bars are in the tree.
- ⏳ Close sub-items in this file or spin separate dated bugs when a slice grows.

---

## LLM notes

- 🚫 Do not put controls in the window header ([no-header-bar-controls](.cursor/rules/no-header-bar-controls.mdc)).
- 🚫 Do not implement the package machines dialog here — [2026-11-14-software-package-machines-grid.md](done/2026-11-14-FIXED-software-package-machines-grid.md).