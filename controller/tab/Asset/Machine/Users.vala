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
		 * Build the split groups / users page.
		 *
		 * @param window the window this page belongs to
		 */
		public Users(Argus.Controller.Window window)
		{
			base("users", "username");
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
#if ANDROID
			filter_bar.spacing = 6;
			filter_bar.margin_start = 0;
			filter_bar.margin_end = 0;
			filter_bar.margin_top = 0;
			filter_bar.margin_bottom = 0;
			var search_toggle = new Gtk.ToggleButton() {
				icon_name = "system-search-symbolic",
				tooltip_text = "Search"
			};
			var search_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				css_classes = { "machines-filter" },
				hexpand = true,
				visible = false
			};
			search_bar.append(search);
			search_toggle.toggled.connect(() => {
				search_bar.visible = search_toggle.active;
				if (search_toggle.active) {
					search.grab_focus();
				}
			});
			filter_bar.append(search_toggle);
			filter_bar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			filter_bar.append(show_system);
#else
			filter_bar.append(search);
			filter_bar.append(show_system);
#endif
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
			var groups_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
#if !ANDROID
			groups_box.width_request = 320;
#endif
			groups_box.append(groups_bar);
			groups_box.append(this.groups);
			this.store.notify["busy"].connect(() => {
				if (this.groups.refreshing) {
					this.refreshing = true;
				}
			});
			this.groups.notify["refreshing"].connect(() => {
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
#if ANDROID
			groups_box.height_request = 160;
			var paned = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			paned.append(groups_box);
			paned.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
			paned.append(this.overlay);
#else
			var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = groups_box,
				end_child = this.overlay,
				resize_start_child = false,
				shrink_start_child = false,
				position = 340,
				hexpand = true,
				vexpand = true
			};
#endif
			this.content.append(filter_bar);
#if ANDROID
			this.content.append(search_bar);
#endif
			this.content.append(paned);
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
