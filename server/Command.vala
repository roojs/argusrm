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
	 * The wire name is ''Argus.Command''. {@link run} writes a client
	 * notification on that agent's app-socket connection. {@link send}
	 * writes a follow-up to the same connection. {@link stdout} and
	 * {@link stderr} are the chunks the agent sends back. Stdin, stdout,
	 * and stderr are appended under {@link Argus.LOG_DIR}, then a client
	 * notification goes to the controller that called {@link run} when
	 * that connection is still up.
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
				"run", "xo",
				"send", "is",
				"stdout", "is",
				"stderr", "is",
				"ended", "i"
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
		private static Gee.HashMap<int, SslConnection> agents;

		/**
		 * Log directory for each run, keyed by {@link identifier}.
		 *
		 * {@link run} sets it from the day the command starts.
		 * Stdin, stdout, and stderr append in that directory.
		 */
		private static Gee.HashMap<int, string> logs;

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
				Command.agents = new Gee.HashMap<int, SslConnection>();
				Command.controllers = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
				Command.logs = new Gee.HashMap<int, string>();
			}
		}

		/**
		 * Tell one agent to run this command.
		 *
		 * The caller is the Unix socket, or a TLS connection whose agent row
		 * has ''is_controller'' set. The notification method is
		 * ''agent.run''. Its argument is this object. The caller's connection
		 * receives later output for {@link identifier}.
		 *
		 * @param request inbound RPC from the controller
		 * @param agent_id ''agent.id'' of the machine that runs it
		 * @param order command to send
		 */
		public void run(OLLMrpc.Request request, int64 agent_id, Command order)
		{
			if (agent_id < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("controller does not run commands")
				});
				return;
			}
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (order.identifier < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid command")
				});
				return;
			}
			foreach (var connection in this.app.ssl_listen.connections) {
				if (!connection.running || connection.agent_id != agent_id) {
					continue;
				}
				var now = new GLib.DateTime.now_local();
				var dir = GLib.Path.build_filename(Argus.LOG_DIR, "commands",
					now.format("%Y"), now.format("%m"), now.format("%d"));
				if (GLib.DirUtils.create_with_parents(dir, 0755) != 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("could not store output")
					});
					return;
				}
				connection.write(new OLLMrpc.Notification() {
					method = "agent.run",
					args = OLLMrpc.args("o", order)
				});
				Command.agents.set(order.identifier, connection);
				Command.controllers.set(order.identifier, request.connection);
				Command.logs.set(order.identifier, dir);
				GLib.debug("run command %d on agent %s", order.identifier, agent_id.to_string());
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
			});
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
			var name = Command.agents.get(identifier).agent_id.to_string() + "-" + identifier.to_string() + ".stdin";
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
			var caller = request.connection as SslConnection;
			if (caller == null || caller.agent_id != Command.agents.get(identifier).agent_id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).agent_id.to_string() + "-" + identifier.to_string() + ".stdout";
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
			var caller = request.connection as SslConnection;
			if (caller == null || caller.agent_id != Command.agents.get(identifier).agent_id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).agent_id.to_string() + "-" + identifier.to_string() + ".stderr";
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
		 * @param request inbound RPC from the agent
		 * @param identifier {@link Command.identifier} of the run
		 */
		public void ended(OLLMrpc.Request request, int identifier)
		{
			if (Command.agents == null || !Command.agents.has_key(identifier)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var caller = request.connection as SslConnection;
			if (caller == null || caller.agent_id != Command.agents.get(identifier).agent_id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
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
