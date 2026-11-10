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

namespace Argus.Controller
{
	/**
	 * Controller for Argus.
	 *
	 * With no command on a desktop, {@link Dialog.Bootstrap} checks saved
	 * connections and may open {@link Window}. ''--give-me-a-certificate''
	 * issues the local login certificate. A registration PIN, the
	 * agent list, and a command are ''argusrm-controller-cli''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var app = new Argus.Controller.Application();
	 * return app.run(args);
	 * }}}
	 */
	public class Application : GLib.Application
	{
		public static string give_certificate;
		public static string deregister_name;
		/**
		 * Agent id for {@link Command.run}.
		 *
		 * The command-line controller sets this. The desktop registers
		 * the type so a later window can send the same object.
		 */
		public static string agent = "";
		/**
		 * Shell line for {@link Command.run}.
		 *
		 * The command-line controller sets this. The desktop registers
		 * the type so a later window can send the same object.
		 */
		public static string command = "";
		private static bool opt_debug;
		private static bool opt_debug_critical;
		private static bool debug_on;
		private static bool debug_critical_enabled;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;
		private const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "give-me-a-certificate", 0, 0, GLib.OptionArg.STRING, ref give_certificate, "Issue a local controller certificate", "USERNAME" },
			{ "deregister", 0, 0, GLib.OptionArg.STRING, ref deregister_name, "Username or fingerprint to deregister", "NAME" },
			{ null }
		};
		public GLib.ApplicationCommandLine cli { get; set; }
		public OLLMrpc.Client rpc { get; set; }
		/**
		 * Main window opened after a connection answers.
		 */
		public Window window { get; set; }
		/**
		 * True while {@link Window} is on screen.
		 *
		 * {@link Dialog.Bootstrap} does not quit when this is true.
		 * Disconnect clears it, then the startup check opens again.
		 */
		public bool running_window = false;
		public GLib.MainLoop loop { get; set; }
		public int code { get; set; default = 1; }

		/**
		 * Create the process.
		 *
		 * The id is ''org.roojs.ArgusController''. Flags are
		 * {@link GLib.ApplicationFlags.HANDLES_COMMAND_LINE} and
		 * {@link GLib.ApplicationFlags.NON_UNIQUE}.
		 */
		public Application()
		{
			Object(
				application_id: "org.roojs.ArgusController",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE | GLib.ApplicationFlags.NON_UNIQUE
			);
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				Application.debug_log(dom, lvl, msg);
			});
		}

		/**
		 * Parse the flags, then run one command or the startup window.
		 *
		 * ''--debug'' shows log lines on stderr. No flag on a desktop
		 * loads ''/argusrm/style.css'', then opens
		 * {@link Dialog.Bootstrap}. ''--give-me-a-certificate''
		 * issues the local login certificate. No desktop tells you to
		 * run ''argusrm-controller-cli''. The Unix socket is
		 * ''argus.sock'' under {@link Argus.SERVER_DATA_DIR}.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when the command finished, otherwise the
		 *   usage, connect, or call error
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			OLLMrpc.rpc_register();
			Argus.Shared.Agent.rpc_register();
			Argus.Shared.Registration.Data.rpc_register();
			Argus.Shared.SQT.Task.rpc_register();
			Argus.Shared.SQT.TaskTarget.rpc_register();
			Argus.Shared.SQT.Script.rpc_register();
			Argus.Shared.SQT.ScriptRepository.rpc_register();
			Argus.Controller.Command.rpc_register();
			give_certificate = "";
			deregister_name = "";
			opt_debug = false;
			opt_debug_critical = false;
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
			unowned string[] leftover = args;
			try {
				opt_context.parse(ref leftover);
			} catch (GLib.OptionError e) {
				command_line.printerr("%s\n", e.message);
				return 1;
			}
			debug_on = opt_debug;
			debug_critical_enabled = opt_debug_critical;
			if (give_certificate != "" && deregister_name != "") {
				command_line.printerr("Use one of --give-me-a-certificate or --deregister.\n");
				return 1;
			}
			if (give_certificate == "" && deregister_name == "") {
				var display = GLib.Environment.get_variable("DISPLAY");
				var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				if ((display == null || display == "") && (wayland == null || wayland == "")) {
					command_line.printerr("Run argusrm-controller-cli on the server.\n");
					return 1;
				}
				Adw.init();
				var screen = Gdk.Display.get_default();
				if (screen != null) {
					var css = new Gtk.CssProvider();
					css.load_from_resource("/argusrm/style.css");
					Gtk.StyleContext.add_provider_for_display(
						screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
				}
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(null);
				this.hold();
				return 0;
			}
#if LINUX
			if (Posix.geteuid() != 0) {
				var data = new Argus.Shared.Registration.Data() {
					error = "root is required"
				};
				command_line.print("%s\n", Json.gobject_to_data(data, null));
				return 1;
			}
#else
			var data = new Argus.Shared.Registration.Data() {
				error = "local certificate issue is Linux only"
			};
			command_line.print("%s\n", Json.gobject_to_data(data, null));
			return 1;
#endif
			this.cli = command_line;
			this.rpc = new OLLMrpc.Client("", "",
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock")) {
				live_handles = true
			};
			this.rpc.debug = false;
			this.loop = new GLib.MainLoop();
			this.code = 1;
			this.rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, this.on_connect);
			this.loop.run();
			return this.code;
		}

		/**
		 * Handle the completed connection to the local Argus Remote Manager server.
		 *
		 * @param rpc the Unix client
		 * @param res the finished connection
		 */
		public void on_connect(GLib.Object? rpc, GLib.AsyncResult res)
		{
			var opened = this.rpc.connect.end(res);
			if (!opened) {
				var data = new Argus.Shared.Registration.Data() {
					error = this.rpc.connect_error
				};
				this.cli.print("%s\n", Json.gobject_to_data(data, null));
				this.loop.quit();
				return;
			}
			var method = "Registration.certificate";
			var call_args = OLLMrpc.args("s", give_certificate);
			if (deregister_name != "") {
				method = "Registration.deregister";
				call_args = OLLMrpc.args("s", deregister_name);
			}
			this.rpc.call.begin(new OLLMrpc.Request() {
				method = method,
				args = call_args
			}, (call_obj, call_res) => {
				try {
					var response = this.rpc.call.end(call_res);
					if (response.error != null) {
						var data = new Argus.Shared.Registration.Data() {
							error = response.error.message
						};
						this.cli.print("%s\n", Json.gobject_to_data(data, null));
						this.loop.quit();
						return;
					}
					if (deregister_name != "") {
						this.cli.print("%s\n", Json.gobject_to_data(new Argus.Shared.Registration.Data(), null));
						this.code = 0;
						this.loop.quit();
						return;
					}
					this.cli.print("%s\n", Json.gobject_to_data((Argus.Shared.Registration.Data) response.retval, null));
				} catch (GLib.Error e) {
					var data = new Argus.Shared.Registration.Data() {
						error = e.message
					};
					this.cli.print("%s\n", Json.gobject_to_data(data, null));
					this.loop.quit();
					return;
				}
				this.code = 0;
				this.loop.quit();
			});
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
				var log_dir = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(), "argusrm");
				var log_file_path = GLib.Path.build_filename(log_dir, "controller.log");
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
