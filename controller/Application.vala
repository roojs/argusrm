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
	 * With no command on a desktop, {@link Bootstrap} checks saved
	 * connections and may open {@link Window}. {@link command_line}
	 * hellos on the Unix socket, then runs one of {@link Pin},
	 * {@link Agents}, or {@link Command}. No flag on a headless
	 * root machine opens registration. Any other headless launch
	 * with no flag prints usage.
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
		public static string give_certificate;
		public static string agent;
		public static string command;
		private const GLib.OptionEntry[] app_options = {
			{ "pin", 0, 0, GLib.OptionArg.NONE, ref pin, "Show a registration PIN", null },
			{ "agents", 0, 0, GLib.OptionArg.NONE, ref agents, "List registered agents", null },
			{ "give-me-a-certificate", 0, 0, GLib.OptionArg.STRING, ref give_certificate, "Issue a local controller certificate", "USERNAME" },
			{ "agent", 0, 0, GLib.OptionArg.STRING, ref agent, "Agent id", "ID" },
			{ "command", 0, 0, GLib.OptionArg.STRING, ref command, "Command to run", "COMMAND" },
			{ null }
		};
		public GLib.ApplicationCommandLine cli { get; set; }
		public OLLMrpc.Client rpc { get; set; }
		/**
		 * Main window opened after a connection answers.
		 */
		public Window window { get; set; }
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
		 * Parse the flags, then run one command or the startup window.
		 *
		 * No flag on a desktop opens {@link Bootstrap}. No flag on a
		 * headless root machine opens registration. The Unix socket
		 * is ''argus.sock'' under {@link Argus.SERVER_DATA_DIR}.
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
			Argus.Controller.Command.rpc_register();
			pin = false;
			agents = false;
			give_certificate = "";
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
			var chosen = (pin ? 1 : 0)
				+ (agents ? 1 : 0)
				+ (give_certificate != "" ? 1 : 0)
				+ (agent != "" || command != "" ? 1 : 0);
			if (chosen > 1) {
				command_line.printerr("Usage:\n  argus-controller --pin\n  argus-controller --agents\n  argus-controller --give-me-a-certificate USERNAME\n  argus-controller --agent ID --command COMMAND...\n");
				return 1;
			}
			if (chosen == 0) {
				var display = GLib.Environment.get_variable("DISPLAY");
				var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				var headless = (display == null || display == "") && (wayland == null || wayland == "");
				if (headless) {
#if LINUX
					if (Posix.geteuid() == 0) {
						pin = true;
					}
#endif
					if (!pin) {
						command_line.printerr("Usage:\n  argus-controller --pin\n  argus-controller --agents\n  argus-controller --give-me-a-certificate USERNAME\n  argus-controller --agent ID --command COMMAND...\n");
						return 1;
					}
				}
				if (!headless) {
					Gtk.init();
					var bootstrap = new Bootstrap(this);
					bootstrap.present(null);
					this.hold();
					return 0;
				}
			}
#if LINUX
			if (give_certificate != "" && Posix.geteuid() != 0) {
				var data = new Argus.Shared.Registration.Data() {
					error = "root is required"
				};
				command_line.print("%s\n", Json.gobject_to_data(data, null));
				return 1;
			}
#else
			if (give_certificate != "") {
				var data = new Argus.Shared.Registration.Data() {
					error = "local certificate issue is Linux only"
				};
				command_line.print("%s\n", Json.gobject_to_data(data, null));
				return 1;
			}
#endif
			if (agent == "" && !pin && !agents && give_certificate == "") {
				command_line.printerr("command needs --agent ID\n");
				return 1;
			}
			var parts = new Gee.ArrayList<string>();
			if (command != "") {
				parts.add(command);
			}
			if (give_certificate == "") {
				parts.add_all_array(leftover[1:leftover.length]);
			}
			if (!pin && !agents && give_certificate == "" && parts.size < 1) {
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
			if (give_certificate == "") {
				this.cli.print("Connecting to the local Argus server...\n");
			}
			this.rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, this.on_connect);
			this.loop.run();
			return this.code;
		}

		/**
		 * Handle the completed connection to the local Argus server.
		 *
		 * @param rpc the Unix client
		 * @param res the finished connection
		 */
		public void on_connect(GLib.Object? rpc, GLib.AsyncResult res)
		{
			var opened = this.rpc.connect.end(res);
			if (!opened) {
				if (give_certificate != "") {
					var data = new Argus.Shared.Registration.Data() {
						error = this.rpc.connect_error
					};
					this.cli.print("%s\n", Json.gobject_to_data(data, null));
				}
				if (give_certificate == "") {
					this.cli.printerr("%s\n", this.rpc.connect_error);
				}
				this.loop.quit();
				return;
			}
			if (give_certificate != "") {
				this.rpc.call.begin(new OLLMrpc.Request() {
					method = "Registration.certificate",
					args = OLLMrpc.args("s", give_certificate)
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
	}
}
