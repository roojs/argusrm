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
	 * Registered machines on the command line.
	 *
	 * Calls ''Agent.list'' on the hellod client. {@link reply}
	 * prints ''id'' and ''requester''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new Argus.Controller.Agents(app).run();
	 * }}}
	 */
	public class Agents : GLib.Object
	{
		public Application app;

		public Agents(Application app)
		{
			this.app = app;
		}

		/**
		 * Fetch the agent list.
		 */
		public void run()
		{
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.list"
			}, this.reply);
		}

		/**
		 * Print ''id'' and ''requester'' from ''Agent.list''.
		 *
		 * @param rpc the Unix client
		 * @param res the finished call
		 */
		public void reply(GLib.Object? rpc, GLib.AsyncResult res)
		{
			try {
				var response = this.app.rpc.call.end(res);
				if (response.error != null) {
					this.app.cli.printerr("%s\n", response.error.message);
					this.app.loop.quit();
					return;
				}
				var rows = (Gee.ArrayList<Argus.Shared.Agent>) response.retval;
				foreach (var row in rows) {
					this.app.cli.print("%lld %s\n", row.id, row.requester);
				}
			} catch (GLib.Error e) {
				this.app.cli.printerr("%s\n", e.message);
				this.app.loop.quit();
				return;
			}
			this.app.code = 0;
			this.app.loop.quit();
		}
	}
}
