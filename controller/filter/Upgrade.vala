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
	 * Local filter for the upgrade-all grid.
	 *
	 * One tab is one kind. Search matches the machine name or a
	 * logged-in user inside that tab.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Upgrade();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Upgrade : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }
		/**
		 * Tab to show. ''deb'', ''rpm'', or ''programs''.
		 */
		public string kind { get; set; default = "deb"; }

		/**
		 * Refilter when the search text or the tab changes.
		 */
		construct
		{
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * Whether this machine stays on the current tab.
		 *
		 * @param item an {@link Argus.Controller.Dialog.UpgradeTarget}
		 * @return true when the kind matches and search is empty or
		 * matches the machine name or a logged-in user
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Controller.Dialog.UpgradeTarget) item;
			if (row.kind != this.kind) {
				return false;
			}
			var needle = this.search.strip().down();
			if (needle == "") {
				return true;
			}
			return row.machine.down().contains(needle) ||
				row.logged_in_users.down().contains(needle);
		}
	}
}
