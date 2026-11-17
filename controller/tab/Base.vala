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
	 * base("system_info", "cpu-brand");
	 * this.column_grid(this.store);
	 * this.content.append(this.overlay);
	 * }}}
	 */
	public abstract class Base : Adw.Bin, Argus.Controller.Store.Base
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
		 * Bold the first column as a row header.
		 */
		public bool bold_header { get; set; default = true; }
		/**
		 * Database name of the column that expands to fill spare width.
		 */
		public string expand_column { get; set; default = ""; }
		/**
		 * Toast overlay wrapping {@link content}.
		 */
		public Adw.ToastOverlay toasts { get; private set; }
		/**
		 * Vertical box inside {@link toasts} where subclasses pack widgets.
		 */
		public Gtk.Box content { get; private set; }
		/**
		 * Scrolled grid overlay carrying {@link spinner}.
		 */
		public Gtk.Overlay overlay { get; private set; }
		/**
		 * Centered loading spinner over {@link grid} when empty.
		 */
		public Adw.Spinner spinner { get; private set; }
		/**
		 * True while a later list call is in flight and rows are already
		 * shown.
		 */
		public bool refreshing { get; protected set; default = false; }

		/**
		 * Emitted when a hold button in a ''bin'' or ''remove'' cell is
		 * held for the full duration.
		 *
		 * @param row model item bound to that grid row
		 */
		public signal void remove_confirmed(GLib.Object row);

		/**
		 * Build the shared vertical {@link content} container inside
		 * {@link toasts}.
		 *
		 * @param table file name under columns without ''.csv''
		 * @param expand_column database name of the expanding column
		 */
		protected Base(string table, string expand_column = "")
		{
			Object(
				table: table,
				expand_column: expand_column
			);
			this.hexpand = true;
			this.vexpand = true;
			this.content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			this.toasts = new Adw.ToastOverlay() {
				child = this.content,
				hexpand = true,
				vexpand = true
			};
			this.child = this.toasts;
		}

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
			foreach (var col in this.read_columns(this.table)) {
				var header_column = first && this.bold_header;
				first = false;
				var factory = this.column_factory(col.name, col.format, header_column);
				var column = new Gtk.ColumnViewColumn(col.title, factory) {
					resizable = true,
					visible = col.visible,
					fixed_width = col.width,
					expand = col.width < 1 || col.name == this.expand_column
				};
				if (col.sort) {
					column.sorter = this.column_sorter(col.name, col.format);
				}
				this.grid.append_column(column);
				columns.add(column);
				var action = new GLib.SimpleAction.stateful(
					col.name, null, new GLib.Variant.boolean(col.visible));
				action.change_state.connect((value) => {
					if (value.get_boolean()) {
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
				var item = new GLib.MenuItem(null, null);
				item.set_attribute("custom", "s", col.name);
				menu.append_item(item);
				var row = new Gtk.CheckButton.with_label(col.title) {
					active = col.visible,
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
				menu_popup.add_child(row, col.name);
			}
			var open = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY,
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			open.pressed.connect((n_press, x, y) => {
				if (this.pick(x, y) != null) {
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
		 * Grid row under a coordinate.
		 *
		 * The return value is the {@link Gtk.ListItem} stored on the widget
		 * under that point, or on an ancestor. A press on a
		 * {@link Argus.Controller.Widget.HoldButton} is that button, so
		 * this returns null. A coordinate that is not a row returns null.
		 *
		 * @param x pointer x in {@link grid} coordinates
		 * @param y pointer y in {@link grid} coordinates
		 * @return the list item for that row, or null
		 */
		protected new Gtk.ListItem? pick(double x, double y)
		{
			var row_widget = this.grid.pick(x, y, Gtk.PickFlags.DEFAULT);
			while (row_widget != null && row_widget != this.grid) {
				if (row_widget is Argus.Controller.Widget.HoldButton) {
					return null;
				}
				var row_item = row_widget.get_data<Gtk.ListItem>("argus-grid-row");
				if (row_item != null) {
					return row_item;
				}
				row_widget = row_widget.parent;
			}
			return null;
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
			this.spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false,
				css_classes = { "package-wait" }
			};
			this.overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			this.overlay.add_overlay(this.spinner);
			var source = model;
			while (source is Gtk.FilterListModel) {
				source = ((Gtk.FilterListModel) source).model;
			}
			((GLib.Object) source).notify["busy"].connect(() => {
				var busy_val = GLib.Value(GLib.Type.BOOLEAN);
				((GLib.Object) source).get_property("busy", ref busy_val);
				var busy = busy_val.get_boolean();
				var count = source.get_n_items();
				this.spinner.visible = busy && count == 0;
				this.refreshing = busy && count > 0;
			});
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
		 *  * ''text'', ''dim-text'', ''date'', ''elapsed'', and ''cidr'' are labels.
		 *  * ''dim-text'' is muted body text.
		 *  * ''controller-kind'' is ''display-kind'' text; ''argus-this-controller'' when this window owns the row.
		 *  * ''recent-created'' / ''recent-last-connected'' bind ''display-created'' / ''display-last''.
		 *  * ''tick-registered'' / ''tick-connected'' are ticks with live ''status'' / ''connected'' bindings.
		 *  * ''elapsed'' shows relative time since a unix timestamp, with
		 *    the local date and time in the tooltip.
		 *  * ''cidr'' appends the prefix length from ''mask'' to ''address''.
		 *  * ''number'' is right aligned.
		 *  * ''mhz'' is a megahertz count with commas and '' MHz'', right aligned.
		 *  * ''bytes'' is a byte count, shown as a size, right aligned.
		 *  * ''maxver'' is a label. It is red with white text when
		 *    it differs from ''min-version'' on that row.
		 *  * ''bin'' is a rubbish bin. It shows when the count is
		 *    above zero. The mouseover is that count, then
		 *    ''uninstallable''.
		 *  * ''remove'' is that same bin. The count is ''installed''.
		 *    The mouseover is the count alone.
		 *  * ''archive'' is a hold button with an archive icon. Holding
		 *    it emits {@link remove_confirmed}. A short click asks for the hold.
		 *  * ''status'' is a centered circle. If the row has a
		 *    ''tooltip-<name>'' string property, it is used as the
		 *    mouseover tooltip.
		 *  * ''tick'' is an image.
		 *  * ''leaf'' is a leaf icon when the int property is not zero.
		 *    The mouseover says the package is top level. A row whose
		 *    ''agent-id'' is zero says that is true on at least one machine.
		 *  * The row header is bold when {@link bold_header} is true.
		 *
		 * A column whose database name is on the row fills its cell. Other columns stay empty.
		 *
		 * @param name JSON name. A hyphen is an underscore.
		 * @param format text, dim-text, controller-kind, recent-created,
		 *   recent-last-connected, tick-registered, tick-connected, number,
		 *   bytes, mhz, date, elapsed, cidr, status, tick, leaf, bin, remove, or archive
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
						var dot = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							css_classes = { "status-dot" },
							halign = Gtk.Align.CENTER,
							valign = Gtk.Align.CENTER,
							hexpand = true,
							visible = false
						};
						var cell = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							hexpand = true,
							vexpand = true
						};
						cell.append(dot);
						item.child = cell;
						break;

					case "tick":
					case "tick-registered":
					case "tick-connected":
					case "leaf":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true,
							pixel_size = 16
						};
						break;

					case "bin":
					case "remove":
					case "archive":
						var hold_button = new Argus.Controller.Widget.HoldButton() {
							halign = Gtk.Align.CENTER,
							valign = Gtk.Align.CENTER,
							visible = false
						};
						if (format == "archive") {
							hold_button.icon_name = "archive-symbolic";
						}
						hold_button.short_click.connect(() => {
							var verb = format == "archive" ? "archive" : "remove";
							this.toasts.add_toast(new Adw.Toast("Click and hold to " + verb));
						});
						hold_button.confirmed.connect(() => {
							if (item.item != null) {
								this.remove_confirmed((GLib.Object) item.item);
							}
						});
						item.child = hold_button;
						break;

					case "number":
					case "bytes":
					case "mhz":
						item.child = new Gtk.Label("") {
							xalign = 1,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					case "controller-kind":
					case "recent-created":
					case "recent-last-connected":
					case "date":
					case "elapsed":
					case "cidr":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					case "dim-text":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							css_classes = { "dim-label" },
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
			factory.unbind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				if (item.child == null) {
					return;
				}
				var binding = item.child.get_data<GLib.Binding>("argus-column-binding");
				if (binding != null) {
					binding.unbind();
				}
				item.child.set_data<GLib.Binding>("argus-column-binding", null);
				if (item.child is Gtk.Label) {
					((Gtk.Label) item.child).remove_css_class("argus-this-controller");
				}
				if (item.child is Argus.Controller.Widget.HoldButton) {
					((Argus.Controller.Widget.HoldButton) item.child).reset();
				}
			});
			factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (GLib.Object) item.item;
				if (item.child == null) {
					return;
				}
				var prior = item.child.get_data<GLib.Binding>("argus-column-binding");
				if (prior != null) {
					prior.unbind();
				}
				item.child.set_data<GLib.Binding>("argus-column-binding", null);
				item.child.remove_css_class("dim-label");
				var dim_prop = row.get_class().find_property("dimmed");
				if (format != "dim-text" && dim_prop != null &&
					dim_prop.value_type == GLib.Type.BOOLEAN) {
					var dim_val = GLib.Value(GLib.Type.BOOLEAN);
					row.get_property("dimmed", ref dim_val);
					if (dim_val.get_boolean()) {
						item.child.add_css_class("dim-label");
					}
				}
				if (format == "dim-text") {
					item.child.add_css_class("dim-label");
				}
				var lookup = name;
				if (format == "remove") {
					lookup = "installed";
				}
				if (format == "archive") {
					lookup = "id";
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

					case GLib.Type.BOOLEAN:
						shown = value.get_boolean() ? "1" : "0";
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
						var cell = (Gtk.Box) item.child;
						var dot = (Gtk.Box) cell.get_first_child();
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
						cell.tooltip_text = null;
						var tip_prop = row.get_class().find_property("tooltip-" + name);
						if (tip_prop != null && tip_prop.value_type == GLib.Type.STRING) {
							var tip_val = GLib.Value(GLib.Type.STRING);
							row.get_property("tooltip-" + name, ref tip_val);
							var tip = tip_val.get_string();
							if (tip != null && tip != "") {
								cell.tooltip_text = tip;
							}
						}
						break;

					case "controller-kind":
						((Gtk.Label) item.child).label = shown;
						((Gtk.Label) item.child).remove_css_class(
							"argus-this-controller");
						var mine = this.grid.get_data<string>(
							"argus-controller-fingerprint");
						if (mine == null || mine == "") {
							break;
						}
						var fp_val = GLib.Value(GLib.Type.STRING);
						row.get_property("fingerprint", ref fp_val);
						if (fp_val.get_string() != mine) {
							break;
						}
						((Gtk.Label) item.child).add_css_class(
							"argus-this-controller");
						break;

					case "recent-created":
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"display-created", item.child, "label",
								GLib.BindingFlags.SYNC_CREATE));
						break;

					case "recent-last-connected":
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"display-last", item.child, "label",
								GLib.BindingFlags.SYNC_CREATE));
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
						var date_label = (Gtk.Label) item.child;
						date_label.label = date_text;
						date_label.tooltip_text = null;
						if (stamp > 0) {
							var tip_when = new GLib.DateTime.from_unix_local(stamp);
							if (tip_when != null) {
								date_label.tooltip_text = tip_when.format("%Y-%m-%d %H:%M:%S");
							}
						}
						break;

					case "elapsed":
						var elapsed_stamp = (int64) 0;
						if (prop.value_type == GLib.Type.INT64) {
							elapsed_stamp = value.get_int64();
						}
						if (prop.value_type == GLib.Type.INT) {
							elapsed_stamp = (int64) value.get_int();
						}
						var elapsed_label = (Gtk.Label) item.child;
						if (elapsed_stamp < 1) {
							elapsed_label.label = "";
							elapsed_label.tooltip_text = null;
							break;
						}
						var elapsed_when = new GLib.DateTime.from_unix_local(elapsed_stamp);
						elapsed_label.tooltip_text = null;
						if (elapsed_when != null) {
							elapsed_label.tooltip_text = elapsed_when.format("%Y-%m-%d %H:%M:%S");
						}
						var diff = new GLib.DateTime.now_local().to_unix() - elapsed_stamp;
						if (diff < 0) {
							diff = 0;
						}
						if (diff < 60) {
							elapsed_label.label = diff.to_string() + "s";
							break;
						}
						if (diff < 3600) {
							elapsed_label.label = (diff / 60).to_string() + "m";
							break;
						}
						if (diff < 86400) {
							var rem_mins = (diff % 3600) / 60;
							elapsed_label.label = (diff / 3600).to_string() + "h";
							if (rem_mins > 0) {
								elapsed_label.label = elapsed_label.label + " " + rem_mins.to_string() + "m";
							}
							break;
						}
						var rem_hours = (diff % 86400) / 3600;
						elapsed_label.label = (diff / 86400).to_string() + "d";
						if (rem_hours > 0) {
							elapsed_label.label = elapsed_label.label + " " + rem_hours.to_string() + "h";
						}
						break;

					case "mhz":
						var mhz = (int64) 0;
						if (prop.value_type == GLib.Type.INT64) {
							mhz = value.get_int64();
						}
						if (prop.value_type == GLib.Type.INT) {
							mhz = (int64) value.get_int();
						}
						((Gtk.Label) item.child).label = "";
						if (mhz > 0) {
							((Gtk.Label) item.child).label = mhz.to_string("%'" + int64.FORMAT) + " MHz";
						}
						break;

					case "cidr":
						var mask_prop = row.get_class().find_property("mask");
						if (shown == "" || mask_prop == null) {
							((Gtk.Label) item.child).label = shown;
							break;
						}
						var mask_value = GLib.Value(mask_prop.value_type);
						row.get_property("mask", ref mask_value);
						var mask_text = mask_value.get_string();
						if (mask_text == null || mask_text == "") {
							((Gtk.Label) item.child).label = shown;
							break;
						}
						var mask_addr = new GLib.InetAddress.from_string(mask_text);
						if (mask_addr == null) {
							((Gtk.Label) item.child).label = shown;
							break;
						}
						unowned uint8[] bytes = mask_addr.to_bytes();
						var size = mask_addr.get_native_size();
						var prefix = 0;
						var valid = true;
						var finished = false;
						for (var idx = (size_t) 0; idx < size; idx++) {
							var part = bytes[idx];
							if (finished && part != 0) {
								valid = false;
								break;
							}
							if (part == 0xff) {
								prefix += 8;
								continue;
							}
							finished = true;
							var bits = part;
							for (var bit = 0; bit < 8; bit++) {
								if ((bits & 0x80) == 0) {
									if (bits != 0) {
										valid = false;
									}
									break;
								}
								prefix++;
								bits = (uint8) (bits << 1);
							}
							if (!valid) {
								break;
							}
						}
						((Gtk.Label) item.child).label = shown;
						if (valid) {
							((Gtk.Label) item.child).label = shown + "/" + prefix.to_string();
						}
						break;

					case "tick-registered":
						var registered_tick = (Gtk.Image) item.child;
						var registered_on = false;
						if (prop.value_type == GLib.Type.INT) {
							registered_on = value.get_int() == 1;
						}
						if (prop.value_type == GLib.Type.INT64) {
							registered_on = value.get_int64() == 1;
						}
						registered_tick.icon_name = registered_on ?
							"object-select-symbolic" : null;
						registered_tick.visible = registered_on;
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"status", item.child, "visible",
								GLib.BindingFlags.SYNC_CREATE));
						break;

					case "tick-connected":
						var connected_tick = (Gtk.Image) item.child;
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								lookup, connected_tick, "icon-name",
								GLib.BindingFlags.SYNC_CREATE,
								(binding, from_value, ref to_value) => {
									var on = from_value.holds(typeof(bool)) &&
										from_value.get_boolean();
									connected_tick.icon_name = on ?
										"object-select-symbolic" : null;
									connected_tick.visible = on;
									return false;
								}));
						break;

					case "leaf":
						var leaf_image = (Gtk.Image) item.child;
						var leaf_on = false;
						if (prop.value_type == GLib.Type.INT) {
							leaf_on = value.get_int() != 0;
						}
						if (prop.value_type == GLib.Type.INT64) {
							leaf_on = value.get_int64() != 0;
						}
						leaf_image.visible = leaf_on;
						leaf_image.icon_name = leaf_on ? "leaf-symbolic" : null;
						leaf_image.tooltip_text = null;
						if (!leaf_on) {
							break;
						}
						var fleet = false;
						var agent_prop = row.get_class().find_property("agent-id");
						if (agent_prop != null && agent_prop.value_type == GLib.Type.INT64) {
							var agent_value = GLib.Value(GLib.Type.INT64);
							row.get_property("agent-id", ref agent_value);
							fleet = agent_value.get_int64() == 0;
						}
						leaf_image.tooltip_text = fleet ?
							"Top level on at least one machine." :
							"Top level package. Nothing installed on this machine depends on it.";
						break;

					case "tick":
						var tick_image = (Gtk.Image) item.child;
						var ticked = false;
						if (prop.value_type == GLib.Type.BOOLEAN) {
							ticked = value.get_boolean();
						}
						if (prop.value_type == GLib.Type.INT) {
							ticked = value.get_int() != 0;
						}
						if (prop.value_type == GLib.Type.INT64) {
							ticked = value.get_int64() != 0;
						}
						tick_image.icon_name = ticked ? "object-select-symbolic" : null;
						tick_image.visible = ticked;
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
						var button = (Argus.Controller.Widget.HoldButton) item.child;
						button.reset();
						button.visible = count > 0;
						button.tooltip_text = count.to_string();
						if (format == "bin") {
							button.tooltip_text = count.to_string() + " uninstallable";
						}
						break;

					case "archive":
						var archive_button = (Argus.Controller.Widget.HoldButton) item.child;
						archive_button.reset();
						archive_button.icon_name = "archive-symbolic";
						archive_button.visible = true;
						archive_button.tooltip_text = "Archive";
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
						var text_label = (Gtk.Label) item.child;
						text_label.label = shown;
						if (name == "name") {
							this.mark_explicit(text_label, row, header_column);
						}
						break;
				}
			});
			return factory;
		}

		/**
		 * Underline a package name that was explicitly installed.
		 *
		 * The row header stays bold. A row without an ''explicit''
		 * property, or with that flag clear, is plain text.
		 *
		 * @param label the name cell
		 * @param row the grid row
		 * @param header_column true when this column is the row header
		 */
		private void mark_explicit(Gtk.Label label, GLib.Object row, bool header_column)
		{
			var attrs = new Pango.AttrList();
			if (header_column) {
				attrs.insert(Pango.attr_weight_new(Pango.Weight.SEMIBOLD));
			}
			var on = false;
			var prop = row.get_class().find_property("explicit");
			if (prop != null && prop.value_type == GLib.Type.INT) {
				var value = GLib.Value(GLib.Type.INT);
				row.get_property("explicit", ref value);
				on = value.get_int() != 0;
			}
			label.tooltip_text = null;
			if (on) {
				attrs.insert(Pango.attr_underline_new(Pango.Underline.SINGLE));
				label.tooltip_text = "Explicitly installed";
			}
			label.attributes = attrs;
		}
	}
}
