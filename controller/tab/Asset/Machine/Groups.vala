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

namespace Argus.Controller.Tab.Asset.Machine
{
	/**
	 * Per-machine groups list in {@link Users}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads ''groups.csv''.
	 * {@link Argus.Controller.Store.Groups} loads ''Groups.list''.
	 * Selection drives the users filter. {@link clear_selection} is the
	 * Clear control.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var groups = new Argus.Controller.Tab.Asset.Machine.Groups(window);
	 * groups.load(1);
	 * }}}
	 */
	public class Groups : Argus.Controller.Tab.Base
	{
		/**
		 * Backing store for this list.
		 */
		public Argus.Controller.Store.Groups store;

		/**
		 * Selected group name changed. Empty when cleared.
		 *
		 * @param group_name selected ''groupname'', or empty
		 */
		public signal void group_selected(string group_name);

		/**
		 * Build the per-machine groups list.
		 *
		 * @param window the window this page belongs to
		 */
		public Groups(
			Argus.Controller.Window window,
			Argus.Controller.Filters.Groups filter
		) {
			base("groups", "groupname");
			this.store = new Argus.Controller.Store.Groups(window.app);
			var rows = new Gtk.FilterListModel(this.store, filter) {
				incremental = true
			};
			this.column_grid(rows);
			var selection = (Gtk.SingleSelection) this.grid.model;
			selection.autoselect = false;
			selection.can_unselect = true;
			selection.selection_changed.connect((position, n_items) => {
				var row = selection.selected_item as Argus.Shared.OSQuery.Groups;
				if (row == null) {
					this.group_selected("");
					return;
				}
				this.group_selected(row.groupname);
			});
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.content.append(this.overlay);
		}

		/**
		 * Clear the current group selection.
		 */
		public void clear_selection()
		{
			var selection = (Gtk.SingleSelection) this.grid.model;
			selection.unselect_all();
			this.group_selected("");
		}

		/**
		 * Load groups for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.clear_selection();
			this.store.load(agent_id);
		}
	}
}
