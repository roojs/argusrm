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

namespace Argus.Controller.Tab.Register
{
	/**
	 * Registered agents and controllers.
	 *
	 * A {@link Gtk.ColumnView} over
	 * {@link Argus.Controller.Store.Agent}.
	 * One button on the page opens registration.
	 * The remove column uses click and hold. Other machines
	 * remove at once. This controller asks first.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Register.Current(window);
	 * }}}
	 */
	public class Current : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Agent store;
		private Gtk.Stack body;

		/**
		 * Build the list. One button opens registration.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Current(Argus.Controller.Window window)
		{
			base("agent", "display-name");
			this.window = window;
			this.store = new Argus.Controller.Store.Agent(window.app);
			var bar_spinner = new Adw.Spinner() {
				visible = false
			};
			var removing_label = new Gtk.Label("Removing") {
				visible = false
			};
			var remove_queue = new Gee.ArrayList<int>();
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
			if (window.server.pem_client_certificate != "") {
				try {
					var cert = new GLib.TlsCertificate.from_pem(
						window.server.pem_client_certificate,
						window.server.pem_client_certificate.length);
					var mine = GLib.Checksum.compute_for_data(
						GLib.ChecksumType.SHA256, cert.certificate.data);
					this.grid.set_data("argus-controller-fingerprint", mine);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			this.remove_confirmed.connect((obj) => {
				var row = obj as Argus.Shared.Agent;
				if (row == null || this.store.busy || removing_label.visible) {
					return;
				}
				var mine = this.grid.get_data<string>(
					"argus-controller-fingerprint");
				var self_remove = mine != null && mine != "" &&
					row.fingerprint == mine;
				if (!self_remove) {
					remove_queue.clear();
					remove_queue.add((int) row.id);
					removing_label.visible = true;
					this.store.remove(remove_queue.get(0));
					return;
				}
				var name = row.display_name;
				var confirm = new Adw.AlertDialog(
					"Remove " + name,
					name + "\nThis removes this controller from the server.");
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
					remove_queue.clear();
					remove_queue.add((int) row.id);
					removing_label.visible = true;
					this.store.remove(remove_queue.get(0));
				});
				confirm.present(this);
			});
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
			this.body.add_named(this.overlay, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(bar_spinner);
			toolbar.append(removing_label);
			toolbar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			toolbar.append(register_add);
			this.content.append(toolbar);
			this.content.append(this.body);
			this.store.bind_property("busy", bar_spinner, "visible",
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
				remove_queue.clear();
				removing_label.visible = false;
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.removed.connect(() => {
				if (remove_queue.size < 1) {
					return;
				}
				remove_queue.remove_at(0);
				if (remove_queue.size > 0) {
					this.store.remove(remove_queue.get(0));
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
			this.map.connect(() => {
				this.store.load();
			});
		}
	}
}