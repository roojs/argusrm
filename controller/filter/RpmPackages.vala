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
	 * Local filter for the RPM package grid.
	 *
	 * Search, version spread, and update pending are properties here.
	 * Update pending starts off. Off shows every installed package.
	 * A change to one of them refilters the grid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.RpmPackages();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class RpmPackages : Gtk.Filter
	{
		/**
		 * Text in the search entry. Matched against the package name.
		 */
		public string search { get; set; default = ""; }
		/**
		 * True keeps rows whose min version and max version differ.
		 */
		public bool spread { get; set; default = false; }
		/**
		 * True keeps a row whose ''update_since'' is greater than zero.
		 * Starts off. RPM rows have no explicit or leaf flag, so this
		 * tick is the only one in the menu.
		 */
		public bool update_pending { get; set; default = false; }

		/**
		 * Refilter when a setting changes.
		 */
		construct
		{
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * The Filters menu for this grid.
		 *
		 * A menu model of one boolean action. ''MenuButton'' draws
		 * it as a check item. Update pending starts off.
		 *
		 * @return the menu button
		 */
		public Gtk.MenuButton menu()
		{
			var menu = new GLib.Menu();
			menu.append("Update pending", "filters.update-pending");
			var group = new GLib.SimpleActionGroup();
			var update_action = new GLib.SimpleAction.stateful(
				"update-pending", null, new GLib.Variant.boolean(false));
			update_action.change_state.connect((value) => {
				update_action.set_state(value);
				this.update_pending = value.get_boolean();
			});
			group.add_action(update_action);
			var button = new Gtk.MenuButton() {
				label = "Filters",
				menu_model = menu
			};
			button.insert_action_group("filters", group);
			return button;
		}

		/**
		 * Whether this row stays on the grid.
		 *
		 *  * Spread keeps a row whose two version cells differ.
		 *  * Update pending keeps a row whose ''update_since'' is
		 *    greater than zero. Off leaves that part open.
		 *  * Search looks at the package name.
		 *
		 * @param item an ''rpm_packages'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.RpmPackages) item;
			if (this.spread && row.min_version == row.max_version) {
				return false;
			}
			if (this.update_pending && row.update_since <= 0) {
				return false;
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			return row.name.down().contains(query);
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" && !this.spread && !this.update_pending) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
