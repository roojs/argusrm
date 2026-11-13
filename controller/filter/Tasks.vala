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
	 * Local filter for the Tasks grid.
	 *
	 *  * Search matches visible text columns.
	 *  * State defaults to ''Active'' (queued, running, and draft rows).
	 *  * Date range bounds the run start or scheduled unix timestamp.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Tasks();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Tasks : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }
		/**
		 * State filter: ''Active'', ''All'', ''Completed'', or ''Failed''.
		 */
		public string state { get; set; default = "Active"; }
		/**
		 * Inclusive range start as a unix timestamp, or ''0'' for unbounded.
		 */
		public int64 date_from { get; set; default = 0; }
		/**
		 * Inclusive range end as a unix timestamp, or ''0'' for unbounded.
		 */
		public int64 date_to { get; set; default = 0; }
		/**
		 * Visible text columns. A hyphen stands in for an underscore.
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
		 * Whether this task target row stays on the grid.
		 *
		 * @param item a ''task_target'' row
		 * @return true when the row passes state, date range, and search
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.SQT.TaskTarget) item;
			switch (this.state) {
				case "All":
					break;

				case "Active":
					if (row.ended > 0 || row.is_cancelled) {
						return false;
					}
					break;

				case "Completed":
					if (row.ended == 0 || row.success != 0 || row.is_cancelled) {
						return false;
					}
					break;

				case "Failed":
					if (!row.is_cancelled && (row.ended == 0 || row.success == 0)) {
						return false;
					}
					break;

				default:
					return false;
			}
			if (this.date_from > 0 || this.date_to > 0) {
				var stamp = row.started > 0 ? row.started :
					(row.scheduled > 0 ? row.scheduled : row.task_id_scheduled);
				if (stamp <= 0) {
					return false;
				}
				if (this.date_from > 0 && stamp < this.date_from) {
					return false;
				}
				if (this.date_to > 0 && stamp > this.date_to) {
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
				var text = value.get_string();
				if (text != null && text.down().contains(query)) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Report filtering strictness so empty search/all-state can fast-path.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" &&
				this.state == "All" &&
				this.date_from == 0 &&
				this.date_to == 0) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
