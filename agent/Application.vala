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
	 * {@link app_options}, including ''--debug''. ''--server'' is
	 * the management IP. {@link host},
	 * {@link port}, and {@link pin} are the registration properties.
	 * {@link hold} keeps the process up. With no address,
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
		 * Argus Remote Manager address for registration. Empty when not registering.
		 */
		public string host { get; set; default = ""; }

		/**
		 * Argus Remote Manager port for registration. Zero when not registering.
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
		 * Server connection. Null until {@link open_connection}.
		 */
		internal OLLMrpc.Transport.TlsClient? connection { get; private set; }

		/**
		 * Osquery runner for this process.
		 */
		internal OSQuery.Execute osquery;

		/**
		 * Startup ''os_version'' row. {@link OSQuery.Execute.send_packages}
		 * reads {@link Argus.Shared.OSQuery.OsVersion.package_manager}.
		 */
		internal Argus.Shared.OSQuery.OsVersion os_version {
			get; set; default = new Argus.Shared.OSQuery.OsVersion();
		}

		/**
		 * True after the first package snapshot was posted.
		 * A later empty query is not forwarded.
		 */
		internal bool packages_sent = false;

		/**
		 * Package watch for this host.
		 *
		 * Created after the startup snapshot.
		 * {@link PackageMonitor.start} reads
		 * {@link Argus.Shared.OSQuery.OsVersion.package_manager}.
		 */
		internal PackageMonitor monitor;

		/**
		 * True when {@link connection} is down.
		 *
		 * Set when {@link open_connection} fails, or when
		 * {@link OLLMrpc.Transport.TlsClient.closed} fires.
		 * {@link attach_connection} tries again on the next retry.
		 */
		internal static bool connection_down = false;

		/**
		 * Emitted when the stored registration or server connection state changes.
		 */
		internal signal void state_changed();

		/**
		 * Last startup or rejection notice for the Windows tray.
		 */
		internal string status_notice = "";

		private uint connection_check_id = 0;
		private bool connecting = false;

		protected static bool opt_debug;
		protected static bool opt_debug_critical;
		protected static string opt_host;
		protected static int opt_port;
		protected static string opt_server;
		protected static string opt_pin;
		protected static bool opt_service;
		protected static bool debug_on;
		protected static bool debug_critical_enabled;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;

		protected const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "host", 0, 0, GLib.OptionArg.STRING, ref opt_host, "Argus Remote Manager address", "HOST" },
			{ "port", 0, 0, GLib.OptionArg.INT, ref opt_port, "Argus Remote Manager port", "PORT" },
			{ "server", 0, 0, GLib.OptionArg.STRING, ref opt_server, "Argus Remote Manager server IP address", "IP" },
			{ "pin", 0, 0, GLib.OptionArg.STRING, ref opt_pin, "Number from the registration window", "PIN" },
			{ "service", 0, 0, GLib.OptionArg.NONE, ref opt_service, "Run as managed service", null },
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
		 * Open the server connection from the stored server and certificate.
		 *
		 * A second call returns the connection already open.
		 * Registration wrote those certificate files. The socket
		 * waits five seconds, then the open fails.
		 *
		 * @return the connection, or null when it cannot be opened
		 */
		internal OLLMrpc.Transport.TlsClient? open_connection()
		{
			if (this.connection != null) {
				return this.connection;
			}
#if LINUX
			var dir = Argus.AGENT_DATA_DIR;
#else
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
#endif
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
			opened.timeout = 5;
			try {
				opened.open();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
			}
			this.connection = opened;
			return this.connection;
		}

		/**
		 * Keep {@link connection} open.
		 *
		 * The first call starts a thirty-second retry. The connection
		 * that is still up is left as it is. A failed open, or
		 * {@link OLLMrpc.Transport.TlsClient.closed}, is tried again
		 * on the next retry.
		 */
		internal void attach_connection()
		{
			if (this.connection_check_id == 0) {
				/* Retry 30 seconds after the previous try. */
				this.connection_check_id = GLib.Timeout.add_seconds(30, () => {
					if (this.connection != null && !Application.connection_down) {
						return true;
					}
					this.attach_connection();
					return true;
				});
			}
			if (this.connecting) {
				return;
			}
			if (this.connection != null && !Application.connection_down) {
				return;
			}
			this.connecting = true;
			var opened = this.connection;
			if (opened == null) {
				opened = this.open_connection();
				if (opened != null) {
					opened.closed.connect(() => {
						Application.connection_down = true;
						this.state_changed();
					});
					opened.notification.connect(this.notification);
				}
			} else {
				try {
					opened.open();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					Application.connection_down = true;
					this.connecting = false;
					this.state_changed();
					return;
				}
			}
			if (opened == null) {
				Application.connection_down = true;
				this.connecting = false;
				this.state_changed();
				return;
			}
			opened.watch();
			Application.connection_down = false;
			GLib.debug("watching the server connection");
			this.connecting = false;
			this.state_changed();
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
			this.osquery = new OSQuery.Execute(this);
		}

		/**
		 * Parse arguments, register when asked, and stay up.
		 *
		 * ''--debug'' shows log lines on stderr. ''--server'' is the
		 * management IP. ''--port'' overrides {@link Argus.REGISTER_PORT}.
		 * ''--server'' or ''--host'' with ''--port'' and ''--pin'' call
		 * {@link Argus.Shared.Register}
		 * immediately. ''--pin'' alone waits for the broadcast, then
		 * registers. The Android app icon opens the registration
		 * window, and the box says this phone is already registered.
		 * A registered process starts
		 * {@link OSQuery.Initialize} and watches the server connection.
		 * A failed open waits and is tried again every thirty seconds.
		 * On Windows a stored certificate that cannot reach the
		 * server, or that the server does not accept, is removed
		 * and the registration window is offered again.
		 * The Android {@link OSQuery.Initialize} does not query.
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
			Argus.Shared.OSQuery.OsVersion.rpc_register();
			Argus.Shared.OSQuery.DebPackages.rpc_register();
			Argus.Shared.OSQuery.RpmPackages.rpc_register();
			Argus.Shared.OSQuery.Programs.rpc_register();
			Argus.Shared.OSQuery.PackageUpdates.rpc_register();
			Command.rpc_register();
			opt_debug = false;
			opt_debug_critical = false;
			opt_host = "";
			opt_port = 0;
			opt_server = "";
			opt_pin = "";
			opt_service = false;
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
			if (opt_server != "" && opt_host != "") {
				command_line.printerr("registration needs one address\n");
				return 1;
			}
			if (opt_server != "") {
				var inet = new GLib.InetAddress.from_string(opt_server.strip());
				if (inet == null || inet.is_any || inet.is_multicast) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
				this.host = inet.to_string();
				if (this.port <= 0) {
					this.port = Argus.REGISTER_PORT;
				}
				if (this.port > 65535) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
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
				this.attach_connection();
				GLib.debug("staying up");
#if LINUX
				this.browse.start();
#endif
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
						this.attach_connection();
					}
					return false;
				});
			}
			GLib.debug("staying up");
#if LINUX
			var cert = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.attach_connection();
				if (this.connection != null && !Application.connection_down) {
					new OSQuery.Initialize(this).start();
					this.osquery.send_startup();
					this.monitor = new PackageMonitor(this);
					this.monitor.start();
				}
				if (this.connection == null || Application.connection_down) {
					GLib.debug("waiting for connection");
					GLib.Timeout.add_seconds(5, () => {
						if (this.connection == null || Application.connection_down) {
							GLib.debug("waiting for connection");
							return true;
						}
						new OSQuery.Initialize(this).start();
						this.osquery.send_startup();
						this.monitor = new PackageMonitor(this);
						this.monitor.start();
						return false;
					});
				}
			}
#else
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				GLib.Idle.add(() => {
					this.attach_connection();
					var rejected = this.connection == null;
					var notice = "Could not reach the management server.";
					if (this.connection != null) {
						try {
							var response = this.connection.call(new OLLMrpc.Request() {
								method = "RPC-Daemon.hello",
								args = OLLMrpc.args("is", 1, "argus-agent")
							});
							if (response.error != null) {
								rejected = true;
								if (response.error.code ==
									(int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED) {
									notice = "Not registered with the management server.";
								}
							}
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							rejected = true;
						}
					}
					if (rejected) {
						if (this.connection_check_id != 0) {
							GLib.Source.remove(this.connection_check_id);
							this.connection_check_id = 0;
						}
						this.connection = null;
						Application.connection_down = true;
						var dir = GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "argus");
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"));
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
						this.status_notice = notice;
						GLib.debug("registration cleared");
						this.state_changed();
						return false;
					}
					this.status_notice = "";
					this.state_changed();
					new GLib.Thread<int>("osquery-init", () => {
						var code = new OSQuery.Initialize(this).run();
						GLib.Idle.add(() => {
							if (code == 0 && this.connection != null) {
								this.osquery.send_startup();
								this.monitor = new PackageMonitor(this);
								this.monitor.start();
							}
							return false;
						});
						return 0;
					});
					return false;
				});
			}
#endif
			this.hold();
			return 0;
		}

		/**
		 * Run a command notification, or follow up on one.
		 *
		 * ''agent.run'' hands the ''Argus.Command'' to
		 * {@link Command.run}. ''agent.send'' writes its text to
		 * the stdin of the command with that id.
		 * ''agent.removed'' deletes the stored certificate.
		 * Any other method returns.
		 *
		 * @param notification notification from the server connection
		 */
		public void notification(OLLMrpc.Notification notification)
		{
			GLib.debug("%s", notification.method);
			switch (notification.method) {
				case "agent.send":
					if (notification.args.size < 2) {
						return;
					}
					var id_value = notification.args.get(0);
					var text_value = notification.args.get(1);
					if (id_value == null || text_value == null) {
						return;
					}
					if (!id_value.holds(typeof(int)) ||
						!text_value.holds(typeof(string))) {
						return;
					}
					var identifier = id_value.get_int();
					Command.send_lock.lock();
					Command order = null;
					if (Command.running != null &&
						Command.running.has_key(identifier)) {
						order = Command.running.get(identifier);
					}
					Command.send_lock.unlock();
					if (order == null) {
						GLib.warning("command %d is not running", identifier);
						return;
					}
					order.send(text_value.get_string());
					return;
				case "agent.removed":
#if LINUX
					var removed = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
#else
					var removed = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "client.pem");
#endif
					GLib.FileUtils.remove(removed);
					GLib.debug("registration removed");
					this.state_changed();
					return;
				case "agent.run":
					if (notification.args.size == 0) {
						GLib.warning("no argument");
						return;
					}
					var value = notification.args.get(0);
					var obj = value.get_object();
					if (!(obj is Command)) {
						GLib.warning("%s", value.type().name());
						return;
					}
					var command = (Command) obj;
					command.run(this.connection);
					return;
				default:
					return;
			}
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
				var configured_log_dir = GLib.Environment.get_variable("ARGUS_LOG_DIR");
				var log_dir = configured_log_dir == null || configured_log_dir == "" ?
					GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(), "argusrm") :
					configured_log_dir;
				var log_file_path = GLib.Path.build_filename(log_dir, "agent.log");
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
}
