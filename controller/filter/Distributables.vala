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
	 * Local filter for the Distributables grid.
	 *
	 * Search matches the name, the platform, and the version.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Distributables();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Distributables : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }

		/**
		 * Refilter when the search text changes.
		 */
		construct
		{
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * Whether this distributable stays on the grid.
		 *
		 * @param item a ''distributable'' list row
		 * @return true when search is empty or matches name, platform, or version
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.SQT.Distributable) item;
			var needle = this.search.strip().down();
			if (needle == "") {
				return true;
			}
			if (row.name.down().contains(needle)) {
				return true;
			}
			if (row.platform.down().contains(needle)) {
				return true;
			}
			return row.version.down().contains(needle);
		}
	}
}
