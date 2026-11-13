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

namespace Argus.Controller.Tab.Asset
{
	/**
	 * ''system_info'' grid on the Assets page.
	 *
	 *  * The switcher titles this half Machines.
	 *  * The filter row writes {@link Argus.Controller.Filters.SystemInfo}.
	 *  * {@link Argus.Controller.Tab.Base.column_menu} builds the columns.
	 *  * A click selects a row. More than one row can be selected.
	 *  * The store loads when this page is shown.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.SystemInfo(window);
	 * }}}
	 */
	public class SystemInfo : Argus.Controller.Tab.Base
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;
		private Argus.Controller.Store.SystemInfo store;
		private Argus.Controller.Filters.SystemInfo filter;
		private bool filling = false;

		/**
		 * Build the filter row and the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public SystemInfo(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "system_info"
			);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.SystemInfo(window.app);
			this.filter = new Argus.Controller.Filters.SystemInfo();
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
			this.filter.visible_text = visible;
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			var group = this.column_grid(rows, true);
			group.action_state_changed.connect((action_name, state) => {
				if (!text_columns.contains(action_name)) {
					return;
				}
				var names = new Gee.ArrayList<string>();
				names.add_all(this.filter.visible_text);
				if (state.get_boolean()) {
					names.add(action_name);
				}
				if (!state.get_boolean()) {
					names.remove(action_name);
				}
				this.filter.visible_text = names;
			});
			var expr = new Gtk.PropertyExpression(typeof(Gtk.StringObject), null, "string");
			var os_names = new Gtk.StringList(null);
			os_names.append("Any");
			var os_drop = new Gtk.DropDown(os_names, expr);
			os_drop.notify["selected"].connect(() => {
				if (this.filling) {
					return;
				}
				var selected = os_drop.selected;
				var model = (Gtk.StringList) os_drop.model;
				var label = "";
				if (selected > 0) {
					label = model.get_string(selected);
				}
				this.filter.os_type = label;
			});
			var status_names = new Gtk.StringList(null);
			status_names.append("Any");
			status_names.append("OS needs update");
			status_names.append("S/W needs update");
			var status_drop = new Gtk.DropDown(status_names, expr);
			status_drop.notify["selected"].connect(() => {
				var selected = status_drop.selected;
				var label = "";
				if (selected > 0) {
					label = status_names.get_string(selected);
				}
				this.filter.status = label;
			});
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			// Note this loads the menu on every single load Uh, which is probably okay
			this.store.items_changed.connect((position, removed, added) => {
				this.filling = true;
				var next = new Gtk.StringList(null);
				next.append("Any");
				var seen = new Gee.ArrayList<string>();
				var keep = next.get_n_items() - 1;
				foreach (var row in this.store.items) {
					var shown = row.operating_system.strip();
					var os_name = shown;
					var major = row.major.strip();
					if (major != "") {
						var at = shown.last_index_of(" " + major);
						if (at > 0) {
							os_name = shown.substring(0, at);
						}
					}
					if (os_name == "" || seen.contains(os_name)) {
						continue;
					}
					seen.add(os_name);
					next.append(os_name);
					if (os_name == this.filter.os_type) {
						keep = next.get_n_items() - 1;
					}
				}
				os_drop.model = next;
				os_drop.selected = keep;
				if (keep == 0) {
					this.filter.os_type = "";
				}
				this.filling = false;
			});
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(new Gtk.Label("OS type"));
			bar.append(os_drop);
			bar.append(new Gtk.Label("Status"));
			bar.append(status_drop);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.map.connect(() => {
				this.store.load();
			});
			this.append(bar);
			this.append(new Gtk.ScrolledWindow() {
				child = this.grid,
				hexpand = true,
				vexpand = true
			});
		}
	}
}
