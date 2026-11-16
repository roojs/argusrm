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
	 * as collapsible {@link Gtk.Expander} sections with flat aligned
	 * key-value rows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.General(window);
	 * tab.store.load.begin(1);
	 * }}}
	 */
	public class General : Gtk.Box
	{
		/**
		 * Store backing this view.
		 */
		public Argus.Controller.Store.MachineGeneral store { get; private set; }
		private Gtk.Box list;

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
			this.list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				css_classes = { "vertical-list" },
				hexpand = true,
				valign = Gtk.Align.START
			};
			this.store.items_changed.connect(() => {
				this.on_items_changed();
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
				visible = false,
				css_classes = { "package-wait" }
			};
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
		 * Rebuild the expander sections and key-value rows from
		 * {@link store}.
		 */
		private void on_items_changed()
		{
			var child = this.list.get_first_child();
			while (child != null) {
				var next = child.get_next_sibling();
				this.list.remove(child);
				child = next;
			}
			var key_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
			var section = new Gtk.ListBox();
			var has_section = false;
			foreach (var entry in this.store.items) {
				if (entry.expander) {
					section = new Gtk.ListBox() {
						selection_mode = Gtk.SelectionMode.NONE,
						show_separators = true,
						css_classes = { "vertical-list-rows" },
						hexpand = true
					};
					var expander = new Gtk.Expander(entry.key) {
						expanded = entry.expanded,
						css_classes = { "vertical-list-expander" },
						child = section
					};
					this.list.append(expander);
					has_section = true;
					continue;
				}
				var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
					css_classes = { "vertical-list-row" },
					margin_start = entry.indent > 1 ? (entry.indent - 1) * 16 : 0,
					hexpand = true
				};
				var key_label = new Gtk.Label(entry.key) {
					xalign = 0,
					yalign = 0,
					css_classes = { "dim-label", "vertical-list-key" }
				};
				key_group.add_widget(key_label);
				row.append(key_label);
				if (entry.css_class.has_prefix("status-")) {
					var status_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
						hexpand = true
					};
					status_box.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
						css_classes = { "status-dot", entry.css_class },
						halign = Gtk.Align.START,
						valign = Gtk.Align.CENTER
					});
					status_box.append(new Gtk.Label(entry.val) {
						xalign = 0,
						hexpand = true,
						selectable = true,
						css_classes = { "vertical-list-value" }
					});
					if (entry.tooltip != "") {
						status_box.tooltip_text = entry.tooltip;
					}
					row.append(status_box);
				}
				if (!entry.css_class.has_prefix("status-")) {
					var val_label = new Gtk.Label(entry.val) {
						xalign = 0,
						hexpand = true,
						wrap = true,
						wrap_mode = Pango.WrapMode.WORD_CHAR,
						selectable = true,
						css_classes = { "vertical-list-value" }
					};
					if (entry.css_class != "") {
						val_label.add_css_class(entry.css_class);
					}
					if (entry.tooltip != "") {
						val_label.tooltip_text = entry.tooltip;
					}
					row.append(val_label);
				}
				if (entry.indent > 0 && has_section) {
					section.append(row);
					continue;
				}
				this.list.append(row);
			}
		}
	}
}
