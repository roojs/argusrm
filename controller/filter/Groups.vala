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
	 * Local filter for the per-machine groups list.
	 *
	 * {@link show_system} mirrors the Users tab control. When false,
	 * groups with ''gid < 1000'' stay visible only when
	 * {@link Argus.Shared.OSQuery.Groups.users_uid_ge_1000_member_count}
	 * is positive.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Groups();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Groups : Gtk.Filter
	{
		/**
		 * True shows every group. False hides ''gid < 1000'' unless a
		 * live member has ''uid >= 1000'' and is not ''nobody''.
		 */
		public bool show_system { get; set; default = false; }

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
		 * Whether this row stays on the list.
		 *
		 * @param item a ''groups'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.Groups) item;
			if (this.show_system) {
				return true;
			}
			if (row.gid >= 1000) {
				return true;
			}
			return row.users_uid_ge_1000_member_count > 0;
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.show_system) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}