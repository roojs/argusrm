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
	 * {@link Asset.SystemInfo} and {@link Asset.Software} are the
	 * two halves. The switcher is an {@link Adw.ViewSwitcher}
	 * on this page. It spans the window, and the two tabs are
	 * the same width. The window header is the server and this
	 * place.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Assets(window);
	 * stack.add_named(page, "assets");
	 * }}}
	 */
	public class Assets : Gtk.Box
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;

		/**
		 * Build the switcher for {@link Asset.SystemInfo} and
		 * {@link Asset.Software}.
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
			pages.add_titled_with_icon(
				new Asset.SystemInfo(window),
				"system-info",
				"Machines",
				"computer-symbolic"
			);
			pages.add_titled_with_icon(
				new Asset.Software(window),
				"software",
				"Software",
				"package-x-generic-symbolic"
			);
			this.append(new Adw.ViewSwitcher() {
				stack = pages,
				policy = Adw.ViewSwitcherPolicy.WIDE,
				hexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 6
			});
			this.append(pages);
		}
	}
}
