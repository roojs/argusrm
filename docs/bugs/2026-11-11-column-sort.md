# Column headers do not sort

**Status:** ⏳ fix proposed — await apply approval

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
- ℹ️ `os-updated`, `os-status`, `pkgs-updated`, and `pkgs-status` are columns on Machines. The row class has none of those properties. [5.10](../plans/5.10-data-enrichment.md) fills them.
- 💩 The running controller was not clicked for this.

## Root cause

- ✔️ A header sorts only when the column has a `sorter` and the selection model is a `Gtk.SortListModel` of `grid.sorter`. Neither is wired.

## Proposed fix

- 🔷 The header click and the arrow stay GTK's. A column with Sort `ON` is given a `sorter`. The rows sit in a `Gtk.SortListModel` whose sorter is the view's sorter.
- 🔷 Sort is the sixth field of the column CSV. `ON` sorts. `off` does not. The format does not decide.
- 🔷 A missing Sort field does not sort.
- 💩 OS status and S/W status start `off`. Every other column in the four files starts `ON`.
- 💩 Text, dates, and versions sort as text, A–Z, ignoring case. `1.10` stays before `1.9`. An address sorts as text.
- 💩 An `int` or `int64` property sorts by that number. `bytes` uses the byte count, not the label `12 MB`. `remove` sorts by `installed`, the count the cell shows.
- ℹ️ `os-updated` and `pkgs-updated` are `ON`. The property is missing, so a click there does not reorder until [5.10](../plans/5.10-data-enrichment.md).
- ℹ️ Agents and Repositories have no column CSV. Their columns are set in code.
- 🔷 The row filter stays under the sort. A filtered grid sorts the rows that are showing.
- 🔷 Agents. Remove reads the selection model, so a sorted row is the row that was ticked.
- 🚫 A sort of the store itself.
- 🚫 A version comparer, or a sort of the painted label.
- 🚫 Deciding sort from the format. `status` and `tick` are not a special case in code.
- 🚫 A new method. The comparison stays in `column_menu`.

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

### 2. `controller/tab/Base.vala` — `column_menu`

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

After `fixed_width`, before `append_column`. The sorter runs only when Sort is `ON`.

#### Add

```vala
				var sorts = parts.length > 5 && parts[5].strip() == "ON";
				if (sorts) {
					var sort_name = name;
					if (format == "remove") {
						sort_name = "installed";
					}
					column.sorter = new Gtk.CustomSorter((a, b) => {
						var left_row = (GLib.Object) a;
						var right_row = (GLib.Object) b;
						var prop = left_row.get_class().find_property(sort_name);
						if (prop == null) {
							return 0;
						}
						var left_value = GLib.Value(prop.value_type);
						var right_value = GLib.Value(prop.value_type);
						left_row.get_property(sort_name, ref left_value);
						right_row.get_property(sort_name, ref right_value);
						if (prop.value_type == GLib.Type.INT) {
							var left_int = left_value.get_int();
							var right_int = right_value.get_int();
							if (left_int == right_int) {
								return 0;
							}
							if (left_int < right_int) {
								return -1;
							}
							return 1;
						}
						if (prop.value_type == GLib.Type.INT64) {
							var left_size = left_value.get_int64();
							var right_size = right_value.get_int64();
							if (left_size == right_size) {
								return 0;
							}
							if (left_size < right_size) {
								return -1;
							}
							return 1;
						}
						var left_text = left_value.get_string();
						var right_text = right_value.get_string();
						if (left_text == null) {
							left_text = "";
						}
						if (right_text == null) {
							right_text = "";
						}
						return left_text.casefold().collate(right_text.casefold());
					});
				}
```

### 3. `controller/tab/Asset/DebPackages.vala`

The sort wraps the filter.

#### Replace with

```vala
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = false
			};
			var sorted = new Gtk.SortListModel(rows, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
```

### 4. `controller/tab/Asset/SystemInfo.vala`

Same wrap. The selection stays a `Gtk.MultiSelection`.

#### Replace with

```vala
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = false
			};
			var sorted = new Gtk.SortListModel(rows, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(new Gtk.MultiSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
```

### 5. `controller/tab/Asset/Programs.vala`

#### Replace with

```vala
			var sorted = new Gtk.SortListModel(this.store, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
```

### 6. `controller/tab/Asset/RpmPackages.vala`

#### Replace with

```vala
			var sorted = new Gtk.SortListModel(this.store, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
```

### 7. `controller/tab/Agent.vala`

Each column sorts the string it shows. The GObject name uses a hyphen.

#### Add

```vala
			name_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "display-name")) {
				ignore_case = true
			};
			address_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "ip")) {
				ignore_case = true
			};
			user_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "username")) {
				ignore_case = true
			};
			kind_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "display-kind")) {
				ignore_case = true
			};
			registered_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "display-registered")) {
				ignore_case = true
			};
			created_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "display-created")) {
				ignore_case = true
			};
			connected_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "display-connected")) {
				ignore_case = true
			};
			last_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(typeof(Argus.Shared.Agent), null, "display-last")) {
				ignore_case = true
			};
```

The selection model is the sorted rows.

#### Replace with

```vala
			var sorted = new Gtk.SortListModel(this.store, null) {
				incremental = false
			};
			this.selection = new Gtk.MultiSelection(sorted);
			var view = new Gtk.ColumnView(this.selection) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = view.sorter;
```

Remove reads that model.

#### Replace with

```vala
				var count = (int) this.selection.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!this.selection.is_selected((uint) i)) {
						continue;
					}
					var row = this.selection.get_item((uint) i) as Argus.Shared.Agent;
```

### 8. `controller/tab/Repository.vala`

#### Add

```vala
			name_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(
					typeof(Argus.Shared.SQT.ScriptRepository), null, "name")) {
				ignore_case = true
			};
			url_column.sorter = new Gtk.StringSorter(
				new Gtk.PropertyExpression(
					typeof(Argus.Shared.SQT.ScriptRepository), null, "url")) {
				ignore_case = true
			};
```

#### Replace with

```vala
			var sorted = new Gtk.SortListModel(this.store, null) {
				incremental = false
			};
			this.selection = new Gtk.SingleSelection(sorted) {
				autoselect = false,
				can_unselect = true
			};
			var view = new Gtk.ColumnView(this.selection) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = view.sorter;
```

## Attempts

- ℹ️ No code change yet.

## Next

- ⏳ 🔷 Apply the proposal after approval.
- ⏳ 🔷 Click a header whose Sort field is `ON`. The rows reverse on the next click, and the arrow follows. OS status does not sort.
- ⏳ 🔷 Click Installed and Max size. The order is numeric.
- ⏳ 🔷 Sort, then remove a ticked agent. The removed row is the one that was ticked.
