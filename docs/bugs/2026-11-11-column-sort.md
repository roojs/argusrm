# Column headers do not sort

**Status:** ⏳ sections 1–6 applied; `Agent` & `Repository` migration + UI verify open

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 A left click on a column header sorts that column.
- 🔷 The next click on that header reverses the order.
- 🔷 The order is the column's value. A size sorts by its byte count. A count sorts by the count.
- ℹ️ The grids are Machines, Debian, RPM, Windows, Agents, and Repositories.

## Evidence

- ✔️ `controller/tab/Base.vala` builds each `Gtk.ColumnViewColumn` with `resizable` and `visible` only. `column.sorter` is never set.
- ✔️ `controller/tab/Agent.vala` and `controller/tab/Repository.vala` do the same.
- ✔️ No grid wraps its rows in a `Gtk.SortListModel`. Machines and Debian put a `Gtk.FilterListModel` straight into the selection. RPM and Windows put the store straight in. Agents and Repositories do too.
- ℹ️ `Gtk.ColumnView.sorter` is the view's own `Gtk.ColumnViewSorter`. A header click changes it only when that column's `sorter` is set. The rows move only when a `Gtk.SortListModel` uses that sorter.
- ℹ️ The column menu gesture in `Base.column_menu` listens for the secondary button. A left click on a header is not that gesture.
- ✔️ Agents. Remove walks `this.store` by index and asks `this.selection.is_selected` with that same index. Those indexes match only while the selection model's order is the store's order.
- ℹ️ `os-updated` and `os-status` exist on `Argus.Shared.OSQuery.SystemInfo`; `pkgs-updated` and `pkgs-status` are not on the row class yet and await [5.10](../plans/5.10-data-enrichment.md).
- 💩 The running controller was not clicked for this.

## Root cause

- ✔️ A header sorts only when the column has a `sorter` and the selection model is a `Gtk.SortListModel` of `grid.sorter`. Neither is wired.

## Proposed fix

- 🔷 The header click and the arrow stay GTK's. A column with Sort `ON` is given a `sorter`. The rows sit in a `Gtk.SortListModel` whose sorter is the view's sorter.
- 🔷 Sort is the sixth field of the column CSV. `ON` sorts. `off` does not. The format does not decide.
- 🔷 A missing Sort field does not sort.
- 🔷 `Base` provides `column_sorter` (inspects the row property's `GLib.Type` once per column via `this.grid.model.get_item_type()` and returns a `Gtk.NumericSorter` or `Gtk.StringSorter` rather than checking types on every comparison) and `column_grid` (wraps `SortListModel`, builds `this.grid`, and calls `column_menu`).
- 🔷 All six grids (`Machines`, `Debian`, `RPM`, `Windows`, `Agents`, `Repositories`) use `Base` and column CSV files rather than hardcoding column sorters per grid.
- 💩 OS status and S/W status start `off`. Every other column in the four asset CSVs starts `ON`.
- 💩 Text and versions sort as text, A–Z, ignoring case. `1.10` stays before `1.9`. An address sorts as text.
- 💩 An `int`, `int64`, or `bool` property sorts by its underlying value (`bytes` by byte count, `remove` by `installed`, `Agent` `created` / `last-connected` by unix timestamp rather than formatted `"HH:MM"` strings).
- ℹ️ `os-updated` and `pkgs-updated` are `ON`. `os-updated` is filled from `os_releases`; `pkgs-updated` awaits [5.10](../plans/5.10-data-enrichment.md).
- 🔷 The row filter stays under the sort. A filtered grid sorts the rows that are showing.
- 🔷 Agents. Remove reads `this.grid.model` (the `Gtk.MultiSelection` over `SortListModel`), so a sorted row is the row that was ticked.
- 💩 Open points to confirm before applying to `Agent` and `Repository`:
  - 💩 `Base.column_menu()` currently claims every secondary click on `this.grid` in `CAPTURE` phase; on `Agent`, right-clicking a row must still open the row `Remove` menu, so `Base` must restrict the column menu to header clicks (needs a GTK4 header-pick probe per `docs/bug-fix-process.md`) or let `Agent` opt out.
  - 💩 `Base` sets `column.expand = true` when the CSV width field is `0` (for `Agent` and `Repository` columns that currently expand).
  - 💩 `Agent` live updates (`Store.Agent` mutates `status`, `last_connected`, `connected` in place without `items_changed`), `Kind` `"argus-this-controller"` CSS highlight, `recent-date` (`%H:%M` today, `%Y-%m-%d` otherwise), and `Repository` `name == ""` fallback / `"dim-label"` styling need small `Base` / model support or explicit approval.
- 🚫 A sort of the store itself.
- 🚫 A version comparer, or a sort of the painted label.
- 🚫 Deciding sort from the format. `status` and `tick` are not a special case in code.
- 🚫 Hardcoding `column.sorter` column-by-column in `Agent.vala` and `Repository.vala`.

### 1. Column files

The first line gains `Sort`. [5.8](../plans/5.8-assets-page.md) names the five words in front of it. Those words stay. `SystemInfo` still reads the format from the fifth field.

#### Replace with

`controller/resources/columns/system_info.csv`

```
Column header  |  Database name [JSON]  |  ON or off  |  Width in pixels  |  Format  |  Sort

Logged in users,logged-in-users,ON,160,text,ON
Hostname,hostname,ON,160,text,ON
Local hostname,local-hostname,off,150,text,ON
Computer name,computer-name,ON,150,text,ON
UUID,uuid,off,270,text,ON

Hardware vendor,hardware-vendor,ON,130,text,ON
Hardware model,hardware-model,off,160,text,ON
Hardware version,hardware-version,off,120,text,ON
Hardware serial,hardware-serial,off,140,text,ON

Board vendor,board-vendor,off,130,text,ON
Board model,board-model,off,140,text,ON
Board version,board-version,off,120,text,ON
Board serial,board-serial,off,140,text,ON

Physical memory,physical-memory,off,90,bytes,ON

CPU brand,cpu-brand,ON,240,text,ON
CPU type,cpu-type,off,80,text,ON
CPU subtype,cpu-subtype,off,80,text,ON
CPU physical cores,cpu-physical-cores,off,72,number,ON
CPU logical cores,cpu-logical-cores,off,72,number,ON
CPU microcode,cpu-microcode,off,110,text,ON

Operating system,operating-system,ON,180,text,ON
Major,major,off,64,number,ON
Minor,minor,off,64,number,ON
Patch,patch,off,64,number,ON
Build,build,off,100,text,ON
Platform,platform,off,90,text,ON
Platform like,platform-like,off,100,text,ON
Codename,codename,off,110,text,ON
Arch,arch,off,72,text,ON

OS updated,os-updated,off,110,date,ON
OS status,os-status,ON,90,status,off

Package updated,pkgs-updated,off,120,date,ON
S/W status,pkgs-status,ON,90,status,off
```

`controller/resources/columns/deb_packages.csv`

```
Column header  |  Database name [JSON]  |  ON or off  |  Width in pixels  |  Format  |  Sort

Name,name,ON,180,text,ON
Arch,arch,ON,90,text,ON
Section,section,ON,110,text,ON
Priority,priority,ON,90,text,ON
Min version,min-version,ON,140,text,ON
Max version,max-version,ON,140,maxver,ON
Max size,max-size,ON,90,bytes,ON
Source,source,off,160,text,ON
Maintainer,maintainer,off,220,text,ON
Installed,installed,ON,80,number,ON
Remove,remove,ON,48,remove,ON
```

`controller/resources/columns/rpm_packages.csv`

```
Column header  |  Database name [JSON]  |  ON or off  |  Width in pixels  |  Format  |  Sort

Name,name,ON,180,text,ON
Arch,arch,ON,90,text,ON
Package group,package-group,ON,220,text,ON
Min version,min-version,ON,160,text,ON
Max version,max-version,ON,160,maxver,ON
Max size,max-size,ON,90,bytes,ON
Source,source,off,180,text,ON
Vendor,vendor,off,160,text,ON
Installed,installed,ON,80,number,ON
```

`controller/resources/columns/programs.csv`

```
Column header  |  Database name [JSON]  |  ON or off  |  Width in pixels  |  Format  |  Sort

Name,name,ON,200,text,ON
Publisher,publisher,ON,160,text,ON
Min version,min-version,ON,120,text,ON
Max version,max-version,ON,120,maxver,ON
Language,language,off,80,text,ON
Identifying number,identifying-number,off,220,text,ON
Install date,install-date,off,110,text,ON
Install location,install-location,off,200,text,ON
Install source,install-source,off,200,text,ON
Uninstall string,uninstall-string,off,220,text,ON
Installed,installed,ON,80,number,ON
Uninstall,uninstall-count,ON,80,bin,ON
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

### 2. `controller/tab/Base.vala` — `column_menu`, `column_sorter`, `column_grid`

The row description names the sort field.

#### Remove

```vala
		 *  * Each row is the header, the JSON name, ''ON'' or ''off'', the width, and the format.
```

#### Replace with

```vala
		 *  * Each row is the header, the JSON name, ''ON'' or ''off'', the width, the format, and sort.
		 *  * Sort is ''ON'' or ''off''. ''ON'' sorts. A missing field does not.
```

After `fixed_width`, before `append_column`. The sorter is built by `column_sorter` once per column only when Sort is `ON`.

#### Add

```vala
				if (width == 0) {
					column.expand = true;
				}
				if (parts.length > 5 && parts[5].strip() == "ON") {
					column.sorter = this.column_sorter(name, format);
				}
```

Add `column_sorter` and `column_grid` helper methods to `Base`:

#### Add

```vala
		/**
		 * Build {@link grid} over ''model'' with sorting and column menu.
		 *
		 * Wraps ''model'' in a {@link Gtk.SortListModel} bound to the
		 * grid's own sorter, then sets up {@link column_menu}.
		 *
		 * @param model store or filter model supplying rows
		 * @param multi true for {@link Gtk.MultiSelection}, false for {@link Gtk.SingleSelection}
		 * @return the group whose actions show and hide columns
		 */
		protected GLib.SimpleActionGroup column_grid(
			GLib.ListModel model,
			bool multi = false
		) {
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = false
			};
			var selection = multi
				? (Gtk.SelectionModel) new Gtk.MultiSelection(sorted)
				: (Gtk.SelectionModel) new Gtk.SingleSelection(sorted);
			this.grid = new Gtk.ColumnView(selection) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
			return this.column_menu();
		}

		/**
		 * Sorter for one column, chosen from the row property's type.
		 *
		 *  * Numeric and boolean properties return {@link Gtk.NumericSorter}.
		 *  * ''remove'' sorts by ''installed''.
		 *  * String properties return {@link Gtk.StringSorter} ignoring case.
		 *  * Returns null when the property is not on the row class yet.
		 *
		 * @param name JSON name. A hyphen is an underscore.
		 * @param format column format from the CSV
		 * @return the sorter for this column, or null when missing
		 */
		private Gtk.Sorter? column_sorter(string name, string format)
		{
			var sort_name = name;
			if (format == "remove") {
				sort_name = "installed";
			}
			var item_type = this.grid.model.get_item_type();
			var klass = (GLib.ObjectClass) item_type.class_ref();
			var prop = klass.find_property(sort_name);
			if (prop == null) {
				return null;
			}
			var expr = (Gtk.Expression) new Gtk.PropertyExpression(item_type, null, sort_name);
			switch (prop.value_type) {
				case GLib.Type.INT:
				case GLib.Type.INT64:
				case GLib.Type.UINT:
				case GLib.Type.UINT64:
				case GLib.Type.FLOAT:
				case GLib.Type.DOUBLE:
				case GLib.Type.BOOLEAN:
					return new Gtk.NumericSorter(expr);

				default:
					return new Gtk.StringSorter(expr) {
						ignore_case = true
					};
			}
		}
```

### 3. `controller/tab/Asset/DebPackages.vala`

The sort wraps the filter via `this.column_grid(rows)`.

#### Remove

```vala
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(rows)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			this.column_menu();
```

#### Replace with

```vala
			this.column_grid(rows);
```

### 4. `controller/tab/Asset/SystemInfo.vala`

Same wrap via `this.column_grid(rows, true)`. The selection stays a `Gtk.MultiSelection`.

#### Remove

```vala
			this.grid = new Gtk.ColumnView(new Gtk.MultiSelection(rows)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			var group = this.column_menu();
```

#### Replace with

```vala
			var group = this.column_grid(rows, true);
```

### 5. `controller/tab/Asset/Programs.vala`

#### Remove

```vala
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(this.store)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			this.column_menu();
```

#### Replace with

```vala
			this.column_grid(this.store);
```

### 6. `controller/tab/Asset/RpmPackages.vala`

#### Remove

```vala
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(this.store)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			this.column_menu();
```

#### Replace with

```vala
			this.column_grid(this.store);
```

### 7. `controller/tab/Agent.vala` (💩 migrate to `Base` + `agent.csv`)

- 💩 Replace hardcoded columns, `header_menu`, and `Gtk.ColumnView` construction with `Argus.Controller.Tab.Base` (`table: "agent"`) and `this.column_grid(this.store, true)`.
- 💩 Prerequisites to resolve before writing the exact hunks:
  - 💩 Restrict `Base.column_menu()`'s secondary-click capture to header widgets (verified with a quick GTK4 probe) so right-clicking a row still opens `Agent`'s `Remove` menu.
  - 💩 Decide how `Base.column_factory()` handles `Agent`'s `recent-date` (`%H:%M` today, `%Y-%m-%d` otherwise), `tick` (`status == 1` / `connected` bool), live updates when `Store.Agent.load()` mutates rows in place, `argus-agent-row` lookup, and the `"argus-this-controller"` CSS highlight on `Kind`.
- 🔷 Remove reads `this.grid.model` (`Gtk.MultiSelection`) instead of `this.store`, so a sorted row is the row that was ticked:

```vala
				var selection = (Gtk.MultiSelection) this.grid.model;
				var count = (int) selection.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!selection.is_selected((uint) i)) {
						continue;
					}
					var row = selection.get_item((uint) i) as Argus.Shared.Agent;
```

### 8. `controller/tab/Repository.vala` (💩 migrate to `Base` + `repository.csv`)

- 💩 Inherit `Argus.Controller.Tab.Base` (`table: "repository"`) and call `this.column_grid(this.store)` instead of hardcoding `name_column.sorter` and `url_column.sorter`.
- 💩 Set `autoselect = false` and `can_unselect = true` on `(Gtk.SingleSelection) this.grid.model`.
- 💩 Prerequisites to confirm before writing the exact hunks:
  - 💩 `ScriptRepository.display_name` (or fallback to `url` when `name == ""`) and `"dim-label"` on `URL`.

## Attempts

- ✔️ Applied sections 1–6: added the `Sort` field to `system_info.csv`, `deb_packages.csv`, `rpm_packages.csv`, and `programs.csv`; added `column_grid` and `column_sorter` (`Gtk.NumericSorter` / `Gtk.StringSorter` chosen by `GLib.Type`) plus `width == 0` expand and CSV sort wiring to `controller/tab/Base.vala`; updated `DebPackages.vala`, `SystemInfo.vala`, `Programs.vala`, and `RpmPackages.vala` to call `this.column_grid(...)`.
- ✔️ Built `ninja -C build controller/argusrm-controller` and `ninja -C build docs/valadoc` with zero new warnings.
- ℹ️ Sections 7 (`Agent.vala`) and 8 (`Repository.vala`) are not applied yet because their `💩` migration prerequisites (`Base` header-only right-click vs row `Remove` menu, `recent-date` / `tick` / live updates / CSS styling) are unconfirmed.

## Next

- ⏳ 🔷 Confirm whether `Agent` and `Repository` should migrate to `Base` + `agent.csv` / `repository.csv` as part of this fix (and resolve the `💩` open points above).
- ⏳ 🔷 Run a GTK4 probe if `Base.column_menu()` needs header-only right-click detection for `Agent`.
- ⏳ 🔷 Click a header whose Sort field is `ON` on Machines, Debian, RPM, and Windows. The rows reverse on the next click, and the arrow follows. OS status does not sort.
- ⏳ 🔷 Click Installed and Max size. The order is numeric.
- ⏳ 🔷 Sort, then remove a ticked agent (once sections 7–8 are applied). The removed row is the one that was ticked.
