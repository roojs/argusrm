/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Agent.Linux
{
	[DBus (use_string_marshalling = true)]
	internal enum ServiceStatus
	{
		STOPPED,
		RUNNING,
		CONNECTED
	}

	[DBus (name = "org.roojs.ArgusAgent.ServiceManager")]
	internal interface ServiceManagerInterface : GLib.Object
	{
		public abstract ServiceStatus status() throws GLib.DBusError, GLib.IOError;
		public abstract bool client_newer() throws GLib.DBusError, GLib.IOError;
	}

	private enum RegistrationOpen
	{
		NONE,
		CONFIGURE,
		LOCAL,
		RECONFIGURE
	}

	internal class Application : Argus.Agent.Application, ServiceManagerInterface
	{
		private uint bus_owner = 0;
		private static bool opt_request;

		private bool is_desktop = false;

		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			GLib.Environment.set_application_name("Argus Remote Management Agent " + Argus.VERSION);
			var display = GLib.Environment.get_variable("DISPLAY");
			var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			this.is_desktop = (display != null && display != "") || (wayland != null && wayland != "");
			var args = command_line.get_arguments();
			var service_mode = false;
			var help = false;
			foreach (var arg in args) {
				if (arg == "--help" || arg == "-h") {
					help = true;
				}
				if (arg == "--service") {
					service_mode = true;
				}
			}
			opt_debug = false;
			opt_debug_critical = false;
			opt_host = "";
			opt_port = 0;
			opt_server = "";
			opt_pin = "";
			opt_request = false;
			opt_service = false;
			var opt_context = new GLib.OptionContext(this.application_id);
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);
			GLib.OptionEntry[] request_option = {
				{ "request", 0, 0, GLib.OptionArg.NONE, ref opt_request, "Register with server approval", null },
				{ null }
			};
			opt_context.add_main_entries(request_option, null);
			if (help) {
				command_line.print("%s", opt_context.get_help(true, null));
				return 0;
			}
			unowned string[] leftover = args;
			try {
				opt_context.parse(ref leftover);
			} catch (GLib.OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n",
					args[0]);
				return 1;
			}
			debug_on = opt_debug;
			debug_critical_enabled = opt_debug_critical;
			OLLMrpc.rpc_register();
			Argus.Shared.SQT.Server.rpc_register();
			if (leftover.length > 1) {
				command_line.printerr("argusrm-agent-gtk does not accept registration arguments.\n");
				return 1;
			}
			if (service_mode) {
				if (Posix.geteuid() != 0) {
					command_line.printerr("Service mode requires root.\n");
					return 1;
				}
				this.bus_owner = GLib.Bus.own_name(
					GLib.BusType.SYSTEM,
					"org.roojs.ArgusAgent",
					GLib.BusNameOwnerFlags.NONE,
					(connection, name) => {
						try {
							connection.register_object<ServiceManagerInterface>("/org/roojs/ArgusAgent", this);
						} catch (GLib.Error e) {
							GLib.critical("Could not publish agent status: %s", e.message);
							this.quit();
						}
					},
					(connection, name) => {
						GLib.debug("agent status bus owned");
					},
					(connection, name) => {
						GLib.critical("Agent status bus name was lost");
						this.quit();
					}
				);
				return base.command_line(command_line);
			}
			if (Posix.geteuid() == 0) {
				if (this.is_desktop && opt_server == "" && opt_host == "" && opt_pin == "" && opt_port <= 0) {
					return this.registration();
				}
				return this.cli(command_line);
			}
			if (!this.is_desktop) {
				command_line.printerr("Run argusrm-agent-gtk as root.\n");
				return 1;
			}
			if (opt_server != "") {
				Gtk.init();
				var rejected = new Argus.Shared.Notice("argusrm-agent-gtk does not accept --server", "");
				rejected.title = "Argus Remote Management Agent " + Argus.VERSION;
				rejected.add_response("ok", "OK");
				rejected.closed.connect(() => {
					this.quit();
				});
				rejected.present(null);
				this.hold();
				return 0;
			}
			Gtk.init();
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				var missing = new Argus.Shared.Notice("Could not request administrator access", "pkexec was not found.");
				missing.title = "Argus Remote Management Agent " + Argus.VERSION;
				missing.add_response("ok", "OK");
				missing.closed.connect(() => {
					this.quit();
				});
				missing.present(null);
				this.hold();
				return 0;
			}
			var executable = "";
			try {
				executable = GLib.FileUtils.read_link("/proc/self/exe");
			} catch (GLib.FileError e) {
				var missing = new Argus.Shared.Notice("Could not resolve argusrm-agent-gtk", e.message);
				missing.title = "Argus Remote Management Agent " + Argus.VERSION;
				missing.add_response("ok", "OK");
				missing.closed.connect(() => {
					this.quit();
				});
				missing.present(null);
				this.hold();
				return 0;
			}
			var launched = false;
			var notice = new Argus.Shared.Notice("This application needs to run as admin", "You will be prompted to escalate privileges.");
			notice.title = "Argus Remote Management Agent " + Argus.VERSION;
			notice.add_response("ok", "OK");
			notice.responded.connect((response) => {
				launched = this.on_start_admin(response, pkexec, executable);
			});
			notice.closed.connect(() => {
				if (!launched) {
					this.quit();
				}
			});
			notice.present(null);
			this.hold();
			return 0;
		}

		/**
		 * Start the elevated agent after the admin notice.
		 *
		 * Runs pkexec with the session display variables so the
		 * root process can show the next window.
		 *
		 * @param response button id from the notice
		 * @param pkexec path to pkexec
		 * @param executable this agent
		 * @return true when elevation was started
		 */
		private bool on_start_admin(string response, string pkexec, string executable)
		{
			if (response != "ok") {
				return false;
			}
			var session_display = GLib.Environment.get_variable("DISPLAY");
			var session_wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			var session_runtime = GLib.Environment.get_variable("XDG_RUNTIME_DIR");
			var session_xauth = GLib.Environment.get_variable("XAUTHORITY");
			var launcher = new GLib.SubprocessLauncher(GLib.SubprocessFlags.NONE);
			if (session_display != null && session_display != "") {
				launcher.setenv("DISPLAY", session_display, true);
			}
			if (session_wayland != null && session_wayland != "") {
				launcher.setenv("WAYLAND_DISPLAY", session_wayland, true);
			}
			if (session_runtime != null && session_runtime != "") {
				launcher.setenv("XDG_RUNTIME_DIR", session_runtime, true);
			}
			if (session_xauth != null && session_xauth != "") {
				launcher.setenv("XAUTHORITY", session_xauth, true);
			}
			if (debug_on) {
				launcher.setenv("ARGUS_LOG_DIR", "/var/log/argusrm", true);
			}
			var argv = new string[] { pkexec, executable };
			if (debug_on) {
				argv += "--debug";
			}
			if (debug_critical_enabled) {
				argv += "--debug-critical";
			}
			GLib.Subprocess proc;
			try {
				proc = launcher.spawnv(argv);
			} catch (GLib.Error e) {
				var failed = new Argus.Shared.Notice("Could not request administrator access", e.message);
				failed.title = "Argus Remote Management Agent " + Argus.VERSION;
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				return true;
			}
			proc.wait_async.begin(null, (obj, res) => {
				try {
					proc.wait_async.end(res);
				} catch (GLib.Error e) {
					var failed = new Argus.Shared.Notice("Could not request administrator access", e.message);
					failed.title = "Argus Remote Management Agent " + Argus.VERSION;
					failed.add_response("ok", "OK");
					failed.closed.connect(() => {
						this.quit();
					});
					failed.present(null);
					return;
				}
				if (proc.get_successful()) {
					this.quit();
					return;
				}
				var denied = new Argus.Shared.Notice("Could not request administrator access", "Administrator access was not granted.");
				denied.title = "Argus Remote Management Agent " + Argus.VERSION;
				denied.add_response("ok", "OK");
				denied.closed.connect(() => {
					this.quit();
				});
				denied.present(null);
			});
			return true;
		}

		public ServiceStatus status() throws GLib.DBusError, GLib.IOError
		{
			if (this.connection == null || Argus.Agent.Application.connection_down) {
				return ServiceStatus.RUNNING;
			}
			return ServiceStatus.CONNECTED;
		}

		public bool client_newer() throws GLib.DBusError, GLib.IOError
		{
			return false;
		}

		/**
		 * Register this machine from the desktop.
		 *
		 * The service is set up first. An existing certificate
		 * shows the running notice. Not connected offers
		 * Configure, which opens the registration window.
		 * Otherwise the registration window opens.
		 * Command-line registration is {@link cli}.
		 *
		 * @return zero when a window is open
		 */
		private int registration()
		{
			this.server.stand_down();
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				Gtk.init();
				var failed = new Argus.Shared.Notice("Could not set up the Argus agent service", e.message);
				failed.title = "Argus Remote Management Agent " + Argus.VERSION;
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			Gtk.init();
			if (!this.ensure_client_db()) {
				var failed = new Argus.Shared.Notice(
					"Could not open the agent database",
					"Run this application as administrator.");
				failed.title = "Argus Remote Management Agent " + Argus.VERSION;
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			var saved_server = false;
			var rows = new Gee.ArrayList<Argus.Agent.SQT.Server>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			Argus.Agent.SQT.Server.query(this.client_db).selectWhere(
				"WHERE deleted_dt = 0", int_binds, text_binds, rows);
			saved_server = rows.size > 0;
			var reg = new Argus.Shared.Register() {
				data_dir = this.data_dir,
				client_db = this.client_db
			};
			reg.probe_local();
			var status = ServiceStatus.STOPPED;
			var client_newer = false;
			var failure_detail = "";
			try {
				status = service.status();
				client_newer = service.client_newer();
			} catch (GLib.Error e) {
				failure_detail = e.message;
			}
			if (saved_server && status == ServiceStatus.CONNECTED) {
				var connected = new Argus.Shared.Notice(
					"Argus agent is running",
					"Connected to the management server.");
				connected.title = "Argus Remote Management Agent " + Argus.VERSION;
				connected.closed.connect(() => {
					this.quit();
				});
				connected.present(null);
				this.hold();
				return 0;
			}
			var heading = "Argus agent is running";
			var detail = failure_detail != "" ? failure_detail :
				"Not connected to the management server.";
			if (!saved_server) {
				heading = "Argus agent is not configured";
				detail = "No management server is configured.";
			}
			if (saved_server && status == ServiceStatus.STOPPED) {
				heading = "Argus agent is not running";
				detail = "The Argus agent service is not running.";
			}
			if (saved_server && status == ServiceStatus.RUNNING && !client_newer) {
				detail +=
					"\n\nThe server still lists this machine. Delete it from the " +
					"agent list in Remote Manager, or clear the registration " +
					"on this server.";
			}
			var notice = new Argus.Shared.Notice(heading, detail);
			notice.title = "Argus Remote Management Agent " + Argus.VERSION;
			var open = RegistrationOpen.NONE;
			if (!saved_server) {
				if (reg.local_registration) {
					notice.add_response("local", "Connect locally");
				}
				notice.add_response("configure", "Configure");
			}
			if (saved_server && status == ServiceStatus.STOPPED) {
				notice.add_response("restart", "Restart");
			}
			if (saved_server && status == ServiceStatus.RUNNING && client_newer) {
				notice.add_response("restart", "Restart");
			}
			if (saved_server && status == ServiceStatus.RUNNING && !client_newer) {
				notice.add_response("retry", "Retry");
				notice.add_response("reconfigure", "Reconfigure");
				if (reg.local_registration) {
					notice.add_response("local", "Connect locally");
				}
			}
			var restart_work = false;
			notice.responded.connect((response) => {
				switch (response) {
					case "local":
						open = RegistrationOpen.LOCAL;
						notice.close();
						return;

					case "configure":
						open = RegistrationOpen.CONFIGURE;
						notice.close();
						return;

					case "reconfigure":
						open = RegistrationOpen.RECONFIGURE;
						notice.close();
						return;

					case "restart":
					case "retry":
						restart_work = true;
						try {
							service.restart();
						} catch (GLib.Error e) {
							restart_work = false;
							var error_notice = new Argus.Shared.Notice(
								"Could not restart the Argus agent service",
								e.message);
							error_notice.title =
								"Argus Remote Management Agent " + Argus.VERSION;
							error_notice.add_response("ok", "OK");
							error_notice.closed.connect(() => {
								this.quit();
							});
							error_notice.present(null);
						}
						return;

					default:
						return;
				}
			});
			notice.closed.connect(() => {
				if (open != RegistrationOpen.NONE) {
					this.present_registration(service, reg, open);
					return;
				}
				if (!restart_work) {
					this.quit();
				}
			});
			notice.present(null);
			this.hold();
			return 0;
		}

		/**
		 * Open registration for this machine.
		 *
		 * A certificate from the window restarts the service.
		 *
		 * @param service the agent service
		 */
		private void present_registration(
			ServiceManager service,
			Argus.Shared.Register reg,
			RegistrationOpen open = RegistrationOpen.CONFIGURE)
		{
			if (!this.ensure_client_db()) {
				var failed = new Argus.Shared.Notice(
					"Could not open the agent database",
					"Run this application as administrator.");
				failed.title = "Argus Remote Management Agent " + Argus.VERSION;
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				return;
			}
			if (open == RegistrationOpen.LOCAL) {
				new LocalRegistration(this).start(service, reg);
				return;
			}
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = this.data_dir,
				client_db = this.client_db,
				reg = reg
			};
			window.title = "Argus Remote Management Agent " + Argus.VERSION;
			window.show_add();
			window.certificate_received.connect(() => {
				var saved = window.registration;
				if (saved == null || saved.server_row == null) {
					window.error_occurred("registration failed: could not save");
					return;
				}
				var row = new Argus.Agent.SQT.Server() {
					data_dir = saved.data_dir != "" ? saved.data_dir : this.data_dir,
				};
				if (!saved.save(row)) {
					window.error_occurred("registration failed: could not save");
					return;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					window.error_occurred(
						"Registered, but could not restart the Argus agent service: " +
						e.message);
					return;
				}
				GLib.Idle.add(() => {
					window.listen_label.label =
						"Registration succeeded. The Argus agent is running and connected. " +
						"This window will close in 10 seconds.";
					return false;
				});
			});
			window.present(null);
			window.closed.connect(() => {
				this.quit();
			});
		}

		/**
		 * Register this machine from the command line.
		 *
		 * ''--server'' is the management IP. ''--pin'' uses that
		 * number instead of asking. Both together register in one
		 * step. ''--request'' calls
		 * {@link Argus.Shared.Register.try_batch}. No address
		 * browses, then asks for the PIN.
		 * An existing certificate is checked with
		 * ''RPC-Daemon.hello''. A certificate the server rejects
		 * is removed and registration continues. A server that
		 * cannot be reached leaves the certificate.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when registration finished, otherwise the
		 *   setup or registration error
		 */
		private int cli(GLib.ApplicationCommandLine command_line)
		{
			if (opt_server != "" && opt_host != "") {
				command_line.printerr("registration needs one address\n");
				return 1;
			}
			if (opt_port < 0 || opt_port > 65535) {
				command_line.printerr("registration needs an IP address\n");
				return 1;
			}
			if (opt_port > 0 && opt_server == "" && opt_host == "") {
				command_line.printerr("registration needs an IP address\n");
				return 1;
			}
			var host = "";
			var port = Argus.REGISTER_PORT;
			if (opt_port > 0) {
				port = opt_port;
			}
			if (opt_server != "") {
				var inet = new GLib.InetAddress.from_string(opt_server.strip());
				if (inet == null || inet.is_any || inet.is_multicast) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
				host = inet.to_string();
			}
			if (opt_host != "") {
				var named = new GLib.InetAddress.from_string(opt_host);
				if (named == null || named.is_any || named.is_multicast) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
				host = named.to_string();
			}
			var given_pin = opt_pin.strip();
			if (given_pin != "") {
				if (!GLib.Regex.match_simple("^[0-9]{6}$", given_pin)) {
					command_line.printerr("Enter the six digits.\n");
					return 1;
				}
			}
			if (opt_request && given_pin != "") {
				command_line.printerr("--request does not take a pin\n");
				return 1;
			}
			if (opt_request && host == "") {
				command_line.printerr("--request needs an IP address\n");
				return 1;
			}
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				command_line.printerr("Could not set up the Argus agent service: %s\n", e.message);
				return 1;
			}
			if (!this.ensure_client_db()) {
				command_line.printerr("registration needs the agent data directory\n");
				return 1;
			}
			var existing = new Gee.ArrayList<Argus.Agent.SQT.Server>();
			Argus.Agent.SQT.Server.query(this.client_db).selectWhere(
				"WHERE deleted_dt = 0",
				new Gee.HashMap<string, int>(),
				new Gee.HashMap<string, string>(),
				existing);
			Argus.Agent.SQT.Server? saved_server = null;
			if (existing.size > 0) {
				var row = existing.get(0);
				row.data_dir = this.data_dir;
				try {
					row.load_certificates();
					if (row.has_certificate) {
						saved_server = row;
					}
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			if (saved_server != null) {
				OLLMrpc.rpc_register();
				var opened = this.open_connection();
				if (opened == null) {
					command_line.printerr("Could not reach the management server.\n");
					return 1;
				}
				OLLMrpc.Response response;
				try {
					response = opened.call(new OLLMrpc.Request() {
						method = "RPC-Daemon.hello",
						args = OLLMrpc.args("iss", 1, "argus-agent", Argus.VERSION)
					});
				} catch (GLib.Error e) {
					command_line.printerr("%s\n", e.message);
					return 1;
				}
				if (response.error == null) {
					var daemon = new OLLMrpc.Daemon();
					daemon.version = response.retval.get_string();
					var order = daemon.compare(Argus.VERSION, 2);
					if (order < 0) {
						command_line.printerr("The server is %s. This client is %s.\n", daemon.version, Argus.VERSION);
						return 1;
					}
					if (order > 0) {
						GLib.warning("This client is %s. The server is %s.", Argus.VERSION, daemon.version);
					}
					command_line.print("Argus agent is already registered.\n");
					return 0;
				}
				if (response.error.code != (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED) {
					command_line.printerr("%s\n", response.error.message);
					return 1;
				}
				try {
					saved_server.remove(this.client_db);
					this.client_db.backup_real();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				GLib.debug("certificate rejected");
			}
			if (host == "") {
				var browse = new Argus.Shared.Browse();
				GLib.debug("browsing");
				browse.start();
				command_line.print("Looking for a management server…\n");
				var found = browse.poll();
				while (found == "") {
					GLib.MainContext.default().iteration(true);
					found = browse.poll();
				}
				browse.stop();
				if (found == "none") {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				var newline = found.index_of("\n");
				if (newline <= 0 || !GLib.Uuid.string_is_valid(found.substring(0, newline))) {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				var hostport = found.substring(newline + 1);
				var colon = hostport.last_index_of(":");
				if (colon <= 0) {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				var announced = 0;
				if (!int.try_parse(hostport.substring(colon + 1), out announced) ||
					announced <= 0 || announced > 65535) {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				host = hostport.substring(0, colon);
				port = announced;
			}
			var registration = new Argus.Shared.Register() {
				data_dir = this.data_dir,
				client_db = this.client_db,
				host_name = GLib.Environment.get_host_name(),
			};
			if (opt_request) {
				var code = registration.try_batch(host, (uint16) port);
				if (code != 0) {
					return 1;
				}
				var row = new Argus.Agent.SQT.Server() {
					data_dir = registration.data_dir != "" ? registration.data_dir : this.data_dir,
				};
				if (!registration.save(row)) {
					command_line.printerr("registration failed: could not save\n");
					return 1;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n", e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
			if (given_pin != "") {
				var code = registration.try_connection(host, (uint16) port, given_pin);
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					return 1;
				}
				var row = new Argus.Agent.SQT.Server() {
					data_dir = registration.data_dir != "" ? registration.data_dir : this.data_dir,
				};
				if (!registration.save(row)) {
					command_line.printerr("registration failed: could not save\n");
					return 1;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n", e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
			while (true) {
				command_line.print("Enter registration PIN: ");
				GLib.stdout.flush();
				var line = GLib.stdin.read_line();
				if (line == null) {
					command_line.printerr("\n");
					return 1;
				}
				var pin = line.strip();
				if (!GLib.Regex.match_simple("^[0-9]{6}$", pin)) {
					command_line.printerr("Enter the six digits.\n");
					continue;
				}
				var code = registration.try_connection(host, (uint16) port, pin);
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					continue;
				}
				var row = new Argus.Agent.SQT.Server() {
					data_dir = registration.data_dir != "" ? registration.data_dir : this.data_dir,
				};
				if (!registration.save(row)) {
					command_line.printerr("registration failed: could not save\n");
					return 1;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n", e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
		}
	}
}
