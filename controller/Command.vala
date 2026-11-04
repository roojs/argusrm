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
	 * Run one command on a registered agent.
	 *
	 * The wire alias is ''Argus.Command''. {@link run} sends
	 * ''Command.run'' on the Unix socket. Notifications emit
	 * {@link stdout}, {@link stderr}, and {@link ended}.
	 * The CLI connects those. A desktop can draw them.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Controller.Command(app);
	 * order.stdout.connect((text) => { });
	 * order.run();
	 * }}}
	 */
	public class Command : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public Application app;
		public int identifier { get; set; default = 0; }
		private static int next_identifier = 1;
		public string command { get; set; default = ""; }
		public string[] environment { get; set; default = {}; }
		public string cwd { get; set; default = ""; }

		public signal void stdout(string text);
		public signal void stderr(string text);
		public signal void ended();

		public Command(Application app)
		{
			this.app = app;
		}

		/**
		 * Register the outbound command object.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Command", typeof(Command));
		}

		/**
		 * Send the command.
		 */
		public void run()
		{
			var id = (int64) 0;
			if (!int64.try_parse(Application.agent, out id) || id < 1) {
				this.stderr("command needs an agent id\n");
				this.ended();
				return;
			}
			this.identifier = Command.next_identifier++;
			this.command = Application.command;
			this.app.rpc.notification.connect((notification) => {
				if (notification.args.size < 1) {
					return;
				}
				if (notification.args.get(0).get_int() != this.identifier) {
					return;
				}
				if (notification.method == "controller.ended") {
					this.ended();
					return;
				}
				if (notification.args.size < 2) {
					return;
				}
				var text = notification.args.get(1).get_string();
				if (notification.method == "controller.stdout") {
					this.stdout(text);
					return;
				}
				if (notification.method == "controller.stderr") {
					this.stderr(text);
				}
			});
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Command.run",
				args = OLLMrpc.args("xo", id, this)
			}, this.on_reply);
		}

		/**
		 * Take the ''Command.run'' reply.
		 *
		 * @param rpc the Unix client
		 * @param res the finished call
		 */
		public void on_reply(GLib.Object? rpc, GLib.AsyncResult res)
		{
			try {
				var response = this.app.rpc.call.end(res);
				if (response.error != null) {
					this.stderr(response.error.message + "\n");
					this.ended();
				}
			} catch (GLib.Error e) {
				this.stderr(e.message + "\n");
				this.ended();
			}
		}
	}
}
