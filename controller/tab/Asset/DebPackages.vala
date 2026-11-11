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
	 * the grid: search, section, and versions differ.
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
		private bool filling = false;

		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public DebPackages(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "deb_packages"
			);
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.DebPackages(window.app);
			this.filter = new Argus.Controller.Filters.DebPackages();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(new Gtk.SingleSelection(rows)) {
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
			var section_rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var section_scroll = new Gtk.ScrolledWindow() {
				child = section_rows,
				propagate_natural_width = true,
				propagate_natural_height = true,
				max_content_height = 360,
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			var section_pop = new Gtk.Popover() {
				child = section_scroll,
				has_arrow = false,
				position = Gtk.PositionType.BOTTOM
			};
			section_pop.add_css_class("menu");
			section_pop.add_css_class("column-menu");
			var section_button = new Gtk.MenuButton() {
				label = "Section",
				popover = section_pop
			};
			this.store.items_changed.connect((position, removed, added) => {
				this.build_sections(section_rows);
			});
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
			bar.append(search);
			bar.append(section_button);
			bar.append(spread);
			this.append(bar);
			this.append(overlay);
		}

		/**
		 * Rebuild the section checks from the packages in the store.
		 *
		 * A section that was unchecked stays off when the names change.
		 * The last checked section stays on. Matching names leave the
		 * menu as it is.
		 *
		 * @param rows the checks in the section menu
		 */
		private void build_sections(Gtk.Box rows)
		{
			var names = new Gee.ArrayList<string>();
			foreach (var package in this.store.items) {
				foreach (var part in package.section.split(",")) {
					var section = part.strip();
					if (section == "" || names.contains(section)) {
						continue;
					}
					names.add(section);
				}
			}
			names.sort((a, b) => {
				return a.ascii_casecmp(b);
			});
			var current = new Gee.ArrayList<string>();
			var child = rows.get_first_child();
			while (child != null) {
				current.add(((Gtk.CheckButton) child).label);
				child = child.get_next_sibling();
			}
			var same = names.size == current.size;
			if (same) {
				for (var i = 0; i < names.size; i++) {
					if (names.get(i) != current.get(i)) {
						same = false;
						break;
					}
				}
			}
			if (same) {
				return;
			}
			var off = new Gee.ArrayList<string>();
			child = rows.get_first_child();
			while (child != null) {
				var shown = (Gtk.CheckButton) child;
				if (!shown.active) {
					off.add(shown.label);
				}
				child = child.get_next_sibling();
			}
			var keep = 0;
			foreach (var section in names) {
				if (off.contains(section)) {
					continue;
				}
				keep++;
			}
			if (keep < 1) {
				off.clear();
			}
			this.filling = true;
			child = rows.get_first_child();
			while (child != null) {
				var next = child.get_next_sibling();
				rows.remove(child);
				child = next;
			}
			var on = new Gee.ArrayList<string>();
			foreach (var section in names) {
				var active = !off.contains(section);
				if (active) {
					on.add(section);
				}
				var button = new Gtk.CheckButton.with_label(section) {
					active = active,
					hexpand = true,
					halign = Gtk.Align.FILL
				};
				button.toggled.connect(() => {
					if (this.filling) {
						return;
					}
					var chosen = new Gee.ArrayList<string>();
					var total = 0;
					var row = rows.get_first_child();
					while (row != null) {
						total++;
						var check = (Gtk.CheckButton) row;
						if (check.active) {
							chosen.add(check.label);
						}
						row = row.get_next_sibling();
					}
					if (chosen.size < 1 && total > 0) {
						this.filling = true;
						button.active = true;
						this.filling = false;
						return;
					}
					this.filter.sections = chosen;
					this.filter.section_count = total;
				});
				rows.append(button);
			}
			this.filter.sections = on;
			this.filter.section_count = names.size;
			this.filling = false;
		}
	}
}
