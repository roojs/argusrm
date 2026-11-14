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
	 * A {@link Gtk.ColumnView} over
	 * {@link Argus.Controller.Store.Agent}.
	 * One button on the page opens registration.
	 * Right-click a row for a menu. Remove on that menu
	 * asks, then deletes the selection.
	 * Right-click a column header to show or hide columns.
	 * Registered starts hidden.
	 * The Kind cell of the controller this window is using
	 * has a green background.
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
		private Gtk.MultiSelection selection;
		private Gtk.Stack body;
		private Adw.Spinner spinner;
		private Adw.ToastOverlay toasts;

		/**
		 * Build the list. One button opens registration.
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
			this.spinner = new Adw.Spinner() {
				visible = false
			};
			var removing_label = new Gtk.Label("Removing") {
				visible = false
			};
			var pending = new Gee.ArrayList<int>();
			var register_add = new Gtk.Button() {
				child = new Adw.ButtonContent() {
					icon_name = "list-add-symbolic",
					label = "Agent or Controller"
				},
				tooltip_text = "Register an agent or a controller"
			};
			register_add.clicked.connect(() => {
				this.activate_action("win.register", null);
			});
			var name_factory = new Gtk.SignalListItemFactory();
			name_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
				item.child.set_data("argus-agent-row", item);
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
				item.child.set_data("argus-agent-row", item);
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
				item.child.set_data("argus-agent-row", item);
			});
			user_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Argus.Shared.Agent) item.item).bind_property("username",
					(Gtk.Label) item.child, "label", GLib.BindingFlags.SYNC_CREATE);
			});
			var mine = "";
			if (window.issued.client_certificate != "") {
				try {
					var cert = new GLib.TlsCertificate.from_pem(
						window.issued.client_certificate,
						window.issued.client_certificate.length);
					mine = GLib.Checksum.compute_for_data(
						GLib.ChecksumType.SHA256, cert.certificate.data);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			var kind_factory = new Gtk.SignalListItemFactory();
			kind_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true
				};
				item.child.set_data("argus-agent-row", item);
			});
			kind_factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.Agent) item.item;
				var label = (Gtk.Label) item.child;
				row.bind_property("display_kind",
					label, "label", GLib.BindingFlags.SYNC_CREATE);
				if (mine != "" && row.fingerprint == mine) {
					label.add_css_class("argus-this-controller");
					return;
				}
				label.remove_css_class("argus-this-controller");
			});
			kind_factory.unbind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				((Gtk.Label) item.child).remove_css_class("argus-this-controller");
			});
			var registered_factory = new Gtk.SignalListItemFactory();
			registered_factory.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0.5f,
					hexpand = true
				};
				item.child.set_data("argus-agent-row", item);
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
				item.child.set_data("argus-agent-row", item);
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
					xalign = 0.5f,
					hexpand = true
				};
				item.child.set_data("argus-agent-row", item);
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
				item.child.set_data("argus-agent-row", item);
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
				resizable = true,
				visible = false
			};
			var created_column = new Gtk.ColumnViewColumn("Registered on", created_factory) {
				expand = true,
				resizable = true
			};
			var connected_column = new Gtk.ColumnViewColumn("Connected", connected_factory) {
				resizable = true
			};
			var last_column = new Gtk.ColumnViewColumn("Last connected", last_factory) {
				expand = true,
				resizable = true
			};
			var all_columns = new Gtk.ColumnViewColumn[] {
				name_column, address_column, user_column, kind_column,
				registered_column, created_column, connected_column, last_column
			};
			var column_menu = new GLib.Menu();
			var column_actions = new GLib.SimpleActionGroup();
			this.insert_action_group("columns", column_actions);
			var hostname_action = new GLib.SimpleAction.stateful(
				"hostname", null, new GLib.Variant.boolean(true));
			hostname_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					hostname_action.set_state(value);
					name_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == name_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				hostname_action.set_state(value);
				name_column.visible = false;
			});
			column_actions.add_action(hostname_action);
			column_menu.append("Hostname", "columns.hostname");
			name_column.header_menu = column_menu;
			var address_action = new GLib.SimpleAction.stateful(
				"address", null, new GLib.Variant.boolean(true));
			address_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					address_action.set_state(value);
					address_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == address_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				address_action.set_state(value);
				address_column.visible = false;
			});
			column_actions.add_action(address_action);
			column_menu.append("Address", "columns.address");
			address_column.header_menu = column_menu;
			var user_action = new GLib.SimpleAction.stateful(
				"user", null, new GLib.Variant.boolean(true));
			user_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					user_action.set_state(value);
					user_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == user_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				user_action.set_state(value);
				user_column.visible = false;
			});
			column_actions.add_action(user_action);
			column_menu.append("User", "columns.user");
			user_column.header_menu = column_menu;
			var kind_action = new GLib.SimpleAction.stateful(
				"kind", null, new GLib.Variant.boolean(true));
			kind_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					kind_action.set_state(value);
					kind_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == kind_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				kind_action.set_state(value);
				kind_column.visible = false;
			});
			column_actions.add_action(kind_action);
			column_menu.append("Kind", "columns.kind");
			kind_column.header_menu = column_menu;
			var registered_action = new GLib.SimpleAction.stateful(
				"registered", null, new GLib.Variant.boolean(false));
			registered_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					registered_action.set_state(value);
					registered_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == registered_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				registered_action.set_state(value);
				registered_column.visible = false;
			});
			column_actions.add_action(registered_action);
			column_menu.append("Registered", "columns.registered");
			registered_column.header_menu = column_menu;
			var created_action = new GLib.SimpleAction.stateful(
				"created", null, new GLib.Variant.boolean(true));
			created_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					created_action.set_state(value);
					created_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == created_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				created_action.set_state(value);
				created_column.visible = false;
			});
			column_actions.add_action(created_action);
			column_menu.append("Registered on", "columns.created");
			created_column.header_menu = column_menu;
			var connected_action = new GLib.SimpleAction.stateful(
				"connected", null, new GLib.Variant.boolean(true));
			connected_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					connected_action.set_state(value);
					connected_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == connected_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				connected_action.set_state(value);
				connected_column.visible = false;
			});
			column_actions.add_action(connected_action);
			column_menu.append("Connected", "columns.connected");
			connected_column.header_menu = column_menu;
			var last_action = new GLib.SimpleAction.stateful(
				"last", null, new GLib.Variant.boolean(true));
			last_action.change_state.connect((value) => {
				var on = value.get_boolean();
				if (on) {
					last_action.set_state(value);
					last_column.visible = true;
					return;
				}
				var others = 0;
				foreach (var other in all_columns) {
					if (other == last_column || !other.visible) {
						continue;
					}
					others++;
				}
				if (others < 1) {
					return;
				}
				last_action.set_state(value);
				last_column.visible = false;
			});
			column_actions.add_action(last_action);
			column_menu.append("Last connected", "columns.last");
			last_column.header_menu = column_menu;
			this.selection = new Gtk.MultiSelection(this.store);
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
			var row_model = new GLib.Menu();
			row_model.append("Remove", "row.remove");
			var row_menu = new Gtk.PopoverMenu.from_model(row_model) {
				has_arrow = false
			};
			row_menu.set_parent(view);
			var remove_rows = new GLib.SimpleAction("remove", null);
			remove_rows.activate.connect(() => {
				if (this.store.busy || removing_label.visible) {
					return;
				}
				string[] names = {};
				var ids = new Gee.ArrayList<int>();
				var count = (int) this.store.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!this.selection.is_selected((uint) i)) {
						continue;
					}
					var row = this.store.get_item((uint) i) as Argus.Shared.Agent;
					if (row == null) {
						continue;
					}
					names += row.display_name;
					ids.add((int) row.id);
				}
				if (ids.size < 1) {
					return;
				}
				var title = "Remove " + names[0];
				var detail = "This removes the machine from the server.";
				if (ids.size > 1) {
					title = "Remove " + ids.size.to_string() + " machines";
					detail = "This removes them from the server.";
				}
				var confirm = new Adw.AlertDialog(title,
					string.joinv("\n", names) + "\n" + detail);
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
					pending.clear();
					foreach (var id in ids) {
						pending.add(id);
					}
					removing_label.visible = true;
					this.store.remove(pending.get(0));
				});
				confirm.present(this);
			});
			var row_actions = new GLib.SimpleActionGroup();
			row_actions.add_action(remove_rows);
			view.insert_action_group("row", row_actions);
			var click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			click.pressed.connect((n_press, x, y) => {
				var picked = view.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (picked != null && picked != view &&
					picked.get_data<Gtk.ListItem>("argus-agent-row") == null) {
					picked = picked.parent;
				}
				if (picked == null || picked == view) {
					click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
				var row_item = picked.get_data<Gtk.ListItem>("argus-agent-row");
				if (row_item == null || this.store.busy || removing_label.visible) {
					return;
				}
				if (row_item.item == null) {
					return;
				}
				if (!this.selection.is_selected(row_item.position)) {
					this.selection.select_item(row_item.position, true);
				}
				var at_x = (int) x;
				var at_y = (int) y;
				var where = Gdk.Rectangle() {
					x = at_x,
					y = at_y,
					width = 1,
					height = 1
				};
				row_menu.set_pointing_to(where);
				row_menu.popup();
			});
			view.add_controller(click);
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
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(this.spinner);
			toolbar.append(removing_label);
			toolbar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			toolbar.append(register_add);
			this.append(toolbar);
			this.append(this.toasts);
			this.store.bind_property("busy", this.spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
			this.store.bind_property("busy", register_add, "sensitive",
				GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.INVERT_BOOLEAN);
			this.store.notify["empty"].connect(() => {
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.failed.connect((heading, message) => {
				pending.clear();
				removing_label.visible = false;
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.removed.connect(() => {
				if (pending.size < 1) {
					return;
				}
				pending.remove_at(0);
				if (pending.size > 0) {
					this.store.remove(pending.get(0));
					return;
				}
				removing_label.visible = false;
				this.toasts.add_toast(new Adw.Toast("Removed"));
				this.store.load();
			});
			this.window.app.rpc.notification.connect((notification) => {
				var refresh = notification.method == "event.agent";
				if (notification.method == "event.pair" && notification.action == "done") {
					refresh = true;
				}
				if (!refresh) {
					return;
				}
				this.store.load();
			});
			this.destroy.connect(() => {
				row_menu.unparent();
			});
			this.map.connect(() => {
				this.store.load();
			});
		}
	}
}
