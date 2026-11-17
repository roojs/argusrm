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
		private Argus.Controller.Store.DebPackages store;
		private Argus.Controller.Filters.DebPackages filter;

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public DebPackages(Argus.Controller.Window window)
		{
			base("deb_packages", "name");
			this.store = new Argus.Controller.Store.DebPackages(window.app);
			this.filter = new Argus.Controller.Filters.DebPackages();
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
				this.store.load(0);
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
			this.content.append(this.overlay);
		}
	}
}
