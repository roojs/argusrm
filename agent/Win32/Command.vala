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
	 * Run one command on Windows.
	 *
	 * The wire name is ''Argus.Command''. {@link run} spawns
	 * ''cmd.exe /c'' with the working directory and the environment, then
	 * waits with {@link GLib.IOChannel.win32_poll}. Stdout goes out as
	 * ''Command.stdout''. Stderr goes out as ''Command.stderr''. An empty
	 * working directory or an empty environment inherits this process.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Agent.Command();
	 * order.identifier = "1";
	 * order.command = "hostname";
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
		 * Command line. {@link run} passes it to ''cmd.exe /c''.
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
		internal static Gee.HashMap<string, Command> running;

		/**
		 * Stdin of the child. Left open so a later write can reach the
		 * command.
		 */
		private int stdin_fd = -1;

		/**
		 * Spawn this command and send its output.
		 *
		 * Stdout bytes are ''Command.stdout''. Stderr bytes are
		 * ''Command.stderr''. Each call is that chunk.
		 *
		 * @param link app socket already open
		 */
		public void run(OLLMrpc.Transport.TlsClient link)
		{
			new GLib.Thread<int>("command", () => {
				this.spawn(link);
				return 0;
			});
		}

		/**
		 * Spawn this command and poll its stdout and stderr.
		 *
		 * Stdin stays open. Stdout bytes are ''Command.stdout''. Stderr bytes
		 * are ''Command.stderr''.
		 *
		 * @param link app socket already open
		 */
		private void spawn(OLLMrpc.Transport.TlsClient link)
		{
			string[] argv = { "cmd.exe", "/c", this.command };
			GLib.Pid child;
			int stdin_fd;
			int stdout_fd;
			int stderr_fd;
			try {
				GLib.Process.spawn_async_with_pipes(
					this.cwd != "" ? this.cwd : null,
					argv,
					this.environment.length > 0 ? this.environment : null,
					GLib.SpawnFlags.SEARCH_PATH,
					null,
					out child,
					out stdin_fd,
					out stdout_fd,
					out stderr_fd);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			GLib.debug("command %s pid %d", this.identifier, (int) child);
			this.stdin_fd = stdin_fd;
			Command.send_lock.lock();
			if (Command.running == null) {
				Command.running = new Gee.HashMap<string, Command>();
			}
			Command.running.set(this.identifier, this);
			Command.send_lock.unlock();
			var stdout_channel = new GLib.IOChannel.win32_new_fd(stdout_fd);
			var stderr_channel = new GLib.IOChannel.win32_new_fd(stderr_fd);
			stdout_channel.set_close_on_unref(true);
			stderr_channel.set_close_on_unref(true);
			stdout_channel.set_buffered(false);
			stderr_channel.set_buffered(false);
			try {
				stdout_channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				stderr_channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				stdout_channel.set_flags(GLib.IOFlags.NONBLOCK);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				stderr_channel.set_flags(GLib.IOFlags.NONBLOCK);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			var stdout_open = true;
			var stderr_open = true;
			var wait = 200;
			while (stdout_open || stderr_open) {
				var out_fd = GLib.PollFD();
				var err_fd = GLib.PollFD();
				out_fd.fd = -1;
				err_fd.fd = -1;
				if (stdout_open) {
					stdout_channel.win32_make_pollfd(
						GLib.IOCondition.IN | GLib.IOCondition.HUP, ref out_fd);
				}
				if (stderr_open) {
					stderr_channel.win32_make_pollfd(
						GLib.IOCondition.IN | GLib.IOCondition.HUP, ref err_fd);
				}
				GLib.PollFD[] polls = { out_fd, err_fd };
				var ready = GLib.IOChannel.win32_poll(polls, wait);
				if (ready < 0) {
					GLib.warning("poll failed");
					break;
				}
				string[] methods = {};
				string[] texts = {};
				var out_ready = stdout_open &&
					(polls[0].revents & (GLib.IOCondition.IN | GLib.IOCondition.HUP)) != 0;
				if (out_ready) {
					char[] buf = new char[4096];
					size_t got = 0;
					GLib.IOStatus status = GLib.IOStatus.NORMAL;
					try {
						status = stdout_channel.read_chars(buf, out got);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						stdout_open = false;
						status = GLib.IOStatus.ERROR;
					}
					if (status == GLib.IOStatus.EOF ||
						(got == 0 && (polls[0].revents & GLib.IOCondition.HUP) != 0)) {
						stdout_open = false;
					}
					if (got > 0) {
						var raw = new uint8[got + 1];
						GLib.Memory.copy(raw, buf, got);
						methods += "Command.stdout";
						texts += (string) raw;
					}
				}
				var err_ready = stderr_open &&
					(polls[1].revents & (GLib.IOCondition.IN | GLib.IOCondition.HUP)) != 0;
				if (err_ready) {
					char[] buf = new char[4096];
					size_t got = 0;
					GLib.IOStatus status = GLib.IOStatus.NORMAL;
					try {
						status = stderr_channel.read_chars(buf, out got);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						stderr_open = false;
						status = GLib.IOStatus.ERROR;
					}
					if (status == GLib.IOStatus.EOF ||
						(got == 0 && (polls[1].revents & GLib.IOCondition.HUP) != 0)) {
						stderr_open = false;
					}
					if (got > 0) {
						var raw = new uint8[got + 1];
						GLib.Memory.copy(raw, buf, got);
						methods += "Command.stderr";
						texts += (string) raw;
					}
				}
				if (methods.length > 0) {
					wait = -1;
				}
				for (var i = 0; i < methods.length; i++) {
					Command.send_lock.lock();
					try {
						var response = link.call(new OLLMrpc.Request() {
							method = methods[i],
							args = OLLMrpc.args("ss", this.identifier, texts[i])
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
			Command.send_lock.lock();
			try {
				link.call(new OLLMrpc.Request() {
					method = "Command.ended",
					args = OLLMrpc.args("s", this.identifier)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			Command.send_lock.unlock();
		}

		/**
		 * Write text to this command's stdin.
		 *
		 * A missing handle is logged. The text is the follow-up from an
		 * ''agent.send'' notification. The handle stays open.
		 *
		 * @param text bytes for this command's stdin
		 */
		public void send(string text)
		{
			if (this.stdin_fd < 0) {
				GLib.warning("command %s is not running", this.identifier);
				return;
			}
			var channel = new GLib.IOChannel.win32_new_fd(this.stdin_fd);
			channel.set_close_on_unref(false);
			channel.set_buffered(false);
			try {
				channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				size_t wrote;
				channel.write_chars((char[]) text.data, out wrote);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				channel.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}
	}
}
