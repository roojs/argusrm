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
	}

	internal class Application : Argus.Agent.Application, ServiceManagerInterface
	{
		private uint bus_owner = 0;

		private bool is_desktop = false;

		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			var display = GLib.Environment.get_variable("DISPLAY");
			var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			this.is_desktop = (display != null && display != "") || (wayland != null && wayland != "");
			var args = command_line.get_arguments();
			var service_mode = false;
			foreach (var arg in args) {
				if (arg == "--help" || arg == "-h") {
					return base.command_line(command_line);
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
			opt_service = false;
			var opt_context = new GLib.OptionContext(this.application_id);
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);
			unowned string[] leftover = args;
			try {
				opt_context.parse(ref leftover);
			} catch (GLib.OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n",
					args[0]);
				return 1;
			}
			if (leftover.length > 1) {
				command_line.printerr("argus-agent does not accept registration arguments.\n");
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
				command_line.printerr("Run argus-agent as root.\n");
				return 1;
			}
			if (opt_server != "") {
				Gtk.init();
				var rejected = new Argus.Shared.Notice("argus-agent does not accept --server", "");
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
				var missing = new Argus.Shared.Notice("Could not resolve argus-agent", e.message);
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
			var session_bus = GLib.Environment.get_variable("DBUS_SESSION_BUS_ADDRESS");
			var env_bin = GLib.Environment.find_program_in_path("env");
			string[] argv = { pkexec };
			if (env_bin != null) {
				argv += env_bin;
				if (session_display != null && session_display != "") {
					argv += "DISPLAY=" + session_display;
				}
				if (session_wayland != null && session_wayland != "") {
					argv += "WAYLAND_DISPLAY=" + session_wayland;
				}
				if (session_runtime != null && session_runtime != "") {
					argv += "XDG_RUNTIME_DIR=" + session_runtime;
				}
				if (session_xauth != null && session_xauth != "") {
					argv += "XAUTHORITY=" + session_xauth;
				}
				if (session_bus != null && session_bus != "") {
					argv += "DBUS_SESSION_BUS_ADDRESS=" + session_bus;
				}
			}
			argv += executable;
			GLib.Subprocess proc;
			try {
				proc = new GLib.Subprocess.newv(argv, GLib.SubprocessFlags.NONE);
			} catch (GLib.Error e) {
				var failed = new Argus.Shared.Notice("Could not request administrator access", e.message);
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
			return this.link == null ? ServiceStatus.RUNNING : ServiceStatus.CONNECTED;
		}

		/**
		 * Register this machine from the desktop.
		 *
		 * The service is set up first. An existing certificate
		 * shows the running notice. Otherwise the registration
		 * window opens. Command-line registration is {@link cli}.
		 *
		 * @return zero when a window is open
		 */
		private int registration()
		{
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				Gtk.init();
				var failed = new Argus.Shared.Notice("Could not set up the Argus agent service", e.message);
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				Gtk.init();
				var failed = false;
				var notice = new Argus.Shared.Notice("Argus agent is running", "");
				notice.add_response("close", "Close");
				notice.add_response("restart", "Restart");
				notice.responded.connect((response) => {
					if (response != "restart") {
						return;
					}
					try {
						service.restart();
					} catch (GLib.Error e) {
						failed = true;
						var error_notice = new Argus.Shared.Notice("Could not restart the Argus agent service", e.message);
						error_notice.add_response("ok", "OK");
						error_notice.closed.connect(() => {
							this.quit();
						});
						error_notice.present(null);
					}
				});
				notice.closed.connect(() => {
					if (!failed) {
						this.quit();
					}
				});
				notice.present(null);
				this.hold();
				return 0;
			}
			Gtk.init();
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = Argus.AGENT_DATA_DIR
			};
			window.show_add();
			window.certificate_received.connect(() => {
				try {
					service.restart();
				} catch (GLib.Error e) {
					window.error_occurred("Registered, but could not restart the Argus agent service: " + e.message);
					return;
				}
				GLib.Idle.add(() => {
					window.listen_label.label = "Registration succeeded. The Argus agent is running and connected. This window will close in 10 seconds.";
					return false;
				});
			});
			window.present(null);
			window.closed.connect(() => {
				this.quit();
			});
			this.hold();
			return 0;
		}

		/**
		 * Register this machine from the command line.
		 *
		 * ''--server'' is the management IP. ''--pin'' uses that
		 * number instead of asking. Both together register in one
		 * step. No address browses, then asks for the PIN.
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
			var port = Argus.SOCKET_PORT;
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
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				command_line.printerr("Could not set up the Argus agent service: %s\n", e.message);
				return 1;
			}
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				command_line.print("Argus agent is already registered.\n");
				return 0;
			}
			if (host == "") {
				var browse = new Argus.Shared.Browse();
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
				data_dir = Argus.AGENT_DATA_DIR
			};
			if (given_pin != "") {
				var code = registration.try_connection(host, (uint16) port, given_pin,
					GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
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
				var code = registration.try_connection(host, (uint16) port, pin,
					GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					continue;
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
