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

namespace Argus.Agent
{
	/**
	 * Long-running agent process.
	 *
	 * A {@link GLib.Application} with no window. Arguments are the same
	 * shape as ''ollmfilesd'': {@link command_line} parses
	 * {@link app_options}, including ''--debug''. {@link host},
	 * {@link port}, and {@link pin} are the registration properties.
		 * {@link hold} keeps the process up. With no host and port,
	 * {@link Argus.Shared.Browse} looks for the broadcast. On
	 * Windows, {@link Win32.Service} starts this when the Service
	 * Control Manager launches ''argus-agent''. ''argus-tray'' is
	 * {@link Win32.Tray}, not this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var app = new Argus.Agent.Application();
	 * return app.run(args);
	 * }}}
	 */
	public class Application : GLib.Application
	{
		/**
		 * Argus address for registration. Empty when not registering.
		 */
		public string host { get; set; default = ""; }

		/**
		 * Argus port for registration. Zero when not registering.
		 */
		public int port { get; set; default = 0; }

		/**
		 * Number from the registration window. Empty when not registering.
		 */
		public string pin { get; set; default = ""; }

		/**
		 * Broadcast browse. Started when this launch was not given
		 * a host and a port. The Windows service reads it when the
		 * tray writes a pin.
		 */
		internal Argus.Shared.Browse browse {
			get; set; default = new Argus.Shared.Browse();
		}

		/**
		 * App socket. Null until {@link open_link}.
		 */
		internal OLLMrpc.Transport.TlsClient? link { get; private set; }

		private static bool opt_debug;
		private static bool opt_debug_critical;
		private static string opt_host;
		private static int opt_port;
		private static string opt_pin;
		private static bool opt_register;
		private static bool debug_on;
		private static bool debug_critical_enabled;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;

		private const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "host", 0, 0, GLib.OptionArg.STRING, ref opt_host, "Argus address", "HOST" },
			{ "port", 0, 0, GLib.OptionArg.INT, ref opt_port, "Argus port", "PORT" },
			{ "pin", 0, 0, GLib.OptionArg.STRING, ref opt_pin, "Number from the registration window", "PIN" },
			{ "register", 0, 0, GLib.OptionArg.NONE, ref opt_register, "Open the registration window", null },
			{ null }
		};

		/**
		 * Create the process.
		 *
		 * The id is ''org.roojs.ArgusAgent''. Flags are
		 * {@link GLib.ApplicationFlags.HANDLES_COMMAND_LINE} and
		 * {@link GLib.ApplicationFlags.NON_UNIQUE}, as in ''ollmfilesd''.
		 * Service mode is not used: it rejects arguments.
		 */
		/**
		 * Open the app socket from the stored server and certificate.
		 *
		 * A second call returns the socket already open.
		 * Registration wrote those certificate files.
		 *
		 * @return the socket, or null when it cannot be opened
		 */
		internal OLLMrpc.Transport.TlsClient? open_link()
		{
			if (this.link != null) {
				return this.link;
			}
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
			var text = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "server"), out text);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
			}
			text = text.strip();
			var mark = text.last_index_of(":");
			if (text == "" || mark < 1) {
				return null;
			}
			var host = text.substring(0, mark);
			var port = int.parse(text.substring(mark + 1));
			if (port <= 0 || port > 65535) {
				return null;
			}
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
			var opened = new OLLMrpc.Transport.TlsClient(host, (uint16) port) {
				accept_any = true,
				tls_certificate = tls_files.certificate
			};
			try {
				opened.open();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
			}
			this.link = opened;
			return this.link;
		}

		public Application()
		{
			Object(
				application_id: "org.roojs.ArgusAgent",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE | GLib.ApplicationFlags.NON_UNIQUE
			);
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				Application.debug_log(dom, lvl, msg);
			});
		}

		/**
		 * Parse arguments, register when asked, and stay up.
		 *
		 * ''--debug'' shows log lines on stderr. ''--host'', ''--port'',
		 * and ''--pin'' together call {@link Argus.Shared.Register}
		 * immediately. ''--pin'' alone waits for the broadcast, then
		 * registers. ''--register'' opens the window and calls the
		 * systemd process over D-Bus. That process calls
		 * {@link Argus.Shared.Register}. The Android app icon
		 * opens that window, and the box says this phone is
		 * already registered. A registered process starts
		 * {@link OSQuery.Initialize} and {@link Listen}. The
		 * Android {@link OSQuery.Initialize} does not query.
		 * With none of those, the process browses and stays up.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when the process stays up or help was printed,
		 *   otherwise the registration or option error
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			OLLMrpc.rpc_register();
			Argus.Shared.OSQuery.SystemInfo.rpc_register();
			Argus.Shared.OSQuery.CpuInfo.rpc_register();
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
			Argus.Shared.OSQuery.InterfaceAddresses.rpc_register();
			Command.rpc_register();
			opt_debug = false;
			opt_debug_critical = false;
			opt_host = "";
			opt_port = 0;
			opt_pin = "";
			opt_register = false;
			var args = command_line.get_arguments();
			var opt_context = new GLib.OptionContext(this.application_id);
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);
			foreach (var arg in args) {
				if (arg == "--help" || arg == "-h") {
					command_line.print("%s", opt_context.get_help(true, null));
					return 0;
				}
			}
			try {
				unowned string[] unowned_args = args;
				opt_context.parse(ref unowned_args);
			} catch (GLib.OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n",
					args[0]);
				return 1;
			}
			debug_on = opt_debug;
			debug_critical_enabled = opt_debug_critical;
			this.host = opt_host;
			this.port = opt_port;
			this.pin = opt_pin;
			var open_window = opt_register;
#if ANDROID
			if (this.host == "" && this.port <= 0) {
				open_window = true;
			}
#endif
			if (open_window) {
				Gtk.init();
				var cert = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus", "client.pem");
				var show_box = GLib.FileUtils.test(cert, GLib.FileTest.EXISTS);
#if LINUX
				if (opt_register) {
					show_box = false;
					try {
						var conn = GLib.Bus.get_sync(GLib.BusType.SYSTEM);
						var reply = conn.call_sync("org.roojs.ArgusAgent",
							"/org/roojs/ArgusAgent", "org.roojs.ArgusAgent", "Registered",
							null, new GLib.VariantType("(b)"),
							GLib.DBusCallFlags.NONE, -1, null);
						reply.get("(b)", out show_box);
					} catch (GLib.Error e) {
						GLib.warning("registration bus: %s", e.message);
					}
				}
#endif
				if (show_box) {
					var already = "This machine is already registered.";
#if ANDROID
					already = "This phone is already registered.";
#endif
					var alert = new Adw.AlertDialog(
						"Connect to management server",
						already);
					alert.add_response("ok", "OK");
					alert.response.connect((response) => {
						this.quit();
					});
					alert.present(null);
					this.hold();
					return 0;
				}
				var window = new Argus.Shared.RegisterWindow();
#if LINUX
				window.use_bus = true;
#endif
				window.show_add();
				window.present(null);
				window.closed.connect(() => {
					this.quit();
				});
				this.hold();
				return 0;
			}
			if (this.host != "" || this.port > 0) {
				if (this.host == "" || this.port <= 0 || this.pin == "") {
					command_line.printerr("registration needs a host, a port, and a pin\n");
					return 1;
				}
				GLib.debug("registering %s:%d", this.host, this.port);
				var registration = new Argus.Shared.Register();
				var code = registration.try_connection(this.host, (uint16) this.port,
					this.pin, GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("registration failed: %d\n", code);
					return code;
				}
				var link = this.open_link();
				if (link != null) {
					new OSQuery.Initialize(link).start();
					new Listen(link).start();
				}
				GLib.debug("staying up");
#if LINUX
				this.browse.start();
#endif
				BusRegistration.start(this);
				this.hold();
				return 0;
			}
			GLib.debug("browsing");
			this.browse.start();
			if (this.pin != "") {
				GLib.Timeout.add_seconds(1, () => {
					var line = this.browse.poll();
					if (line == "") {
						return true;
					}
					if (line == "none") {
						return false;
					}
					var split = line.index_of("\n");
					if (split < 1) {
						return false;
					}
					var hostport = line.substring(split + 1);
					var colon = hostport.last_index_of(":");
					if (colon < 1) {
						return false;
					}
					this.host = hostport.substring(0, colon);
					this.port = int.parse(hostport.substring(colon + 1));
					if (this.port <= 0) {
						return false;
					}
					GLib.debug("registering %s:%d", this.host, this.port);
					var registration = new Argus.Shared.Register();
					var code = registration.try_connection(this.host, (uint16) this.port,
						this.pin, GLib.Environment.get_host_name());
					if (code != 0) {
						GLib.printerr("registration failed: %d\n", code);
					}
					if (code == 0) {
						var link = this.open_link();
						if (link != null) {
							new OSQuery.Initialize(link).start();
							new Listen(link).start();
						}
					}
					return false;
				});
			}
			GLib.debug("staying up");
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				var link = this.open_link();
				if (link != null) {
					new OSQuery.Initialize(link).start();
					new Listen(link).start();
				}
			}
			BusRegistration.start(this);
			this.hold();
			return 0;
		}

		/**
		 * Write one log line, and show it when ''--debug'' is on.
		 *
		 * Critical lines are always shown. ''--debug-critical'' aborts
		 * on a critical line. Every line is also appended to the cache
		 * log for this application.
		 *
		 * @param domain log domain, empty when the caller passed none
		 * @param level log level
		 * @param message log text
		 */
		private static void debug_log(string? domain, GLib.LogLevelFlags level, string message)
		{
			if (debug_log_in_progress) {
				return;
			}
			var timestamp = (new GLib.DateTime.now_local()).format("%H:%M:%S.%f");
			var shown_domain = domain == null ? "" : domain;
			var show = debug_on || (level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0;
			if (show) {
				GLib.stderr.printf(timestamp + ": " + level.to_string() + " : " +
					shown_domain + " : " + message + "\n");
			}
			if ((level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0 && debug_critical_enabled) {
				GLib.error("Critical warning: [%s] %s", shown_domain, message);
			}
			debug_log_in_progress = true;
			if (debug_log_file == null) {
				var log_dir = GLib.Path.build_filename(GLib.Environment.get_home_dir(), ".cache", "argus");
				var log_file_path = GLib.Path.build_filename(log_dir, "org.roojs.ArgusAgent.debug.log");
				if (!GLib.FileUtils.test(log_dir, GLib.FileTest.IS_DIR)) {
					GLib.DirUtils.create_with_parents(log_dir, 0755);
				}
				debug_log_file = GLib.FileStream.open(log_file_path, "w");
				if (debug_log_file == null) {
					GLib.stderr.printf("ERROR: FAILED TO OPEN DEBUG LOG FILE: Unable to open file stream\n");
					debug_log_in_progress = false;
					return;
				}
			}
			debug_log_file.puts(timestamp + ": " + level.to_string() + " : " + message + "\n");
			debug_log_file.flush();
			debug_log_in_progress = false;
		}
	}

	int main(string[] args)
	{
#if WINDOWS
		var exe_name = GLib.Path.get_basename(args[0]).down();
		if (exe_name == "argus-tray" || exe_name == "argus-tray.exe") {
			var tray = new Win32.Tray();
			return tray.run();
		}
		var service = new Win32.Service();
		var service_exit = service.start();
		if (service_exit >= 0) {
			return service_exit;
		}
#endif
		var app = new Application();
		return app.run(args);
	}
}
