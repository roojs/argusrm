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

namespace Argus.Server
{
	/**
	 * Headless Argus process.
	 *
	 * A {@link GLib.Application} with no window. Arguments are the
	 * same shape as ''ollmfilesd'': {@link command_line} parses
	 * {@link app_options}, including ''--debug''. {@link socket} is
	 * the app RPC. {@link download} is the download socket, fixed
	 * in the config. The Unix socket under {@link LOCALSTATEDIR}
	 * is how the controller opens the registration window.
	 * {@link hold} keeps the process up.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var app = new Argus.Server.Application();
	 * return app.run(args);
	 * }}}
	 */
	public class Application : GLib.Application
	{
		/**
		 * App socket, ''host:port''. Empty until {@link command_line}
		 * reads the config or ''--socket''.
		 */
		public string socket { get; set; default = ""; }

		/**
		 * Download socket, ''host:port''. Empty until
		 * {@link command_line} reads the config or ''--download''.
		 */
		public string download { get; set; default = ""; }

		/**
		 * Server certificate and product CA. {@link command_line}
		 * fills this before either socket binds.
		 */
		public OLLMrpc.Transport.Cert tls {
			get; set; default = new OLLMrpc.Transport.Cert();
		}

		/**
		 * App socket. {@link command_line} calls {@link SslListen.listen}.
		 */
		public SslListen ssl_listen { get; private set; }

		/**
		 * Download socket. {@link command_line} calls
		 * {@link Download.listen}.
		 */
		public Download download_listen { get; private set; }

		/**
		 * Certificate rows. The file is ''argus.sqlite'' under
		 * {@link LOCALSTATEDIR}.
		 */
		public SQ.Database db { get; private set; }

		/**
		 * Unix socket the controller uses for {@link ClientCert.pair}.
		 */
		public OLLMrpc.Transport.SocketListen listen { get; private set; }

		/**
		 * mDNS publish for the registration window. {@link ClientCert.pair}
		 * starts and stops it.
		 */
		public OLLMrpc.Transport.PairPublish publish {
			get; set; default = new OLLMrpc.Transport.PairPublish();
		}

		private static bool opt_debug;
		private static bool opt_debug_critical;
		private static string opt_socket;
		private static string opt_download;
		private static bool debug_on;
		private static bool debug_critical_enabled;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;

		private const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "socket", 0, 0, GLib.OptionArg.STRING, ref opt_socket, "App socket host:port", "HOST:PORT" },
			{ "download", 0, 0, GLib.OptionArg.STRING, ref opt_download, "Download socket host:port", "HOST:PORT" },
			{ null }
		};

		/**
		 * Create the process.
		 *
		 * The id is ''org.roojs.Argus''. Flags are
		 * {@link GLib.ApplicationFlags.HANDLES_COMMAND_LINE} and
		 * {@link GLib.ApplicationFlags.NON_UNIQUE}, as in ''ollmfilesd''.
		 * Service mode is not used: it rejects arguments.
		 */
		public Application()
		{
			Object(
				application_id: "org.roojs.Argus",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE | GLib.ApplicationFlags.NON_UNIQUE
			);
			this.ssl_listen = new SslListen(this);
			this.download_listen = new Download(this);
			if (!GLib.FileUtils.test(LOCALSTATEDIR, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(LOCALSTATEDIR, 0755);
			}
			this.db = new SQ.Database(
				GLib.Path.build_filename(LOCALSTATEDIR, "argus.sqlite"), true);
			this.listen = new OLLMrpc.Transport.SocketListen(
				GLib.Path.build_filename(LOCALSTATEDIR, "argus.sock")) {
				live_handles = true
			};
			this.publish.failed.connect(() => {
				GLib.warning("Could not publish the pairing service");
			});
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				Application.debug_log(dom, lvl, msg);
			});
			this.shutdown.connect(() => {
				this.publish.stop();
				this.listen.stop();
				this.db.backup_real();
				this.ssl_listen.stop();
				this.download_listen.stop();
			});
		}

		/**
		 * Parse arguments, open both sockets, and stay up.
		 *
		 * ''--debug'' shows log lines on stderr. ''--socket'' is the
		 * app RPC. ''--download'' is the download socket. When a flag
		 * is absent, the value is one line in the config under
		 * {@link SYSCONFDIR}. The default build is
		 * ''/etc/argusrm/socket'' and ''/etc/argusrm/download''.
		 * Each line is ''host:port'', the same text the agent
		 * stores. With no line, the process listens on
		 * ''0.0.0.0'' and the build ports {@link SOCKET_PORT}
		 * and {@link DOWNLOAD_PORT}. {@link Initialize.fetch_osquery}
		 * fetches the osquery installers into {@link LOCALSTATEDIR}
		 * before the sockets bind. {@link ClientCert.pair} on the
		 * Unix socket opens the registration window.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when both sockets are up or help was printed,
		 *   otherwise the option or bind error
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			OLLMrpc.rpc_register();
			opt_debug = false;
			opt_debug_critical = false;
			opt_socket = "";
			opt_download = "";
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
			this.socket = opt_socket;
			this.download = opt_download;
			if (this.socket == "") {
				var path = GLib.Path.build_filename(SYSCONFDIR, "socket");
				var text = "";
				try {
					GLib.FileUtils.get_contents(path, out text);
				} catch (GLib.Error e) {
					text = "";
				}
				this.socket = text.strip();
			}
			if (this.socket == "") {
				this.socket = "0.0.0.0:" + SOCKET_PORT.to_string();
			}
			if (this.download == "") {
				var path = GLib.Path.build_filename(SYSCONFDIR, "download");
				var text = "";
				try {
					GLib.FileUtils.get_contents(path, out text);
				} catch (GLib.Error e) {
					text = "";
				}
				this.download = text.strip();
			}
			if (this.download == "") {
				this.download = "0.0.0.0:" + DOWNLOAD_PORT.to_string();
			}
			var tls_dir = GLib.Path.build_filename(LOCALSTATEDIR, "tls");
			if (!GLib.FileUtils.test(tls_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(tls_dir, 0700);
			}
			var ca_pem = GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem");
			var ca_key = GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem");
			if (!GLib.FileUtils.test(ca_pem, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_pem,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA PEM: %s", e.message);
				}
			}
			if (!GLib.FileUtils.test(ca_key, GLib.FileTest.EXISTS)) {
				try {
					GLib.FileUtils.set_contents(ca_key,
						(string) GLib.resources_lookup_data("/ollmrpc/ollmrpc-ca-key.pem",
							GLib.ResourceLookupFlags.NONE).get_data());
				} catch (GLib.Error e) {
					GLib.error("extract CA key: %s", e.message);
				}
			}
			this.tls.dir = tls_dir;
			this.tls.ca_pem_path = ca_pem;
			this.tls.ca_key_path = ca_key;
			this.tls.server_san = true;
			this.tls.cn = "argus";
			this.tls.ensure();
			if (this.tls.trust == null) {
				command_line.printerr("error: CA trust was not loaded\n");
				return 1;
			}
			Agent.rpc_register();
			Daemon.rpc_register();
			OSQuery.rpc_register();
			Agent.init_db(this.db);
			Argus.Shared.OSQuery.init_db(this.db);
			OLLMrpc.Request.register("ClientCert", new Agent.for_rpc(this));
			OLLMrpc.Request.register("RPC-Daemon", new Daemon());
			OLLMrpc.Request.register("OSQuery", new OSQuery(this));
			if (!(new Initialize()).fetch_osquery()) {
				command_line.printerr("error: download store was not created\n");
				return 1;
			}
			if (!this.listen.start()) {
				command_line.printerr("error: local socket did not bind\n");
				return 1;
			}
			if (!this.ssl_listen.listen()) {
				this.listen.stop();
				command_line.printerr("error: app socket did not bind\n");
				return 1;
			}
			if (!this.download_listen.listen()) {
				this.ssl_listen.stop();
				this.listen.stop();
				command_line.printerr("error: download socket did not bind\n");
				return 1;
			}
			GLib.debug("staying up");
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
				var configured_log_dir = GLib.Environment.get_variable("ARGUS_LOG_DIR");
				var log_dir = configured_log_dir == null || configured_log_dir == "" ?
					GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(), "argusrm") :
					configured_log_dir;
				var log_file_path = GLib.Path.build_filename(log_dir, "server.log");
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

		/**
		 * Send one notification on the Unix socket and the app socket.
		 *
		 * @param notification bin notification
		 */
		public void broadcast(OLLMrpc.Notification notification)
		{
			this.listen.broadcast(notification);
			this.ssl_listen.broadcast(notification);
		}
	}

	int main(string[] args)
	{
		var app = new Application();
		return app.run(args);
	}
}
