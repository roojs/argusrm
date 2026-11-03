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
	 * Command-line registration window.
	 *
	 * A {@link GLib.Application} with no drawing. {@link command_line}
	 * creates a six-digit pin, the same range as
	 * ''PairingDialog.open'', prints it, and sends it with
	 * ''ClientCert.pair''. Sixty seconds later it sends an empty
	 * pin and exits.
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
		 * Open the registration window for sixty seconds.
		 *
		 * Prints the pin after Argus accepts it. The Unix socket
		 * is ''argus.sock'' under {@link LOCALSTATEDIR}.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when the window was opened, otherwise the
		 *   connect or pair error
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			OLLMrpc.rpc_register();
			var n = GLib.Random.int_range(0, 1000000);
			var pin = "%06d".printf(n);
			var rpc = new OLLMrpc.Client("", "",
				GLib.Path.build_filename(LOCALSTATEDIR, "argus.sock"));
			rpc.debug = false;
			var loop = new GLib.MainLoop();
			var code = 1;
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				var opened = rpc.connect.end(res);
				if (!opened) {
					command_line.printerr("%s\n", rpc.connect_error);
					loop.quit();
					return;
				}
				rpc.call.begin(new OLLMrpc.Request() {
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				}, (obj, res) => {
					try {
						var response = rpc.call.end(res);
						if (response.error != null) {
							command_line.printerr("%s\n", response.error.message);
							loop.quit();
							return;
						}
					} catch (GLib.Error e) {
						command_line.printerr("%s\n", e.message);
						loop.quit();
						return;
					}
					command_line.print("%s\n", pin);
					GLib.Timeout.add_seconds(60, () => {
						rpc.call.begin(new OLLMrpc.Request() {
							method = "ClientCert.pair",
							args = OLLMrpc.args("s", "")
						}, (obj, res) => {
							try {
								rpc.call.end(res);
							} catch (GLib.Error e) {
								GLib.warning("%s", e.message);
							}
							code = 0;
							loop.quit();
						});
						return false;
					});
				});
			});
			loop.run();
			return code;
		}
	}

	int main(string[] args)
	{
		var app = new Application();
		return app.run(args);
	}
}
