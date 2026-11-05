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

namespace Argus.Controller
{
	/**
	 * One-minute window that shows a PIN while a machine pairs.
	 *
	 * {@link open} draws a new six-digit PIN and a line that counts
	 * down from sixty seconds. ''event.pair'' says ''number rejected''
	 * or closes after one machine pairs. The title bar closes the
	 * dialog and clears the PIN. {@link pairing} is true only while
	 * the dialog is open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pair = new Argus.Controller.PairingDialog(window);
	 * pair.open("Agent");
	 * }}}
	 */
	public class PairingDialog : Adw.Dialog
	{
		private unowned Window window;
		private OLLMrpc.Client? rpc;
		private Gtk.Label title_label;
		private Gtk.Label pin_label;
		private Gtk.Label note;
		private Gtk.ProgressBar line;
		private uint tick_id = 0;
		private int remaining = 60;
		private int generation = 0;
		private bool finished = false;

		/**
		 * True while this dialog is counting down.
		 */
		public bool pairing { get; private set; default = false; }

		/**
		 * @param window main window that presents this dialog
		 */
		public PairingDialog(Window window)
		{
			this.window = window;
			this.title = "Register";
			this.set_content_width(560);
			var css = new Gtk.CssProvider();
			css.load_from_string(
				".pairing-pin { font-size: 64px; font-weight: 800; letter-spacing: 0.35em; font-family: monospace; }");
			var display = Gdk.Display.get_default();
			if (display != null) {
				Gtk.StyleContext.add_provider_for_display(display, css,
					Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			}
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.title_label = new Gtk.Label("Register") {
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
			box.append(body);
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
				this.arm("");
			});
		}

		/**
		 * Show a new PIN and start the sixty-second line.
		 *
		 * @param kind ''Agent'' or ''Controller''
		 */
		public void open(string kind)
		{
			if (this.pairing) {
				return;
			}
			var n = GLib.Random.int_range(0, 1000000);
			var pin = "%06d".printf(n);
			this.pin_label.label = pin;
			this.note.label = "";
			this.remaining = 60;
			this.line.fraction = 1;
			this.finished = false;
			this.pairing = true;
			var heading = "Register " + kind.down();
			this.title = heading;
			this.title_label.label = heading;
			this.generation++;
			var ticket = this.generation;
			var rpc = new OLLMrpc.Client("", "",
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock")) {
				live_handles = true
			};
			rpc.debug = false;
			this.rpc = rpc;
			rpc.notification.connect((notification) => {
				if (ticket != this.generation || this.finished) {
					return;
				}
				if (notification.method != "event.pair") {
					return;
				}
				if (notification.action == "rejected") {
					this.note.label = "number rejected";
					return;
				}
				if (notification.action != "done") {
					return;
				}
				this.finished = true;
				this.close();
			});
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				if (ticket != this.generation) {
					return;
				}
				var opened = rpc.connect.end(res);
				if (!opened) {
					this.pairing = false;
					var down = new Argus.Shared.Notice(
						"Could not start pairing", rpc.connect_error);
					down.add_response("ok", "OK");
					down.present(this.window);
					return;
				}
				this.present(this.window);
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
				this.arm(pin);
			});
		}

		/**
		 * Send ''pin'' to ''Agent.pair''.
		 *
		 * Empty clears the window. ''used'' or ''ok'' closes it.
		 *
		 * @param pin six digits, or empty
		 */
		private void arm(string pin)
		{
			var rpc = this.rpc;
			if (rpc == null) {
				return;
			}
			var ticket = this.generation;
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.pair",
				args = OLLMrpc.args("s", pin)
			}, (obj, res) => {
				if (ticket != this.generation) {
					return;
				}
				try {
					var response = rpc.call.end(res);
					if (this.finished || pin == "") {
						return;
					}
					if (response.error != null) {
						this.note.label = response.error.message;
						return;
					}
					if (response.msg == "used" || response.msg == "ok") {
						this.finished = true;
						this.close();
					}
				} catch (GLib.Error e) {
					if (this.finished || pin == "") {
						if (pin == "") {
							GLib.warning("%s", e.message);
						}
						return;
					}
					this.note.label = e.message;
				}
			});
		}
	}
}
