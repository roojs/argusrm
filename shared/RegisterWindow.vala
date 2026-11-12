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
	 * the host name. While it listens, it names the server command
	 * that turns on broadcast and prints the number. Enter IP/domain
	 * reveals an address. Connect checks that address every twenty
	 * seconds. Okay shows the same six digits.
	 */
	public class RegisterWindow : Adw.Dialog
	{
		/**
		 * Certificate and listen addresses from a successful registration.
		 *
		 * Null until {@link certificate_received}.
		 */
		public Argus.Shared.Registration.Data? issued { get; private set; }

		/**
		 * {{{tcp://host:port}}} that answered hello. Null until then.
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
		private Gtk.Entry address_entry;
		private Gtk.Box address_box;
		private Gtk.Box offer_box;
		private Gtk.Button address_button;
		private string found = "";
		private uint browse_id = 0;
		private uint close_id = 0;
		private uint poll_id = 0;
		private int poll_token = 0;
		private bool by_address = false;
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
		 * True stores this registration as a controller.
		 *
		 * Agents leave this false.
		 */
		public bool is_controller = false;

		/**
		 * Operating-system login name for a controller registration.
		 */
		public string username = "";

		/**
		 * Machine name for a controller registration.
		 */
		public string hostname = "";

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
		 * The Windows tray connects this and writes the number and
		 * ''hostport'' on the local pipe. The reply is stored in
		 * {@link pipe_code}.
		 *
		 * @param pin the six digits
		 * @param hostport host and port this window is using
		 */
		public signal void send_pin(string pin, string hostport);

		public RegisterWindow()
		{
			this.title = "Connect to management server " + Argus.VERSION;
			this.set_content_height(480);
			this.set_content_width(520);

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
			var server_hint = new Gtk.Label(
				"Run this on the server to turn on broadcast and display the number.") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				css_classes = {"dim-label"}
			};
			var server_command = new Gtk.Label("sudo argusrm-controller-cli") {
				selectable = true,
				xalign = 0.5f,
				css_classes = {"monospace"}
			};
			this.address_button = new Gtk.Button.with_label("Enter IP/domain to connect to") {
				halign = Gtk.Align.CENTER,
				margin_top = 12,
			};
			this.offer_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
			this.offer_box.append(server_hint);
			this.offer_box.append(server_command);
			this.offer_box.append(this.address_button);
			body.append(this.offer_box);
			this.address_entry = new Gtk.Entry() {
				xalign = 0.5f,
				hexpand = true,
				height_request = 64,
				css_classes = {"title-1"}
			};
			var connect_button = new Gtk.Button.with_label("Connect") {
				halign = Gtk.Align.CENTER,
				css_classes = {"suggested-action"}
			};
			this.address_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				visible = false
			};
			this.address_box.append(this.address_entry);
			this.address_box.append(connect_button);
			body.append(this.address_box);
			content.append(body);
			this.set_child(content);
			this.address_button.clicked.connect(() => {
				this.address_button.visible = false;
				this.address_box.visible = true;
				this.address_entry.grab_focus();
			});
			connect_button.clicked.connect(() => {
				var text = this.address_entry.text.strip();
				if (text == "") {
					this.listen_label.label = "Enter an IP address or domain";
					return;
				}
				var host = text;
				var port = Argus.REGISTER_PORT;
				var colon = text.last_index_of(":");
				if (colon > 0) {
					var parsed = 0;
					if (!int.try_parse(text.substring(colon + 1), out parsed) ||
						parsed < 1 || parsed > 65535) {
						this.listen_label.label = "Bad address";
						return;
					}
					host = text.substring(0, colon);
					port = parsed;
				}
				if (host == "") {
					this.listen_label.label = "Enter an IP address or domain";
					return;
				}
				this.poll_token++;
				this.by_address = true;
				this.found = host + ":" + port.to_string();
				this.server_id = "";
				this.pin_box.visible = false;
				this.listen_label.label = "Looking for a management server…";
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				this.browse.stop();
				if (this.poll_id != 0) {
					GLib.Source.remove(this.poll_id);
					this.poll_id = 0;
				}
				this.poll_id = GLib.Timeout.add_seconds(20, this.on_wait);
				this.on_wait();
			});
			this.address_entry.activate.connect(() => {
				connect_button.clicked();
			});

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
				GLib.Timeout.add(300, () => {
					if (this.registering ||
						!this.valid_pin(this.pin_entry.text.strip())) {
						return false;
					}
					this.request.begin();
					return false;
				});
			});
			this.pin_entry.activate.connect(() => {
				this.request.begin();
			});
			this.closed.connect(() => {
				this.can_close = true;
				this.by_address = false;
				this.poll_token++;
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				if (this.close_id != 0) {
					GLib.Source.remove(this.close_id);
					this.close_id = 0;
				}
				if (this.poll_id != 0) {
					GLib.Source.remove(this.poll_id);
					this.poll_id = 0;
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
		 * Check the typed address.
		 *
		 * A connection that opens is Okay and shows the six digits.
		 * A refusal is Not active. The same check runs again in
		 * twenty seconds until Okay, or until the dialog moves on.
		 *
		 * @return true to check again
		 */
		private bool on_wait()
		{
			if (!this.by_address || this.registering) {
				return false;
			}
			var mark = this.found.last_index_of(":");
			if (mark <= 0) {
				this.listen_label.label = "Not active";
				return true;
			}
			var parsed = 0;
			if (!int.try_parse(this.found.substring(mark + 1), out parsed) || parsed < 1) {
				this.listen_label.label = "Not active";
				return true;
			}
			var token = this.poll_token;
			var client = new GLib.SocketClient();
			client.timeout = 5;
			client.connect_to_host_async.begin(this.found.substring(0, mark),
				(uint16) parsed, null, (obj, res) => {
					if (token != this.poll_token) {
						return;
					}
					var opened = false;
					try {
						var conn = client.connect_to_host_async.end(res);
						opened = true;
						try {
							conn.close();
						} catch (GLib.Error close_error) {
							GLib.warning("%s", close_error.message);
						}
					} catch (GLib.Error e) {
						opened = false;
					}
					if (token != this.poll_token) {
						return;
					}
					if (!opened) {
						this.listen_label.label = "Not active";
						this.pin_box.visible = false;
						return;
					}
					if (this.poll_id != 0) {
						GLib.Source.remove(this.poll_id);
						this.poll_id = 0;
					}
					this.poll_token++;
					this.listen_label.label = "Okay";
					this.offer_box.visible = false;
					this.address_box.visible = false;
					this.pin_box.visible = true;
					this.pin_entry.grab_focus();
				});
			return true;
		}

		/**
		 * Prepares the dialog before {@link Gtk.Window.present}.
		 */
		public void show_add()
		{
			this.issued = null;
			this.registered_url = null;
			this.registered_addresses = "";
			this.server_id = "";
			this.found = "";
			this.registering = false;
			this.by_address = false;
			this.poll_token++;
			this.pin_entry.text = "";
			this.pin_box.visible = false;
			this.address_entry.text = "";
			this.address_box.visible = false;
			this.address_button.visible = true;
			this.offer_box.visible = true;
			this.listen_label.label = "Looking for a management server…";
			if (this.poll_id != 0) {
				GLib.Source.remove(this.poll_id);
				this.poll_id = 0;
			}
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
					this.by_address = false;
					this.poll_token++;
					if (this.poll_id != 0) {
						GLib.Source.remove(this.poll_id);
						this.poll_id = 0;
					}
					this.offer_box.visible = false;
					this.address_box.visible = false;
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
			if (!this.by_address && !GLib.Uuid.string_is_valid(this.server_id)) {
				this.error_occurred("No server id");
				return;
			}
			var pin = this.pin_entry.text.strip();
			if (!this.valid_pin(pin)) {
				this.error_occurred("Enter the six digits");
				return;
			}
			this.registering = true;
			this.poll_token++;
			if (this.poll_id != 0) {
				GLib.Source.remove(this.poll_id);
				this.poll_id = 0;
			}
			this.listen_label.label = "Registering…";
			var who = GLib.Environment.get_host_name();
#if ANDROID
			who = this.browse.label;
#endif
			if (this.use_pipe) {
				this.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				this.send_pin(pin, this.found);
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
				data_dir = this.data_dir,
				is_controller = this.is_controller,
				username = this.username,
				hostname = this.hostname
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
					if (code == 1) {
						label = "This machine is already registered.";
					}
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
				var app_port = (int) port;
				var lines = registration.addresses.split("\n");
				if (lines.length > 0) {
					var listed = lines[0].strip();
					var mark = listed.last_index_of(":");
					if (mark > 0) {
						int.try_parse(listed.substring(mark + 1), out app_port);
					}
				}
				this.registered_url = "tcp://" + host + ":" + app_port.to_string();
				this.registered_addresses = registration.addresses;
				if (!this.remember(host, app_port, registration.addresses)) {
					return;
				}
				this.registration_succeeded();
				return;
			}
		}

		/**
		 * Build {@link issued} from the files this window just wrote.
		 *
		 * ''addresses'' is one ''host:port'' per line. The connected
		 * host is included when the reply did not list it.
		 *
		 * @param host address that accepted the registration
		 * @param port app socket port
		 * @param addresses listen addresses from the reply
		 * @return false when the files or the address could not be read
		 */
		private bool remember(string host, int port, string addresses)
		{
			var dir = this.data_dir;
			if (dir == "") {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argus");
			}
			var client = "";
			var key = "";
			var ca = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client.pem"), out client);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client-key.pem"), out key);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), out ca);
			} catch (GLib.Error e) {
				this.error_occurred(e.message);
				return false;
			}
			string[] hosts = {};
			foreach (var line in addresses.split("\n")) {
				var text = line.strip();
				if (text == "") {
					continue;
				}
				var mark = text.last_index_of(":");
				if (mark > 0) {
					hosts += text.substring(0, mark);
					continue;
				}
				hosts += text;
			}
			var listed = false;
			foreach (var one in hosts) {
				if (one == host) {
					listed = true;
				}
			}
			if (host != "" && !listed) {
				string[] with_host = { host };
				foreach (var one in hosts) {
					with_host += one;
				}
				hosts = with_host;
			}
			if (host == "" || port < 1) {
				this.error_occurred("The server did not return a connection.");
				return false;
			}
			this.issued = new Argus.Shared.Registration.Data() {
				name = host,
				port = port,
				addresses = hosts,
				private_key = key,
				client_certificate = client,
				ca_certificate = ca
			};
			return true;
		}

		private void registration_succeeded()
		{
			this.pin_box.visible = false;
			this.offer_box.visible = false;
			this.address_box.visible = false;
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
