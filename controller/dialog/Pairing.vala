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

namespace Argus.Controller.Dialog
{
	/**
	 * Registration window. It opens on a six-digit number.
	 *
	 * {@link open} asks the controller's server connection for
	 * a six-digit number and counts down from sixty seconds.
	 * A typed number still closes this dialog. The first
	 * ''event.pair'' / ''pending'' stops that countdown and
	 * shows {@link Argus.Controller.Tab.Pairing}. Further pending
	 * requests append a row. The title bar closes the dialog.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pair = new Argus.Controller.Dialog.Pairing(window);
	 * pair.open();
	 * }}}
	 */
	public class Pairing : Adw.Dialog
	{
		private unowned Window window;
		private Gtk.Label title_label;
		private Gtk.Label pin_label;
		private Gtk.Label note;
		private Gtk.ProgressBar line;
		private Gtk.Stack pages;
		private Argus.Controller.Tab.Pairing queue;
		private uint tick_id = 0;
		private int remaining = 60;
		private int generation = 0;
		private bool finished = false;
		private bool wired = false;
		private bool listing = false;

		/**
		 * True while this dialog is counting down.
		 */
		public bool pairing { get; private set; default = false; }

		/**
		 * @param window main window that presents this dialog
		 */
		public Pairing(Window window)
		{
			this.window = window;
			this.title = "Register " + Argus.VERSION;
			this.set_content_width(560);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.title_label = new Gtk.Label("Register " + Argus.VERSION) {
				css_classes = { "title" }
			};
			box.append(new Adw.HeaderBar() {
				title_widget = this.title_label
			});
			var body = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24
			};
			this.pin_label = new Gtk.Label("") {
				halign = Gtk.Align.CENTER,
				selectable = true,
				focusable = false,
				css_classes = { "pairing-pin" }
			};
			body.append(this.pin_label);
			this.line = new Gtk.ProgressBar() {
				fraction = 1,
				hexpand = true
			};
			body.append(this.line);
			this.note = new Gtk.Label("") {
				halign = Gtk.Align.CENTER,
				css_classes = { "dim-label" }
			};
			body.append(this.note);
			this.queue = new Argus.Controller.Tab.Pairing();
			this.pages = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.pages.add_named(body, "number");
			this.pages.add_named(this.queue, "queue");
			this.pages.visible_child_name = "number";
			box.append(this.pages);
			this.set_child(box);
			this.closed.connect(() => {
				this.pairing = false;
				if (this.tick_id != 0) {
					GLib.Source.remove(this.tick_id);
					this.tick_id = 0;
				}
				if (this.finished) {
					return;
				}
				this.finished = true;
			});
		}

		/**
		 * Ask the server connection for a number.
		 */
		public void open()
		{
			if (this.pairing) {
				return;
			}
			var rpc = this.window.app.rpc;
			if (rpc == null || !rpc.connected) {
				this.refuse("The server connection is not open.");
				return;
			}
			this.begin();
		}

		/**
		 * Show the dialog and ask ''Agent.offer'' for the six digits.
		 */
		private void begin()
		{
			var rpc = this.window.app.rpc;
			if (rpc == null || !rpc.connected || this.pairing) {
				return;
			}
			this.pin_label.label = "";
			this.note.label = "";
			this.remaining = 60;
			this.line.fraction = 1;
			this.finished = false;
			this.listing = false;
			this.queue.clear();
			this.pages.visible_child_name = "number";
			this.pairing = true;
			this.title = "Register " + Argus.VERSION;
			this.title_label.label = "Register " + Argus.VERSION;
			this.generation++;
			this.present(this.window);
			this.arm();
			if (this.wired) {
				return;
			}
			this.wired = true;
			rpc.notification.connect((notification) => {
				if (this.finished) {
					return;
				}
				if (notification.method != "event.pair") {
					return;
				}
				if (notification.action == "rejected") {
					this.note.label = "number rejected";
					return;
				}
				if (notification.action == "done") {
					this.finished = true;
					this.close();
					return;
				}
				if (notification.action != "pending") {
					return;
				}
				if (notification.args.size < 2 || !this.pairing) {
					return;
				}
				var id = (int64) notification.args.get(0).get_int();
				var ip = notification.args.get(1).get_string();
				var name = "";
				if (notification.args.size > 2) {
					name = notification.args.get(2).get_string();
				}
				if (this.listing) {
					this.queue.add_machine(id, ip, name);
					return;
				}
				this.listing = true;
				if (this.tick_id != 0) {
					GLib.Source.remove(this.tick_id);
					this.tick_id = 0;
				}
				this.generation++;
				this.pages.visible_child_name = "queue";
				this.queue.add_machine(id, ip, name);
			});
		}

		/**
		 * Tell the user that pairing did not start.
		 *
		 * @param message reason under the heading
		 */
		private void refuse(string message)
		{
			var down = new Argus.Shared.Notice("Could not start pairing", message);
			down.add_response("ok", "OK");
			down.present(this.window);
		}

		/**
		 * Ask ''Agent.offer'' for the six digits.
		 */
		private void arm()
		{
			var rpc = this.window.app.rpc;
			if (rpc == null) {
				return;
			}
			var ticket = this.generation;
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.offer"
			}, (obj, res) => {
				if (ticket != this.generation || this.finished) {
					return;
				}
				try {
					var response = rpc.call.end(res);
					if (response.error != null) {
						this.note.label = response.error.message;
						return;
					}
					var reply = (string[]) response.retval;
					if (reply.length < 1 || reply[0].length != 6) {
						this.note.label = "The server did not return a number.";
						return;
					}
					this.pin_label.label = reply[0];
					this.pin_label.select_region(0, 0);
					this.tick_id = GLib.Timeout.add_seconds(1, () => {
						if (ticket != this.generation) {
							return false;
						}
						this.remaining -= 1;
						this.line.fraction = this.remaining / 60.0;
						if (this.remaining > 0) {
							return true;
						}
						this.tick_id = 0;
						this.close();
						return false;
					});
				} catch (GLib.Error e) {
					if (this.finished) {
						GLib.warning("%s", e.message);
						return;
					}
					this.note.label = e.message;
				}
			});
		}
	}
}
