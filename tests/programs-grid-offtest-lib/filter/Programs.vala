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
	 * Local filter for the Windows program grid.
	 *
	 * Search, version spread, and can uninstall are properties here.
	 * Can uninstall starts off. Off shows every installed program.
	 * A change to one of them refilters the grid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Programs();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Programs : Gtk.Filter
	{
		/**
		 * Text in the search entry. Matched against the program
		 * name and the publisher.
		 */
		public string search { get; set; default = ""; }
		/**
		 * True keeps rows whose min version and max version differ.
		 */
		public bool spread { get; set; default = false; }
		/**
		 * True keeps a row that has an uninstall command.
		 * A machine row matches on ''uninstall_string''. An aggregate
		 * row matches on ''uninstall_count''. Starts off.
		 */
		public bool can_uninstall { get; set; default = false; }

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
		 * it as a check item. Can uninstall starts off.
		 *
		 * @return the menu button
		 */
		public Gtk.MenuButton menu()
		{
			var menu = new GLib.Menu();
			menu.append("Can uninstall", "filters.can-uninstall");
			var group = new GLib.SimpleActionGroup();
			var uninstall_action = new GLib.SimpleAction.stateful(
				"can-uninstall", null, new GLib.Variant.boolean(false));
			uninstall_action.change_state.connect((value) => {
				uninstall_action.set_state(value);
				this.can_uninstall = value.get_boolean();
			});
			group.add_action(uninstall_action);
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
		 *  * Can uninstall keeps a row with an uninstall command.
		 *    Off leaves that part open.
		 *  * Search looks at the program name and the publisher.
		 *
		 * @param item a ''programs'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.Programs) item;
			if (this.spread && row.min_version == row.max_version) {
				return false;
			}
			if (this.can_uninstall &&
				row.uninstall_string.strip() == "" &&
				row.uninstall_count < 1) {
				return false;
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			if (row.name.down().contains(query)) {
				return true;
			}
			return row.publisher.down().contains(query);
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" && !this.spread && !this.can_uninstall) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
