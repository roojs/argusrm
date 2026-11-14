# MachineGeneral store, CSV base interface, and General tab

**Status:** ⏳ code proposal ready for review — awaiting approval

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md`, `docs/coding-standards.md`, [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md)

---

## Purpose

- 🔷 Generalize `/argusrm/columns/*.csv` parsing onto `Argus.Controller.Store.Base` (`controller/store/Base.vala`) with `out` maps/lists, and migrate `Tab.Base`, `Tab.Asset.SystemInfo`, and `Tab.Tasks` to it.
- 🔷 Add `Argus.Controller.Store.KeyValue` (`controller/store/KeyValue.vala`) with `expander` flag.
- 🔷 Add `Argus.Controller.Store.MachineGeneral` (`controller/store/MachineGeneral.vala`) loading `SystemInfo.list(agent_id, false)`, `OsVersion.list(agent_id)`, and `OsReleases.list(agent_id)` and replacing `items` on load.
- 🔷 Add `Argus.Controller.Tab.Asset.Machine.General` (`controller/tab/Asset/Machine/General.vala`), wire it first in `Detail.vala`, and add `.vertical-list` CSS in `controller/resources/style.css`.

---

## Proposed changes

### 1. `controller/store/Base.vala` — shared CSV interface

**Why:** Deduplicate `/argusrm/columns/<table>.csv` parsing across stores and tabs using `out` maps and lists.

**Where:** new file `controller/store/Base.vala`.

**Depends on:** none.

#### Add — `controller/store/Base.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Store
{
	/**
	 * Shared column CSV reader for controller stores and tabs.
	 *
	 * Parses ''/argusrm/columns/'' resource files into ordered column
	 * maps and text-filter lists.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var labels = new Gee.HashMap<string, string>();
	 * var formats = new Gee.HashMap<string, string>();
	 * this.read_csv("system_info", out labels, out formats);
	 * }}}
	 */
	public interface Base : GLib.Object
	{
		/**
		 * Read column definitions from ''/argusrm/columns/<table>.csv''.
		 *
		 * @param table file name under columns without ''.csv''
		 * @param order ordered column JSON names
		 * @param labels map of column name to header label
		 * @param starts map of column name to initial visibility
		 * @param widths map of column name to fixed pixel width
		 * @param formats map of column name to display format
		 * @param sorts map of column name to sortable flag
		 */
		public void read_columns(
			string table,
			out Gee.ArrayList<string> order,
			out Gee.HashMap<string, string> labels,
			out Gee.HashMap<string, bool> starts,
			out Gee.HashMap<string, int> widths,
			out Gee.HashMap<string, string> formats,
			out Gee.HashMap<string, bool> sorts
		) {
			order = new Gee.ArrayList<string>();
			labels = new Gee.HashMap<string, string>();
			starts = new Gee.HashMap<string, bool>();
			widths = new Gee.HashMap<string, int>();
			formats = new Gee.HashMap<string, string>();
			sorts = new Gee.HashMap<string, bool>();
			var text = (string) GLib.resources_lookup_data(
				"/argusrm/columns/" + table + ".csv",
				GLib.ResourceLookupFlags.NONE).get_data();
			var headings = true;
			foreach (var line in text.split("\n")) {
				if (line.strip() == "") {
					continue;
				}
				if (headings) {
					headings = false;
					continue;
				}
				var parts = line.strip().split(",");
				if (parts.length < 4) {
					continue;
				}
				var title = parts[0].strip();
				var name = parts[1].strip();
				if (title == "" || name == "") {
					continue;
				}
				var format = "text";
				if (parts.length > 4 && parts[4].strip() != "") {
					format = parts[4].strip();
				}
				var width = 0;
				if (!int.try_parse(parts[3].strip(), out width) || width < 0) {
					width = 0;
				}
				order.add(name);
				labels.set(name, title);
				starts.set(name, parts[2].strip() == "ON");
				widths.set(name, width);
				formats.set(name, format);
				sorts.set(name, parts.length > 5 && parts[5].strip() == "ON");
			}
		}

		/**
		 * Read column labels and display formats for ''table''.
		 *
		 * @param table file name under columns without ''.csv''
		 * @param labels map of column name to header label
		 * @param formats map of column name to display format
		 */
		public void read_csv(
			string table,
			out Gee.HashMap<string, string> labels,
			out Gee.HashMap<string, string> formats
		) {
			var order = new Gee.ArrayList<string>();
			var starts = new Gee.HashMap<string, bool>();
			var widths = new Gee.HashMap<string, int>();
			var sorts = new Gee.HashMap<string, bool>();
			this.read_columns(table, out order, out labels, out starts,
				out widths, out formats, out sorts);
		}

		/**
		 * Read text column names and initially visible text columns.
		 *
		 * @param table file name under columns without ''.csv''
		 * @param text_columns all columns whose format is ''text''
		 * @param visible ''text'' columns marked ''ON''
		 */
		public void read_text_columns(
			string table,
			out Gee.ArrayList<string> text_columns,
			out Gee.ArrayList<string> visible
		) {
			text_columns = new Gee.ArrayList<string>();
			visible = new Gee.ArrayList<string>();
			var order = new Gee.ArrayList<string>();
			var labels = new Gee.HashMap<string, string>();
			var starts = new Gee.HashMap<string, bool>();
			var widths = new Gee.HashMap<string, int>();
			var formats = new Gee.HashMap<string, string>();
			var sorts = new Gee.HashMap<string, bool>();
			this.read_columns(table, out order, out labels, out starts,
				out widths, out formats, out sorts);
			foreach (var name in order) {
				if (formats.get(name) != "text") {
					continue;
				}
				text_columns.add(name);
				if (starts.get(name)) {
					visible.add(name);
				}
			}
		}
	}
}
```

---

### 2. `controller/tab/Base.vala`, `controller/tab/Asset/SystemInfo.vala`, & `controller/tab/Tasks.vala` — use `Store.Base`

**Why:** Replace inline CSV loops in existing tabs with `Store.Base.read_columns()` and `Store.Base.read_text_columns()`.

**Where:** `Base` class declaration and `column_menu()` in `controller/tab/Base.vala`; constructor in `controller/tab/Asset/SystemInfo.vala`; constructor in `controller/tab/Tasks.vala`.

**Depends on:** item 1.

#### Remove (`controller/tab/Base.vala`, class header and top of `column_menu()`)

```vala
	public abstract class Base : Gtk.Box
	{
```

#### Replace with (`controller/tab/Base.vala`)

```vala
	public abstract class Base : Gtk.Box, Argus.Controller.Store.Base
	{
```

#### Remove (`controller/tab/Base.vala`, inside `column_menu()`)

```vala
		public GLib.SimpleActionGroup column_menu()
		{
			var text = (string) GLib.resources_lookup_data(
				"/argusrm/columns/" + this.table + ".csv",
				GLib.ResourceLookupFlags.NONE).get_data();
			var columns = new Gee.ArrayList<Gtk.ColumnViewColumn>();
			var menu = new GLib.Menu();
			var menu_popup = new Gtk.PopoverMenu.from_model(menu) {
				has_arrow = false,
				position = Gtk.PositionType.BOTTOM
			};
			menu_popup.add_css_class("column-menu");
			menu_popup.set_parent(this.grid);
			var group = new GLib.SimpleActionGroup();
			var headings = true;
			var first = true;
			this.insert_action_group(this.table, group);
			foreach (var line in text.split("\n")) {
				if (line.strip() == "") {
					continue;
				}
				if (headings) {
					headings = false;
					continue;
				}
				var parts = line.strip().split(",");
				if (parts.length < 4) {
					continue;
				}
				var title = parts[0].strip();
				var name = parts[1].strip();
				if (title == "" || name == "") {
					continue;
				}
				var starts = parts[2].strip() == "ON";
				var format = "text";
				if (parts.length > 4 && parts[4].strip() != "") {
					format = parts[4].strip();
				}
				var header_column = first && this.bold_header;
				first = false;
				var width = 0;
				var factory = this.column_factory(name, format, header_column);
				var column = new Gtk.ColumnViewColumn(title, factory) {
					resizable = true,
					visible = starts
				};
				if (int.try_parse(parts[3].strip(), out width) && width > 0) {
					column.fixed_width = width;
				}
				if (width == 0 || name == this.expand_column) {
					column.expand = true;
				}
				if (parts.length > 5 && parts[5].strip() == "ON") {
					column.sorter = this.column_sorter(name, format);
				}
```

#### Replace with (`controller/tab/Base.vala`)

```vala
		public GLib.SimpleActionGroup column_menu()
		{
			var order = new Gee.ArrayList<string>();
			var labels = new Gee.HashMap<string, string>();
			var starts_map = new Gee.HashMap<string, bool>();
			var widths = new Gee.HashMap<string, int>();
			var formats = new Gee.HashMap<string, string>();
			var sorts = new Gee.HashMap<string, bool>();
			this.read_columns(this.table, out order, out labels, out starts_map,
				out widths, out formats, out sorts);
			var columns = new Gee.ArrayList<Gtk.ColumnViewColumn>();
			var menu = new GLib.Menu();
			var menu_popup = new Gtk.PopoverMenu.from_model(menu) {
				has_arrow = false,
				position = Gtk.PositionType.BOTTOM
			};
			menu_popup.add_css_class("column-menu");
			menu_popup.set_parent(this.grid);
			var group = new GLib.SimpleActionGroup();
			var first = true;
			this.insert_action_group(this.table, group);
			foreach (var name in order) {
				var title = labels.get(name);
				var starts = starts_map.get(name);
				var format = formats.get(name);
				var width = widths.get(name);
				var header_column = first && this.bold_header;
				first = false;
				var factory = this.column_factory(name, format, header_column);
				var column = new Gtk.ColumnViewColumn(title, factory) {
					resizable = true,
					visible = starts
				};
				if (width > 0) {
					column.fixed_width = width;
				}
				if (width == 0 || name == this.expand_column) {
					column.expand = true;
				}
				if (sorts.get(name)) {
					column.sorter = this.column_sorter(name, format);
				}
```

#### Remove (`controller/tab/Asset/SystemInfo.vala`)

```vala
			var text = (string) GLib.resources_lookup_data("/argusrm/columns/system_info.csv",
				GLib.ResourceLookupFlags.NONE).get_data();

			var text_columns = new Gee.ArrayList<string>();
			var visible = new Gee.ArrayList<string>();
			var headings = true;
			foreach (var line in text.split("\n")) {
				if (line.strip() == "") {
					continue;
				}
				if (headings) {
					headings = false;
					continue;
				}
				var parts = line.strip().split(",");
				var name = parts[1].strip();
				if (parts[4].strip() != "text") {
					continue;
				}
				text_columns.add(name);
				if (parts[2].strip() == "ON") {
					visible.add(name);
				}
			}
```

#### Replace with (`controller/tab/Asset/SystemInfo.vala`)

```vala
			var text_columns = new Gee.ArrayList<string>();
			var visible = new Gee.ArrayList<string>();
			this.read_text_columns(this.table, out text_columns, out visible);
```

#### Remove (`controller/tab/Tasks.vala`)

```vala
			var text = (string) GLib.resources_lookup_data("/argusrm/columns/task_targets.csv",
					GLib.ResourceLookupFlags.NONE).get_data();
					
			var text_columns = new Gee.ArrayList<string>();
			var visible = new Gee.ArrayList<string>();
			var headings = true;
			foreach (var line in text.split("\n")) {
				if (line.strip() == "") {
					continue;
				}
				if (headings) {
					headings = false;
					continue;
				}
				var parts = line.strip().split(",");
				if (parts.length < 5) {
					continue;
				}
				var name = parts[1].strip();
				if (parts[4].strip() != "text") {
					continue;
				}
				text_columns.add(name);
				if (parts[2].strip() == "ON") {
					visible.add(name);
				}
			}
```

#### Replace with (`controller/tab/Tasks.vala`)

```vala
			var text_columns = new Gee.ArrayList<string>();
			var visible = new Gee.ArrayList<string>();
			this.read_text_columns(this.table, out text_columns, out visible);
```

---

### 3. `controller/store/KeyValue.vala` — `KeyValue` data object

**Why:** Data object rendered by `Tab.Asset.Machine.General` with `expander` flag.

**Where:** new file `controller/store/KeyValue.vala`.

**Depends on:** none.

#### Add — `controller/store/KeyValue.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Store
{
	/**
	 * One key-value entry or expander header in {@link MachineGeneral}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var header = new Argus.Controller.Store.KeyValue() {
	 *     key = "System info",
	 *     val = "web-01",
	 *     expander = true
	 * };
	 * var row = new Argus.Controller.Store.KeyValue() {
	 *     key = "Hostname",
	 *     val = "web-01"
	 * };
	 * }}}
	 */
	public class KeyValue : GLib.Object
	{
		/**
		 * Section heading or field label.
		 */
		public string key { get; set; default = ""; }

		/**
		 * Formatted field value or expander summary.
		 */
		public string val { get; set; default = ""; }

		/**
		 * True when this entry opens a collapsible group.
		 */
		public bool expander { get; set; default = false; }

		/**
		 * Initial expanded state when {@link expander} is true.
		 */
		public bool expanded { get; set; default = true; }

		/**
		 * Display format (''text'', ''number'', ''bytes'', ''date'',
		 * or ''status'').
		 */
		public string format { get; set; default = "text"; }

		/**
		 * Status flag when {@link format} is ''status''.
		 */
		public int status { get; set; default = -1; }

		/**
		 * Optional tooltip text.
		 */
		public string tooltip { get; set; default = ""; }
	}
}
```

---

### 4. `controller/store/MachineGeneral.vala` — `Store.MachineGeneral`

**Why:** Load `SystemInfo.list(agent_id, false)`, `OsVersion.list(agent_id)`, and `OsReleases.list(agent_id)`, map each result onto an expander `KeyValue` and formatted field entries using `Store.Base.read_csv`, and clear/replace `items`.

**Where:** new file `controller/store/MachineGeneral.vala`.

**Depends on:** items 1, 3, plus Phase 3 RPCs in `docs/bugs/2026-11-13-machines-detail-pane.md`.

#### Add — `controller/store/MachineGeneral.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Store
{
	/**
	 * Key-value rows for the per-machine General detail tab.
	 *
	 * A {@link GLib.ListModel} of {@link KeyValue}. {@link load} fetches
	 * ''SystemInfo.list'', ''OsVersion.list'', and ''OsReleases.list''
	 * for one ''agent_id'' and replaces {@link items} with one expander
	 * entry per query followed by its formatted properties.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.MachineGeneral(app);
	 * store.load(1);
	 * }}}
	 */
	public class MachineGeneral : GLib.Object, GLib.ListModel, Base
	{
		public Application app;
		private Gee.ArrayList<KeyValue> items_store {
			get; set; default = new Gee.ArrayList<KeyValue>();
		}
		private int epoch = 0;
		private int loaded_agent = -1;

		/**
		 * Rows from the last load. This list is the model.
		 */
		public Gee.ArrayList<KeyValue> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * True while subquery RPC calls are in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * One of the subquery calls failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * @param app the controller process
		 */
		public MachineGeneral(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(KeyValue);
		}

		/**
		 * Number of entries in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Entry at ''position''.
		 *
		 * @param position zero-based index
		 * @return the entry, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''SystemInfo.list'', ''OsVersion.list'', and
		 * ''OsReleases.list'' for ''agent_id'' and replace {@link items}.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<KeyValue>();
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			this.fetch.begin(agent_id, this.epoch);
		}

		/**
		 * Run the three subquery RPCs for ''agent_id'' and build
		 * {@link items}.
		 *
		 * @param agent_id selected machine agent id
		 * @param epoch load generation for cancellation
		 */
		private async void fetch(int agent_id, int epoch)
		{
			var labels = new Gee.HashMap<string, string>();
			var formats = new Gee.HashMap<string, string>();
			this.read_csv("system_info", out labels, out formats);
			var built = new Gee.ArrayList<KeyValue>();

			var sys_req = new OLLMrpc.Request();
			// avoid async vala ctor bug
			sys_req.method = "SystemInfo.list";
			sys_req.args = OLLMrpc.args("ib", agent_id, false);
			var sys_rows = yield this.call_list<Argus.Shared.OSQuery.SystemInfo>(
				sys_req, "System info", epoch);
			if (epoch != this.epoch) {
				return;
			}
			if (sys_rows.size == 0) {
				built.add(new KeyValue() {
					key = "System info",
					val = "None",
					expander = true,
					expanded = false
				});
			}
			if (sys_rows.size > 0) {
				var sys = sys_rows.get(0);
				this.append_section(built, "System info",
					sys.hostname != "" ? sys.hostname : sys.computer_name,
					sys, labels, formats, {
						"id", "agent-id", "deleted-dt",
						"operating-system", "major", "minor", "patch", "build",
						"platform", "platform-like", "codename", "arch",
						"os-updated", "os-status", "reboot-required",
						"logged-in-users"
					});
			}

			var os_req = new OLLMrpc.Request();
			// avoid async vala ctor bug
			os_req.method = "OsVersion.list";
			os_req.args = OLLMrpc.args("i", agent_id);
			var os_rows = yield this.call_list<Argus.Shared.OSQuery.OsVersion>(
				os_req, "OS version", epoch);
			if (epoch != this.epoch) {
				return;
			}
			if (os_rows.size == 0) {
				built.add(new KeyValue() {
					key = "OS version",
					val = "None",
					expander = true,
					expanded = false
				});
			}
			if (os_rows.size > 0) {
				var os = os_rows.get(0);
				this.append_section(built, "OS version",
					(os.name + " " + os.version).strip(),
					os, labels, formats, { "id", "agent-id", "deleted-dt" });
			}

			var rel_req = new OLLMrpc.Request();
			// avoid async vala ctor bug
			rel_req.method = "OsReleases.list";
			rel_req.args = OLLMrpc.args("i", agent_id);
			var rel_rows = yield this.call_list<Argus.Shared.OsReleases>(
				rel_req, "OS release", epoch);
			if (epoch != this.epoch) {
				return;
			}
			if (rel_rows.size == 0) {
				built.add(new KeyValue() {
					key = "OS release",
					val = "None",
					expander = true,
					expanded = false
				});
			}
			if (rel_rows.size > 0) {
				var rel = rel_rows.get(0);
				this.append_section(built, "OS release", rel.name,
					rel, labels, formats, { "id" });
			}

			this.items = built;
			this.busy = false;
		}

		/**
		 * Execute one list RPC and return typed rows, or emit {@link failed}.
		 *
		 * @param req RPC request
		 * @param title section title used on error
		 * @param epoch load generation for cancellation
		 * @return list of decoded rows, empty on error or no matches
		 */
		private async Gee.ArrayList<T> call_list<T>(
			OLLMrpc.Request req,
			string title,
			int epoch
		) {
			var rows = new Gee.ArrayList<T>();
			OLLMrpc.Response response;
			try {
				response = yield this.app.rpc.call(req);
			} catch (GLib.Error e) {
				if (epoch == this.epoch) {
					this.busy = false;
					this.failed("Could not load " + title, e.message);
				}
				return rows;
			}
			if (epoch != this.epoch) {
				return rows;
			}
			if (response.error != null) {
				this.busy = false;
				this.failed("Could not load " + title, response.error.message);
				return rows;
			}
			if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
				return (Gee.ArrayList<T>) response.retval.get_object();
			}
			return rows;
		}

		/**
		 * Append an expander header and formatted properties for ''row''.
		 *
		 * @param built target list of entries
		 * @param title section heading
		 * @param summary expander subtitle text
		 * @param row source row object
		 * @param labels CSV column labels
		 * @param formats CSV column formats
		 * @param skip property names to omit
		 */
		private void append_section(
			Gee.ArrayList<KeyValue> built,
			string title,
			string summary,
			GLib.Object row,
			Gee.HashMap<string, string> labels,
			Gee.HashMap<string, string> formats,
			string[] skip
		) {
			built.add(new KeyValue() {
				key = title,
				val = summary,
				expander = true,
				expanded = true
			});
			foreach (var prop in row.get_class().list_properties()) {
				if (GLib.strv_contains(skip, prop.name)) {
					continue;
				}
				built.add(this.format_entry(row, prop, labels, formats));
			}
		}

		/**
		 * Format one GObject property into a {@link KeyValue} row.
		 *
		 * @param row source row object
		 * @param prop property descriptor
		 * @param labels CSV column labels
		 * @param formats CSV column formats
		 * @return formatted key-value entry
		 */
		private KeyValue format_entry(
			GLib.Object row,
			GLib.ParamSpec prop,
			Gee.HashMap<string, string> labels,
			Gee.HashMap<string, string> formats
		) {
			var label = "";
			if (labels.has_key(prop.name)) {
				label = labels.get(prop.name);
			}
			if (label == "") {
				switch (prop.name) {
					case "added-dt":
						label = "Added";
						break;

					case "updated-dt":
						label = "Updated";
						break;

					case "short-id":
						label = "Short ID";
						break;

					case "is-lts":
						label = "LTS";
						break;

					default:
						var raw = prop.name.replace("-", " ");
						label = raw.length > 0 ?
							raw.substring(0, 1).up() + raw.substring(1) : raw;
						break;
				}
			}
			var format = "text";
			if (formats.has_key(prop.name)) {
				format = formats.get(prop.name);
			}
			if (!formats.has_key(prop.name)) {
				switch (prop.name) {
					case "added-dt":
					case "updated-dt":
					case "updated":
						format = "date";
						break;

					default:
						if (prop.value_type == GLib.Type.INT ||
							prop.value_type == GLib.Type.INT64) {
							format = "number";
						}
						break;
				}
			}
			var value = GLib.Value(prop.value_type);
			row.get_property(prop.name, ref value);
			var shown = "";
			var flag = -1;
			var tip = "";
			switch (format) {
				case "bytes":
					var count = prop.value_type == GLib.Type.INT64 ?
						(uint64) value.get_int64() :
						(uint64) value.get_int();
					shown = GLib.format_size(count, GLib.FormatSizeFlags.IEC_UNITS)
						.replace("\xc2\xa0", " ")
						.replace("TiB", "TB")
						.replace("GiB", "GB")
						.replace("MiB", "MB")
						.replace("KiB", "KB")
						.replace(".0 ", " ");
					break;

				case "date":
					var stamp = prop.value_type == GLib.Type.INT64 ?
						value.get_int64() :
						(int64) value.get_int();
					if (stamp > 0) {
						var when = new GLib.DateTime.from_unix_local(stamp);
						if (when != null) {
							var formatted = when.format("%Y-%m-%d");
							shown = formatted != null ? formatted : "";
							var full = when.format("%Y-%m-%d %H:%M:%S");
							tip = full != null ? full : "";
						}
					}
					break;

				case "status":
					flag = value.get_int();
					if (row is Argus.Shared.OSQuery.OsVersion &&
						prop.name == "pkgs-status" &&
						((Argus.Shared.OSQuery.OsVersion) row).pkgs_updated == 0) {
						flag = -1;
					}
					switch (flag) {
						case 1:
							shown = "Up to date";
							break;

						case 2:
							shown = "Update available";
							break;

						case 0:
							shown = "Update waiting";
							break;

						default:
							shown = "Unchecked";
							break;
					}
					break;

				default:
					switch (prop.value_type) {
						case GLib.Type.INT:
							shown = value.get_int().to_string();
							break;

						case GLib.Type.INT64:
							shown = value.get_int64().to_string();
							break;

						default:
							var str = value.get_string();
							shown = str != null ? str : "";
							break;
					}
					break;
			}
			return new KeyValue() {
				key = label,
				val = shown,
				expander = false,
				format = format,
				status = flag,
				tooltip = tip
			};
		}
	}
}
```

---

### 5. `controller/tab/Asset/Machine/General.vala` — render `Store.MachineGeneral`

**Why:** Render each `expander == true` item as an `Adw.ExpanderRow` and each `expander == false` item as an aligned key-value row with `.vertical-list` styling.

**Where:** new file `controller/tab/Asset/Machine/General.vala`.

**Depends on:** items 3, 4.

#### Add — `controller/tab/Asset/Machine/General.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Tab.Asset.Machine
{
	/**
	 * Per-machine General detail tab in {@link Detail}.
	 *
	 * Renders {@link Argus.Controller.Store.MachineGeneral}
	 * ({@link GLib.ListModel} of {@link Argus.Controller.Store.KeyValue})
	 * as collapsible {@link Adw.ExpanderRow} groups with aligned
	 * key-value rows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.General(window);
	 * tab.load(1);
	 * }}}
	 */
	public class General : Gtk.Box
	{
		private Argus.Controller.Store.MachineGeneral store;
		private Gtk.ListBox list;

		/**
		 * True while a later load is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the per-machine General vertical key-value view.
		 *
		 * @param window the window this page belongs to
		 */
		public General(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.MachineGeneral(window.app);
			this.list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.NONE,
				css_classes = { "boxed-list", "vertical-list" },
				hexpand = true,
				valign = Gtk.Align.START
			};
			this.store.items_changed.connect((position, removed, added) => {
				var child = this.list.get_first_child();
				while (child != null) {
					var next = child.get_next_sibling();
					this.list.remove(child);
					child = next;
				}
				var key_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
				var expander = new Adw.ExpanderRow();
				var has_expander = false;
				foreach (var entry in this.store.items) {
					if (entry.expander) {
						expander = new Adw.ExpanderRow() {
							title = entry.key,
							subtitle = entry.val,
							use_markup = false,
							expanded = entry.expanded
						};
						expander.add_css_class("vertical-list-expander");
						this.list.append(expander);
						has_expander = true;
						continue;
					}
					if (!has_expander) {
						continue;
					}
					var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
						css_classes = { "vertical-list-row" },
						hexpand = true
					};
					var key_label = new Gtk.Label(entry.key) {
						xalign = 0,
						yalign = 0,
						css_classes = { "dim-label", "vertical-list-key" }
					};
					key_group.add_widget(key_label);
					row.append(key_label);
					if (entry.format == "status") {
						var status_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
							hexpand = true
						};
						var dot = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							css_classes = { "status-dot" },
							halign = Gtk.Align.START,
							valign = Gtk.Align.CENTER,
							visible = entry.status == 0 || entry.status == 1 || entry.status == 2
						};
						switch (entry.status) {
							case 1:
								dot.add_css_class("status-ok");
								break;

							case 2:
								dot.add_css_class("status-warn");
								break;

							case 0:
								dot.add_css_class("status-bad");
								break;

							default:
								break;
						}
						status_box.append(dot);
						status_box.append(new Gtk.Label(entry.val) {
							xalign = 0,
							hexpand = true,
							selectable = true,
							css_classes = { "vertical-list-value" }
						});
						row.append(status_box);
						expander.add_row(row);
						continue;
					}
					var val_label = new Gtk.Label(entry.val) {
						xalign = 0,
						hexpand = true,
						wrap = true,
						wrap_mode = Pango.WrapMode.WORD_CHAR,
						selectable = true,
						css_classes = { "vertical-list-value" }
					};
					if (entry.tooltip != "") {
						val_label.tooltip_text = entry.tooltip;
					}
					row.append(val_label);
					expander.add_row(row);
				}
			});
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			spinner.add_css_class("package-wait");
			var scroll = new Gtk.ScrolledWindow() {
				child = this.list,
				hexpand = true,
				vexpand = true
			};
			var overlay = new Gtk.Overlay() {
				child = scroll,
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(spinner);
			this.store.notify["busy"].connect(() => {
				spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = this.store.busy && this.store.get_n_items() > 0;
			});
			this.append(overlay);
		}

		/**
		 * Load General machine fields for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.store.load(agent_id);
		}
	}
}
```

---

### 6. `controller/tab/Asset/Machine/Detail.vala` & `namespace.vala` — wire `General` tab first

**Why:** Add `General` as the first tab in `Machine.Detail` and default selection to `"general"`.

**Where:** `controller/tab/Asset/Machine/Detail.vala` and `controller/tab/Asset/Machine/namespace.vala`.

**Depends on:** item 5.

#### Remove (`controller/tab/Asset/Machine/namespace.vala`)

```vala
 * {@link Detail} switches per-machine tabs below
 * {@link Argus.Controller.Tab.Asset.SystemInfo}. Per-machine tabs load
 * {@link LoggedInUsers}, {@link DebPackages}, {@link RpmPackages},
 * {@link Programs}, {@link InterfaceAddresses}, and {@link CpuInfo}
 * for the selected machine's ''agent_id''.
```

#### Replace with (`controller/tab/Asset/Machine/namespace.vala`)

```vala
 * {@link Detail} switches per-machine tabs below
 * {@link Argus.Controller.Tab.Asset.SystemInfo}. Per-machine tabs load
 * {@link General}, {@link LoggedInUsers}, {@link DebPackages},
 * {@link RpmPackages}, {@link Programs}, {@link InterfaceAddresses},
 * and {@link CpuInfo} for the selected machine's ''agent_id''.
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala` fields)

```vala
		private Adw.Toggle users_toggle;
		private Adw.Toggle debian_toggle;
		private Adw.Toggle rpm_toggle;
		private Adw.Toggle windows_toggle;
		private Adw.Toggle interfaces_toggle;
		private Adw.Toggle cpus_toggle;
		private LoggedInUsers users;
		private DebPackages debian;
		private RpmPackages rpm;
		private Programs windows;
		private InterfaceAddresses interfaces;
		private CpuInfo cpus;
		private int current_agent_id = 0;
		private Argus.Shared.OSQuery.PackageManager current_pm = Argus.Shared.OSQuery.PackageManager.UNKNOWN;
		private bool has_pm = false;
		private bool users_loaded = false;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala` fields)

```vala
		private Adw.Toggle general_toggle;
		private Adw.Toggle users_toggle;
		private Adw.Toggle debian_toggle;
		private Adw.Toggle rpm_toggle;
		private Adw.Toggle windows_toggle;
		private Adw.Toggle interfaces_toggle;
		private Adw.Toggle cpus_toggle;
		private General general;
		private LoggedInUsers users;
		private DebPackages debian;
		private RpmPackages rpm;
		private Programs windows;
		private InterfaceAddresses interfaces;
		private CpuInfo cpus;
		private int current_agent_id = 0;
		private Argus.Shared.OSQuery.PackageManager current_pm = Argus.Shared.OSQuery.PackageManager.UNKNOWN;
		private bool has_pm = false;
		private bool general_loaded = false;
		private bool users_loaded = false;
```

#### Add (`controller/tab/Asset/Machine/Detail.vala` constructor, directly after `this.group.add_css_class("both");`)

```vala
			this.general = new General(window);
			this.pages.add_titled_with_icon(
				this.general, "general", "General", "dialog-information-symbolic");
			var general_spin = new Adw.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var general_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			general_row.append(new Gtk.Image.from_icon_name("dialog-information-symbolic"));
			general_row.append(new Gtk.Label("General"));
			this.general_toggle = new Adw.Toggle() {
				name = "general",
				child = new Gtk.CenterBox() {
					center_widget = general_row,
					end_widget = general_spin,
					hexpand = true
				}
			};
			this.general.bind_property("refreshing", general_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
```

#### Add (`controller/tab/Asset/Machine/Detail.vala`, `active-name` switch, before `case "users":`)

```vala
					case "general":
						if (this.general_loaded) {
							break;
						}
						this.general_loaded = true;
						this.general.load(this.current_agent_id);
						break;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`, `clear()`)

```vala
		public void clear()
		{
			this.current_agent_id = 0;
			this.users_loaded = false;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			this.interfaces_loaded = false;
			this.cpus_loaded = false;
		}
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`, `clear()`)

```vala
		public void clear()
		{
			this.current_agent_id = 0;
			this.general_loaded = false;
			this.users_loaded = false;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			this.interfaces_loaded = false;
			this.cpus_loaded = false;
		}
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`, `show_machine()`)

```vala
			this.current_agent_id = 0;
			this.users_loaded = false;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			this.interfaces_loaded = false;
			this.cpus_loaded = false;
			var pm = machine.package_manager();
			if (!this.has_pm || pm != this.current_pm) {
				this.has_pm = true;
				this.current_pm = pm;
				var previous = "";
				if (this.group.active_name != null) {
					previous = this.group.active_name;
				}
				var pkg_tab = "";
				while (this.group.n_toggles > 0) {
					var toggle = this.group.get_toggle(0);
					if (toggle == null) {
						break;
					}
					this.group.remove(toggle);
				}
				this.group.add(this.users_toggle);
				switch (pm) {
					case Argus.Shared.OSQuery.PackageManager.APT:
						this.group.add(this.debian_toggle);
						pkg_tab = "debian";
						break;

					case Argus.Shared.OSQuery.PackageManager.DNF:
						this.group.add(this.rpm_toggle);
						pkg_tab = "rpm";
						break;

					case Argus.Shared.OSQuery.PackageManager.WIN:
						this.group.add(this.windows_toggle);
						pkg_tab = "windows";
						break;

					default:
						break;
				}
				this.group.add(this.interfaces_toggle);
				this.group.add(this.cpus_toggle);
				var target = "users";
				switch (previous) {
					case "users":
					case "interfaces":
					case "cpus":
						target = previous;
						break;

					case "debian":
					case "rpm":
					case "windows":
						if (pkg_tab != "") {
							target = pkg_tab;
						}
						break;

					default:
						break;
				}
				this.group.active_name = target;
			}
			this.current_agent_id = agent_id;
			var active = "users";
			if (this.group.active_name != null) {
				active = this.group.active_name;
			}
			this.pages.visible_child_name = active;
			switch (active) {
				case "users":
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`, `show_machine()`)

```vala
			this.current_agent_id = 0;
			this.general_loaded = false;
			this.users_loaded = false;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			this.interfaces_loaded = false;
			this.cpus_loaded = false;
			var pm = machine.package_manager();
			if (!this.has_pm || pm != this.current_pm) {
				this.has_pm = true;
				this.current_pm = pm;
				var previous = "";
				if (this.group.active_name != null) {
					previous = this.group.active_name;
				}
				var pkg_tab = "";
				while (this.group.n_toggles > 0) {
					var toggle = this.group.get_toggle(0);
					if (toggle == null) {
						break;
					}
					this.group.remove(toggle);
				}
				this.group.add(this.general_toggle);
				this.group.add(this.users_toggle);
				switch (pm) {
					case Argus.Shared.OSQuery.PackageManager.APT:
						this.group.add(this.debian_toggle);
						pkg_tab = "debian";
						break;

					case Argus.Shared.OSQuery.PackageManager.DNF:
						this.group.add(this.rpm_toggle);
						pkg_tab = "rpm";
						break;

					case Argus.Shared.OSQuery.PackageManager.WIN:
						this.group.add(this.windows_toggle);
						pkg_tab = "windows";
						break;

					default:
						break;
				}
				this.group.add(this.interfaces_toggle);
				this.group.add(this.cpus_toggle);
				var target = "general";
				switch (previous) {
					case "general":
					case "users":
					case "interfaces":
					case "cpus":
						target = previous;
						break;

					case "debian":
					case "rpm":
					case "windows":
						if (pkg_tab != "") {
							target = pkg_tab;
						}
						break;

					default:
						break;
				}
				this.group.active_name = target;
			}
			this.current_agent_id = agent_id;
			var active = "general";
			if (this.group.active_name != null) {
				active = this.group.active_name;
			}
			this.pages.visible_child_name = active;
			switch (active) {
				case "general":
					if (this.general_loaded) {
						break;
					}
					this.general_loaded = true;
					this.general.load(agent_id);
					break;

				case "users":
```

---

### 7. `controller/resources/style.css` — vertical list CSS styling

**Why:** Dedicated styling for vertical key-value lists distinct from `ColumnView` horizontal rows.

**Where:** end of `controller/resources/style.css`.

**Depends on:** item 5.

#### Add — end of `controller/resources/style.css`

```css
.vertical-list {
	margin: 12px;
}

.vertical-list-row {
	padding: 8px 16px;
}

.vertical-list-expander list > row:nth-child(even) {
	background-color: color-mix(in srgb, currentColor 4%, transparent);
}

.vertical-list-key {
	min-width: 140px;
}
```

---

### 8. `controller/meson.build` & `docs/meson.build` — add new source files

**Why:** Compile `Store.Base`, `Store.KeyValue`, `Store.MachineGeneral`, and `Machine.General`, and include them in Valadoc generation in dependency order.

**Where:** `controller/meson.build` (`sources`) and `docs/meson.build` (`valadoc_sources`).

**Depends on:** items 1, 3, 4, 5.

#### Remove (`controller/meson.build`)

```meson
	'store/Agent.vala',
```

#### Replace with (`controller/meson.build`)

```meson
	'store/Base.vala',
	'store/KeyValue.vala',
	'store/Agent.vala',
```

#### Remove (`controller/meson.build`)

```meson
	'store/Repository.vala',
```

#### Replace with (`controller/meson.build`)

```meson
	'store/Repository.vala',
	'store/MachineGeneral.vala',
```

#### Remove (`controller/meson.build`)

```meson
	'tab/Asset/Machine/namespace.vala',
	'tab/Asset/Machine/LoggedInUsers.vala',
```

#### Replace with (`controller/meson.build`)

```meson
	'tab/Asset/Machine/namespace.vala',
	'tab/Asset/Machine/General.vala',
	'tab/Asset/Machine/LoggedInUsers.vala',
```

#### Remove (`docs/meson.build`)

```meson
  '../controller/store/Agent.vala',
```

#### Replace with (`docs/meson.build`)

```meson
  '../controller/store/Base.vala',
  '../controller/store/KeyValue.vala',
  '../controller/store/Agent.vala',
```

#### Remove (`docs/meson.build`)

```meson
  '../controller/store/Repository.vala',
```

#### Replace with (`docs/meson.build`)

```meson
  '../controller/store/Repository.vala',
  '../controller/store/MachineGeneral.vala',
```

#### Remove (`docs/meson.build`)

```meson
  '../controller/tab/Asset/Machine/namespace.vala',
  '../controller/tab/Asset/Machine/LoggedInUsers.vala',
```

#### Replace with (`docs/meson.build`)

```meson
  '../controller/tab/Asset/Machine/namespace.vala',
  '../controller/tab/Asset/Machine/General.vala',
  '../controller/tab/Asset/Machine/LoggedInUsers.vala',
```

---

## Next

- ⏳ 🔷 Review code hunks `### 1`–`### 8` above (plus RPCs in [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md)) and approve to apply.
