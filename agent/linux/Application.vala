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

		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
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
				return this.registration(command_line);
			}
			var display = GLib.Environment.get_variable("DISPLAY");
			var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			if ((display == null || display == "") && (wayland == null || wayland == "")) {
				command_line.printerr("Run argus-agent as root.\n");
				return 1;
			}
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				command_line.printerr("Could not request administrator access: pkexec was not found.\n");
				return 1;
			}
			var executable = "";
			try {
				executable = GLib.FileUtils.read_link("/proc/self/exe");
			} catch (GLib.FileError e) {
				command_line.printerr("Could not resolve argus-agent: %s\n", e.message);
				return 1;
			}
			try {
				new GLib.Subprocess.newv({pkexec, executable}, GLib.SubprocessFlags.NONE);
			} catch (GLib.Error e) {
				command_line.printerr("Could not request administrator access: %s\n", e.message);
				return 1;
			}
			return 0;
		}

		public ServiceStatus status() throws GLib.DBusError, GLib.IOError
		{
			return this.link == null ? ServiceStatus.RUNNING : ServiceStatus.CONNECTED;
		}

		private int registration(GLib.ApplicationCommandLine command_line)
		{
			var args = command_line.get_arguments();
			if (args.length > 1) {
				command_line.printerr("argus-agent does not accept registration arguments.\n");
				return 1;
			}
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				command_line.printerr("Could not set up the Argus agent service: %s\n",
					e.message);
				return 1;
			}
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				command_line.print("Argus agent is already registered.\n");
				return 0;
			}
			var display = GLib.Environment.get_variable("DISPLAY");
			var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			if ((display != null && display != "") || (wayland != null && wayland != "")) {
				Gtk.init();
				var window = new Argus.Shared.RegisterWindow() {
					data_dir = Argus.AGENT_DATA_DIR
				};
				window.show_add();
				window.certificate_received.connect(() => {
					try {
						service.restart();
						GLib.Idle.add(() => {
							window.listen_label.label =
								"Registration succeeded. The Argus agent is running and connected. " +
								"This window will close in 10 seconds.";
							return false;
						});
					} catch (GLib.Error e) {
						window.error_occurred(
							"Registered, but could not restart the Argus agent service: " +
							e.message);
					}
				});
				window.present(null);
				window.closed.connect(() => {
					this.quit();
				});
				this.hold();
				return 0;
			}
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
			var port = 0;
			if (!int.try_parse(hostport.substring(colon + 1), out port) ||
				port <= 0 || port > 65535) {
				command_line.printerr("No management server found.\n");
				return 1;
			}
			var registration = new Argus.Shared.Register() {
				data_dir = Argus.AGENT_DATA_DIR
			};
			while (true) {
				command_line.print("Enter registration PIN: ");
				GLib.stdout.flush();
				var line = GLib.stdin.read_line();
				if (line == null) {
					command_line.printerr("\n");
					return 1;
				}
				var pin = line.strip();
				var valid_pin = pin.length == 6;
				for (var i = 0; valid_pin && i < pin.length; i++) {
					if (pin[i] < '0' || pin[i] > '9') {
						valid_pin = false;
					}
				}
				if (!valid_pin) {
					command_line.printerr("Enter the six digits.\n");
					continue;
				}
				var code = registration.try_connection(hostport.substring(0, colon),
					(uint16) port, pin, GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					continue;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n",
						e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
		}
	}
}
