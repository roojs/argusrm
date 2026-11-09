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
	 * Startup window for saved server connections.
	 *
	 * The page starts as ''Checking connections''. One server that
	 * answers opens {@link Window}. Several answers ask which
	 * server to use. None offers local deregister, retry, and
	 * registration. A server that does not answer within five
	 * seconds can be removed locally while the check continues.
	 * An empty list offers registration only. The header X closes the
	 * window. With no saved server the page is titled
	 * ''Argus Remote Manager'' and offers a local login or a
	 * remote connection. ''Log in to local machine'' runs the
	 * Polkit certificate command and stores it in the user
	 * keyring. ''Connect a remote machine'' opens
	 * {@link Argus.Shared.RegisterWindow}. Closing that returns
	 * here. A saved server is used only when that certificate
	 * is present. Success shows ''Server registered'', then
	 * probes the saved addresses and opens the main window.
		 * {@link Tab.Settings} opens this again. Pass ''add'' to
		 * register another server. Pass ''choose'' after disconnect
		 * so one live server stays a choice. Pass a saved name to
		 * open that server and replace the window on screen.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var bootstrap = new Argus.Controller.Dialog.Bootstrap(app);
	 * bootstrap.present(null);
	 * }}}
	 */
	public class Bootstrap : Adw.Dialog
	{
		public Application app;
		public bool opened = false;
		private Gtk.Label heading;
		private Gtk.Label body;
		private Gtk.Box actions;
		private Gee.ArrayList<Connection> connections {
			get; set; default = new Gee.ArrayList<Connection>();
		}
		private Gee.ArrayList<Connection> reached {
			get; set; default = new Gee.ArrayList<Connection>();
		}
		private Gee.HashMap<string, Argus.Shared.Registration.Data> credentials {
			get; set; default = new Gee.HashMap<string, Argus.Shared.Registration.Data>();
		}
		private Gee.HashMap<string, string> answered {
			get; set; default = new Gee.HashMap<string, string>();
		}
		private int next = 0;
		private int address_index = 0;
		private int generation = 0;
		private uint probe_offer = 0;
		private bool running = true;
		/**
		 * Saved server to open. Empty checks every saved server.
		 *
		 * ''add'' is not stored here. That request sets {@link adding}.
		 */
		public string prefer = "";
		/**
		 * True when Settings asked to register another server.
		 *
		 * The saved rows stay loaded so registration can append one.
		 * The probe does not run until that registration finishes.
		 */
		public bool adding = false;
		/**
		 * True after disconnect, before a server is chosen.
		 *
		 * One answering server stays on the choice page. The
		 * window does not open until that choice is clicked.
		 */
		public bool choose = false;

		/**
		 * Create the check window and start {@link check}.
		 *
		 * @param app the controller process
		 * @param prefer saved server name, ''add'', ''choose'', or empty
		 */
		public Bootstrap(Application app, string prefer = "")
		{
			this.app = app;
			this.prefer = prefer;
			if (prefer == "add") {
				this.adding = true;
				this.prefer = "";
			}
			if (prefer == "choose") {
				this.choose = true;
				this.prefer = "";
			}
			this.title = "Argus Remote Manager";
			this.set_content_height(280);
			this.set_content_width(480);

			var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false
			};
			var close_button = new Gtk.Button.from_icon_name("window-close-symbolic") {
				tooltip_text = "Close",
				css_classes = {"flat"}
			};
			close_button.clicked.connect(() => {
				this.close();
			});
			header.pack_end(close_button);
			content.append(header);

			var body_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				valign = Gtk.Align.CENTER,
				vexpand = true
			};
			this.heading = new Gtk.Label("Checking connections") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				css_classes = {"title-2"}
			};
			this.body = new Gtk.Label("") {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				visible = false,
				css_classes = {"dim-label"}
			};
			this.actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.CENTER,
				margin_top = 12,
				visible = false
			};
			body_box.append(this.heading);
			body_box.append(this.body);
			body_box.append(this.actions);
			content.append(body_box);
			this.set_child(content);
			this.closed.connect(() => {
				this.running = false;
				if (this.opened || this.app.running_window) {
					return;
				}
				this.app.quit();
			});
			this.check();
		}

		/**
		 * Load ''connections.json'' and try each saved server.
		 *
		 * A missing or empty file offers ''Log in to register''.
		 * An unreadable file offers retry and registration.
		 */
		private void check()
		{
			this.generation++;
			var ticket = this.generation;
			this.connections.clear();
			this.reached.clear();
			this.credentials.clear();
			this.answered.clear();
			this.next = 0;
			this.address_index = 0;
			if (!this.adding) {
				this.page("Checking connections", "", {}, {});
			}
			var path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "connections.json");
			if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
				return;
			}
			var text = "";
			try {
				GLib.FileUtils.get_contents(path, out text);
			} catch (GLib.Error e) {
				this.page("Could not connect", "The saved connections could not be read.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var parser = new Json.Parser();
			try {
				parser.load_from_data(text);
			} catch (GLib.Error e) {
				this.page("Could not connect", "The saved connections could not be read.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				this.page("Could not connect", "The saved connections could not be read.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var list = root.get_array();
			var count = list.get_length();
			for (var i = 0; i < (int) count; i++) {
				var element = list.get_element(i);
				if (element.get_node_type() != Json.NodeType.OBJECT) {
					continue;
				}
				var obj = Json.gobject_deserialize(typeof(Connection), element);
				if (obj == null) {
					continue;
				}
				this.connections.add((Connection) obj);
			}
			if (this.connections.size < 1 || this.adding) {
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
				return;
			}
#if LINUX
			var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(GLib.str_hash, GLib.str_equal);
			types.insert("service", Secret.SchemaAttributeType.STRING);
			types.insert("server", Secret.SchemaAttributeType.STRING);
			types.insert("name", Secret.SchemaAttributeType.STRING);
			var schema = new Secret.Schema.newv("org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
			foreach (var connection in this.connections) {
				var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
				attrs.insert("service", "argusrm");
				attrs.insert("name", connection.name);
				var secret = "";
				try {
					var found = Secret.password_lookupv_sync(schema, attrs, null);
					if (found != null) {
						secret = found;
					}
				} catch (GLib.Error e) {
					this.page("Could not connect", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				if (secret == "") {
					continue;
				}
				try {
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.Registration.Data), secret)
						as Argus.Shared.Registration.Data;
					if (parsed == null || parsed.private_key == "" || parsed.client_certificate == "") {
						continue;
					}
					this.credentials.set(connection.name, parsed);
				} catch (GLib.Error e) {
					continue;
				}
			}
#endif
			if (this.credentials.size < 1) {
				this.page("Could not connect", "The saved server has no certificate.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			this.arm_local_offer(ticket);
			this.probe(ticket);
		}

		/**
		 * Try the next saved address, then show the result.
		 *
		 * @param ticket {@link check} generation that started this attempt
		 */
		private void probe(int ticket)
		{
			if (ticket != this.generation || !this.running) {
				return;
			}
			while (this.next < this.connections.size) {
				var connection = this.connections.get(this.next);
				if (this.prefer != "" && connection.name != this.prefer) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				if (!this.credentials.has_key(connection.name) ||
					connection.port < 1 || connection.port > 65535 ||
					this.address_index >= connection.addresses.length) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				var client = new GLib.SocketClient();
				client.set_timeout(3);
				var host = connection.addresses[this.address_index];
				this.address_index++;
				client.connect_to_host_async.begin(host, (uint16) connection.port, null, (obj, res) => {
					if (ticket != this.generation || !this.running) {
						return;
					}
					GLib.SocketConnection conn;
					try {
						conn = client.connect_to_host_async.end(res);
					} catch (GLib.Error e) {
						this.probe(ticket);
						return;
					}
					try {
						conn.close();
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
					this.reached.add(connection);
					this.answered.set(connection.name, host);
					if (this.prefer != "" && connection.name == this.prefer) {
						this.use(connection);
						return;
					}
					this.next++;
					this.address_index = 0;
					this.probe(ticket);
				});
				return;
			}
			if (this.reached.size == 1 && !this.choose) {
				this.use(this.reached.get(0));
				return;
			}
			if (this.reached.size > 0) {
				string[] labels = {};
				string[] responses = {};
				foreach (var connection in this.reached) {
					labels += connection.name;
					responses += connection.name;
				}
				if (this.choose) {
					labels += "Add a connection";
					responses += "remote";
				}
				this.page("Choose a server", "", labels, responses);
				return;
			}
			this.page("Could not connect", "The saved server did not answer.",
				{ "Deregister locally", "Retry", "Log in to register" },
				{ "local", "retry", "register" });
		}

		/**
		 * Show local deregister if this check is still waiting.
		 *
		 * The probe keeps going. Choosing the button stops it.
		 *
		 * @param ticket {@link check} generation that started this attempt
		 */
		private void arm_local_offer(int ticket)
		{
			this.probe_offer = GLib.Timeout.add_seconds(5, () => {
				this.probe_offer = 0;
				if (ticket != this.generation || !this.running || this.opened) {
					return false;
				}
				this.page("Checking connections", "The server has not answered.",
					{ "Deregister locally" }, { "local" });
				return false;
			});
		}

		/**
		 * Replace the heading, body, and action buttons.
		 *
		 * @param heading large centred title
		 * @param body dim text under the heading, or empty
		 * @param labels button captions, in order
		 * @param responses ids matching {@link labels}
		 */
		private void page(string heading, string body, string[] labels, string[] responses)
		{
			if (this.probe_offer != 0) {
				GLib.Source.remove(this.probe_offer);
				this.probe_offer = 0;
			}
			this.heading.label = heading;
			this.body.label = body;
			this.body.visible = body != "";
			var child = this.actions.get_first_child();
			while (child != null) {
				var next = child.get_next_sibling();
				this.actions.remove(child);
				child = next;
			}
			this.actions.visible = labels.length > 0;
			this.actions.orientation = labels.length > 2 ?
				Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL;
			for (var i = 0; i < labels.length; i++) {
				this.add_button(responses[i], labels[i], i == labels.length - 1);
			}
		}

		/**
		 * Add one action button. The last one is suggested.
		 *
		 * @param response ''retry'', ''register'', ''remote'', or a server name
		 * @param label button text
		 * @param suggested true for the primary button
		 */
		private void add_button(string response, string label, bool suggested)
		{
			var button = new Gtk.Button.with_label(label);
			if (suggested) {
				button.add_css_class("suggested-action");
			}
			button.clicked.connect(() => {
				if (response == "retry") {
					this.check();
					return;
				}
				if (response == "register") {
					this.register();
					return;
				}
				if (response == "remote") {
					this.connect_remote();
					return;
				}
				if (response == "local") {
					this.deregister_local();
					return;
				}
				foreach (var connection in this.reached) {
					if (connection.name != response) {
						continue;
					}
					this.use(connection);
					return;
				}
			});
			this.actions.append(button);
		}

		/**
		 * Issue a certificate through Polkit.
		 *
		 * The login button is the prompt. There is no extra page
		 * explaining that administrator access is required.
		 */
		private void register()
		{
#if LINUX
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				this.page("Could not request administrator access", "pkexec was not found.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var executable = "";
			try {
				executable = GLib.FileUtils.read_link("/proc/self/exe");
			} catch (GLib.FileError e) {
				this.page("Could not resolve argus-controller", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var username = GLib.Environment.get_user_name();
			this.page("Registering server", "", {}, {});
			this.issue(pkexec, executable, username);
#else
			this.page("Could not register", "Local registration is Linux only.",
				{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
		}

		/**
		 * Run the privileged certificate command and store the connection.
		 *
		 * Standard output is {@link Argus.Shared.Registration.Data}.
		 * The private key stays on {@link Window}. The name, addresses,
		 * and port are written to ''connections.json''.
		 *
		 * @param pkexec path to pkexec
		 * @param executable this controller
		 * @param username controller login name
		 */
		private void issue(string pkexec, string executable, string username)
		{
			this.generation++;
			string[] argv = {};
			argv += pkexec;
			argv += executable;
			argv += "--give-me-a-certificate";
			argv += username;
			GLib.Subprocess proc;
			try {
				proc = new GLib.Subprocess.newv(argv,
					GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
			} catch (GLib.Error e) {
				this.page("Could not request administrator access", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			proc.communicate_utf8_async.begin(null, null, (obj, res) => {
				if (!this.running) {
					return;
				}
				string? stdout_text = null;
				string? stderr_text = null;
				try {
					proc.communicate_utf8_async.end(res, out stdout_text, out stderr_text);
				} catch (GLib.Error e) {
					this.page("Could not request administrator access", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var output = stdout_text != null ? stdout_text.strip() : "";
				var error_output = stderr_text != null ? stderr_text.strip() : "";
				if (output == "") {
					var message = error_output;
					if (message == "") {
						message = "Administrator access was not granted.";
					}
					this.page("Could not register", message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var data = new Argus.Shared.Registration.Data() {
					error = "The certificate command failed."
				};
				try {
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.Registration.Data), output)
						as Argus.Shared.Registration.Data;
					if (parsed != null) {
						data = parsed;
					}
				} catch (GLib.Error e) {
					data.error = error_output != "" ? error_output : e.message;
				}
				if (data.error != "" || data.name == "" || data.port < 1) {
					var message = data.error;
					if (message == "") {
						message = "The server did not return a connection.";
					}
					this.page("Could not register", message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				this.finish_registration(data);
			});
		}

		/**
		 * Save one registration, then probe its addresses.
		 *
		 * The keyring holds the certificate. ''connections.json''
		 * holds the name, addresses, and port. Two seconds later
		 * the same probe used at startup records the address that
		 * answers and opens the main window.
		 *
		 * @param data certificate and listen addresses
		 */
		private void finish_registration(Argus.Shared.Registration.Data data)
		{
			var saved = new Connection() {
				name = data.name,
				addresses = data.addresses,
				port = data.port
			};
			var replaced = false;
			foreach (var row in this.connections) {
				if (row.name != saved.name) {
					continue;
				}
				row.addresses = saved.addresses;
				row.port = saved.port;
				replaced = true;
			}
			if (!replaced) {
				this.connections.add(saved);
			}
			var parts = new Gee.ArrayList<string>();
			foreach (var row in this.connections) {
				parts.add(Json.gobject_to_data(row, null));
			}
			var json = "[\n" + string.joinv(",\n", parts.to_array()) + "\n]\n";
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(), "argusrm");
			var path = GLib.Path.build_filename(dir, "connections.json");
#if LINUX
			GLib.TlsCertificate ca_cert;
			try {
				ca_cert = new GLib.TlsCertificate.from_pem(data.ca_certificate, data.ca_certificate.length);
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var fingerprint = GLib.Checksum.compute_for_data(GLib.ChecksumType.SHA256, ca_cert.certificate.data);
			var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(GLib.str_hash, GLib.str_equal);
			types.insert("service", Secret.SchemaAttributeType.STRING);
			types.insert("server", Secret.SchemaAttributeType.STRING);
			types.insert("name", Secret.SchemaAttributeType.STRING);
			var schema = new Secret.Schema.newv("org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
			var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
			attrs.insert("service", "argusrm");
			attrs.insert("name", data.name);
			var existing_secret = "";
			try {
				var found = Secret.password_lookupv_sync(schema, attrs, null);
				if (found != null) {
					existing_secret = found;
				}
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			if (existing_secret != "") {
				var existing_fingerprint = "";
				try {
					var existing = Json.gobject_from_data(typeof(Argus.Shared.Registration.Data), existing_secret)
						as Argus.Shared.Registration.Data;
					if (existing != null && existing.ca_certificate != "") {
						var existing_ca = new GLib.TlsCertificate.from_pem(
							existing.ca_certificate, existing.ca_certificate.length);
						existing_fingerprint = GLib.Checksum.compute_for_data(
							GLib.ChecksumType.SHA256, existing_ca.certificate.data);
					}
				} catch (GLib.Error e) {
					this.page("Could not register", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				if (existing_fingerprint != "" && existing_fingerprint != fingerprint) {
					this.page("Could not register", "The saved server certificate does not match.",
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
			}
			attrs.insert("server", fingerprint);
			var secret = new Argus.Shared.Registration.Data() {
				private_key = data.private_key,
				client_certificate = data.client_certificate,
				ca_certificate = data.ca_certificate
			};
			try {
				Secret.password_storev_sync(schema, attrs, Secret.COLLECTION_DEFAULT,
					data.name, Json.gobject_to_data(secret, null), null);
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
#endif
			this.credentials.set(data.name, data);
			if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
				this.page("Could not register", "Could not create the configuration directory",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			try {
				GLib.FileUtils.set_contents(path, json);
				GLib.FileUtils.chmod(path, 0600);
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			this.page("Server registered", saved.name, {}, {});
			GLib.Timeout.add_seconds(2, () => {
				if (!this.running || this.opened) {
					return false;
				}
				this.reached.clear();
				this.answered.clear();
				this.next = 0;
				this.address_index = 0;
				this.generation++;
				this.probe(this.generation);
				return false;
			});
		}

		/**
		 * Remove every saved login without calling the server.
		 *
		 * Each saved name drops its keyring secret and row.
		 * The empty-list page follows.
		 */
		private void deregister_local()
		{
			this.generation++;
			foreach (var connection in this.connections) {
				var data = new Argus.Shared.Registration.Data() {
					name = connection.name
				};
				try {
					data.clear_saved_login();
				} catch (GLib.Error e) {
					this.page("Could not deregister", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
			}
			this.connections.clear();
			this.reached.clear();
			this.credentials.clear();
			this.page("Argus Remote Manager", "",
				{ "Log in to local machine", "Connect a remote machine" },
				{ "register", "remote" });
		}

		/**
		 * Browse for a server and register this controller there.
		 *
		 * Closing the dialog without a certificate returns to the
		 * local-or-remote page.
		 */
		private void connect_remote()
		{
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argusrm"),
				is_controller = true,
				username = GLib.Environment.get_user_name(),
				hostname = GLib.Environment.get_host_name()
			};
			var done = false;
			window.certificate_received.connect(() => {
				done = true;
				if (window.issued == null) {
					this.page("Could not register",
						"The server did not return a connection.",
						{ "Log in to local machine", "Connect a remote machine" },
						{ "register", "remote" });
					return;
				}
				this.finish_registration(window.issued);
			});
			window.dialog_closed.connect(() => {
				if (done || this.opened || !this.running) {
					return;
				}
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
			});
			window.show_add();
			window.present(this);
		}

		/**
		 * Open the main window for one answering server.
		 *
		 * @param connection the server to use
		 */
		private void use(Connection connection)
		{
			if (this.opened) {
				return;
			}
			this.generation++;
			this.opened = true;
			var issued = new Argus.Shared.Registration.Data();
			if (this.credentials.has_key(connection.name)) {
				issued = this.credentials.get(connection.name);
			}
			issued.name = connection.name;
			var host = this.answered.get(connection.name);
			if (host == null || host == "") {
				this.opened = false;
				this.page("Could not connect", "The saved server did not answer.",
					{ "Deregister locally", "Retry", "Log in to register" },
					{ "local", "retry", "register" });
				return;
			}
			GLib.TlsCertificate certificate;
			GLib.TlsDatabase trust;
			try {
				var pem = issued.client_certificate + "\n" + issued.private_key;
				certificate = new GLib.TlsCertificate.from_pem(pem, pem.length);
				var dir = GLib.Environment.get_user_runtime_dir();
				if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
					throw new GLib.FileError.FAILED(
						"Could not create the runtime directory");
				}
				var ca_path = GLib.Path.build_filename(dir, "argusrm-ca.pem");
				GLib.FileUtils.set_contents(ca_path, issued.ca_certificate);
				GLib.FileUtils.chmod(ca_path, 0600);
				trust = GLib.TlsFileDatabase.@new(ca_path);
			} catch (GLib.Error e) {
				this.opened = false;
				this.page("Could not connect", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var rpc = new OLLMrpc.Client("", "",
				"tcp://" + host + ":" + connection.port.to_string()) {
				live_handles = true
			};
			rpc.debug = false;
			rpc.configure_tls.connect((tls) => {
				tls.certificate = certificate;
				tls.database = trust;
			});
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				if (!this.running) {
					return;
				}
				var opened = rpc.connect.end(res);
				if (!opened) {
					this.opened = false;
					this.page("Could not connect", rpc.connect_error,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var app = this.app;
				var previous = app.window;
				var replace = app.running_window;
				if (replace) {
					app.rpc.disconnect();
					previous.leaving = true;
				}
				var window = new Window(app, connection, issued);
				app.rpc = rpc;
				app.running_window = true;
				app.window = window;
				window.present();
				this.close();
				if (replace) {
					previous.close();
				}
			});
		}
	}
}
