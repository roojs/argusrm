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
	 * Repository page.
	 *
	 * A {@link Gtk.ColumnView} over {@link Argus.Controller.Store.Repository}.
	 * Clone, pull, and remove sit on this page. Clone opens
	 * {@link Argus.Controller.Dialog.Repository}. The store loads when the
	 * page is created.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Repository(window);
	 * stack.add_named(page, "repositories");
	 * }}}
	 */
	public class Repository : Gtk.Box
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Repository store;
		private Argus.Controller.Dialog.Repository dialog;
		private Gtk.SingleSelection selection;
		private Gtk.Stack body;
		private Gtk.Button pull_button;
		private Gtk.Button remove_button;
		private Gtk.Button clone_button;
		private Adw.Spinner spinner;
		private Adw.ToastOverlay toasts;

		/**
		 * Build the list, with Clone above it and pull and remove below it.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Repository(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Repository(window.app);
			this.dialog = new Argus.Controller.Dialog.Repository(this.store);
			this.spinner = new Adw.Spinner() {
				visible = false
			};
			this.clone_button = new Gtk.Button.with_label("Clone") {
				css_classes = { "suggested-action" },
				tooltip_text = "Clone a repository onto the server",
				halign = Gtk.Align.END
			};
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(this.spinner);
			var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			};
			toolbar.append(spacer);
			toolbar.append(this.clone_button);
			this.pull_button = new Gtk.Button.with_label("Pull") {
				sensitive = false,
				tooltip_text = "Fetch this clone and refresh its scripts"
			};
			this.remove_button = new Gtk.Button.with_label("Remove library") {
				sensitive = false,
				css_classes = { "destructive-action" },
				tooltip_text = "Delete this clone from the server"
			};
			var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.END,
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			bottom.append(this.pull_button);
			bottom.append(this.remove_button);
			var name_factory = new Gtk.SignalListItemFactory();
			name_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			name_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQT.ScriptRepository) item.item;
				var title = row.name;
				if (title == "") {
					title = row.url;
				}
				((Gtk.Label) item.child).label = title;
			});
			var url_factory = new Gtk.SignalListItemFactory();
			url_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					css_classes = { "dim-label" }
				};
			});
			url_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQT.ScriptRepository) item.item;
				((Gtk.Label) item.child).label = row.url;
			});
			var name_column = new Gtk.ColumnViewColumn("Name", name_factory) {
				expand = true,
				resizable = true
			};
			var url_column = new Gtk.ColumnViewColumn("URL", url_factory) {
				expand = true,
				resizable = true
			};
			this.selection = new Gtk.SingleSelection(this.store) {
				autoselect = false,
				can_unselect = true
			};
			var view = new Gtk.ColumnView(this.selection) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			view.append_column(name_column);
			view.append_column(url_column);
			var scroll = new Gtk.ScrolledWindow() {
				child = view,
				vexpand = true,
				hexpand = true
			};
			var empty = new Adw.StatusPage() {
				title = "No repositories",
				description = "Clone a git repository onto this server.",
				icon_name = "folder-symbolic",
				vexpand = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(scroll, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			this.toasts = new Adw.ToastOverlay() {
				child = this.body,
				hexpand = true,
				vexpand = true
			};
			this.append(toolbar);
			this.append(this.toasts);
			this.append(bottom);
			this.store.bind_property("busy", this.spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
			this.store.notify["empty"].connect(() => {
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.notify["busy"].connect(() => {
				this.clone_button.sensitive = !this.store.busy;
				if (this.store.busy) {
					this.pull_button.sensitive = false;
					this.remove_button.sensitive = false;
					return;
				}
				var on = this.selection.selected != Gtk.INVALID_LIST_POSITION;
				this.pull_button.sensitive = on;
				this.remove_button.sensitive = on;
			});
			this.selection.selection_changed.connect((position, n_items) => {
				if (this.store.busy) {
					return;
				}
				var on = this.selection.selected != Gtk.INVALID_LIST_POSITION;
				this.pull_button.sensitive = on;
				this.remove_button.sensitive = on;
			});
			this.store.failed.connect((heading, message) => {
				if (this.dialog.showing) {
					return;
				}
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.saved.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Cloned"));
			});
			this.store.pulled.connect((count) => {
				this.toasts.add_toast(new Adw.Toast(
					"Pulled " + count.to_string() + " scripts"));
			});
			this.store.removed.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Removed"));
			});
			this.clone_button.clicked.connect(() => {
				if (this.store.busy) {
					return;
				}
				this.dialog.open(this);
			});
			this.pull_button.clicked.connect(() => {
				var row = this.selection.selected_item as Argus.Shared.SQT.ScriptRepository;
				if (row == null) {
					return;
				}
				this.store.pull((int) row.id);
			});
			this.remove_button.clicked.connect(() => {
				var row = this.selection.selected_item as Argus.Shared.SQT.ScriptRepository;
				if (row == null) {
					return;
				}
				var id = (int) row.id;
				var name = row.name;
				var confirm = new Adw.AlertDialog(
					"Remove " + name,
					"This deletes the clone on the server.");
				confirm.add_response("cancel", "Cancel");
				confirm.add_response("remove", "Remove");
				confirm.set_response_appearance(
					"remove", Adw.ResponseAppearance.DESTRUCTIVE);
				confirm.set_default_response("cancel");
				confirm.set_close_response("cancel");
				confirm.response.connect((response) => {
					if (response != "remove") {
						return;
					}
					this.store.remove(id);
				});
				confirm.present(this);
			});
			this.store.load();
		}
	}
}
