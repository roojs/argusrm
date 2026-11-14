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
	 * Local filter for the per-machine users grid.
	 *
	 * Search, show-system, and the selected group name are properties
	 * here. A change to one of them refilters the grid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Users();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Users : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }
		/**
		 * True shows accounts with ''uid < 1000'' and ''nobody''.
		 */
		public bool show_system { get; set; default = false; }
		/**
		 * Selected group name. Empty means every user. Otherwise the
		 * row must list that name in {@link Argus.Shared.OSQuery.Users.groups_groupnames}.
		 */
		public string group_name { get; set; default = ""; }

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
		 * Whether this row stays on the grid.
		 *
		 * @param item a ''users'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.Users) item;
			if (!this.show_system) {
				if (row.uid < 1000 || row.uid == 65534) {
					return false;
				}
			}
			var group = this.group_name.strip();
			if (group != "") {
				var hit = false;
				foreach (var part in row.groups_groupnames.split(",")) {
					if (part.strip() != group) {
						continue;
					}
					hit = true;
					break;
				}
				if (!hit) {
					return false;
				}
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			if (row.username.down().contains(query)) {
				return true;
			}
			if (row.description.down().contains(query)) {
				return true;
			}
			if (row.directory.down().contains(query)) {
				return true;
			}
			if (row.shell.down().contains(query)) {
				return true;
			}
			if (row.gid_groupname.down().contains(query)) {
				return true;
			}
			return row.groups_groupnames.down().contains(query);
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" && this.show_system && this.group_name.strip() == "") {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
