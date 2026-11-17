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

namespace Argus.Controller.Tab
{
	/**
	 * Distributables page.
	 *
	 * A {@link Gtk.ColumnView} over {@link Argus.Controller.Store.Distributable}.
	 * Search filters name, platform, and version. Archive holds to set
	 * ''deleted_dt''. Upload sends the file in chunks.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Distributables(window);
	 * stack.add_named(page, "distributables");
	 * }}}
	 */
	public class Distributables : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Distributable store;
		private Argus.Controller.Filters.Distributables filter;
		private Gtk.Stack body;
		private Gtk.Button upload_button;
		private Argus.Controller.Dialog.Upload uploader;

		/**
		 * Build the search bar, the grid, and the empty page.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Distributables(Argus.Controller.Window window)
		{
			base("distributables", "name");
			this.window = window;
			this.store = new Argus.Controller.Store.Distributable(window.app);
			this.filter = new Argus.Controller.Filters.Distributables();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows, false);

			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search name, platform, or version",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var bar_spinner = new Adw.Spinner() {
				visible = false
			};
			this.upload_button = new Gtk.Button.with_label("Upload") {
				css_classes = { "suggested-action" },
				tooltip_text = "Upload an installer",
				halign = Gtk.Align.END
			};
			this.uploader = new Argus.Controller.Dialog.Upload(this.store);
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(search);
			toolbar.append(bar_spinner);
			toolbar.append(this.upload_button);

			var empty = new Adw.StatusPage() {
				title = "No distributables",
				description = "Upload an installer to keep it here.",
				icon_name = "package-x-generic-symbolic",
				vexpand = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(this.overlay, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			this.content.append(toolbar);
			this.content.append(this.body);
			this.store.bind_property("busy", bar_spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
			this.store.notify["empty"].connect(() => {
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.notify["busy"].connect(() => {
				this.upload_button.sensitive = !this.store.busy && !this.store.uploading;
			});
			this.store.notify["uploading"].connect(() => {
				this.upload_button.sensitive = !this.store.busy && !this.store.uploading;
			});
			this.remove_confirmed.connect((row) => {
				var item = row as Argus.Shared.SQT.Distributable;
				if (item == null || this.store.busy || this.store.uploading) {
					return;
				}
				this.store.archive((int) item.id);
			});
			this.upload_button.clicked.connect(() => {
				this.uploader.open(this.window);
			});
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.archived.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Archived"));
			});
			this.store.uploaded.connect((row) => {
				this.toasts.add_toast(new Adw.Toast(row.name + " " + row.version));
			});
			this.store.upload_cancelled.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Upload cancelled"));
			});
			this.store.load();
		}
	}
}
