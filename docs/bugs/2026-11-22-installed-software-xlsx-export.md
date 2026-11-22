# Windows Software — matrix export to XLSX

**Status:** ⏳ opened

**Pointer:** `docs/bug-fix-process.md`, [done/2026-11-21-DONE-installed-software-xlsx-investigation.md](done/2026-11-21-DONE-installed-software-xlsx-investigation.md), [../plans/done/5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [2026-11-14-software-filters-remaining.md](2026-11-14-software-filters-remaining.md), [`controller/resources/columns/programs.csv`](../../controller/resources/columns/programs.csv), [`vapi/xlsxwriter.vapi`](../../vapi/xlsxwriter.vapi)

**Supersedes:** investigation and throwaway POC in [done/2026-11-21-DONE-installed-software-xlsx-investigation.md](done/2026-11-21-DONE-installed-software-xlsx-investigation.md). **Writer:** libxlsxwriter (BSD), Vala bindings under `vapi/`.

---

## Problem

- 🔷 **Expected:** On the Windows **Software** tab, an operator downloads a fleet **matrix** `.xlsx`: application identity on the left, one column per machine, **version** (or blank) in each cell — for rollout sign-off without opening every package dialog.
- 🚫 **Actual:** Aggregate grid and per-name drill-down only; no export.

---

## Phases

| Phase | Deliverable | Status |
| --- | --- | --- |
| **1** | Object-oriented `vapi/xlsxwriter.vapi` + Meson/pkg-config wiring when controller links libxlsxwriter | ⏳ in progress |
| **2** | Frozen **layout spec** (row keys, headers, data/RPC, styling rules) | ⏳ design |
| **3** | **Export** control on Windows Software page bar + `Gtk.FileDialog` save | 🚫 blocked on 2 |

---

## Phase 1 — Vala bindings (libxlsxwriter)

- 🔷 **API style:** `new Lxw.Workbook (path)`, `book.add_worksheet ()`, `sheet.write_string (...)`, `book.close ()` — not bare `workbook_new` at call sites.
- 🔷 **Surface in tree:** `vapi/xlsxwriter.vapi` — `Workbook`, `Worksheet`, `Format`, `Error`, `Color`, `Alignment`, `Pattern`, `strerror`, writes / freeze / column width.
- 🔷 **Vala ownership:** libxlsxwriter is not refcounted — `vapi/xlsxwriter_shim.h` and [`shared/xlsxwriter_vala_unref.c`](../../shared/xlsxwriter_vala_unref.c) supply a no-op `lxw_workbook_unref` for scope cleanup; **always** call `close()` to flush the file.
- 🔷 **Build (Phase 3):** `vapi/xlsxwriter.deps` → pkg-config `xlsxwriter`; `--vapidir` → repo `vapi/`; link `xlsxwriter_vala_unref.c` and `-I` to `vapi/` on any target using `Lxw`.
- ✔️ **Spike discarded:** `tests/xlsxwriter-poc.vala` removed.
- ⏳ **Done criterion:** controller Meson wires dependency + shim (with Phase 3 or a compile smoke target).

---

## Phase 2 — Worksheet layout (decide before code)

### Matrix shape

| Region | Content |
| --- | --- |
| **Row identity (left, frozen)** | One or more columns describing each installed product row — **not** a single undocumented string. |
| **Column headers (top, frozen)** | One column per machine (see `PackageMachine.machine` + logged-in users pattern). |
| **Body** | `version` when that `(source, name)` is on that machine; empty cell otherwise. |

### Row identity — use `programs.csv`

The Software grid already defines columns in [`controller/resources/columns/programs.csv`](../../controller/resources/columns/programs.csv). Phase 2 should **reuse that schema** (via `Argus.Controller.Store.ColumnSchema` / the same loader as `Tab.Base`) rather than invent parallel labels.

**Default proposal (confirm with operator):**

| Export column | CSV `Database name` | Visible in grid | In export matrix left block |
| --- | --- | --- | --- |
| Platform | `source` | ON | ✔️ always (programs / appx / chocolatey / …) |
| Name | `name` | ON | ✔️ always |
| Publisher | `publisher` | ON | ✔️ recommended |
| Scope | `scope` | ON | 💩 optional — include if rollout cares user vs system |
| Others | identifying-number, install-location, … | off in CSV | 🚫 omit in v1 unless we add an export profile |

- 🔷 **Sort order:** match Software grid default — `source`, then `name` (same as aggregate SQL).
- 🔷 **Row key for pivot:** `(source, name)`; other left columns are display only.
- 🔷 **Header row for machines:** row 0 — machine name; row 1 optional second line for `logged_in_users` (same strings as [`PackageMachine`](../../shared/SQV/PackageMachine.vala)). Pick **one row vs two** before Phase 3.
- 🔷 **Version cells:** text from `programs.version`; no `maxver` red styling in v1 unless cheap via `Format` (mirror grid rule later).
- 💩 **Filtered export:** export rows/columns matching current **Programs** filter bar vs entire fleet — default TBD.

### Data / RPC (layout depends on fleet size)

From [investigation](done/2026-11-21-DONE-installed-software-xlsx-investigation.md):

1. 🔷 **Preferred:** new server RPC (e.g. `Programs.matrix` or dedicated struct) — one query: live `programs` × machine display columns.
2. 🔷 **Fallback:** single “all agents, all live rows” list + controller pivot — acceptable only for small fleets.

🚫 Per-package `Programs.machines` loops.

Document chosen RPC in `docs/rpc-commands.md` in the same change as Phase 3.

---

## Phase 3 — UI

- 🔷 **Where:** Windows [`controller/tab/Asset/Programs.vala`](../../controller/tab/Asset/Programs.vala) / [`controller/filter/Programs.vala`](../../controller/filter/Programs.vala) — **page bar**, not window header ([no-header-bar-controls](.cursor/rules/no-header-bar-controls.mdc)).
- 🔷 **Action:** e.g. **Export…** → `Gtk.FileDialog` save (pattern [`controller/dialog/Upload.vala`](../../controller/dialog/Upload.vala)); default `Argus-Windows-Software-YYYY-MM-DD.xlsx`.
- 🔷 **Flow:** fetch matrix data → build sheet with Phase 2 layout → `Lxw.Workbook` → close → toast or error dialog on failure (`Lxw.strerror`).
- ℹ️ Debian/RPM matrix exports reuse Phases 1–3 later with `deb_packages.csv` / `rpm_packages.csv`.

---

## Open questions (Phase 2 sign-off)

- 💩 One or two header rows for machines?
- 💩 How many left columns from `programs.csv` (minimal: source + name only)?
- 💩 Export filtered view or full fleet?
- 💩 libxlsxwriter shared vs static on Windows controller build?

---

## Next

1. Finish Phase 1 (bindings + controller Meson when linking).
2. Operator answers open questions; lock layout section.
3. Implement RPC (if any) + Phase 3.