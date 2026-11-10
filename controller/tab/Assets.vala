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
	 * Assets page.
	 *
	 * Machines and Software are the two halves. The switcher is
	 * an {@link Adw.ViewSwitcher} on this page. Machines is a
	 * grid of the columns in ''columns/machines.csv'' and has
	 * no rows. {@link Base.column_menu} builds that grid. A
	 * right-click on a column header shows or hides each column,
	 * and the last visible column stays. Software is the word
	 * Software. There is no filter row and no call to the
	 * server. The window header stays the server name.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Assets(window);
	 * stack.add_named(page, "assets");
	 * }}}
	 */
	public class Assets : Base
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;

		/**
		 * Build the machine grid and the Software word.
		 *
		 * The grid has every machines column and no rows.
		 * Those columns are ''columns/machines.csv''.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Assets(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			var pages = new Adw.ViewStack() {
				hexpand = true,
				vexpand = true
			};
			var grid = new Gtk.ColumnView(new Gtk.NoSelection(
				new GLib.ListStore(typeof(GLib.Object)))) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			this.column_menu(grid, "machines");
			pages.add_titled_with_icon(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true
			}, "machines", "Machines", "computer-symbolic");
			pages.add_titled_with_icon(new Gtk.Label("Software") {
				xalign = 0,
				yalign = 0,
				hexpand = true,
				vexpand = true,
				margin_start = 12,
				margin_top = 12
			}, "software", "Software", "package-x-generic-symbolic");
			this.append(new Adw.ViewSwitcher() {
				stack = pages,
				policy = Adw.ViewSwitcherPolicy.WIDE,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			});
			this.append(pages);
		}
	}
}
