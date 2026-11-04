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
	 * Placeholder command on Android.
	 *
	 * The wire name is ''Argus.Command''. The properties match
	 * the Linux and Windows class. {@link run} does not spawn.
	 * How a phone would run a command is still open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Agent.Command();
	 * order.identifier = "1";
	 * order.command = "true";
	 * order.run(link);
	 * }}}
	 */
	public class Command : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * Register the wire name ''Argus.Command''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Command", typeof(Command));
		}

		/**
		 * Run identifier from the server.
		 */
		public string identifier { get; set; default = ""; }

		/**
		 * Command line. {@link run} does not execute it.
		 */
		public string command { get; set; default = ""; }

		/**
		 * Environment, each entry ''NAME=value''.
		 *
		 * Empty inherits this process.
		 */
		public string[] environment { get; set; default = {}; }

		/**
		 * Working directory. Empty inherits this process.
		 */
		public string cwd { get; set; default = ""; }

		/**
		 * One call at a time on the shared app socket.
		 */
		internal static GLib.Mutex send_lock;

		/**
		 * Commands accepted so far, keyed by {@link identifier}.
		 *
		 * {@link send} is the follow-up on that command.
		 */
		internal static Gee.HashMap<string, Command> running;

		/**
		 * Accept the command and report that it started.
		 *
		 * Sends ''Command.stdout'' with an empty chunk.
		 * No process is spawned.
		 *
		 * @param link app socket already open
		 */
		public void run(OLLMrpc.Transport.TlsClient link)
		{
			GLib.warning("command %s was not run", this.identifier);
			Command.send_lock.lock();
			if (Command.running == null) {
				Command.running = new Gee.HashMap<string, Command>();
			}
			Command.running.set(this.identifier, this);
			Command.send_lock.unlock();
			try {
				var response = link.call(new OLLMrpc.Request() {
					method = "Command.stdout",
					args = OLLMrpc.args("ss", this.identifier, "")
				});
				if (response.error != null) {
					GLib.warning("command %d", response.error.code);
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}

		/**
		 * Follow up on this command. Android does not write.
		 *
		 * @param text bytes that would go to stdin
		 */
		public void send(string text)
		{
			GLib.warning("command %s was not run", this.identifier);
		}
	}
}
