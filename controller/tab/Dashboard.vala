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
	 * Dashboard page.
	 *
	 * Shows the application logo centred at half the pane width.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Dashboard(window);
	 * stack.add_named(page, "dashboard");
	 * }}}
	 */
	public class Dashboard : Gtk.Box
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;

		/**
		 * Build the dashboard with the centred logo.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Dashboard(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			var paintable = Gtk.IconTheme.get_for_display(
				Gdk.Display.get_default()).lookup_icon(
				"org.roojs.ArgusController", null, 512, 2,
				Gtk.TextDirection.NONE, Gtk.IconLookupFlags.FORCE_REGULAR);
			var picture = new Gtk.Picture.for_paintable(paintable) {
				can_shrink = true,
				content_fit = Gtk.ContentFit.CONTAIN,
				hexpand = true,
				vexpand = true,
				alternative_text = "Argus Remote Manager"
			};
			var grid = new Gtk.Grid() {
				hexpand = true,
				vexpand = true,
				column_homogeneous = true
			};
			grid.attach(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			}, 0, 0, 1, 1);
			grid.attach(picture, 1, 0, 2, 1);
			grid.attach(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			}, 3, 0, 1, 1);
			this.append(grid);
		}
	}
}
