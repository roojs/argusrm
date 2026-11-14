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
	 * Per-machine users page in {@link Detail}.
	 *
	 * Groups list on the left with Clear. Users grid on the right with
	 * search and show-system. {@link Argus.Controller.Tab.Base.column_menu}
	 * on the users grid reads ''users.csv''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.Users(window);
	 * tab.load(1);
	 * }}}
	 */
	public class Users : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Users store;
		private Argus.Controller.Filters.Users filter;
		private Groups groups;

		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the split groups / users page.
		 *
		 * @param window the window this page belongs to
		 */
		public Users(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "users",
				expand_column: "username"
			);
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Users(window.app);
			this.filter = new Argus.Controller.Filters.Users();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var search = new Gtk.SearchEntry() {
				hexpand = true,
				placeholder_text = "Search users"
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var groups_filter = new Argus.Controller.Filters.Groups();
			var show_system = new Gtk.CheckButton.with_label("Show system users");
			show_system.toggled.connect(() => {
				var on = show_system.active;
				this.filter.show_system = on;
				groups_filter.show_system = on;
			});
			var filter_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 4
			};
			filter_bar.append(search);
			filter_bar.append(show_system);
			this.groups = new Groups(window, groups_filter);
			this.groups.group_selected.connect((group_name) => {
				this.filter.group_name = group_name;
			});
			var clear = new Gtk.Button.with_label("Clear");
			clear.clicked.connect(() => {
				this.groups.clear_selection();
			});
			var groups_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 8,
				margin_end = 8,
				margin_top = 4,
				margin_bottom = 4
			};
			groups_bar.append(new Gtk.Label("Groups") {
				hexpand = true,
				xalign = 0
			});
			groups_bar.append(clear);
			var groups_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				width_request = 320
			};
			groups_box.append(groups_bar);
			groups_box.append(this.groups);
			var users_spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			users_spinner.add_css_class("package-wait");
			var users_overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			users_overlay.add_overlay(users_spinner);
			this.store.notify["busy"].connect(() => {
				users_spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			this.groups.notify["refreshing"].connect(() => {
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = groups_box,
				end_child = users_overlay,
				resize_start_child = false,
				shrink_start_child = false,
				position = 340,
				hexpand = true,
				vexpand = true
			};
			this.append(filter_bar);
			this.append(paned);
		}

		/**
		 * Load groups and users for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.groups.load(agent_id);
			this.store.load(agent_id);
		}
	}
}
