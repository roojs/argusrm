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
	 * Tick list of machines waiting to be registered.
	 *
	 * Search and Select all are the bar. The body is a stack: a
	 * spinner, a scrolled column view, and an empty label. Select
	 * all ticks the rows the search is showing. The button becomes
	 * Select none once every listed row is ticked. A hidden row
	 * keeps its tick. A row that arrives after Select all is unticked.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var list = new Argus.Controller.Tab.Pairing();
	 * list.add_machine(4, "192.168.88.14", "web-03");
	 * }}}
	 */
	public class Pairing : Gtk.Box
	{
		private Argus.Controller.Store.Pairing store;
		private Argus.Controller.Filters.Pairing filter;
		private Gtk.FilterListModel listed;
		private Gtk.SearchEntry search;
		private Gtk.Button select_all;
		private Gtk.Stack body;
		/**
		 * How many listed rows are in the store's picked map.
		 */
		private int shown_picked = 0;

		/**
		 * Empty list with the search bar.
		 */
		public Pairing()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12);
			this.store = new Argus.Controller.Store.Pairing();
			this.filter = new Argus.Controller.Filters.Pairing();
			this.listed = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = false
			};
			var sorted = new Gtk.SortListModel(this.listed, null) {
				incremental = false
			};
			var grid = new Gtk.ColumnView(new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = grid.sorter;
			var checks = new Gtk.SignalListItemFactory();
			checks.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.CheckButton() {
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.CENTER
				};
			});
			checks.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.AgentPending) item.item;
				var check = (Gtk.CheckButton) item.child;
				check.set_data("argus-column-binding", row.bind_property(
					"picked", check, "active",
					GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE));
			});
			checks.unbind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				if (item.child == null) {
					return;
				}
				var binding = item.child.get_data<GLib.Binding>("argus-column-binding");
				if (binding != null) {
					binding.unbind();
				}
				item.child.set_data<GLib.Binding>("argus-column-binding", null);
			});
			grid.append_column(new Gtk.ColumnViewColumn("", checks) {
				fixed_width = 48,
				resizable = false
			});
			var addresses = new Gtk.SignalListItemFactory();
			addresses.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
			});
			addresses.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.AgentPending) item.item;
				var label = (Gtk.Label) item.child;
				var text = row.ip;
				if (row.hostname != "") {
					text = row.ip + "    " + row.hostname;
				}
				label.label = text;
				label.tooltip_text = text;
			});
			var address_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.AgentPending), null, "ip");
			grid.append_column(new Gtk.ColumnViewColumn("Address", addresses) {
				expand = true,
				resizable = true,
				sorter = new Gtk.StringSorter(address_expr) {
					ignore_case = true
				}
			});
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			this.select_all = new Gtk.Button.with_label("Select all") {
				halign = Gtk.Align.END
			};
			var empty_label = new Gtk.Label("No machines") {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				wrap = true
			};
			var wait = new Adw.Spinner() {
				width_request = 48,
				height_request = 48,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(wait, "wait");
			this.body.add_named(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true,
				min_content_height = 240
			}, "list");
			this.body.add_named(empty_label, "empty");
			this.body.visible_child_name = "wait";
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			bar.append(this.search);
			bar.append(this.select_all);
			this.append(bar);
			this.append(this.body);
			this.margin_top = 16;
			this.margin_bottom = 16;
			this.margin_start = 16;
			this.margin_end = 16;
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
			});
			this.select_all.clicked.connect(() => {
				var total = this.listed.get_n_items();
				var all = total > 0 && this.shown_picked == (int) total;
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Shared.AgentPending) this.listed.get_item(i);
					row.picked = !all;
				}
			});
			this.store.changed.connect((row) => {
				if (!this.filter.match(row)) {
					return;
				}
				if (this.store.picked.has_key(row.id)) {
					this.shown_picked++;
				}
				if (!this.store.picked.has_key(row.id)) {
					this.shown_picked--;
				}
				this.mark_select();
			});
			this.listed.items_changed.connect(() => {
				var total = this.listed.get_n_items();
				var n = 0;
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Shared.AgentPending) this.listed.get_item(i);
					if (this.store.picked.has_key(row.id)) {
						n++;
					}
				}
				this.shown_picked = n;
				this.mark_select();
				if (total < 1) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
		}

		/**
		 * Drop the rows and clear the search.
		 */
		public void clear()
		{
			this.store.clear();
			this.search.text = "";
			this.filter.search = "";
			this.select_all.label = "Select all";
			this.body.visible_child_name = "wait";
		}

		/**
		 * Add one waiting machine.
		 *
		 * @param id ''agent_pending.id''
		 * @param ip peer address
		 * @param name machine name, or empty
		 */
		public void add_machine(int64 id, string ip, string name)
		{
			this.store.append(id, ip, name);
		}

		/**
		 * Rename Select all once every listed row is ticked.
		 */
		private void mark_select()
		{
			var total = this.listed.get_n_items();
			if (total > 0 && this.shown_picked == (int) total) {
				this.select_all.label = "Select none";
				return;
			}
			this.select_all.label = "Select all";
		}
	}
}
