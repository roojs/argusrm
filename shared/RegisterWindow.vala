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

namespace Argus.Shared
{
	/**
	 * Registration window for the agent and the controller.
	 *
	 * Listens for the pairing service, then asks for the six digits.
	 * The sixth digit starts registration. Android sends
	 * {@link Browse.label} as the requester. Linux and Windows send
	 * the host name.
	 */
	public class RegisterWindow : Adw.Dialog
	{
		/**
		 * ''tcp://host:port'' that answered hello. Null until then.
		 */
		public string? registered_url { get; private set; }

		/**
		 * Every ''host:port'' from the reply, one per line.
		 */
		public string registered_addresses { get; private set; default = ""; }

		/**
		 * Id from the broadcast TXT record.
		 */
		public string server_id { get; private set; default = ""; }

		/**
		 * Certificate storage directory.
		 *
		 * Empty keeps the current-user default.
		 */
		public string data_dir { get; set; default = ""; }

		public Gtk.Label listen_label;
		private Gtk.Entry pin_entry;
		private Gtk.Box pin_box;
		private string found = "";
		private uint browse_id = 0;
		private uint close_id = 0;
		private Browse browse = new Browse();
		private bool registering = false;

		/**
		 * The tray asks the service to register.
		 *
		 * Android and the controller leave this false and call
		 * {@link Register} in this window. The Windows tray sets
		 * it and handles {@link send_pin}.
		 */
		public bool use_pipe = false;

		/**
		 * Registration code written by {@link send_pin}.
		 *
		 * The tray sets this before the signal returns.
		 */
		public int pipe_code = 0;

		/**
		 * Registration failed, or there is nothing to register.
		 *
		 * The window shows this text and logs it.
		 *
		 * @param error_message failure text
		 */
		public signal void error_occurred(string error_message);

		/**
		 * The dialog has closed.
		 *
		 * Browse is stopped and the pin entry is cleared.
		 */
		public signal void dialog_closed();

		/**
		 * Registration wrote the certificate files.
		 */
		public signal void certificate_received();

		/**
		 * Six digits for the service to register.
		 *
		 * The Windows tray connects this and writes the number on
		 * the local pipe. The reply is stored in {@link pipe_code}.
		 *
		 * @param pin the six digits
		 */
		public signal void send_pin(string pin);

		public RegisterWindow()
		{
			this.title = "Connect to management server";
			this.set_content_height(280);
			this.set_content_width(480);

			var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			var close_button =
				new Gtk.Button.from_icon_name("window-close-symbolic") {
					tooltip_text = "Close",
					css_classes = {"flat"}
				};
			close_button.clicked.connect(() => {
				this.close();
			});
			header.pack_end(close_button);
			content.append(header);

			var body = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				valign = Gtk.Align.CENTER,
				vexpand = true
			};
			var pin_label = new Gtk.Label("Enter registration PIN") {
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				css_classes = {"dim-label"}
			};
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "000000",
				max_length = 6,
				input_purpose = Gtk.InputPurpose.DIGITS,
				xalign = 0.5f,
				hexpand = true,
				height_request = 64,
				css_classes = {"title-1"}
			};
			this.pin_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				visible = false,
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			this.pin_box.append(pin_label);
			this.pin_box.append(this.pin_entry);
			body.append(this.pin_box);
			this.listen_label = new Gtk.Label("Looking for a management server…") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				margin_top = 12,
				margin_bottom = 12
			};
			body.append(this.listen_label);
			content.append(body);
			this.set_child(content);

			this.error_occurred.connect((error_message) => {
				this.listen_label.label = error_message;
				this.registering = false;
				this.pin_entry.grab_focus();
				GLib.warning("%s", error_message);
			});
			this.pin_entry.changed.connect(() => {
				if (!this.valid_pin(this.pin_entry.text.strip())) {
					return;
				}
				this.request.begin();
			});
			this.pin_entry.activate.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.can_close = true;
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				if (this.close_id != 0) {
					GLib.Source.remove(this.close_id);
					this.close_id = 0;
				}
				var root = this.get_root() as Gtk.Window;
				if (root != null) {
					this.browse.stop();
				}
				this.pin_entry.text = "";
				this.dialog_closed();
			});
		}

		/**
		 * Prepares the dialog before {@link Gtk.Window.present}.
		 */
		public void show_add()
		{
			this.registered_url = null;
			this.registered_addresses = "";
			this.server_id = "";
			this.found = "";
			this.registering = false;
			this.pin_entry.text = "";
			this.pin_box.visible = false;
			this.listen_label.label = "Looking for a management server…";
			if (this.close_id != 0) {
				GLib.Source.remove(this.close_id);
				this.close_id = 0;
			}
			if (this.browse_id != 0) {
				GLib.Source.remove(this.browse_id);
				this.browse_id = 0;
			}
			this.browse_id = GLib.Idle.add(() => {
				this.browse_id = 0;
				var window = this.get_root() as Gtk.Window;
				if (window == null) {
					this.listen_label.label = "No management server found";
					return false;
				}
				this.browse.start();
				this.browse_id = GLib.Timeout.add(200, () => {
					var hit = this.browse.poll();
					if (hit == "") {
						return true;
					}
					var root = this.get_root() as Gtk.Window;
					if (root != null) {
						this.browse.stop();
					}
					this.browse_id = 0;
					if (hit == "none") {
						this.listen_label.label = "No management server found";
						return false;
					}
					var nl = hit.index_of("\n");
					if (nl <= 0 || !GLib.Uuid.string_is_valid(hit.substring(0, nl))) {
						this.listen_label.label = "No server id";
						return false;
					}
					this.server_id = hit.substring(0, nl);
					this.found = hit.substring(nl + 1);
					this.listen_label.label =
						"Management server found. Enter the six-digit PIN.";
					this.pin_box.visible = true;
					this.pin_entry.grab_focus();
					return false;
				});
				return false;
			});
		}

		private async void request()
		{
			if (this.registering) {
				return;
			}
			if (this.found == "") {
				this.error_occurred("No management server found");
				return;
			}
			var colon = this.found.last_index_of(":");
			if (colon <= 0) {
				this.error_occurred("Bad address");
				return;
			}
			var port = 0;
			if (!int.try_parse(this.found.substring(colon + 1), out port)) {
				this.error_occurred("Bad address");
				return;
			}
			var host = this.found.substring(0, colon);
			if (!GLib.Uuid.string_is_valid(this.server_id)) {
				this.error_occurred("No server id");
				return;
			}
			var pin = this.pin_entry.text.strip();
			if (!this.valid_pin(pin)) {
				this.error_occurred("Enter the six digits");
				return;
			}
			this.registering = true;
			this.listen_label.label = "Registering…";
			var who = GLib.Environment.get_host_name();
#if ANDROID
			who = this.browse.label;
#endif
			if (this.use_pipe) {
				this.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				this.send_pin(pin);
			}
			if (this.use_pipe) {
				if (this.pipe_code != 0) {
					var label = "The management server rejected the request.";
					if (this.pipe_code == 1) {
						label = "This machine is already registered.";
					}
					switch (this.pipe_code) {
						case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
							label = "Not registered with the management server.";
							break;

						case (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR:
							label = "Could not reach the management server.";
							break;

						default:
							break;
					}
					this.error_occurred(label);
					return;
				}
				this.registration_succeeded();
				return;
			}
			var registration = new Register() {
				data_dir = this.data_dir
			};
			var force_register = false;
			while (true) {
				var code = registration.try_connection(
					host, (uint16) port, pin, who);
				if (code == (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED
					&& !force_register) {
					force_register = true;
					continue;
				}
				if (code != 0) {
					var label = "The management server rejected the request.";
					switch (code) {
						case (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED:
							label = "Not registered with the management server.";
							break;

						case (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR:
							label = "Could not reach the management server.";
							break;

						default:
							break;
					}
					this.error_occurred(label);
					return;
				}
				this.registered_url = "tcp://" + host + ":" + port.to_string();
				this.registered_addresses = registration.addresses;
				this.registration_succeeded();
				return;
			}
		}

		private void registration_succeeded()
		{
			this.certificate_received();
			if (!this.registering) {
				return;
			}
			this.listen_label.label =
				"Registration succeeded. This window will close in 10 seconds.";
			this.close_id = GLib.Timeout.add_seconds(10, () => {
				this.close_id = 0;
				this.close();
				return false;
			});
		}

		private bool valid_pin(string pin)
		{
			if (pin.length != 6) {
				return false;
			}
			for (var i = 0; i < pin.length; i++) {
				if (pin[i] < '0' || pin[i] > '9') {
					return false;
				}
			}
			return true;
		}
	}
}
