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

namespace Argus.Controller.Tab
{
	/**
	 * Shared behaviour for a controller page.
	 *
	 * A page that shows a grid uses {@link column_menu}. The
	 * definition is a CSV under ''columns/'', named for that
	 * table, and compiled into ''/argusrm/columns/''. A row is
	 * the title, the action name, whether it starts shown, and
	 * the width. The header menu is that list. The last visible
	 * column stays.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.column_menu(grid, "machines");
	 * }}}
	 */
	public abstract class Base : Gtk.Box
	{
		/**
		 * Add one table's columns and its header menu.
		 *
		 * The file is ''/argusrm/columns/TABLE.csv''. TABLE is
		 * {@link table}. The first row is the headings. Each
		 * later row is title, name, shown, and width. ''on''
		 * starts visible. Width is pixels. The menu action is
		 * TABLE.name. Hiding the last visible column does
		 * nothing. A missing file leaves the grid unchanged.
		 *
		 * @param grid the view that receives the columns
		 * @param table file name under columns, without ''.csv''
		 */
		public void column_menu(Gtk.ColumnView grid, string table)
		{
			var text = "";
			try {
				var bytes = GLib.resources_lookup_data(
					"/argusrm/columns/" + table + ".csv",
					GLib.ResourceLookupFlags.NONE);
				text = (string) bytes.get_data();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			var columns = new Gee.ArrayList<Gtk.ColumnViewColumn>();
			var menu = new GLib.Menu();
			var group = new GLib.SimpleActionGroup();
			this.insert_action_group(table, group);
			foreach (var line in text.split("\n")) {
				var parts = line.strip().split(",");
				if (parts.length < 4) {
					continue;
				}
				if (parts[0].strip() == "title" && parts[1].strip() == "name") {
					continue;
				}
				var title = parts[0].strip();
				var name = parts[1].strip();
				if (title == "" || name == "") {
					continue;
				}
				var starts = parts[2].strip() == "on";
				var width = 0;
				var factory = new Gtk.SignalListItemFactory();
				factory.setup.connect((obj) => {
					var item = (Gtk.ListItem) obj;
					item.child = new Gtk.Label("") {
						xalign = 0,
						hexpand = true
					};
				});
				var column = new Gtk.ColumnViewColumn(title, factory) {
					resizable = true,
					visible = starts
				};
				if (int.try_parse(parts[3].strip(), out width) && width > 0) {
					column.fixed_width = width;
				}
				grid.append_column(column);
				columns.add(column);
				var action = new GLib.SimpleAction.stateful(
					name, null, new GLib.Variant.boolean(starts));
				action.change_state.connect((value) => {
					var on = value.get_boolean();
					if (on) {
						action.set_state(value);
						column.visible = true;
						return;
					}
					var others = 0;
					foreach (var other in columns) {
						if (other == column || !other.visible) {
							continue;
						}
						others++;
					}
					if (others < 1) {
						return;
					}
					action.set_state(value);
					column.visible = false;
				});
				group.add_action(action);
				menu.append(title, table + "." + name);
				column.header_menu = menu;
			}
		}
	}
}
