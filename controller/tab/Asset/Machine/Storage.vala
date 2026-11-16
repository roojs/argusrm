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
	 * Per-machine storage grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''mounts_machine.csv''. {@link Argus.Controller.Store.Mounts} loads
	 * ''Mounts.list'' (column sort via {@link Argus.Controller.Tab.Base} / CSV).
	 */
	public class Storage : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Mounts store;
		private Argus.Controller.Filters.Mounts filter;

		public Storage(Argus.Controller.Window window)
		{
			base("mounts_machine", "path");
			this.store = new Argus.Controller.Store.Mounts(window.app);
			this.filter = new Argus.Controller.Filters.Mounts();
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
				hexpand = true,
				placeholder_text = "Search mounts"
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var show_system = new Gtk.CheckButton.with_label("Show system mounts");
			show_system.toggled.connect(() => {
				this.filter.show_system_mounts = show_system.active;
			});
			var filter_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 4
			};
#if ANDROID
			filter_bar.spacing = 6;
			filter_bar.margin_start = 0;
			filter_bar.margin_end = 0;
			filter_bar.margin_top = 0;
			filter_bar.margin_bottom = 0;
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
			filter_bar.append(search_toggle);
			filter_bar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			filter_bar.append(show_system);
			this.content.append(filter_bar);
			this.content.append(search_bar);
#else
			filter_bar.append(search);
			filter_bar.append(show_system);
			this.content.append(filter_bar);
#endif
			this.content.append(this.overlay);
		}

		public void load(int agent_id)
		{
			this.store.load(agent_id);
		}
	}
}