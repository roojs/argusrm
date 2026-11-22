# Installed software matrix — XLSX export (investigation)

**Status:** ✅ archived 2026-11-22 — libxlsxwriter chosen; POC removed. **Implementation:** [2026-11-22-installed-software-xlsx-export.md](../2026-11-22-installed-software-xlsx-export.md)

**Pointer:** `docs/bug-fix-process.md`, [../plans/done/5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [2026-11-14-software-filters-remaining.md](../2026-11-14-software-filters-remaining.md), [done/2026-11-14-FIXED-software-package-machines-grid.md](2026-11-14-FIXED-software-package-machines-grid.md), [../rpc-commands.md](../rpc-commands.md)

**Related PHP (fallback port):** `/home/alan/gitlive/web.Texon/pear/Document/Excel.php` and `/home/alan/gitlive/web.Texon/pear/Document/Excel/` (~1k lines, LGPL-3.0, streams rows then zips OOXML).

**Outcome:** ✔️ **libxlsxwriter** via object-oriented `vapi/xlsxwriter.vapi`. ✔️ Throwaway `tests/xlsxwriter-poc.vala` deleted after it proved Vala linkage. 🚫 Document_Excel port not needed unless libxlsxwriter packaging fails on Windows.

---

## Problem

- 🔷 **Expected:** Before rolling Argus out to a large set of Windows PCs, an operator can download an **Excel `.xlsx`** that lays out installed software as a **matrix**: package names down the left, machines across the top (machine name and logged-in user, or a combined label), and **version** (or empty) in each cell. The grid should be usable for spot-checking version drift across the fleet without clicking every package in the Software tab.
- 🚫 **Actual:** The Windows Software grid (`Programs.list` with `agent_id = 0`) is **one row per package name** with aggregate min/max version and install count. Per-machine detail exists only through **`Programs.machines`** / **`PackageMachine.machines`** — one package at a time in a dialog. There is no export and no writer library in the Argus tree.

---

## Evidence

- ✔️ Windows inventory is `programs` rows synced from the agent ([`shared/OSQuery/Programs.vala`](../../../shared/OSQuery/Programs.vala)). Row identity in the UI is **`source` + `name`** (and related fields on the aggregate list).
- ✔️ Machine display naming and logged-in users for the Software drill-down match **`Argus.Shared.SQV.PackageMachine`**: `machine` from `system_info.computer_name` / `agent.hostname` / fallbacks; `logged_in_users` from live `logged_in_users` ([`shared/SQV/PackageMachine.vala`](../../../shared/SQV/PackageMachine.vala), server SQL in `server/SQV/PackageMachine.vala`).
- ✔️ The controller already uses **`Gtk.FileDialog`** for filesystem paths ([`controller/dialog/Upload.vala`](../../../controller/dialog/Upload.vala)) — a natural pattern for **Save as…** on export.
- ℹ️ Existing RooJS XLSX code lives in **Texon** (`Document_Excel`), not in Argus.

---

## Target worksheet (v1)

| | Machine A (user1) | Machine B (user2, user3) | … |
| --- | --- | --- | --- |
| **programs** / Package Foo | 1.2.3 | | |
| **appx** / Contoso App | 2024.1 | 2024.1 | |
| … | | | |

---

## Data / RPC gap

| Call | What it returns |
| --- | --- |
| `Programs.list(0)` | Aggregates by `(source, name)` — not enough for the grid |
| `Programs.list(agent_id)` | One agent's rows — N round-trips for N machines |
| `Programs.machines(name, source)` | One package, all machines — M round-trips for M packages |
| `PackageMachine.machines` | Same as above, with `machine` / `logged_in_users` |

**Options:** new `Programs.matrix` RPC (preferred) vs controller pivot vs 🚫 per-package loops.

---

## XLSX writer options (C / Vala stack)

**Chosen:** [libxlsxwriter](https://github.com/jmcnamara/libxlsxwriter) (BSD-2-Clause). **Fallback if packaging fails:** port Texon `Document_Excel`.

| Option | Verdict |
| --- | --- |
| libxlsxwriter | ✔️ selected |
| Document_Excel port | fallback |
| CSV only | 🚫 not deliverable |
| PhpSpreadsheet / LibreOffice | 🚫 |