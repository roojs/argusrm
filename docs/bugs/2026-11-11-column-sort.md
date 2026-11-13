# Column headers do not sort

**Status:** ⏳ `column_sorter()` unwrap inlined and ready to verify; `Agent` & `Repository` split to [2026-11-13-agent-repository-column-sort.md](2026-11-13-agent-repository-column-sort.md)

**Pointer:** `docs/bug-fix-process.md`, `docs/bugs/2026-11-13-agent-repository-column-sort.md`

---

## Problem

- 🔷 A left click on a column header sorts that column.
- 🔷 The next click on that header reverses the order.
- 🔷 The order is the column's value. A size sorts by its byte count. A count sorts by the count.
- ℹ️ The grids in scope here are Machines, Debian, RPM, and Windows. Agents and Repositories were split to [2026-11-13-agent-repository-column-sort.md](2026-11-13-agent-repository-column-sort.md).

## Evidence

- ✔️ `controller/tab/Base.vala` originally built each `Gtk.ColumnViewColumn` with `resizable` and `visible` only (`column.sorter` never set), and no grid wrapped its rows in a `Gtk.SortListModel`.
- ✔️ After sections 1–6 landed, clicking any column header on Machines, Debian, RPM, or Windows still showed no sort indicator and did not sort.
- ✔️ `/tmp/probe_sort.vala` (`valac --pkg gtk4`) proved why:
  - `Gtk.SingleSelection.get_item_type()`, `Gtk.MultiSelection.get_item_type()`, `Gtk.SortListModel.get_item_type()`, and `Gtk.FilterListModel.get_item_type()` all return `GObject` (`GLib.Type.OBJECT`), NOT the underlying store's row type (`Row`).
  - `column_sorter()` called `this.grid.model.get_item_type()` and `klass.find_property(sort_name)` on `GObject`, so `prop` was always `null` and `column.sorter` was never set on any column.
  - Unwrapping `Gtk.SingleSelection` / `Gtk.MultiSelection` / `Gtk.SortListModel` / `Gtk.FilterListModel` down to the underlying store yields `Row`, `find_property()` resolves `min-version` / `max-size` / `installed`, and `grid.sort_by_column(...)` sets `column.sorter` and sorts `Gtk.SortListModel` numerically and alphabetically.
- ℹ️ `Gtk.ColumnView.sorter` is the view's own `Gtk.ColumnViewSorter`. A header click changes it only when that column's `sorter` is set. The rows move only when a `Gtk.SortListModel` uses that sorter.
- ℹ️ The column menu gesture in `Base.column_menu` listens for the secondary button. A left click on a header is not that gesture.
- ℹ️ `os-updated` and `os-status` exist on `Argus.Shared.OSQuery.SystemInfo`; `pkgs-updated` and `pkgs-status` are not on the row class yet and await [5.10](../plans/5.10-data-enrichment.md).

## Root cause

- ✔️ Two causes:
  1. Neither `column.sorter` nor `Gtk.SortListModel` was wired originally (fixed in sections 1–6).
  2. `Base.column_sorter()` inspected `this.grid.model.get_item_type()`, which returns `GObject` on GTK4 selection/filter/sort wrapper models, so `klass.find_property()` always returned `null` and left `column.sorter` unset on every column.

## Proposed fix

- 🔷 The header click and the arrow stay GTK's. A column with Sort `ON` is given a `sorter`. The rows sit in a `Gtk.SortListModel` whose sorter is the view's sorter.
- 🔷 Sort is the sixth field of the column CSV. `ON` sorts. `off` does not. The format does not decide.
- 🔷 A missing Sort field does not sort.
- 🔷 `Base` provides `column_sorter` (unwraps GTK selection/sort/filter wrapper models inline to the store's `GLib.Type`, inspects the row property's `GLib.Type` once per column, and returns a `Gtk.NumericSorter` or `Gtk.StringSorter` rather than checking types on every comparison) and `column_grid` (wraps `SortListModel`, builds `this.grid`, and calls `column_menu`).
- 💩 OS status and S/W status start `off`. Every other column in the four asset CSVs starts `ON`.
- 💩 Text and versions sort as text, A–Z, ignoring case. `1.10` stays before `1.9`. An address sorts as text.
- 💩 An `int`, `int64`, or `bool` property sorts by its underlying value (`bytes` by byte count, `remove` by `installed`).
- ℹ️ `os-updated` and `pkgs-updated` are `ON`. `os-updated` is filled from `os_releases`; `pkgs-updated` awaits [5.10](../plans/5.10-data-enrichment.md).
- 🔷 The row filter stays under the sort. A filtered grid sorts the rows that are showing.
- ℹ️ Agents and Repositories column sorting split to [2026-11-13-agent-repository-column-sort.md](2026-11-13-agent-repository-column-sort.md).
- 🚫 A sort of the store itself.
- 🚫 A version comparer, or a sort of the painted label.
- 🚫 Deciding sort from the format. `status` is not a special case in code.

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
			var model = (GLib.ListModel) this.grid.model;
			while (true) {
				if (model is Gtk.SingleSelection) {
					model = ((Gtk.SingleSelection) model).model;
					continue;
				}
				if (model is Gtk.MultiSelection) {
					model = ((Gtk.MultiSelection) model).model;
					continue;
				}
				if (model is Gtk.SortListModel) {
					model = ((Gtk.SortListModel) model).model;
					continue;
				}
				if (model is Gtk.FilterListModel) {
					model = ((Gtk.FilterListModel) model).model;
					continue;
				}
				break;
			}
			var item_type = model.get_item_type();
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

## Attempts

- ✔️ Applied sections 1–6: added the `Sort` field to `system_info.csv`, `deb_packages.csv`, `rpm_packages.csv`, and `programs.csv`; added `column_grid` and `column_sorter` (`Gtk.NumericSorter` / `Gtk.StringSorter` chosen by `GLib.Type`) plus `width == 0` expand and CSV sort wiring to `controller/tab/Base.vala`; updated `DebPackages.vala`, `SystemInfo.vala`, `Programs.vala`, and `RpmPackages.vala` to call `this.column_grid(...)`.
- ✔️ Built `ninja -C build controller/argusrm-controller` and `ninja -C build docs/valadoc` with zero new warnings.
- ✔️ Diagnosed why headers still showed no sort indicator on the new controller: `/tmp/probe_sort.vala` proved `Gtk.SingleSelection`, `Gtk.MultiSelection`, `Gtk.SortListModel`, and `Gtk.FilterListModel` all return `GObject` from `get_item_type()`, so `column_sorter()` never found any row property and left `column.sorter == null`.
- ✔️ Split sections 7 (`Agent`) and 8 (`Repository`) out into [2026-11-13-agent-repository-column-sort.md](2026-11-13-agent-repository-column-sort.md).
- ✔️ Inlined model unwrapping directly inside `column_sorter()` in `controller/tab/Base.vala` (removed the unapproved helper method).

## Next

- ⏳ 🔷 Click a header whose Sort field is `ON` on Machines, Debian, RPM, and Windows. The rows reverse on the next click, and the arrow follows. OS status does not sort.
- ⏳ 🔷 Click Installed and Max size. The order is numeric.
- ⏳ 🔷 Move to `docs/bugs/done/2026-11-11-FIXED-column-sort.md` once user verifies on the running controller.
