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

namespace Argus.Controller
{
	/**
	 * Sidebar places for {@link Window}.
	 *
	 * The scrolling rows are the places. Settings is a separate row
	 * pinned to the bottom, drawn over the list, so a long list
	 * slides underneath it. A bottom margin on the list keeps the
	 * last place from staying hidden under that row. {@link chosen}
	 * is the place to show on the right. The first place is selected
	 * when the list is shown, including when that page is empty.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tabs = new Argus.Controller.TabList();
	 * tabs.chosen.connect((key, title) => {
	 *     pages.visible_child_name = key;
	 * });
	 * }}}
	 */
	public class TabList : Gtk.Box
	{
		/**
		 * Page names, in sidebar order. Settings is not one of these.
		 */
		public string[] keys = {
			"dashboard",
			"agents",
			"assets",
			"tasks",
			"monitoring",
			"scripts",
			"repositories"
		};
		/**
		 * Header text for {@link keys}, in the same order.
		 */
		public string[] titles = {
			"Dashboard",
			"Agent / Controllers",
			"Assets",
			"Tasks",
			"Monitoring",
			"Scripts",
			"Repositories"
		};
		/**
		 * The place the user picked.
		 *
		 * @param key page name, ''settings'' for the bottom row
		 * @param title header text
		 */
		public signal void chosen(string key, string title);

		/**
		 * Build the place list and the pinned Settings row.
		 */
		public TabList()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = true;
			var list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				css_classes = { "navigation-sidebar" },
				vexpand = true,
				hexpand = true
			};
			for (var i = 0; i < this.keys.length; i++) {
				var row = new Gtk.ListBoxRow();
				row.child = new Gtk.Label(this.titles[i]) {
					xalign = 0,
					margin_top = 6,
					margin_bottom = 6,
					margin_start = 12,
					margin_end = 12
				};
				row.name = this.keys[i];
				list.append(row);
			}
			var scroll = new Gtk.ScrolledWindow() {
				child = list,
				vexpand = true,
				hexpand = true,
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			var overlay = new Gtk.Overlay() {
				hexpand = true,
				vexpand = true
			};
			overlay.child = scroll;
			var settings_list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				css_classes = { "navigation-sidebar" },
				hexpand = true
			};
			var settings_row = new Gtk.ListBoxRow();
			var settings_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_top = 6,
				margin_bottom = 6,
				margin_start = 12,
				margin_end = 12
			};
			settings_box.append(new Gtk.Image.from_icon_name("preferences-system-symbolic"));
			settings_box.append(new Gtk.Label("Settings") {
				xalign = 0,
				hexpand = true
			});
			settings_row.child = settings_box;
			settings_row.name = "settings";
			settings_list.append(settings_row);
			var settings_bar = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				valign = Gtk.Align.END,
				hexpand = true,
				css_classes = { "tab-list-settings" }
			};
			settings_bar.append(settings_list);
			overlay.add_overlay(settings_bar);
			this.append(overlay);
			list.row_selected.connect((row) => {
				if (row == null) {
					return;
				}
				settings_list.unselect_all();
				this.chosen(row.name, ((Gtk.Label) row.child).label);
			});
			settings_list.row_selected.connect((row) => {
				if (row == null) {
					return;
				}
				list.unselect_all();
				this.chosen("settings", "Settings");
			});
			settings_bar.map.connect(() => {
				GLib.Idle.add(() => {
					var height = settings_bar.get_height();
					if (height > 0) {
						list.margin_bottom = height;
					}
					return false;
				});
			});
			var opened = false;
			list.map.connect(() => {
				if (opened) {
					return;
				}
				opened = true;
				GLib.Idle.add(() => {
					var opener = list.get_row_at_index(0);
					if (opener == null) {
						return false;
					}
					list.select_row(opener);
					return false;
				});
			});
		}
	}
}
