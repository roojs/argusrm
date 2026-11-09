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
	 * Agent page.
	 *
	 * A {@link Gtk.ColumnView} over {@link Argus.Controller.Store.Agent}.
	 * Each column binds a property of {@link Argus.Shared.Agent}.
	 * Register sits above the list. Remove sits below it.
	 * The store loads when the page is shown.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Agent(window);
	 * stack.add_named(page, "agents");
	 * }}}
	 */
	public class Agent : Gtk.Box
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Agent store;
		private Gtk.SingleSelection selection;
		private Gtk.Stack body;
		private Gtk.Button remove_button;
		private Gtk.Spinner spinner;
		private Adw.ToastOverlay toasts;

		/**
		 * Build the list, with Register above it and Remove below it.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Agent(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Agent(window.app);
			this.spinner = new Gtk.Spinner() {
				visible = false
			};
			var menu = new GLib.Menu();
			menu.append("Register agent", "win.register('Agent')");
			menu.append("Register controller", "win.register('Controller')");
			var register_button = new Gtk.MenuButton() {
				label = "Register",
				menu_model = menu,
				tooltip_text = "Register a machine with this server",
				css_classes = { "suggested-action" }
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
			toolbar.append(register_button);
			this.remove_button = new Gtk.Button.with_label("Remove") {
				sensitive = false,
				css_classes = { "destructive-action" },
				tooltip_text = "Remove this machine from the server"
			};
			var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.END,
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
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
				((Argus.Shared.Agent) item.item).bind_property("display_name",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var address_factory = new Gtk.SignalListItemFactory();
			address_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			address_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("ip",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var user_factory = new Gtk.SignalListItemFactory();
			user_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			user_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("username",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var kind_factory = new Gtk.SignalListItemFactory();
			kind_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			kind_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("display_kind",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var registered_factory = new Gtk.SignalListItemFactory();
			registered_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			registered_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("display_registered",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var created_factory = new Gtk.SignalListItemFactory();
			created_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			created_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("display_created",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var connected_factory = new Gtk.SignalListItemFactory();
			connected_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			connected_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("display_connected",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var last_factory = new Gtk.SignalListItemFactory();
			last_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
			});
			last_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("display_last",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var name_column = new Gtk.ColumnViewColumn("Hostname", name_factory) {
				expand = true,
				resizable = true
			};
			var address_column = new Gtk.ColumnViewColumn("Address", address_factory) {
				expand = true,
				resizable = true
			};
			var user_column = new Gtk.ColumnViewColumn("User", user_factory) {
				expand = true,
				resizable = true
			};
			var kind_column = new Gtk.ColumnViewColumn("Kind", kind_factory) {
				expand = true,
				resizable = true
			};
			var registered_column = new Gtk.ColumnViewColumn("Registered", registered_factory) {
				expand = true,
				resizable = true
			};
			var created_column = new Gtk.ColumnViewColumn("Registered on", created_factory) {
				expand = true,
				resizable = true
			};
			var connected_column = new Gtk.ColumnViewColumn("Connected", connected_factory) {
				expand = true,
				resizable = true
			};
			var last_column = new Gtk.ColumnViewColumn("Last connected", last_factory) {
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
			view.append_column(address_column);
			view.append_column(user_column);
			view.append_column(kind_column);
			view.append_column(registered_column);
			view.append_column(created_column);
			view.append_column(connected_column);
			view.append_column(last_column);
			var scroll = new Gtk.ScrolledWindow() {
				child = view,
				vexpand = true,
				hexpand = true
			};
			var empty = new Adw.StatusPage() {
				title = "No machines",
				description = "Register a machine to see it here.",
				icon_name = "computer-symbolic",
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
			this.store.bind_property("busy", this.spinner, "spinning",
				GLib.BindingFlags.SYNC_CREATE);
			this.store.bind_property("busy", this.spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
			this.store.bind_property("busy", register_button, "sensitive",
				GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.INVERT_BOOLEAN);
			this.store.notify["empty"].connect(() => {
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.notify["busy"].connect(() => {
				if (this.store.busy) {
					this.remove_button.sensitive = false;
					return;
				}
				var on = this.selection.selected != Gtk.INVALID_LIST_POSITION;
				this.remove_button.sensitive = on;
			});
			this.selection.selection_changed.connect((position, n_items) => {
				if (this.store.busy) {
					return;
				}
				var on = this.selection.selected != Gtk.INVALID_LIST_POSITION;
				this.remove_button.sensitive = on;
			});
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.removed.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Removed"));
			});
			this.remove_button.clicked.connect(() => {
				var row = this.selection.selected_item as Argus.Shared.Agent;
				if (row == null) {
					return;
				}
				var id = (int) row.id;
				var confirm = new Adw.AlertDialog(
					"Remove " + row.display_name,
					"This removes the machine from the server.");
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
			this.window.app.rpc.notification.connect((notification) => {
				if (notification.method != "event.pair") {
					return;
				}
				if (notification.action != "done") {
					return;
				}
				this.store.load();
			});
			this.map.connect(() => {
				this.store.load();
			});
		}
	}
}
