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
		private Gee.ArrayList<Argus.Controller.SQT.Server> servers {
			get; set; default = new Gee.ArrayList<Argus.Controller.SQT.Server>();
		}
		private Gee.ArrayList<Argus.Controller.SQT.Server> reached {
			get; set; default = new Gee.ArrayList<Argus.Controller.SQT.Server>();
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
			this.title = "Argus Remote Manager " + Argus.VERSION;
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
		 * Load saved servers from SQLite and try each address.
		 *
		 * An empty list offers ''Log in to register''.
		 * An unreadable store offers retry and registration.
		 */
		private void check()
		{
			this.generation++;
			var ticket = this.generation;
			this.servers.clear();
			this.reached.clear();
			this.answered.clear();
			this.next = 0;
			this.address_index = 0;
			if (!this.adding) {
				this.page("Checking connections", "", {}, {});
			}
			try {
				var store = new Argus.Controller.Store.Server(this.app);
				this.servers = store.list();
			} catch (GLib.Error e) {
#if ANDROID
				this.page("Could not connect", e.message,
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not connect", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
			var with_pem = new Gee.ArrayList<Argus.Controller.SQT.Server>();
			foreach (var row in this.servers) {
				if (row.has_certificate) {
					with_pem.add(row);
				}
			}
			this.servers = with_pem;
			if (this.servers.size < 1 || this.adding) {
#if ANDROID
				this.page("Argus Remote Manager", "",
					{ "Connect a remote machine" }, { "remote" });
#else
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
#endif
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
			while (this.next < this.servers.size) {
				var row = this.servers.get(this.next);
				if (this.prefer != "" && row.name != this.prefer) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				if (!row.has_certificate) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				var hosts = row.address_list();
				if (this.address_index >= hosts.size) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				var client = new GLib.SocketClient();
				client.set_timeout(3);
				var host = hosts[this.address_index];
				this.address_index++;
				client.connect_to_host_async.begin(host, (uint16) row.port, null, (obj, res) => {
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
					this.reached.add(row);
					this.answered.set(row.name, host);
					if (this.prefer != "" && row.name == this.prefer) {
						this.use(row);
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
				foreach (var row in this.reached) {
					labels += row.name;
					responses += row.name;
				}
				if (this.choose) {
					labels += "Add a connection";
					responses += "remote";
				}
				this.page("Choose a server", "", labels, responses);
				return;
			}
#if ANDROID
			this.page("Could not connect", "The saved server did not answer.",
				{ "Deregister locally", "Retry", "Connect a remote machine" },
				{ "local", "retry", "remote" });
#else
			this.page("Could not connect", "The saved server did not answer.",
				{ "Deregister locally", "Retry", "Log in to register" },
				{ "local", "retry", "register" });
#endif
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
					this.exe_root("--give-me-a-certificate", "controller",
						"Registering server", "");
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
		 * Run one privileged command and read its JSON.
		 *
		 * ''option'' is ''--give-me-a-certificate'' (via
		 * {@link Argus.SERVER_EXECUTABLE}) or
		 * ''--deregister'' on the controller. Standard output is
		 * {@link Argus.Shared.SQT.Server}. A certificate
		 * is stored by {@link finish_registration}. A deregister
		 * with an empty error returns to the local-or-remote page.
		 * ''prior_error'' is shown when the command itself succeeds.
		 * A missing pkexec, or an unreadable ''/proc/self/exe'',
		 * stops with no further action.
		 *
		 * @param option root command option
		 * @param value username passed to that option
		 * @param waiting heading shown while the command runs
		 * @param prior_error earlier failure, or empty
		 */
		private void exe_root(string option, string value, string waiting, string prior_error)
		{
			this.generation++;
#if LINUX
			var failed = "Could not register";
			if (option == "--deregister") {
				failed = "Could not deregister";
			}
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				this.page("Could not request administrator access",
					"pkexec was not found.", {}, {});
				return;
			}
			var executable = "";
			if (option == "--give-me-a-certificate") {
				executable = Argus.SERVER_EXECUTABLE;
			} else {
				try {
					executable = GLib.FileUtils.read_link("/proc/self/exe");
				} catch (GLib.FileError e) {
					executable = "";
				}
				if (executable == ""
					|| !GLib.FileUtils.test(executable, GLib.FileTest.IS_EXECUTABLE)) {
					executable = Argus.CONTROLLER_EXECUTABLE;
				}
			}
			if (!GLib.FileUtils.test(executable, GLib.FileTest.IS_EXECUTABLE)) {
				var missing = option == "--give-me-a-certificate" ?
					"argusrm-server" : "argusrm-controller";
				this.page("Could not resolve " + missing,
					missing + " is missing.", {}, {});
				return;
			}
			this.page(waiting, "", {}, {});
			string[] argv = {};
			argv += pkexec;
			argv += executable;
			if (option == "--give-me-a-certificate") {
				argv += "--give-me-a-certificate";
				argv += value;
			} else {
				argv += option;
				argv += value;
			}
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
					this.page(failed, message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var data = new Argus.Shared.SQT.Server() {
					error = "The command failed."
				};
				try {
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), output)
						as Argus.Shared.SQT.Server;
					if (parsed != null) {
						data = parsed;
					}
				} catch (GLib.Error e) {
					data.error = error_output != "" ? error_output : e.message;
				}
				if (option == "--deregister") {
					if (data.error != "") {
						this.page(failed, data.error,
							{ "Retry", "Log in to register" }, { "retry", "register" });
						return;
					}
					if (prior_error != "") {
						this.page(failed, prior_error,
							{ "Retry", "Log in to register" }, { "retry", "register" });
						return;
					}
					this.page("Argus Remote Manager", "",
						{ "Log in to local machine", "Connect a remote machine" },
						{ "register", "remote" });
					return;
				}
				if (data.error != "" || data.name == "" || data.port < 1
					|| data.addresses == "" || !data.has_certificate) {
					var message = data.error;
					if (message == "") {
						message = "The server did not return a connection.";
					}
					if (message == "This machine is already registered.") {
						this.page(failed, message,
							{ "Deregister locally", "Retry" }, { "local", "retry" });
						return;
					}
					this.page(failed, message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var reg = new Argus.Shared.Register() {
					client_db = this.app.client_db,
					server_row = data
				};
				var row = new Argus.Controller.SQT.Server() {
					name = data.name
				};
				this.finish_registration(reg, row);
			});
#else
			this.page("Could not request administrator access",
				"Local registration is Linux only.", {}, {});
#endif
		}

		/**
		 * Save one registration, then probe its addresses.
		 *
		 * @param reg enroll outcome with {@link Argus.Shared.Register.server_row}
		 * @param row controller row to persist (often name only before {@link Argus.Shared.Register.save})
		 */
		private void finish_registration(
			Argus.Shared.Register reg,
			Argus.Controller.SQT.Server row)
		{
#if LINUX
			var ca_pem = "";
			if (reg.server_row != null && reg.server_row.pem_ca_certificate != "") {
				ca_pem = reg.server_row.pem_ca_certificate;
			} else if (row.pem_ca_certificate != "") {
				ca_pem = row.pem_ca_certificate;
			}
			if (ca_pem != "") {
			try {
				var ca_cert = new GLib.TlsCertificate.from_pem(ca_pem, ca_pem.length);
				var fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256, ca_cert.certificate.data);
				var store = new Argus.Controller.Store.Server(this.app);
				foreach (var existing in store.list()) {
					if (existing.name != row.name || existing.pem_ca_certificate == "") {
						continue;
					}
					var old_ca = new GLib.TlsCertificate.from_pem(
						existing.pem_ca_certificate, existing.pem_ca_certificate.length);
					var old_fp = GLib.Checksum.compute_for_data(
						GLib.ChecksumType.SHA256, old_ca.certificate.data);
					if (old_fp != fingerprint) {
						this.page("Could not register",
							"The saved server certificate does not match.",
							{ "Retry", "Log in to register" }, { "retry", "register" });
						return;
					}
					break;
				}
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			}
#endif
			reg.client_db = this.app.client_db;
			if (!reg.save(row)) {
#if ANDROID
				this.page("Could not register",
					"The registration could not be saved.",
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not register",
					"The registration could not be saved.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
			var replaced = false;
			for (var i = 0; i < this.servers.size; i++) {
				if (this.servers.get(i).name != row.name) {
					continue;
				}
				this.servers.set(i, row);
				replaced = true;
				break;
			}
			if (!replaced) {
				this.servers.add(row);
			}
			this.page("Server registered", row.name, {}, {});
			this.prefer = row.name;
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
		 * Deregister this controller.
		 *
		 * Each saved name drops its keyring secret and row.
		 * {@link exe_root} then runs ''--deregister'' for this username.
		 * A saved-login failure does not skip that command.
		 * The empty-list page follows when the command returns no error.
		 */
		private void deregister_local()
		{
			this.generation++;
			var local_error = "";
			try {
				var store = new Argus.Controller.Store.Server(this.app);
				foreach (var row in store.list()) {
					try {
						row.remove(this.app.client_db);
					} catch (GLib.Error e) {
						if (local_error == "") {
							local_error = e.message;
						}
					}
				}
			} catch (GLib.Error e) {
				if (local_error == "") {
					local_error = e.message;
				}
			}
			this.servers.clear();
			this.reached.clear();
#if ANDROID
			if (local_error != "") {
				this.page("Could not deregister", local_error,
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
				return;
			}
			this.page("Argus Remote Manager", "",
				{ "Connect a remote machine" }, { "remote" });
#else
			this.exe_root("--deregister", GLib.Environment.get_user_name(),
				"Deregistering", local_error);
#endif
		}

		/**
		 * Browse for a server and register this controller there.
		 *
		 * Closing the dialog without a certificate returns to the
		 * local-or-remote page.
		 */
		private void connect_remote()
		{
#if ANDROID
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "certs");
#else
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argusrm");
#endif
#if ANDROID
			var hostname = new Argus.Shared.Browse().label;
			if (hostname == "") {
				hostname = GLib.Environment.get_host_name();
			}
#else
			var hostname = GLib.Environment.get_host_name();
#endif
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = data_dir,
				is_controller = true,
				username = GLib.Environment.get_user_name(),
				hostname = hostname
			};
			var done = false;
			window.certificate_received.connect(() => {
				done = true;
				var reg = window.registration;
				if (reg == null || reg.server_row == null || !reg.server_row.has_certificate) {
#if ANDROID
					this.page("Could not register",
						"The server did not return a connection.",
						{ "Connect a remote machine" }, { "remote" });
#else
					this.page("Could not register",
						"The server did not return a connection.",
						{ "Log in to local machine", "Connect a remote machine" },
						{ "register", "remote" });
#endif
					return;
				}
				reg.client_db = this.app.client_db;
				var row = new Argus.Controller.SQT.Server() {
					name = window.registration_name,
				};
				this.finish_registration(reg, row);
				window.close();
			});
			window.dialog_closed.connect(() => {
				if (done || this.opened || !this.running) {
					return;
				}
#if ANDROID
				this.page("Argus Remote Manager", "",
					{ "Connect a remote machine" }, { "remote" });
#else
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
#endif
			});
			window.present(this);
			window.show_add();
		}

		/**
		 * Open the main window for one answering server.
		 *
		 * @param connection the server to use
		 */
		private void use(Argus.Controller.SQT.Server server)
		{
			if (this.opened) {
				return;
			}
			this.generation++;
			this.opened = true;
			var host = this.answered.get(server.name);
			if (host == null || host == "") {
				this.opened = false;
#if ANDROID
				this.page("Could not connect", "The saved server did not answer.",
					{ "Deregister locally", "Retry", "Connect a remote machine" },
					{ "local", "retry", "remote" });
#else
				this.page("Could not connect", "The saved server did not answer.",
					{ "Deregister locally", "Retry", "Log in to register" },
					{ "local", "retry", "register" });
#endif
				return;
			}
			GLib.TlsCertificate certificate;
			GLib.TlsDatabase trust;
			try {
				certificate = server.tls_certificate();
#if ANDROID
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(), "argusrm");
#else
				var dir = GLib.Environment.get_user_runtime_dir();
#endif
				if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
					throw new GLib.FileError.FAILED(
						"Could not create the runtime directory");
				}
				var ca_path = GLib.Path.build_filename(dir, "argusrm-ca.pem");
				GLib.FileUtils.set_contents(ca_path, server.pem_ca_certificate);
				GLib.FileUtils.chmod(ca_path, 0600);
				trust = GLib.TlsFileDatabase.@new(ca_path);
			} catch (GLib.Error e) {
				this.opened = false;
#if ANDROID
				this.page("Could not connect", e.message,
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not connect", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
			var rpc = new OLLMrpc.Client("", "",
				"tcp://" + host + ":" + server.port.to_string()) {
				live_handles = true,
				call_timeout_seconds = 5,
				force_localhost_tls = true
			};
			rpc.debug = false;
			rpc.configure_tls.connect((tls) => {
				tls.certificate = certificate;
				tls.database = trust;
			});
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "argus-controller", Argus.VERSION)
			}, null, (obj, res) => {
				if (!this.running) {
					return;
				}
				var opened = rpc.connect.end(res);
				if (!opened) {
					this.opened = false;
#if ANDROID
					this.page("Could not connect", rpc.connect_error,
						{ "Deregister locally", "Retry", "Connect a remote machine" },
						{ "local", "retry", "remote" });
#else
					this.page("Could not connect", rpc.connect_error,
						{ "Deregister locally", "Retry", "Log in to register" },
						{ "local", "retry", "register" });
#endif
					return;
				}
				var app = this.app;
				var replace = app.running_window;
				if (replace) {
					app.rpc.disconnect();
				}
				/* The agent page connects notifications while the window is built. */
				app.rpc = rpc;
#if ANDROID
				app.running_window = true;
				app.window.open(server, host);
				this.close();
#else
				var previous = app.window;
				if (replace) {
					previous.leaving = true;
				}
				var window = new Window(app, server, host);
				app.running_window = true;
				app.window = window;
				window.present();
				this.close();
				if (replace) {
					previous.close();
				}
#endif
			});
		}
	}
}
