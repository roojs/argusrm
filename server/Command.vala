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

namespace Argus.Server
{
	/**
	 * One command the server asks an agent to run.
	 *
	 * The wire name is ''Argus.Command''. A task dispatch writes
	 * ''agent.run'' on that agent's app-socket connection. {@link send}
	 * writes a follow-up to the same connection. {@link stdout} and
	 * {@link stderr} are the chunks the agent sends back. Stdin, stdout,
	 * and stderr are appended under {@link Argus.LOG_DIR}, then a client
	 * notification goes to a controller watching that target when
	 * that connection is still up. An unwatched target is not sent one.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Server.Command();
	 * order.identifier = 1;
	 * order.command = "true";
	 * }}}
	 */
	public class Command : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * Register ''Argus.Command'' and the command calls.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Command", typeof(Command));
			OLLMrpc.Request.add_class(
				"Command", typeof(Command),
				"send", "is",
				"stdout", "is",
				"stderr", "is",
				"ended", "ii"
			);
		}

		/**
		 * Run identifier. Also the output file name.
		 */
		public int identifier { get; set; default = 0; }

		/**
		 * Command line the agent passes to the shell.
		 */
		public string command { get; set; default = ""; }

		/**
		 * Environment, each entry ''NAME=value''.
		 *
		 * Empty inherits the agent process.
		 */
		public string[] environment { get; set; default = {}; }

		/**
		 * Working directory. Empty inherits the agent process.
		 */
		public string cwd { get; set; default = ""; }

		/**
		 * Server that owns the database and the app socket.
		 */
		public Application app { get; private set; }

		/**
		 * Controller connection for each run, keyed by {@link identifier}.
		 */
		private static Gee.HashMap<int, OLLMrpc.Transport.Connection> controllers;

		/**
		 * Agent connection for each run, keyed by {@link identifier}.
		 */
		private static Gee.HashMap<int, Net.SslConnection> agents;

		/**
		 * Log directory for each run, keyed by {@link identifier}.
		 *
		 * {@link run} sets it from the day the command starts.
		 * Stdin, stdout, and stderr append in that directory.
		 */
		private static Gee.HashMap<int, string> logs;

		/**
		 * Controller connection for each watched target, keyed by target id.
		 *
		 * {@link Argus.Server.SQT.Task.run} copies it onto {@link controllers}
		 * when that target is sent.
		 */
		private static Gee.HashMap<int, OLLMrpc.Transport.Connection> tasks;

		private static int next_identifier = 0;

		/**
		 * Empty instance for the bin decoder.
		 */
		public Command()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public Command.for_rpc(Application app)
		{
			Object();
			this.app = app;
			if (Command.agents == null) {
				Command.agents = new Gee.HashMap<int, Net.SslConnection>();
				Command.controllers = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
				Command.logs = new Gee.HashMap<int, string>();
				Command.tasks = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
			}
		}

		/**
		 * Remember the controller watching one target.
		 *
		 * Output for a later dispatch goes to this connection when it is
		 * still up. {@link Argus.Shared.SQT.TaskTarget.is_watched} is the
		 * flag that this stream was asked for.
		 *
		 * @param target_id ''task_target.id''
		 * @param connection controller that asked to watch
		 */
		public static void watch(int target_id, OLLMrpc.Transport.Connection connection)
		{
			if (Command.tasks == null) {
				Command.tasks = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
			}
			Command.tasks.set(target_id, connection);
		}

		/**
		 * Drop the controller remembered for a task.
		 *
		 * @param target_id ''task_target.id''
		 */
		public static void unwatch(int target_id)
		{
			if (Command.tasks != null) {
				Command.tasks.unset(target_id);
			}
		}

		/**
		 * Controller connection stored for a target, or null.
		 *
		 * @param target_id ''task_target.id''
		 * @return the watching connection
		 */
		public static OLLMrpc.Transport.Connection? watcher(int target_id)
		{
			if (Command.tasks == null || !Command.tasks.has_key(target_id)) {
				return null;
			}
			return Command.tasks.get(target_id);
		}

		/**
		 * Tell one agent to run this command.
		 *
		 * The notification method is ''agent.run''. {@link identifier} is
		 * assigned here when it is still 0. The watching controller receives
		 * later output for that identifier.
		 *
		 * @param agent_id ''agent.id'' of the machine that runs it
		 * @param order command to send
		 * @param controller watching connection, or null
		 * @param error reason the send did not happen
		 * @return true when ''agent.run'' was written
		 */
		public bool dispatch(int64 agent_id, Command order,
			OLLMrpc.Transport.Connection? controller, out string error)
		{
			error = "unknown agent";
			if (agent_id < 1 || this.app == null || this.app.ssl_listen == null) {
				return false;
			}
			foreach (var connection in this.app.ssl_listen.connections) {
				if (!connection.running || connection.user.id != agent_id) {
					continue;
				}
				var now = new GLib.DateTime.now_local();
				var dir = GLib.Path.build_filename(Argus.LOG_DIR, "commands",
					now.format("%Y"), now.format("%m"), now.format("%d"));
				if (GLib.DirUtils.create_with_parents(dir, 0755) != 0) {
					error = "could not store output";
					return false;
				}
				if (order.identifier < 1) {
					order.identifier = this.allocate_identifier();
				}
				connection.write(new OLLMrpc.Notification() {
					method = "agent.run",
					args = OLLMrpc.args("o", order)
				});
				Command.agents.set(order.identifier, connection);
				Command.logs.set(order.identifier, dir);
				if (controller != null) {
					Command.controllers.set(order.identifier, controller);
				}
				GLib.debug("run command %d on agent %s", order.identifier, agent_id.to_string());
				error = "";
				return true;
			}
			return false;
		}

		/**
		 * Next log identifier, above any identifier already stored.
		 *
		 * @return an identifier of at least 1
		 */
		private int allocate_identifier()
		{
			if (Command.next_identifier == 0 && this.app != null && this.app.db != null) {
				var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
				Argus.Shared.SQT.TaskTarget.query(this.app.db).select("", rows);
				foreach (var row in rows) {
					if (row.identifier > Command.next_identifier) {
						Command.next_identifier = row.identifier;
					}
				}
			}
			Command.next_identifier++;
			return Command.next_identifier;
		}

		/**
		 * Follow up on a command {@link run} already sent.
		 *
		 * The notification method is ''agent.send''. The arguments are the
		 * identifier, then the text. That text is appended to the command's
		 * stdin log. The agent writes it to the command's stdin.
		 *
		 * @param request inbound RPC from a controller
		 * @param identifier {@link Command.identifier} of the run
		 * @param text bytes for the command's stdin
		 */
		public void send(OLLMrpc.Request request, int identifier, string text)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (Command.agents == null || !Command.agents.has_key(identifier) || !Command.agents.get(identifier).running) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).user.id.to_string() + "-" + identifier.to_string() + ".stdin";
			var path = GLib.Path.build_filename(Command.logs.get(identifier), name);
			var stream = GLib.FileStream.open(path, "a");
			if (stream == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not store output")
				});
				return;
			}
			stream.puts(text);
			stream.flush();
			Command.agents.get(identifier).write(new OLLMrpc.Notification() {
				method = "agent.send",
				args = OLLMrpc.args("is", identifier, text)
			});
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Append one stdout chunk and tell the controller.
		 *
		 * The file is the day {@link run} stored, named with the machine id,
		 * the identifier, and ''.stdout''. The controller notification method
		 * is ''controller.stdout'' when the connection that called
		 * {@link run} is still up.
		 *
		 * @param request inbound RPC from the agent
		 * @param identifier {@link Command.identifier} of the run
		 * @param text this stdout chunk
		 */
		public void stdout(OLLMrpc.Request request, int identifier, string text)
		{
			if (Command.agents == null || !Command.agents.has_key(identifier)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user.id != Command.agents.get(identifier).user.id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).user.id.to_string() + "-" + identifier.to_string() + ".stdout";
			var path = GLib.Path.build_filename(Command.logs.get(identifier), name);
			var stream = GLib.FileStream.open(path, "a");
			if (stream == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not store output")
				});
				return;
			}
			stream.puts(text);
			stream.flush();
			if (Command.controllers != null && Command.controllers.has_key(identifier) && Command.controllers.get(identifier).running) {
				Command.controllers.get(identifier).write(new OLLMrpc.Notification() {
					method = "controller.stdout",
					args = OLLMrpc.args("is", identifier, text)
				});
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Append one stderr chunk and tell the controller.
		 *
		 * The file is the stderr name beside {@link stdout}. The controller
		 * notification method is ''controller.stderr'' when the connection
		 * that called {@link run} is still up.
		 *
		 * @param request inbound RPC from the agent
		 * @param identifier {@link Command.identifier} of the run
		 * @param text this stderr chunk
		 */
		public void stderr(OLLMrpc.Request request, int identifier, string text)
		{
			if (Command.agents == null || !Command.agents.has_key(identifier)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user.id != Command.agents.get(identifier).user.id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).user.id.to_string() + "-" + identifier.to_string() + ".stderr";
			var path = GLib.Path.build_filename(Command.logs.get(identifier), name);
			var stream = GLib.FileStream.open(path, "a");
			if (stream == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not store output")
				});
				return;
			}
			stream.puts(text);
			stream.flush();
			if (Command.controllers != null && Command.controllers.has_key(identifier) && Command.controllers.get(identifier).running) {
				Command.controllers.get(identifier).write(new OLLMrpc.Notification() {
					method = "controller.stderr",
					args = OLLMrpc.args("is", identifier, text)
				});
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Tell the controller the child is dead.
		 *
		 * The exit code is stored on the task target that owns this
		 * identifier. The controller notification stays ''controller.ended''
		 * with that identifier.
		 *
		 * @param request inbound RPC from the agent
		 * @param identifier {@link Command.identifier} of the run
		 * @param exit_code process exit code
		 */
		public void ended(OLLMrpc.Request request, int identifier, int exit_code)
		{
			if (Command.agents == null || !Command.agents.has_key(identifier)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user.id != Command.agents.get(identifier).user.id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			if (this.app != null) {
				new Argus.Server.SQT.Task.for_rpc(this.app).finish(identifier, exit_code);
			}
			if (Command.controllers != null && Command.controllers.has_key(identifier) && Command.controllers.get(identifier).running) {
				Command.controllers.get(identifier).write(new OLLMrpc.Notification() {
					method = "controller.ended",
					args = OLLMrpc.args("i", identifier)
				});
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}
