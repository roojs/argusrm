# Software Assets: remaining filter and bar work

**Status:** ⏳ opened — Debian phase-1 bar shipped; items below are separate small tasks

**Pointer:** `docs/bug-fix-process.md`, [../plans/done/5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [5.9.2.1-DONE-debian-filters-phase1.md](../plans/done/5.9.2.1-DONE-debian-filters-phase1.md), [2026-11-14-debian-package-change-filter.md](2026-11-14-debian-package-change-filter.md), [../plans/done/5.10-DONE-data-enrichment.md](../plans/done/5.10-DONE-data-enrichment.md), [1.2-aim-debian-update.md](../plans/1.2-aim-debian-update.md)

---

## Problem

- 🔷 Software phase 1 (three aggregate grids) is in the tree. Debian has a minimal filter bar. RPM and Windows have **no** bar. Several filter behaviours drawn in [5.5](../plans/5.5-controller-user-interface.md) and [1.2](../plans/1.2-aim-debian-update.md) are not implemented on Software.
- 🔷 Track remaining UI in this file and linked bugs (no separate filter plan).

---

## Inventory

| Item | Platform | State |
| --- | --- | --- |
| Search + section + Versions differ + remove column | Debian | ✔️ shipped |
| **Change / Recent changes** | Debian | ⏳ [2026-11-14-debian-package-change-filter.md](2026-11-14-debian-package-change-filter.md) |
| Rubbish bin **click** → Remove task | Debian | ⏳ icon only; [5.5](../plans/5.5-controller-user-interface.md) / tasks |
| Hide secondary binaries of one source package | Debian | ⏳ not started |
| Filter bar (fields TBD) | RPM | ⏳ not started |
| Filter bar (fields TBD) | Windows | ⏳ not started |
| **Needs updating** (`update_since` > 0 on aggregate row) | Debian/RPM | ⏳ data on RPC; no column/filter on Software grid |
| Saved filters replace temp bar | All | ⏳ [5.7](../plans/5.7-list-filters.md) |

---

## Evidence

✔️ Debian: `controller/tab/Asset/DebPackages.vala`, `controller/filter/DebPackages.vala`.

🚫 No `controller/filter/RpmPackages.vala` or `Programs.vala`.

✔️ `update_since` on `DebPackages` / `RpmPackages` from `package_updates` ([2026-11-13-FIXED-package-updates.md](done/2026-11-13-FIXED-package-updates.md)); not in `controller/resources/columns/deb_packages.csv`.

ℹ️ **Versions differ** is machine version spread, not package-manager pending updates ([5.10](../plans/done/5.10-DONE-data-enrichment.md)).

---

## Proposed fix (by task — implement as separate commits)

1. **RPM / Windows bars** — mirror Debian patterns where they apply (search + platform-specific facets); write bar spec in this bug before code if fields differ from Debian.
2. **Needs updating** — visible column and/or bar toggle on Debian and RPM; wire `Filters.*.match` to `update_since`.
3. **Secondary packages** — Debian-only filter rule (source/namesake); do not suffix-heuristic hide `-dev` (per old plan LLM notes).
4. **Bin click** — depends on task UI / signing; link [2026-11-13-machines-package-update.md](2026-11-13-machines-package-update.md) when Remove exists.

---

## Next

- ⏳ Pick next slice: RPM bar vs **needs updating** vs secondary packages.
- ⏳ Close sub-items in this file or spin separate dated bugs when a slice grows.

---

## LLM notes

- 🚫 Do not put controls in the window header ([no-header-bar-controls](.cursor/rules/no-header-bar-controls.mdc)).
- 🚫 Do not implement the package machines grid here — [2026-11-14-software-package-machines-grid.md](2026-11-14-software-package-machines-grid.md).