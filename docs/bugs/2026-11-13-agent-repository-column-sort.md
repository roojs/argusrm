# Agent and Repository column sorting (migrate to Base)

**Status:** ⏳ root cause confirmed; apply hunks incomplete — see **Proposed fix**

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md` (**Edit syntax contract**, **Code proposals — one place, not two**), [2026-11-11-FIXED-column-sort.md](done/2026-11-11-FIXED-column-sort.md)

---

## Problem

- 🔷 A left click on a column header on **Agents** (`controller/tab/Agent.vala`) and **Repositories** (`controller/tab/Repository.vala`) sorts that column; the next click reverses the order.
- 🔷 Both grids use `Argus.Controller.Tab.Base` (`column_grid`) and column CSV files (`agent.csv`, `repository.csv`), not per-column sorters in each tab.
- 🔷 On **Agents**, Remove must read `this.grid.model` (`Gtk.MultiSelection` over `Gtk.SortListModel`) so the removed row is the ticked row after a sort.

## Evidence

- ✔️ `Agent.vala` and `Repository.vala` build columns manually; no `column.sorter`, no `Gtk.SortListModel`.
- ✔️ `Agent.vala:480-485` indexes `this.store` while `this.selection` tracks store order, not sorted view order.
- ✔️ `Base.column_menu()` already denies the header menu when the pick hits `argus-grid-row` (`Base.vala:150-158`). `Agent` still tags `argus-agent-row` until it uses `column_grid`.

## Root cause

- ✔️ `Agent` and `Repository` do not call `column_grid`.
- ✔️ `Base.column_factory()` lacks `recent-date`, `dim-text`, Kind highlight, and live `notify` refresh for in-place agent row updates.

## Proposed fix

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding lines before applying.

- 🔷 Migrate tabs on the same pattern as `controller/tab/Tasks.vala` and `controller/tab/Asset/SystemInfo.vala` (`Base`, `table`, `expand_column`, `column_grid`).
- 🔷 Header vs row right-click: keep `Base.column_menu()`; row menu uses `argus-grid-row`.
- 🔷 Formats: `recent-date`, `dim-text`, `tick` with `notify` on the bound property; Kind uses `argus-controller-fingerprint` on the grid.
- 🔷 Repository: `display_name` on `ScriptRepository`; `(Gtk.SingleSelection) this.grid.model` with `autoselect = false`, `can_unselect = true`.
- 🚫 Per-column `column.sorter` in `Agent.vala` / `Repository.vala`.

- 💩 ⏳ **Agent / Repository constructor migration** and **`Base.column_factory` extensions** need full **Remove** + **Replace with** regions (no `…` in fences) before apply — same standard as `docs/plans/done/5.10-DONE-data-enrichment.md` **Why / Where / Depends on** per `###`. Until those hunks are written, only the **Add** sections below are mechanical.

### 1. `controller/resources/columns/agent.csv` — new column file

**Why:** `column_menu` reads `table` + CSV; sort flags live in the file like asset grids.

**Where:** new file under `controller/resources/columns/`.

**Depends on:** none.

#### Add — new file `controller/resources/columns/agent.csv`

```
Column header | Database name [JSON] | Visible | Width | Format | Sort

Hostname,display-name,ON,0,text,ON
Address,ip,ON,0,text,ON
User,username,ON,0,text,ON
Kind,display-kind,ON,0,text,ON
Registered,status,off,90,tick,ON
Registered on,created,ON,0,recent-date,ON
Connected,connected,ON,90,tick,ON
Last connected,last-connected,ON,0,recent-date,ON
```

### 2. `controller/resources/columns/repository.csv` — new column file

**Why:** Repository grid uses the same Base column path.

**Where:** new file under `controller/resources/columns/`.

**Depends on:** none.

#### Add — new file `controller/resources/columns/repository.csv`

```
Column header | Database name [JSON] | Visible | Width | Format | Sort

Name,display-name,ON,0,text,ON
URL,url,ON,0,dim-text,ON
```

### 3. `controller/resources/argusrm.gresource.xml` — register column CSVs

**Why:** bundled columns must be in the gresource.

**Where:** inside `<gresource>`, with the other `columns/*.csv` entries.

**Depends on:** ### 1, ### 2.

#### Add — after existing `columns/task_targets.csv` entry

```xml
    <file>columns/agent.csv</file>
    <file>columns/repository.csv</file>
```

### 4. `shared/SQT/ScriptRepository.vala` — `display_name`

**Why:** Name column sorts and shows `url` when `name` is empty.

**Where:** after the `key` property.

**Depends on:** none.

#### Add — after `public string key { get; set; default = ""; }`

```vala
		/**
		 * ''name'' when set, otherwise ''url''.
		 */
		public string display_name {
			owned get {
				if (this.name != "") {
					return this.name;
				}
				return this.url;
			}
		}
```

### 5. `controller/tab/Agent.vala` — `remove_rows.activate`: selection over sorted model

**Why:** after `column_grid`, selection indices follow the sorted view, not the store.

**Where:** `remove_rows.activate.connect` body, the loop that collects `names` and `ids`.

**Depends on:** Agent tab uses `column_grid(this.store, true)` (🔷 💩 ⏳ ctor hunks not written yet).

#### Remove

```vala
				var count = (int) this.store.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!this.selection.is_selected((uint) i)) {
						continue;
					}
					var row = this.store.get_item((uint) i) as Argus.Shared.Agent;
```

#### Replace with

```vala
				var selection = (Gtk.MultiSelection) this.grid.model;
				var count = (int) selection.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!selection.is_selected((uint) i)) {
						continue;
					}
					var row = selection.get_item((uint) i) as Argus.Shared.Agent;
```

### 6. `controller/tab/Base.vala` — `column_factory` formats

**Why:** CSV references `recent-date` and `dim-text`; agent cells refresh without `items_changed`.

**Where:** `column_factory` setup/bind/unbind; docblock on `column_factory`.

**Depends on:** ### 1.

- 💩 ⏳ **🔷** Write one canonical **Remove** + **Replace with** (or ordered chunks) for `column_factory` here before product edits — no summary bullets in place of fences.

### 7. `controller/tab/Agent.vala` — migrate constructor to `Base`

**Why:** sorting, column menu, and `argus-grid-row` tagging come from `column_grid`.

**Where:** class declaration; constructor grid setup (replace manual factories/columns/view).

**Depends on:** ### 1, ### 6.

- ℹ️ Precedent: `controller/tab/Tasks.vala` (`Object(table: …)`, `column_grid`, row gestures on `this.grid`).
- 💩 ⏳ **🔷** Full ctor **Remove** + **Replace with** still owed (large region — follow **guide-to-writing-plans.md** *Large replacement*).

### 8. `controller/tab/Repository.vala` — migrate constructor to `Base`

**Why:** same as Agents.

**Where:** class declaration; constructor grid setup; then `SingleSelection` flags on `this.grid.model`.

**Depends on:** ### 2, ### 3, ### 4, ### 6.

- ℹ️ Precedent: `Tasks.vala` lines that set `autoselect` / `can_unselect` after `column_grid`.
- 💩 ⏳ **🔷** Full ctor **Remove** + **Replace with** still owed.

## Attempts

- ℹ️ Split from [2026-11-11-FIXED-column-sort.md](done/2026-11-11-FIXED-column-sort.md) (sections 7–8) on 2026-11-13.
- ℹ️ 2026-11-14: first proposal draft used invalid fences (`…`, prose **Replace**/**With**); revised to match **guide-to-writing-plans.md**.

## Next

- 🔷 ⏳ Finish **### 6–8** verbatim hunks, then apply 1–8; `ninja -C build controller/argusrm-controller`.
- 🔷 ⏳ Sort, tick an agent, sort again, Remove — removed row matches tick.
- 🔷 ⏳ Row right-click → Remove; header/empty right-click → column menu.