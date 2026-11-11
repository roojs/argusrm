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
	 * Search, the checked sections, and the version spread are
	 * properties here. A change to one of them refilters the grid.
	 * Recent changes is not here. That choice waits on a change time.
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
		 * Checked section names. The same length as
		 * {@link section_count} means every section is on.
		 */
		public Gee.ArrayList<string> sections {
			get; set; default = new Gee.ArrayList<string>();
		}
		/**
		 * How many sections the popover lists. Zero before any rows.
		 */
		public int section_count { get; set; default = 0; }
		/**
		 * True keeps rows whose min version and max version differ.
		 */
		public bool spread { get; set; default = false; }

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
		 *  * Search looks at the package name.
		 *  * A narrowed section list keeps a row that has one
		 *    checked section. A set of sections matches any of them.
		 *  * Spread keeps a row whose two version cells differ.
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
			if (this.section_count > 0 && this.sections.size < this.section_count) {
				var hit = false;
				foreach (var part in row.section.split(",")) {
					var section = part.strip();
					if (section == "") {
						continue;
					}
					if (!this.sections.contains(section)) {
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
			return row.name.down().contains(query);
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			var open = this.section_count == 0 || this.sections.size == this.section_count;
			if (this.search.strip() == "" && !this.spread && open) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
