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
	 * Machines waiting for registration approval.
	 *
	 * {@link Argus.Controller.Tab.Pairing} and
	 * {@link Argus.Controller.Store.Pairing} back the list.
	 * Accept and Reject call ''Offering.accept'' and
	 * ''Offering.reject''. Stop bulk registration is shown
	 * here while provisional registration is open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Register.Pending(window);
	 * }}}
	 */
	public class Pending : Gtk.Box
	{
		private Argus.Controller.Window window;
		/**
		 * Tick list and {@link Argus.Controller.Store.Pairing}.
		 */
		public Argus.Controller.Tab.Pairing queue { get; private set; }
		/**
		 * Ends provisional registration.
		 *
		 * Shown on this tab only while bulk registration is open.
		 */
		public Gtk.Button stop_bulk;
		private Adw.ToastOverlay toasts;

		/**
		 * Build the tick list and action bar.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Pending(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.queue = new Argus.Controller.Tab.Pairing();
			var reject = new Gtk.Button.with_label("Reject");
			var accept = new Gtk.Button.with_label("Accept") {
				css_classes = { "suggested-action" }
			};
			this.queue.append(new Gtk.CenterBox() {
				hexpand = true,
				start_widget = reject,
				end_widget = accept
			});
			reject.clicked.connect(() => {
				this.decide(false);
			});
			accept.clicked.connect(() => {
				this.decide(true);
			});
			this.stop_bulk = new Gtk.Button.with_label("Stop bulk registration") {
				visible = false,
				halign = Gtk.Align.START,
				margin_top = 12,
				margin_start = 12,
				margin_end = 12,
				css_classes = { "destructive-action" }
			};
			this.stop_bulk.clicked.connect(() => {
				var rpc = this.window.app.rpc;
				if (rpc == null || !rpc.connected) {
					this.toasts.add_toast(new Adw.Toast(
						"The server connection is not open."));
					return;
				}
				rpc.call.begin(new OLLMrpc.Request() {
					method = "Offering.close",
					args = OLLMrpc.args("b", true)
				}, (obj, res) => {
					OLLMrpc.Response response;
					try {
						response = rpc.call.end(res);
					} catch (GLib.Error e) {
						this.toasts.add_toast(new Adw.Toast(e.message));
						return;
					}
					if (response.error != null) {
						this.toasts.add_toast(new Adw.Toast(response.error.message));
						return;
					}
					this.window.register_page.bulk_on = false;
				});
			});
			this.toasts = new Adw.ToastOverlay() {
				hexpand = true,
				vexpand = true,
				child = this.queue
			};
			this.append(this.stop_bulk);
			this.append(this.toasts);
			this.window.app.rpc.notification.connect((notification) => {
				if (notification.method != "event.pair") {
					return;
				}
				if (notification.action != "pending") {
					return;
				}
				if (notification.args.size < 2) {
					return;
				}
				var id = (int64) notification.args.get(0).get_int();
				var ip = notification.args.get(1).get_string();
				var name = "";
				if (notification.args.size > 2) {
					name = notification.args.get(2).get_string();
				}
				this.queue.add_machine(id, ip, name);
			});
		}

		/**
		 * Accept or reject the ticked rows.
		 *
		 * @param accept true for ''Offering.accept''
		 */
		private void decide(bool accept)
		{
			if (this.queue.store.picked.size < 1) {
				return;
			}
			var rpc = this.window.app.rpc;
			if (rpc == null || !rpc.connected) {
				return;
			}
			int[] ids = new int[this.queue.store.picked.size];
			var n = 0;
			foreach (var row in this.queue.store.picked.values) {
				ids[n] = (int) row.id;
				n++;
			}
			var method = accept ? "Offering.accept" : "Offering.reject";
			rpc.call.begin(new OLLMrpc.Request() {
				method = method,
				args = OLLMrpc.args("ai", ids, ids.length)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = rpc.call.end(res);
				} catch (GLib.Error e) {
					this.toasts.add_toast(new Adw.Toast(e.message));
					return;
				}
				if (response.error != null) {
					this.toasts.add_toast(new Adw.Toast(response.error.message));
					return;
				}
				for (var i = 0; i < ids.length; i++) {
					this.queue.store.drop((int64) ids[i]);
				}
			});
		}
	}
}