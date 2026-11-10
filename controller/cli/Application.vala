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
	 * Command-line controller.
	 *
	 * The desktop program is {@link Application} in
	 * ''Application.vala''. This copy has no window. The command
	 * is ''argusrm-controller-cli'', installed with the server.
	 * It does not use GTK. Root with no flag opens registration.
	 * ''--pin'', ''--agents'', and ''--agent'' with ''--command''
	 * talk to the Unix socket ''argus.sock''.
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
		public static bool pin;
		public static bool agents;
		public static string agent;
		public static string command;
		public static string deregister_name;
		private static bool opt_debug;
		private static bool opt_debug_critical;
		private static bool debug_on;
		private static bool debug_critical_enabled;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;
		private const GLib.OptionEntry[] app_options = {
			{ "debug", 'd', 0, GLib.OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, GLib.OptionArg.NONE, ref opt_debug_critical, "Treat critical warnings as errors", null },
			{ "pin", 0, 0, GLib.OptionArg.NONE, ref pin, "Show a registration PIN", null },
			{ "agents", 0, 0, GLib.OptionArg.NONE, ref agents, "List registered agents", null },
			{ "agent", 0, 0, GLib.OptionArg.STRING, ref agent, "Agent id", "ID" },
			{ "command", 0, 0, GLib.OptionArg.STRING, ref command, "Command to run", "COMMAND" },
			{ "deregister", 0, 0, GLib.OptionArg.STRING, ref deregister_name, "Username or fingerprint to deregister", "NAME" },
			{ null }
		};
		public GLib.ApplicationCommandLine cli { get; set; }
		public OLLMrpc.Client rpc { get; set; }
		public GLib.MainLoop loop { get; set; }
		public int code { get; set; default = 1; }

		/**
		 * Create the process.
		 *
		 * The id is ''org.roojs.ArgusControllerCli''. Flags are
		 * {@link GLib.ApplicationFlags.HANDLES_COMMAND_LINE} and
		 * {@link GLib.ApplicationFlags.NON_UNIQUE}.
		 */
		public Application()
		{
			Object(
				application_id: "org.roojs.ArgusControllerCli",
				flags: GLib.ApplicationFlags.HANDLES_COMMAND_LINE | GLib.ApplicationFlags.NON_UNIQUE
			);
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				Application.debug_log(dom, lvl, msg);
			});
		}

		/**
		 * Parse the flags, then run one command.
		 *
		 * ''--debug'' shows log lines on stderr. Root with no flag
		 * opens registration. The Unix socket is ''argus.sock''
		 * under {@link Argus.SERVER_DATA_DIR}.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when the command finished, otherwise the
		 *   usage, connect, or call error
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			OLLMrpc.rpc_register();
			Argus.Shared.Agent.rpc_register();
			Argus.Shared.SQT.Task.rpc_register();
			Argus.Shared.SQT.TaskTarget.rpc_register();
			Argus.Shared.SQT.Script.rpc_register();
			Argus.Shared.SQT.ScriptRepository.rpc_register();
			Argus.Controller.Command.rpc_register();
			pin = false;
			agents = false;
			agent = "";
			command = "";
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
			var removing = deregister_name != "";
			var chosen = (pin ? 1 : 0)
				+ (agents ? 1 : 0)
				+ (removing ? 1 : 0)
				+ (agent != "" || command != "" ? 1 : 0);
			var usage = """Usage:
  argusrm-controller-cli
  argusrm-controller-cli --pin
  argusrm-controller-cli --agents
  argusrm-controller-cli --deregister NAME
  argusrm-controller-cli --agent ID --command COMMAND...
""";
			if (chosen > 1) {
				command_line.printerr("%s", usage);
				return 1;
			}
			if (removing && Posix.geteuid() != 0) {
				command_line.printerr("root is required\n");
				return 1;
			}
			if (chosen == 0) {
#if LINUX
				if (Posix.geteuid() == 0) {
					pin = true;
				}
#endif
				if (!pin) {
					command_line.printerr("%s", usage);
					return 1;
				}
			}
			if (agent == "" && !pin && !agents && !removing) {
				command_line.printerr("command needs --agent ID\n");
				return 1;
			}
			var parts = new Gee.ArrayList<string>();
			if (command != "") {
				parts.add(command);
			}
			parts.add_all_array(leftover[1:leftover.length]);
			if (!pin && !agents && !removing && parts.size < 1) {
				command_line.printerr("command needs --command\n");
				return 1;
			}
			command = string.joinv(" ", parts.to_array());
			this.cli = command_line;
			this.rpc = new OLLMrpc.Client("", "",
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock")) {
				live_handles = true
			};
			this.rpc.debug = false;
			this.loop = new GLib.MainLoop();
			this.code = 1;
			this.cli.print("Connecting to the local Argus Remote Manager server...\n");
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
				this.cli.printerr("%s\n", this.rpc.connect_error);
				this.loop.quit();
				return;
			}
			if (pin) {
				new Pin(this).run();
				return;
			}
			if (agents) {
				new Agents(this).run();
				return;
			}
			if (deregister_name != "") {
				this.rpc.call.begin(new OLLMrpc.Request() {
					method = "Registration.deregister",
					args = OLLMrpc.args("s", deregister_name)
				}, (call_obj, call_res) => {
					try {
						var response = this.rpc.call.end(call_res);
						if (response.error != null) {
							this.cli.printerr("%s\n", response.error.message);
							this.loop.quit();
							return;
						}
					} catch (GLib.Error e) {
						this.cli.printerr("%s\n", e.message);
						this.loop.quit();
						return;
					}
					this.cli.print("Deregistered %s.\n", deregister_name);
					this.code = 0;
					this.loop.quit();
				});
				return;
			}
			var command = new Command(this);
			command.ref();
			command.stdout.connect((text) => {
				this.cli.print("%s", text);
			});
			command.stderr.connect((text) => {
				this.cli.printerr("%s", text);
			});
			command.ended.connect(() => {
				this.code = 0;
				this.loop.quit();
			});
			command.run();
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
				var log_file_path = GLib.Path.build_filename(log_dir, "controller-cli.log");
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
