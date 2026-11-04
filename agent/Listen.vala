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

namespace Argus.Agent
{
	/**
	 * Notifications on the open app socket.
	 *
	 * An ''agent.run'' notification carries an ''Argus.Command''.
	 * {@link notification} hands that object to {@link Command.run}.
	 * An ''agent.send'' notification carries the run id and text,
	 * and {@link Command.send} writes that text to the command's
	 * stdin. Any other method returns. Linux, Windows, and
	 * Android each compile their own {@link Command}.
	 * {@link OLLMrpc.Transport.TlsClient.call} only returns a
	 * response, so {@link start} does not pull a notification yet.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new Argus.Agent.Listen(link).start();
	 * }}}
	 */
	public class Listen : GLib.Object
	{
		/**
		 * App socket opened by {@link Application.open_link}.
		 */
		private OLLMrpc.Transport.TlsClient link;

		/**
		 * @param link app socket already open
		 */
		public Listen(OLLMrpc.Transport.TlsClient link)
		{
			this.link = link;
		}

		/**
		 * Watch the app socket for notifications.
		 *
		 * Returns without a read. The socket type has no call that
		 * yields a {@link OLLMrpc.Notification}.
		 */
		public void start()
		{
			GLib.debug("command notifications wait on the app socket");
		}

		/**
		 * Run a command notification, or follow up on one.
		 *
		 * ''agent.run'' hands the ''Argus.Command'' to {@link Command.run}.
		 * ''agent.send'' writes its text to the stdin of the command with
		 * that id. Any other method returns.
		 *
		 * @param notification notification from the app socket
		 */
		public void notification(OLLMrpc.Notification notification)
		{
			switch (notification.method) {
				case "agent.send":
					if (notification.args.size < 2) {
						return;
					}
					var id_value = notification.args.get(0);
					var text_value = notification.args.get(1);
					if (id_value == null || text_value == null) {
						return;
					}
					if (!id_value.holds(typeof(string)) ||
						!text_value.holds(typeof(string))) {
						return;
					}
					var identifier = id_value.get_string();
					Command.send_lock.lock();
					Command order = null;
					if (Command.running != null &&
						Command.running.has_key(identifier)) {
						order = Command.running.get(identifier);
					}
					Command.send_lock.unlock();
					if (order == null) {
						GLib.warning("command %s is not running", identifier);
						return;
					}
					order.send(text_value.get_string());
					return;
				case "agent.run":
					if (notification.args.size == 0) {
						return;
					}
					var value = notification.args.get(0);
					if (value == null) {
						return;
					}
					if (!value.holds(typeof(GLib.Object))) {
						return;
					}
					var obj = value.get_object();
					if (!(obj is Command)) {
						return;
					}
					var command = (Command) obj;
					command.run(this.link);
					return;
				default:
					return;
			}
		}
	}
}
