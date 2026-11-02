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
	 * The sixth digit runs the check. OLLMchat ''FileConnectionAdd''
	 * waits for the Request button.
	 */
	public class RegisterWindow : Adw.PreferencesDialog
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

		private Gtk.Label listen_label;
		private Gtk.Entry pin_entry;
		private Adw.ActionRow pin_row;
		private Gtk.Button request_button;
		private Adw.PreferencesGroup group;
		private string found = "";
		private uint browse_id = 0;
		private Browse browse = new Browse();

		/**
		 * The tray asks the service to register.
		 *
		 * Linux and Android leave this false and call
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
			this.set_content_height(360);
			this.set_content_width(720);

			var page = new Adw.PreferencesPage();
			this.group = new Adw.PreferencesGroup();
			this.pin_entry = new Gtk.Entry() {
				placeholder_text = "Six digits",
				max_length = 6,
				input_purpose = Gtk.InputPurpose.DIGITS
			};
			this.pin_row = new Adw.ActionRow() {
				title = "PIN",
				visible = false
			};
			this.pin_row.add_suffix(this.pin_entry);
			this.group.add(this.pin_row);
			this.listen_label = new Gtk.Label("Listening") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				margin_top = 18
			};
			this.group.add(this.listen_label);
			page.add(this.group);

			this.request_button = new Gtk.Button() {
				label = "Request",
				css_classes = {"suggested-action"},
				sensitive = false
			};
			var footer = new Adw.PreferencesGroup();
			footer.add(this.request_button);
			page.add(footer);
			this.add(page);

			this.error_occurred.connect((error_message) => {
				this.listen_label.label = error_message;
				this.request_button.sensitive = this.found != "";
				GLib.warning("%s", error_message);
			});
			this.pin_entry.changed.connect(() => {
				if (this.pin_entry.text.strip().length != 6) {
					return;
				}
				this.request.begin();
			});
			this.pin_entry.activate.connect(() => {
				this.request.begin();
			});
			this.request_button.clicked.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.can_close = true;
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				var root = this.get_root() as Gtk.Window;
				if (root != null) {
					this.browse.stop();
				}
				this.pin_entry.text = "";
				this.request_button.sensitive = false;
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
			this.pin_entry.text = "";
			this.pin_row.visible = false;
			this.listen_label.label = "Listening";
			this.request_button.sensitive = false;
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
					this.listen_label.label = this.found;
					this.pin_row.visible = true;
					this.request_button.sensitive = true;
					this.pin_entry.grab_focus();
					return false;
				});
				return false;
			});
		}

		private async void request()
		{
			this.request_button.sensitive = false;
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
			if (pin.length != 6) {
				this.error_occurred("Enter the six digits");
				return;
			}
			if (this.use_pipe) {
				this.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				this.send_pin(pin);
				if (this.pipe_code != 0) {
					var label = "The management server rejected the request.";
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
				this.close();
				return;
			}
			var registration = new Register();
			var force_register = false;
			while (true) {
				var code = registration.try_connection(
					host, (uint16) port, pin, GLib.Environment.get_host_name());
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
				this.close();
				return;
			}
		}
	}
}
