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
	 * ''system_info'' grid on the Assets page.
	 *
	 * The switcher titles this half Machines.
	 * A {@link Gtk.ColumnView} over
	 * {@link Argus.Controller.Store.SystemInfo}.
	 * {@link Argus.Controller.Tab.Base.column_menu} builds the
	 * columns from ''columns/system_info.csv''. The store loads
	 * when this page is shown. ''system_info'' fills its
	 * columns. The other columns stay empty.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.SystemInfo(window);
	 * }}}
	 */
	public class SystemInfo : Argus.Controller.Tab.Base
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;
		private Argus.Controller.Store.SystemInfo store;

		/**
		 * Build the grid.
		 *
		 * The grid has every column in ''columns/system_info.csv''.
		 * The store fills the ''system_info'' columns. The others
		 * stay empty.
		 *
		 * @param window the controller window this page belongs to
		 */
		public SystemInfo(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.SystemInfo(window.app);
			var grid = new Gtk.ColumnView(new Gtk.NoSelection(this.store)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			this.column_menu(grid, "system_info");
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.map.connect(() => {
				this.store.load();
			});
			this.append(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true
			});
		}
	}
}
