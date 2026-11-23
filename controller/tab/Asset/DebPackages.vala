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
	 * Debian package grid on the Software page.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''deb_packages.csv''. {@link Argus.Controller.Store.DebPackages}
	 * loads ''DebPackages.list'' with zero, every agent.
	 * {@link Argus.Controller.Filters.DebPackages} is the bar above
	 * the grid: search, Filters, and versions differ.
	 * A double-click, or a long press, opens
	 * {@link Argus.Controller.Dialog.PackageMachines} for that name.
	 * Holding Remove opens {@link Argus.Controller.Dialog.AptDepends}
	 * for the packages that have to be removed with it.
	 * The grid loads when this page is shown. An empty grid
	 * shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.DebPackages(window);
	 * }}}
	 */
	public class DebPackages : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.DebPackages store;
		private Argus.Controller.Filters.DebPackages filter;
		private Argus.Controller.Dialog.PackageMachines machines;
		private Argus.Controller.Dialog.AptDepends depends;
		private bool refresh = false;

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public DebPackages(Argus.Controller.Window window)
		{
			base("deb_packages", "name");
			this.window = window;
			this.store = new Argus.Controller.Store.DebPackages(window.app);
			this.filter = new Argus.Controller.Filters.DebPackages();
			this.machines = new Argus.Controller.Dialog.PackageMachines(window.app, "deb");
			this.depends = new Argus.Controller.Dialog.AptDepends(window.app);
			this.remove_confirmed.connect((obj) => {
				var row = (Argus.Shared.OSQuery.DebPackages) obj;
				this.depends.open(this.window, row.name);
			});
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.map.connect(() => {
				this.store.load(0, this.refresh);
				this.refresh = false;
			});
			this.window.app.db_changed.connect((table, agent_id) => {
				if (table != "DebPackages" && table != "PackageUpdates") {
					return;
				}
				if (this.get_mapped()) {
					this.store.load(0, true);
					return;
				}
				this.refresh = true;
			});
			var filters = this.filter.menu();
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var spread = new Gtk.CheckButton.with_label("Versions differ");
			spread.toggled.connect(() => {
				this.filter.spread = spread.active;
			});
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
#if ANDROID
			bar.spacing = 6;
			var search_toggle = new Gtk.ToggleButton() {
				icon_name = "system-search-symbolic",
				tooltip_text = "Search"
			};
			var search_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				css_classes = { "machines-filter" },
				hexpand = true,
				visible = false
			};
			search_bar.append(search);
			search_toggle.toggled.connect(() => {
				search_bar.visible = search_toggle.active;
				if (search_toggle.active) {
					search.grab_focus();
				}
			});
			bar.append(search_toggle);
			bar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			bar.append(filters);
			bar.append(spread);
			this.content.append(bar);
			this.content.append(search_bar);
#else
			bar.append(search);
			bar.append(filters);
			bar.append(spread);
			this.content.append(bar);
#endif
			var click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_PRIMARY
			};
			click.pressed.connect((n_press, x, y) => {
				if (n_press < 2) {
					return;
				}
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					return;
				}
				this.machines.open(this.window,
					((Argus.Shared.OSQuery.DebPackages) row_item.item).name);
			});
			var hold = new Gtk.GestureLongPress() {
				touch_only = true
			};
			hold.pressed.connect((x, y) => {
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					return;
				}
				this.machines.open(this.window,
					((Argus.Shared.OSQuery.DebPackages) row_item.item).name);
			});
			this.grid.add_controller(click);
			this.grid.add_controller(hold);
			this.content.append(this.overlay);
		}
	}
}
