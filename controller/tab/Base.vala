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
	 * A grid page sets {@link table} and {@link grid}, then calls {@link column_menu}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Object(table: "system_info");
	 * this.grid = view;
	 * this.column_menu();
	 * }}}
	 */
	public abstract class Base : Gtk.Box
	{
		/**
		 * File name under columns, without ''.csv''.
		 */
		public string table { get; set; default = ""; }
		/**
		 * Grid that receives the columns.
		 */
		public Gtk.ColumnView grid { get; set; }

		/**
		 * Add this table's columns and its header menu.
		 *
		 * The file is ''/argusrm/columns/'' plus {@link table}.
		 *
		 *  * The first row is headings. Blank lines are skipped.
		 *  * Each row is the header, the JSON name, ''ON'' or ''off'',
		 *    the width, the format, and sort.
		 *  * Sort is ''ON'' or ''off''. ''ON'' sorts. A missing field
		 *    does not.
		 *  * A hyphen in the JSON name stands in for an underscore.
		 *  * The file order is the column order. The first column is the row header.
		 *  * The menu stays open so several columns can be chosen.
		 *  * Hiding the last visible column does nothing.
		 *
		 * @return the group whose actions show and hide columns
		 */
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
				var header_column = first;
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
				if (width == 0) {
					column.expand = true;
				}
				if (parts.length > 5 && parts[5].strip() == "ON") {
					column.sorter = this.column_sorter(name, format);
				}
				this.grid.append_column(column);
				columns.add(column);
				var action = new GLib.SimpleAction.stateful(
					name, null, new GLib.Variant.boolean(starts));
				action.change_state.connect((value) => {
					var on = value.get_boolean();
					var keep = true;
					if (!on) {
						var others = 0;
						foreach (var other in columns) {
							if (other == column || !other.visible) {
								continue;
							}
							others++;
						}
						if (others < 1) {
							keep = false;
						}
					}
					if (keep) {
						action.set_state(value);
						column.visible = on;
					}
				});
				group.add_action(action);
				var item = new GLib.MenuItem(null, null);
				item.set_attribute("custom", "s", name);
				menu.append_item(item);
				var row = new Gtk.CheckButton.with_label(title) {
					active = starts,
					hexpand = true,
					halign = Gtk.Align.FILL
				};
				row.toggled.connect(() => {
					action.change_state(new GLib.Variant.boolean(row.active));
					if (row.active == action.state.get_boolean()) {
						return;
					}
					row.active = action.state.get_boolean();
				});
				var tick = new Gtk.GestureClick() {
					button = 1,
					exclusive = true,
					propagation_phase = Gtk.PropagationPhase.CAPTURE
				};
				tick.pressed.connect((n_press, x, y) => {
					tick.set_state(Gtk.EventSequenceState.CLAIMED);
				});
				row.add_controller(tick);
				menu_popup.add_child(row, name);
			}
			var open = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY,
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			open.pressed.connect((n_press, x, y) => {
				var picked = this.grid.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (picked != null && picked != this.grid &&
					picked.get_data<Gtk.ListItem>("argus-grid-row") == null) {
					picked = picked.parent;
				}
				if (picked != null && picked != this.grid) {
					open.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
				open.set_state(Gtk.EventSequenceState.CLAIMED);
				var where = Gdk.Rectangle() {
					x = (int) x,
					y = (int) y,
					width = 1,
					height = 1
				};
				menu_popup.set_pointing_to(where);
				menu_popup.popup();
			});
			this.grid.add_controller(open);
			return group;
		}

		/**
		 * Build {@link grid} over ''model'' with sorting and column menu.
		 *
		 * Wraps ''model'' in a {@link Gtk.SortListModel} bound to the
		 * grid's own sorter, then sets up {@link column_menu}.
		 *
		 * @param model store or filter model supplying rows
		 * @param multi true for {@link Gtk.MultiSelection}, false for
		 *   {@link Gtk.SingleSelection}
		 * @return the group whose actions show and hide columns
		 */
		protected GLib.SimpleActionGroup column_grid(GLib.ListModel model, bool multi = false)
		{
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(multi
				? (Gtk.SelectionModel) new Gtk.MultiSelection(sorted)
				: (Gtk.SelectionModel) new Gtk.SingleSelection(sorted)) {
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
		 *  * Numeric and boolean properties return
		 *    {@link Gtk.NumericSorter}.
		 *  * ''remove'' sorts by ''installed''.
		 *  * String properties return {@link Gtk.StringSorter}
		 *    ignoring case.
		 *  * Returns null when the property is not on the row class yet.
		 *
		 * @param name JSON name. A hyphen is an underscore.
		 * @param format column format from the CSV
		 * @return the sorter for this column, or null when missing
		 */
		private Gtk.Sorter? column_sorter(string name, string format)
		{
			var sort_name = format == "remove" ? "installed" : name;
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

		/**
		 * Factory for one column format.
		 *
		 *  * ''text'' and ''date'' are labels.
		 *  * ''number'' is right aligned.
		 *  * ''bytes'' is a byte count, shown as a size, right aligned.
		 *  * ''maxver'' is a label. It is red with white text when
		 *    it differs from ''min-version'' on that row.
		 *  * ''bin'' is a rubbish bin. It shows when the count is
		 *    above zero. The mouseover is that count, then
		 *    ''uninstallable''.
		 *  * ''remove'' is that same bin. The count is ''installed''.
		 *    The mouseover is the count alone.
		 *  * ''status'' and ''tick'' are an image.
		 *  * The row header is bold.
		 *
		 * A column whose database name is on the row fills its cell. Other columns stay empty.
		 *
		 * @param name JSON name. A hyphen is an underscore.
		 * @param format text, number, bytes, date, status, tick, bin, or remove
		 * @param header_column true for the row header
		 * @return the factory that sets up each cell
		 */
		private Gtk.SignalListItemFactory column_factory(
			string name,
			string format,
			bool header_column
		) {
			var attrs = new Pango.AttrList();
			attrs.insert(Pango.attr_weight_new(Pango.Weight.SEMIBOLD));
			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				switch (format) {
					case "status":
						item.child = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							css_classes = { "status-dot" },
							halign = Gtk.Align.CENTER,
							valign = Gtk.Align.CENTER,
							visible = false
						};
						break;

					case "tick":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true
						};
						break;

					case "bin":
					case "remove":
						item.child = new Gtk.Image() {
							icon_name = "user-trash-symbolic",
							halign = Gtk.Align.CENTER,
							hexpand = true,
							visible = false
						};
						break;

					case "number":
					case "bytes":
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
				item.child.set_data("argus-grid-row", item);
			});
			factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (GLib.Object) item.item;
				item.child.remove_css_class("dim-label");
				var dim_prop = row.get_class().find_property("dimmed");
				if (dim_prop != null && dim_prop.value_type == GLib.Type.BOOLEAN) {
					var dim_val = GLib.Value(GLib.Type.BOOLEAN);
					row.get_property("dimmed", ref dim_val);
					if (dim_val.get_boolean()) {
						item.child.add_css_class("dim-label");
					}
				}
				var lookup = name;
				if (format == "remove") {
					lookup = "installed";
				}
				var prop = row.get_class().find_property(lookup);
				if (prop == null) {
					return;
				}
				var value = GLib.Value(prop.value_type);
				((GLib.Object) row).get_property(lookup, ref value);
				var shown = "";
				switch (prop.value_type) {
					case GLib.Type.INT:
						shown = value.get_int().to_string();
						break;

					case GLib.Type.INT64:
						shown = value.get_int64().to_string();
						break;

					default:
						shown = value.get_string();
						break;
				}
				switch (format) {
					case "status":
						var flag = -1;
						if (prop.value_type == GLib.Type.INT) {
							flag = value.get_int();
						}
						var dot = (Gtk.Box) item.child;
						dot.remove_css_class("status-ok");
						dot.remove_css_class("status-warn");
						dot.remove_css_class("status-bad");
						dot.visible = flag == 0 || flag == 1 || flag == 2;
						switch (flag) {
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
						break;

					case "date":
						var stamp = (int64) 0;
						if (prop.value_type == GLib.Type.INT64) {
							stamp = value.get_int64();
						}
						if (prop.value_type == GLib.Type.INT) {
							stamp = (int64) value.get_int();
						}
						var date_text = "";
						if (stamp > 0) {
							var when = new GLib.DateTime.from_unix_local(stamp);
							if (when != null) {
								var formatted = when.format("%Y-%m-%d");
								date_text = formatted != null ? formatted : "";
							}
						}
						((Gtk.Label) item.child).label = date_text;
						break;

					case "tick":
						break;

					case "maxver":
						((Gtk.Label) item.child).label = shown;
						((Gtk.Label) item.child).remove_css_class("version-spread");
						var min_prop = row.get_class().find_property("min-version");
						if (min_prop != null) {
							var min_value = GLib.Value(min_prop.value_type);
							row.get_property("min-version", ref min_value);
							var min_text = min_value.get_string();
							if (min_text == null) {
								min_text = "";
							}
							if (min_text != shown) {
								((Gtk.Label) item.child).add_css_class("version-spread");
							}
						}
						break;

					case "bin":
					case "remove":
						var count = 0;
						if (prop.value_type == GLib.Type.INT) {
							count = value.get_int();
						}
						var image = (Gtk.Image) item.child;
						image.visible = count > 0;
						image.tooltip_text = count.to_string();
						if (format == "bin") {
							image.tooltip_text = count.to_string() + " uninstallable";
						}
						break;

					case "bytes":
						var count = (uint64) 0;
						if (prop.value_type == GLib.Type.INT64) {
							count = (uint64) value.get_int64();
						}
						if (prop.value_type == GLib.Type.INT) {
							count = (uint64) value.get_int();
						}
						var size = GLib.format_size(count, GLib.FormatSizeFlags.IEC_UNITS)
							.replace("\xc2\xa0", " ")
							.replace("TiB", "TB")
							.replace("GiB", "GB")
							.replace("MiB", "MB")
							.replace("KiB", "KB")
							.replace(".0 ", " ");
						((Gtk.Label) item.child).label = size;
						break;

					default:
						((Gtk.Label) item.child).label = shown;
						break;
				}
			});
			return factory;
		}
	}
}
