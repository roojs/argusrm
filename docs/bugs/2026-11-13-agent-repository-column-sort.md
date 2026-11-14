# Agent and Repository column sorting (migrate to Base)

**Status:** ⏳ split from [2026-11-11-FIXED-column-sort.md](done/2026-11-11-FIXED-column-sort.md); open points to confirm before applying

**Pointer:** `docs/bug-fix-process.md`, [2026-11-11-FIXED-column-sort.md](done/2026-11-11-FIXED-column-sort.md)

---

## Problem

- 🔷 A left click on a column header on the **Agents** (`controller/tab/Agent.vala`) and **Repositories** (`controller/tab/Repository.vala`) grids sorts that column, and the next click reverses the order.
- 🔷 Both grids use `Argus.Controller.Tab.Base` (`column_grid`) and column CSV files (`agent.csv`, `repository.csv`) rather than hardcoding column sorters per grid.
- 🔷 On **Agents**, Remove reads `this.grid.model` (`Gtk.MultiSelection` over `Gtk.SortListModel`) so a sorted row is the row that was ticked, rather than indexing `this.store` directly.

## Evidence

- ✔️ `controller/tab/Agent.vala` and `controller/tab/Repository.vala` build their `Gtk.ColumnViewColumn` instances manually with `resizable` (and `expand = true`) and never set `column.sorter`, nor wrap `this.store` in a `Gtk.SortListModel`.
- ✔️ `controller/tab/Agent.vala:479-490` walks `this.store` by index `0 .. count` and calls `this.selection.is_selected((uint) i)`. Those indexes match only while the selection model's order is the store's order.
- ✔️ `controller/tab/Base.vala` (`column_menu`) attaches a `Gtk.GestureClick` (`button = Gdk.BUTTON_SECONDARY`, `propagation_phase = Gtk.PropagationPhase.CAPTURE`) directly to `this.grid`, which currently claims every right-click on the grid (headers and data rows). On `Agent`, right-clicking a data row must still open the row `Remove` menu.

## Root cause

- ✔️ Neither `Agent` nor `Repository` uses `Base.column_grid` / `Base.column_menu`, and `Base` does not yet separate header right-clicks from data-row right-clicks or support `Agent`/`Repository`-specific cell formatting (`recent-date`, `tick`, `argus-this-controller` highlight, `Repository` empty-name fallback and `dim-label`).

## Proposed fix

- 🔷 Migrate `Agent` and `Repository` to `Argus.Controller.Tab.Base` (`column_grid`) with `agent.csv` and `repository.csv`.
- 🔷 Remove in `Agent` reads `this.grid.model` (`Gtk.MultiSelection`) instead of `this.store`:

```vala
				var selection = (Gtk.MultiSelection) this.grid.model;
				var count = (int) selection.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!selection.is_selected((uint) i)) {
						continue;
					}
					var row = selection.get_item((uint) i) as Argus.Shared.Agent;
```

- 💩 `controller/resources/columns/agent.csv` (and add to `controller/resources/argusrm.gresource.xml`):

```
Column header  |  Database name [JSON]  |  ON or off  |  Width in pixels  |  Format  |  Sort

Hostname,display-name,ON,0,text,ON
Address,ip,ON,0,text,ON
User,username,ON,0,text,ON
Kind,display-kind,ON,0,text,ON
Registered,status,off,90,tick,ON
Registered on,created,ON,0,recent-date,ON
Connected,connected,ON,90,tick,ON
Last connected,last-connected,ON,0,recent-date,ON
```

- 💩 `controller/resources/columns/repository.csv` (and add to `controller/resources/argusrm.gresource.xml`):

```
Column header  |  Database name [JSON]  |  ON or off  |  Width in pixels  |  Format  |  Sort

Name,name,ON,0,text,ON
URL,url,ON,0,text,ON
```

- 💩 Open points to confirm before writing the exact code hunks:
  - 💩 Restrict `Base.column_menu()`'s secondary-click capture to header / empty grid space (skipping tagged data-row widgets, e.g. `argus-grid-row` / `argus-agent-row`, also tracked in `docs/bugs/2026-11-13-machines-package-update.md` and `docs/plans/7.2-tasks-ui-and-signing.md`) so right-clicking a row on `Agent` still opens `Remove`.
  - 💩 Decide how `Base.column_factory()` handles `Agent`'s `recent-date` (`%H:%M` today, `%Y-%m-%d` otherwise), `tick` (`status == 1` / `connected` bool), live updates when `Store.Agent.load()` mutates `status`, `last_connected`, and `connected` in place without `items_changed`, and the `"argus-this-controller"` CSS highlight on `Kind`.
  - 💩 `Repository`: `ScriptRepository.display_name` (or fallback to `url` when `name == ""`), `"dim-label"` on `URL`, and `autoselect = false` / `can_unselect = true` on `(Gtk.SingleSelection) this.grid.model`.
- 🚫 Hardcoding `column.sorter` column-by-column in `Agent.vala` and `Repository.vala`.

## Attempts

- ℹ️ Split out from [2026-11-11-FIXED-column-sort.md](done/2026-11-11-FIXED-column-sort.md) (sections 7–8) on 2026-11-13 so the four asset grids (`Machines`, `Debian`, `RPM`, `Windows`) can close separately.

## Next

- ⏳ 🔷 Confirm the open points above for `Base.column_menu` row-click pass-through, `Agent` formatting/live binding, and `Repository` formatting.
- ⏳ 💩 Write verbatim `Remove` / `Replace with` / `Add` code proposals once confirmed.
- ⏳ 🔷 Sort, then remove a ticked agent. The removed row is the one that was ticked.
