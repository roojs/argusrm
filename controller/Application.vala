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
	 * Command-line controller for Argus.
	 *
	 * A {@link GLib.Application} with no drawing. {@link command_line}
	 * hellos on the Unix socket, then runs one of {@link Pin},
	 * {@link Agents}, or {@link Command}. No flag prints usage.
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
		private const GLib.OptionEntry[] app_options = {
			{ "pin", 0, 0, GLib.OptionArg.NONE, ref pin, "Show a registration PIN", null },
			{ "agents", 0, 0, GLib.OptionArg.NONE, ref agents, "List registered agents", null },
			{ "agent", 0, 0, GLib.OptionArg.STRING, ref agent, "Agent id", "ID" },
			{ "command", 0, 0, GLib.OptionArg.STRING, ref command, "Command to run", "COMMAND" },
			{ null }
		};
		public GLib.ApplicationCommandLine cli { get; set; }
		public OLLMrpc.Client rpc { get; set; }
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
		}

		/**
		 * Parse the flags, hello, then run one command.
		 *
		 * The Unix socket is ''argus.sock'' under
		 * {@link Argus.SERVER_DATA_DIR}.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when the command finished, otherwise the
		 *   usage, connect, or call error
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			OLLMrpc.rpc_register();
			Argus.Shared.Agent.rpc_register();
			Argus.Controller.Command.rpc_register();
			pin = false;
			agents = false;
			agent = "";
			command = "";
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
			var chosen = 0;
			chosen += pin ? 1 : 0;
			chosen += agents ? 1 : 0;
			chosen += agent != "" || command != "" ? 1 : 0;
			if (chosen != 1) {
				command_line.printerr("Usage:\n  argus-controller --pin\n  argus-controller --agents\n  argus-controller --agent ID --command COMMAND...\n");
				return 1;
			}
			if (agent == "" && !pin && !agents) {
				command_line.printerr("command needs --agent ID\n");
				return 1;
			}
			var parts = new Gee.ArrayList<string>();
			if (command != "") {
				parts.add(command);
			}
			parts.add_all_array(leftover[1:leftover.length]);
			if (!pin && !agents && parts.size < 1) {
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
			this.cli.print("Connecting to the local Argus server...\n");
			this.rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
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
				var order = new Command(this);
				order.stdout.connect((text) => {
					this.cli.print("%s", text);
				});
				order.stderr.connect((text) => {
					this.cli.printerr("%s", text);
				});
				order.ended.connect(() => {
					this.code = 0;
					this.loop.quit();
				});
				order.run();
			});
			this.loop.run();
			return this.code;
		}
	}

	int main(string[] args)
	{
		var app = new Application();
		return app.run(args);
	}
}
