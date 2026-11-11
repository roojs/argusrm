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
	 * RPM package grid on the Software page.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''rpm_packages.csv''. {@link Argus.Controller.Store.RpmPackages}
	 * loads ''RpmPackages.list'' with zero, every agent.
	 * The grid loads when this page is shown. An empty grid
	 * shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.RpmPackages(window);
	 * }}}
	 */
	public class RpmPackages : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.RpmPackages store;

		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public RpmPackages(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "rpm_packages"
			);
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.RpmPackages(window.app);
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(this.store)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			this.column_menu();
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.map.connect(() => {
				this.store.load(0);
			});
			var spinner = new Gtk.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			spinner.add_css_class("package-wait");
			var overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(spinner);
			this.store.notify["busy"].connect(() => {
				var waiting = this.store.busy && this.store.get_n_items() == 0;
				spinner.visible = waiting;
				spinner.spinning = waiting;
				this.refreshing = this.store.busy && this.store.get_n_items() > 0;
			});
			this.append(overlay);
		}
	}
}
