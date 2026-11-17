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
	 * Local filter for the package machines grid.
	 *
	 * Search matches the machine name or a logged-in user.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.PackageMachines();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class PackageMachines : Gtk.Filter
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
		 * Whether this machine stays on the grid.
		 *
		 * @param item a {@link Argus.Shared.SQV.PackageMachine}
		 * @return true when search is empty or matches the machine name
		 * or a logged-in user
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.SQV.PackageMachine) item;
			var needle = this.search.strip().down();
			if (needle == "") {
				return true;
			}
			return row.machine.down().contains(needle) ||
				row.logged_in_users.down().contains(needle);
		}
	}
}
