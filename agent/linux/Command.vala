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
	 * Run one command on Linux.
	 *
	 * The wire name is ''Argus.Command''. {@link run} spawns ''sh -c''
	 * with the working directory and the environment. Stdin, stdout, and
	 * stderr stay open on the child. Stdout and stderr are watched with
	 * {@link GLib.IOChannel.add_watch}, the same read used for a bubble
	 * command. Stdout lines go out as ''Command.stdout''. Stderr lines go
	 * out as ''Command.stderr''. An empty working directory or an empty
	 * environment inherits this process.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Agent.Command();
	 * order.identifier = 1;
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
		public int identifier { get; set; default = 0; }

		/**
		 * Command line. {@link run} passes it to ''sh -c''.
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
		 * Commands still running, keyed by {@link identifier}.
		 *
		 * {@link send} writes the follow-up text to that command's stdin.
		 */
		internal static Gee.HashMap<int, Command> running;

		/**
		 * Child. Its stdin, stdout, and stderr pipes stay open.
		 */
		private GLib.Subprocess child;

		/**
		 * App socket for {@link Command.stdout} and {@link Command.stderr}.
		 */
		private OLLMrpc.Transport.TlsClient link;

		/**
		 * Stdin of {@link child}. Left open so a later write can reach the
		 * command.
		 */
		private GLib.OutputStream stdin_pipe;

		/**
		 * Stdout of {@link child}.
		 */
		private GLib.InputStream stdout_pipe;

		/**
		 * Stderr of {@link child}.
		 */
		private GLib.InputStream stderr_pipe;

		/**
		 * Spawn this command and watch stdout and stderr.
		 *
		 * Returns after the watches are attached. Stdout lines are
		 * ''Command.stdout''. Stderr lines are ''Command.stderr''. Each call
		 * is that chunk.
		 *
		 * @param link app socket already open
		 */
		public void run(OLLMrpc.Transport.TlsClient link)
		{
			this.link = link;
			string[] argv = { "sh", "-c", this.command };
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDIN_PIPE |
				GLib.SubprocessFlags.STDOUT_PIPE |
				GLib.SubprocessFlags.STDERR_PIPE);
			if (this.cwd != "") {
				launcher.set_cwd(this.cwd);
			}
			if (this.environment.length > 0) {
				launcher.set_environ(this.environment);
			}
			GLib.Subprocess child;
			try {
				child = launcher.spawnv(argv);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			this.child = child;
			GLib.debug("command %d", this.identifier);
			var stdin_pipe = child.get_stdin_pipe();
			var stdout_pipe = child.get_stdout_pipe();
			var stderr_pipe = child.get_stderr_pipe();
			if (stdin_pipe == null || stdout_pipe == null || stderr_pipe == null) {
				GLib.warning("command is missing a pipe");
				return;
			}
			this.stdin_pipe = stdin_pipe;
			this.stdout_pipe = stdout_pipe;
			this.stderr_pipe = stderr_pipe;
			Command.send_lock.lock();
			if (Command.running == null) {
				Command.running = new Gee.HashMap<int, Command>();
			}
			Command.running.set(this.identifier, this);
			Command.send_lock.unlock();
			var unix_out = this.stdout_pipe as GLib.UnixInputStream;
			var unix_err = this.stderr_pipe as GLib.UnixInputStream;
			if (unix_out == null || unix_err == null) {
				GLib.warning("command pipes are not unix streams");
				return;
			}
			var stdout_ch = new GLib.IOChannel.unix_new(unix_out.get_fd());
			var stderr_ch = new GLib.IOChannel.unix_new(unix_err.get_fd());
			try {
				stdout_ch.set_flags(GLib.IOFlags.NONBLOCK);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				stderr_ch.set_flags(GLib.IOFlags.NONBLOCK);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			stdout_ch.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(channel, condition) => {
					if ((condition & GLib.IOCondition.IN) != 0) {
						this.read_channel(channel, "Command.stdout");
					}
					if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						return false;
					}
					return true;
				});
			stderr_ch.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(channel, condition) => {
					if ((condition & GLib.IOCondition.IN) != 0) {
						this.read_channel(channel, "Command.stderr");
					}
					if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						return false;
					}
					return true;
				});
			this.child.wait_async.begin(null, (obj, res) => {
				try {
					this.child.wait_async.end(res);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				try {
					this.link.call(new OLLMrpc.Request() {
						method = "Command.ended",
						args = OLLMrpc.args("i", this.identifier)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			});
		}

		/**
		 * Read ready lines from one pipe and send them.
		 *
		 * @param channel stdout or stderr of {@link child}
		 * @param method ''Command.stdout'' or ''Command.stderr''
		 */
		private void read_channel(GLib.IOChannel channel, string method)
		{
			while (true) {
				string buffer = "";
				size_t len = 0;
				size_t term = 0;
				GLib.IOStatus status = GLib.IOStatus.NORMAL;
				try {
					status = channel.read_line(out buffer, out len, out term);
				} catch (GLib.Error e) {
					return;
				}
				if (status != GLib.IOStatus.NORMAL || len == 0) {
					return;
				}
				this.report(method, buffer);
			}
		}

		/**
		 * Write text to this command's stdin.
		 *
		 * A missing pipe is logged. The text is the follow-up from an
		 * ''agent.send'' notification.
		 *
		 * @param text bytes for this command's stdin
		 */
		public void send(string text)
		{
			if (this.stdin_pipe == null) {
				GLib.warning("command %d is not running", this.identifier);
				return;
			}
			try {
				this.stdin_pipe.write(text.data);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				this.stdin_pipe.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}

		/**
		 * Send one command call on the app socket.
		 *
		 * @param method ''Command.stdout'' or ''Command.stderr''
		 * @param text output from the child
		 */
		private void report(string method, string text)
		{
			Command.send_lock.lock();
			try {
				var response = this.link.call(new OLLMrpc.Request() {
					method = method,
					args = OLLMrpc.args("is", this.identifier, text)
				});
				if (response.error != null) {
					GLib.warning("command %d", response.error.code);
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			Command.send_lock.unlock();
		}
	}
}
