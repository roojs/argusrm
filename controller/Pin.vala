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
	 * Asks ''Agent.offer'' for a six-digit pin and prints it.
	 * The number lasts sixty seconds. {@link Application}
	 * already hellos.
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
			this.app.rpc.notification.connect((notification) => {
				if (notification.method != "event.pair" || notification.action != "done") {
					return;
				}
				this.app.cli.print("Registration PIN has been used.\n");
				this.app.code = 0;
				this.app.loop.quit();
			});
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.offer"
			}, (obj, res) => {
				try {
					var response = this.app.rpc.call.end(res);
					if (response.error != null) {
						this.app.cli.printerr("%s\n", response.error.message);
						this.app.loop.quit();
						return;
					}
					var pin = response.retval as string;
					if (pin == null || pin.length != 6) {
						this.app.cli.printerr("The server did not return a number.\n");
						this.app.loop.quit();
						return;
					}
					this.app.cli.print("Registration PIN: %s\nRegistration is open for 60 seconds. Press Ctrl+C to close it early.\n", pin);
				} catch (GLib.Error e) {
					this.app.cli.printerr("%s\n", e.message);
					this.app.loop.quit();
					return;
				}
			});
			GLib.Timeout.add_seconds(60, () => {
				this.app.code = 0;
				this.app.loop.quit();
				return false;
			});
		}
	}
}
