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
	 * Registration PIN on the command line.
	 *
	 * Creates a six-digit pin, prints it, and sends it with
	 * ''Agent.pair''. Sixty seconds later it sends an empty
	 * pin. {@link Application} already hellos.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new Argus.Controller.Pin(app).run();
	 * }}}
	 */
	public class Pin : GLib.Object
	{
		public Application app;

		public Pin(Application app)
		{
			this.app = app;
		}

		/**
		 * Open the registration PIN.
		 */
		public void run()
		{
			var n = GLib.Random.int_range(0, 1000000);
			var pin = "%06d".printf(n);
			this.app.cli.print("Registration PIN: %s\nRegistration is open for 60 seconds. Press Ctrl+C to close it early.\n", pin);
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.pair",
				args = OLLMrpc.args("s", pin)
			}, (obj, res) => {
				try {
					var response = this.app.rpc.call.end(res);
					if (response.error != null) {
						this.app.cli.printerr("%s\n", response.error.message);
						this.app.loop.quit();
						return;
					}
					if (response.msg == "used") {
						this.app.cli.print("Registration PIN has been used.\n");
					}
				} catch (GLib.Error e) {
					this.app.cli.printerr("%s\n", e.message);
					this.app.loop.quit();
					return;
				}
				this.app.code = 0;
				this.app.loop.quit();
			});
			GLib.Timeout.add_seconds(60, () => {
				this.app.rpc.call.begin(new OLLMrpc.Request() {
					method = "Agent.pair",
					args = OLLMrpc.args("s", "")
				}, (obj, res) => {
					try {
						this.app.rpc.call.end(res);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				});
				return false;
			});
		}
	}
}
