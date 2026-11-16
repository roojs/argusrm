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
	 * Local filter for the per-machine mounts grid.
	 */
	public class Mounts : Gtk.Filter
	{
		public string search { get; set; default = ""; }
		/**
		 * When false, {@link Argus.Shared.OSQuery.Mounts.is_system_mount} rows are hidden.
		 */
		public bool show_system_mounts { get; set; default = false; }

		construct
		{
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.Mounts) item;
			if (!this.show_system_mounts && row.is_system_mount()) {
				return false;
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			if (row.path.down().contains(query)) {
				return true;
			}
			if (row.device.down().contains(query)) {
				return true;
			}
			return row.ctype.down().contains(query);
		}

		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" && this.show_system_mounts) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}