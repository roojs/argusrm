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
	 * Per-machine network interface addresses grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''interface_addresses_machine.csv''.
	 * {@link Argus.Controller.Store.InterfaceAddresses} loads
	 * ''InterfaceAddresses.list'' for the selected ''agent_id''.
	 * {@link Argus.Controller.Filters.InterfaceAddresses} is the bar
	 * above the grid: search on the left, ''Show IPv6'' on the right.
	 * An empty grid shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown and a later
	 * call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.InterfaceAddresses(window);
	 * tab.load(1);
	 * }}}
	 */
	public class InterfaceAddresses : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.InterfaceAddresses store;
		private Argus.Controller.Filters.InterfaceAddresses filter;

		/**
		 * Build the per-machine network interfaces grid.
		 *
		 * @param window the window this page belongs to
		 */
		public InterfaceAddresses(Argus.Controller.Window window)
		{
			base("interface_addresses_machine", "address");
			this.store = new Argus.Controller.Store.InterfaceAddresses(window.app);
			this.filter = new Argus.Controller.Filters.InterfaceAddresses();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var show_ipv6 = new Gtk.CheckButton.with_label("Show IPv6");
			show_ipv6.halign = Gtk.Align.END;
			show_ipv6.toggled.connect(() => {
				this.filter.show_ipv6 = show_ipv6.active;
			});
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(show_ipv6);
			this.content.append(bar);
			this.content.append(this.overlay);
		}

		/**
		 * Load interface addresses for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.store.load(agent_id);
		}
	}
}