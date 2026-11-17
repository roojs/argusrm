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
	 * Local filter for the Debian package grid.
	 *
	 * Search, version spread, and three ticks are properties here.
	 * A tick adds rows. An off tick does not hide a row that another
	 * tick still matches. All three off shows every installed package.
	 * A change to one of them refilters the grid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.DebPackages();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class DebPackages : Gtk.Filter
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
		 * True keeps a row whose ''explicit'' flag is set.
		 */
		public bool explicit { get; set; default = true; }
		/**
		 * True keeps a row whose ''leaf'' flag is set.
		 */
		public bool leaf { get; set; default = true; }
		/**
		 * True keeps a row whose ''update_since'' is greater than zero.
		 */
		public bool update_pending { get; set; default = true; }

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
		 * A menu model of three boolean actions. ''MenuButton'' draws
		 * those as check items. All three start on. Unticking one
		 * drops a package only when no other tick still matches it.
		 *
		 * @return the menu button
		 */
		public Gtk.MenuButton menu()
		{
			var menu = new GLib.Menu();
			menu.append("Explicitly installed", "filters.explicit");
			menu.append("Top level packages (leaf)", "filters.leaf");
			menu.append("Update pending", "filters.update-pending");
			var group = new GLib.SimpleActionGroup();
			var explicit_action = new GLib.SimpleAction.stateful(
				"explicit", null, new GLib.Variant.boolean(true));
			explicit_action.change_state.connect((value) => {
				explicit_action.set_state(value);
				this.explicit = value.get_boolean();
			});
			group.add_action(explicit_action);
			var leaf_action = new GLib.SimpleAction.stateful(
				"leaf", null, new GLib.Variant.boolean(true));
			leaf_action.change_state.connect((value) => {
				leaf_action.set_state(value);
				this.leaf = value.get_boolean();
			});
			group.add_action(leaf_action);
			var update_action = new GLib.SimpleAction.stateful(
				"update-pending", null, new GLib.Variant.boolean(true));
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
		 *  * A tick that is on keeps a row with that fact. An off
		 *    tick is not a reason to drop the row. All ticks off
		 *    leaves this part of the match open.
		 *  * Search looks at the package name.
		 *
		 * @param item a ''deb_packages'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.DebPackages) item;
			if (this.spread && row.min_version == row.max_version) {
				return false;
			}
			if (this.explicit || this.leaf || this.update_pending) {
				var hit = false;
				if (this.explicit && row.explicit != 0) {
					hit = true;
				}
				if (this.leaf && row.leaf != 0) {
					hit = true;
				}
				if (this.update_pending && row.update_since > 0) {
					hit = true;
				}
				if (!hit) {
					return false;
				}
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
			if (this.search.strip() == "" && !this.spread &&
				!this.explicit && !this.leaf && !this.update_pending) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
