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

namespace Argus.Controller.Tab.Asset
{
	/**
	 * Windows program grid on the Software page.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''programs.csv''. {@link Argus.Controller.Store.Programs}
	 * loads ''Programs.list'' with zero, every agent.
	 * The grid loads when this page is shown. An empty grid
	 * shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.Programs(window);
	 * }}}
	 */
	public class Programs : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Programs store;

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			base("programs", "name");
			this.store = new Argus.Controller.Store.Programs(window.app);
			this.column_grid(this.store);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.map.connect(() => {
				this.store.load(0);
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
				if (row == null) {
					return;
				}
				this.store.load_machines(row.name);
			});
			this.store.machines_loaded.connect((name, rows) => {
				var grouped = new Gee.HashMap<string, Gee.ArrayList<int32>>();
				var total = 0;
				foreach (var row in rows) {
					if (row.agent_id < 1) {
						continue;
					}
					var cmd = row.silent_command();
					if (cmd == "") {
						continue;
					}
					if (!grouped.has_key(cmd)) {
						grouped.set(cmd, new Gee.ArrayList<int32>());
					}
					var ids = grouped.get(cmd);
					if (!ids.contains((int32) row.agent_id)) {
						ids.add((int32) row.agent_id);
						total++;
					}
				}
				if (total < 1) {
					this.toasts.add_toast(new Adw.Toast(
						"No uninstall command found for " + name));
					return;
				}
				var count_label = total == 1 ? "1 machine" : total.to_string() + " machines";
				var confirm = new Adw.AlertDialog(
					"Uninstall " + name,
					"This removes " + name + " from " + count_label +
						".\nType \"delete all\" to confirm.");
				var entry = new Gtk.Entry() {
					placeholder_text = "delete all"
				};
				confirm.set_extra_child(entry);
				confirm.add_response("cancel", "Cancel");
				confirm.add_response("uninstall", "Uninstall");
				confirm.set_response_appearance(
					"uninstall", Adw.ResponseAppearance.DESTRUCTIVE);
				confirm.set_response_enabled("uninstall", false);
				confirm.set_default_response("cancel");
				confirm.set_close_response("cancel");
				entry.changed.connect(() => {
					confirm.set_response_enabled(
						"uninstall", entry.text.strip() == "delete all");
				});
				confirm.response.connect((response) => {
					if (response != "uninstall" || entry.text.strip() != "delete all") {
						return;
					}
					foreach (var entry_cmd in grouped.entries) {
						task_store.run_command(
							"Uninstall " + name, entry_cmd.key, entry_cmd.value);
					}
				});
				confirm.present(this);
			});
			this.content.append(this.overlay);
		}
	}
}
