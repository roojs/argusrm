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
	 * Per-machine Windows program grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''programs_machine.csv''. {@link Argus.Controller.Store.Programs}
	 * loads ''Programs.list'' for the selected ''agent_id''.
	 * {@link Argus.Controller.Filters.Programs} is the bar above
	 * the grid: search on the left, Filters on the right. An empty
	 * grid shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.Programs(window);
	 * tab.load(1);
	 * }}}
	 */
	public class Programs : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Programs store;
		private Argus.Controller.Filters.Programs filter;

		/**
		 * Build the per-machine Windows program grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			base("programs_machine", "name");
			this.store = new Argus.Controller.Store.Programs(window.app);
			this.filter = new Argus.Controller.Filters.Programs();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var task_store = new Argus.Controller.Store.TaskTarget(window.app);
			task_store.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			task_store.submitted.connect((count) => {
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				this.toasts.add_toast(new Adw.Toast(label));
			});
			this.remove_confirmed.connect((obj) => {
				var row = obj as Argus.Shared.OSQuery.Programs;
				if (row == null || row.agent_id < 1) {
					return;
				}
				var cmd = row.silent_command();
				if (cmd == "") {
					this.toasts.add_toast(new Adw.Toast(
						"No uninstall command found for " + row.name));
					return;
				}
				var ids = new Gee.ArrayList<int32>();
				ids.add((int32) row.agent_id);
				task_store.run_command("Uninstall " + row.name, cmd, ids);
			});
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(this.filter.menu());
			this.content.append(bar);
			this.content.append(this.overlay);
		}

		/**
		 * Load installed Windows programs for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.store.load(agent_id);
		}
	}
}
