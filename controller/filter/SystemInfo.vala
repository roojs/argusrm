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
	 * Local filter for the Machines grid.
	 *
	 *  * Search, OS type, Status, and the visible text columns are properties here.
	 *  * A change to one of them refilters the grid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.SystemInfo();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class SystemInfo : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }
		/**
		 * Chosen operating-system name. Empty means every OS.
		 */
		public string os_type { get; set; default = ""; }
		/**
		 * Empty means every row. ''OS needs update'' keeps rows with
		 * ''os_status == 0'' or ''os_status == 2''. ''S/W needs update''
		 * keeps rows with ''pkgs_status == 0''.
		 */
		public string status { get; set; default = ""; }
		/**
		 * Visible text columns. The names are JSON. A hyphen stands in for an underscore.
		 */
		public Gee.ArrayList<string> visible_text { get; set; default = new Gee.ArrayList<string>(); }

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
		 *  * Search looks in {@link visible_text}.
		 *  * OS type is the operating-system name.
		 *  * ''OS needs update'' keeps rows with ''os_status'' ''0'' or ''2''.
		 *  * ''S/W needs update'' keeps rows with ''pkgs_status'' ''0''.
		 *
		 * @param item a ''system_info'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.SystemInfo) item;
			switch (this.status) {
				case "":
					break;

				case "OS needs update":
					switch (row.os_status) {
						case 0:
						case 2:
							break;

						default:
							return false;
					}
					break;

				case "S/W needs update":
					if (row.pkgs_status != 0) {
						return false;
					}
					break;

				default:
					return false;
			}
			if (this.os_type != "") {
				var shown = row.operating_system;
				if (shown != this.os_type &&
					!shown.has_prefix(this.os_type + " ")) {
					return false;
				}
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			foreach (var name in this.visible_text) {
				var value = GLib.Value(GLib.Type.STRING);
				((GLib.Object) row).get_property(name, ref value);
				if (value.get_string().down().contains(query)) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" &&
				this.os_type == "" &&
				this.status == "") {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
