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
	 * Per-machine RPM package grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''rpm_packages_machine.csv''. {@link Argus.Controller.Store.RpmPackages}
	 * loads ''RpmPackages.list'' for the selected ''agent_id''.
	 * {@link Argus.Controller.Filters.RpmPackages} is the bar above
	 * the grid: search on the left, Filters on the right, then
	 * Update. Upgrade is shown when a package on this machine has
	 * an update waiting. An empty
	 * grid shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.RpmPackages(window);
	 * tab.load(1);
	 * }}}
	 */
	public class RpmPackages : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.RpmPackages store;
		private Argus.Controller.Store.TaskTarget tasks;
		private Argus.Controller.Filters.RpmPackages filter;
		private int agent_id = 0;

		/**
		 * Build the per-machine RPM package grid.
		 *
		 * @param window the window this page belongs to
		 */
		public RpmPackages(Argus.Controller.Window window)
		{
			base("rpm_packages_machine", "name");
			this.store = new Argus.Controller.Store.RpmPackages(window.app);
			this.tasks = new Argus.Controller.Store.TaskTarget(window.app);
			this.filter = new Argus.Controller.Filters.RpmPackages();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.tasks.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			this.tasks.submitted.connect((count) => {
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				this.toasts.add_toast(new Adw.Toast(label));
			});
			var update = new Gtk.Button.with_label("Update");
			var upgrade = new Gtk.Button.with_label("Upgrade") {
				visible = false
			};
			this.store.items_changed.connect((position, removed, added) => {
				var any = false;
				foreach (var row in this.store.items) {
					if (row.update_since > 0) {
						any = true;
						break;
					}
				}
				upgrade.visible = any;
			});
			update.clicked.connect(() => {
				if (this.agent_id < 1) {
					return;
				}
				var ids = new Gee.ArrayList<int32>();
				ids.add((int32) this.agent_id);
				this.tasks.run_script("linux", "dnf", "update", ids);
			});
			upgrade.clicked.connect(() => {
				if (this.agent_id < 1) {
					return;
				}
				var ids = new Gee.ArrayList<int32>();
				ids.add((int32) this.agent_id);
				this.tasks.run_script("linux", "dnf", "upgrade", ids);
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
			bar.append(update);
			bar.append(upgrade);
			this.content.append(bar);
			this.content.append(this.overlay);
		}

		/**
		 * Load installed RPM packages for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.agent_id = agent_id;
			this.store.load(agent_id);
		}
	}
}
