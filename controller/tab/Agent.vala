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
	public class Agent : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Agent store;
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
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "agent",
				expand_column: "display-name"
			);
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
			this.column_grid(this.store, true);
			if (window.issued.client_certificate != "") {
				try {
					var cert = new GLib.TlsCertificate.from_pem(
						window.issued.client_certificate,
						window.issued.client_certificate.length);
					var mine = GLib.Checksum.compute_for_data(
						GLib.ChecksumType.SHA256, cert.certificate.data);
					this.grid.set_data("argus-controller-fingerprint", mine);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			var row_model = new GLib.Menu();
			row_model.append("Remove", "row.remove");
			var row_menu = new Gtk.PopoverMenu.from_model(row_model) {
				has_arrow = false
			};
			row_menu.set_parent(this.grid);
			var remove_rows = new GLib.SimpleAction("remove", null);
			remove_rows.activate.connect(() => {
				if (this.store.busy || removing_label.visible) {
					return;
				}
				string[] names = {};
				var ids = new Gee.ArrayList<int>();
				var selection = (Gtk.MultiSelection) this.grid.model;
				var count = (int) selection.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!selection.is_selected((uint) i)) {
						continue;
					}
					var row = selection.get_item((uint) i) as Argus.Shared.Agent;
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
			this.grid.insert_action_group("row", row_actions);
			var click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			var selection = (Gtk.MultiSelection) this.grid.model;
			click.pressed.connect((n_press, x, y) => {
				var picked = this.grid.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (picked != null && picked != this.grid &&
					picked.get_data<Gtk.ListItem>("argus-grid-row") == null) {
					picked = picked.parent;
				}
				if (picked == null || picked == this.grid) {
					click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
				var row_item = picked.get_data<Gtk.ListItem>("argus-grid-row");
				if (row_item == null || this.store.busy || removing_label.visible) {
					return;
				}
				if (row_item.item == null) {
					return;
				}
				if (!selection.is_selected(row_item.position)) {
					selection.select_item(row_item.position, true);
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
			this.grid.add_controller(click);
			var scroll = new Gtk.ScrolledWindow() {
				child = this.grid,
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
