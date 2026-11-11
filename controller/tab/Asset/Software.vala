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

namespace Argus.Controller.Tab.Asset
{
	/**
	 * Software half of the Assets page.
	 *
	 * The word Software. The package grid is a later plan.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.Software();
	 * }}}
	 */
	public class Software : Gtk.Box
	{
		/**
		 * Show the word Software.
		 */
		public Software()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = true;
			this.append(new Gtk.Label("Software") {
				xalign = 0,
				yalign = 0,
				hexpand = true,
				vexpand = true,
				margin_start = 12,
				margin_top = 12
			});
		}
	}
}
