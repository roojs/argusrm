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

namespace Argus.Controller.Filters
{
	/**
	 * Local filter for the Debian dependency preview.
	 *
	 * Search matches the package name.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.AptDepends();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class AptDepends : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }

		/**
		 * Refilter when the search text changes.
		 */
		public AptDepends()
		{
			Object();
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * Whether this package stays on the grid.
		 *
		 * @param item a {@link Argus.Shared.SQV.AptDepends}
		 * @return true when search is empty or matches the name
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.SQV.AptDepends) item;
			var needle = this.search.strip().down();
			if (needle == "") {
				return true;
			}
			return row.name.down().contains(needle);
		}
	}
}
