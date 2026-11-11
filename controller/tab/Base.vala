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
	 * table, and compiled into ''/argusrm/columns/''. The first
	 * field is the column header. Then the database name in
	 * JSON, whether it starts shown, the width, and
	 * a format. A hyphen in that name stands in for an
	 * underscore. The first row is only for reading the
	 * file, and it is
	 * ignored. A blank line follows it. An empty line is
	 * skipped.
	 * A blank line separates a category. The file order is the
	 * column order. The first column is the row header. The
	 * header menu is that list. The last visible column stays.
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
		 * {@link table}. The first row is only for reading the
		 * file. Pipes and spaces lay the names out. That row is
		 * ignored, and a blank line follows it. Each later row
		 * is the column header, the database name in
		 * JSON, shown, width, and format. A hyphen stands in
		 * for an underscore.
		 * ''ON'' starts visible. ''off'' does not. Width is
		 * pixels. ''number'' is right aligned. ''text'' and
		 * ''date'' are labels.
		 * ''status'' and ''tick'' are an image. An empty line is
		 * skipped. It separates a category, and the file order
		 * is the column order. The first column is the row
		 * header, in bold.
		 * The menu action uses that database name.
		 * Hiding the last visible column does nothing.
		 * {@link column_factory} builds each cell.
		 *
		 * @param grid the view that receives the columns
		 * @param table file name under columns, without ''.csv''
		 */
		public void column_menu(Gtk.ColumnView grid, string table)
		{
			var text = (string) GLib.resources_lookup_data(
				"/argusrm/columns/" + table + ".csv",
				GLib.ResourceLookupFlags.NONE).get_data();
			var columns = new Gee.ArrayList<Gtk.ColumnViewColumn>();
			var menu = new GLib.Menu();
			var group = new GLib.SimpleActionGroup();
			var headings = true;
			var first = true;
			this.insert_action_group(table, group);
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
				var header_column = first;
				first = false;
				var width = 0;
				var factory = this.column_factory(format, header_column);
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

		/**
		 * Factory for one column format.
		 *
		 * ''text'' and ''date'' are labels. ''number'' is right
		 * aligned. ''status'' and ''tick'' are an image. The row
		 * header is bold. Further formats are further cases.
		 *
		 * @param format text, number, date, status, or tick
		 * @param header_column true for the row header
		 * @return the factory that sets up each cell
		 */
		private Gtk.SignalListItemFactory column_factory(string format, bool header_column)
		{
			var attrs = new Pango.AttrList();
			attrs.insert(Pango.attr_weight_new(Pango.Weight.SEMIBOLD));
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				switch (format) {
					case "status":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true
						};
						break;

					case "tick":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true
						};
						break;

					case "number":
						item.child = new Gtk.Label("") {
							xalign = 1,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					case "date":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					case "text":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					default:
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;
				}
			});
			return factory;
		}
	}
}
