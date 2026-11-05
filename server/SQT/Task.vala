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

namespace Argus.Server.SQT
{
	/**
	 * Server-side task and target management.
	 *
	 * Controllers create draft tasks, add enabled machines, approve the
	 * task, and copy tasks to or from templates.
	 * {@link Scheduler} calls {@link run} when an approved task is due.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQT.Task.rpc_register();
	 * OLLMrpc.Request.register("Task",
	 *     new Argus.Server.SQT.Task.for_rpc(app));
	 * }}}
	 */
	public class Task : Argus.Shared.SQT.Task
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public Task()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public Task.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register the task row types and calls.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQT.Task.rpc_register();
			Argus.Shared.SQT.TaskTarget.rpc_register();
			OLLMrpc.Request.add_class(
				"Task", typeof(Task),
				"create", "o",
				"update", "o",
				"list", "",
				"target", "iv",
				"watch", "i",
				"approve", "ib",
				"duplicate", "i",
				"targets", "i"
			);
		}

		/**
		 * Create a task without targets.
		 *
		 * Templates always receive a negative schedule. The inbound id and
		 * completion time are discarded.
		 *
		 * @param request inbound RPC from the controller
		 * @param row task values
		 */
		public void create(OLLMrpc.Request request, Argus.Shared.SQT.Task row)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (row.script_id < 0 || (!row.is_script && row.script_id > 0) ||
				(row.script_id == 0 && row.command == "")) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid task")
				});
				return;
			}
			if (row.script_id > 0) {
				var scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
				var binds = new Gee.HashMap<string, int>();
				binds.set("id", (int) row.script_id);
				Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
					"WHERE id = $id AND filetype = 'script'", binds, null, scripts);
				if (scripts.size == 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
			}
			row.id = 0;
			row.completed = 0;
			row.is_draft = true;
			if (row.is_template && row.scheduled >= 0) {
				row.scheduled = -1;
			}
			Argus.Shared.SQT.Task.query(this.app.db).insert(row);
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", row),
				msg = "ok"
			});
		}

		/**
		 * Update the editable properties of a task.
		 *
		 * The row id selects the task. Completion and approval state are
		 * preserved.
		 *
		 * @param request inbound RPC from the controller
		 * @param row replacement task values
		 */
		public void update(OLLMrpc.Request request, Argus.Shared.SQT.Task row)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (row.id < 1 || row.script_id < 0 ||
				(!row.is_script && row.script_id > 0) ||
				(row.script_id == 0 && row.command == "")) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid task")
				});
				return;
			}
			if (row.script_id > 0) {
				var scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
				var script_binds = new Gee.HashMap<string, int>();
				script_binds.set("id", (int) row.script_id);
				Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
					"WHERE id = $id AND filetype = 'script'",
					script_binds, null, scripts);
				if (scripts.size == 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", (int) row.id);
			Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
				"WHERE id = $id", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown task")
				});
				return;
			}
			if (rows.get(0).completed > 0 || !rows.get(0).is_draft) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("task is approved")
				});
				return;
			}
			rows.get(0).copy_from(row, { "id", "is_draft", "completed" });
			rows.get(0).scheduled = row.is_template && row.scheduled >= 0 ?
				-1 : row.scheduled;
			Argus.Shared.SQT.Task.query(this.app.db).updateById(rows.get(0));
			this.app.db.backupDB();
			this.app.scheduler.reschedule();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
		}

		/**
		 * List tasks and templates.
		 *
		 * @param request inbound RPC from the controller
		 */
		public void list(OLLMrpc.Request request)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			Argus.Shared.SQT.Task.query(this.app.db).select("", rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Add enabled machines to a draft task.
		 *
		 * @param request inbound RPC from the controller
		 * @param task_id ''task.id''
		 * @param agent_ids variant containing an ''ai'' array of agent ids
		 */
		public void target(OLLMrpc.Request request, int task_id, GLib.Variant agent_ids)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (!agent_ids.is_of_type(new GLib.VariantType("ai"))) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("agent ids must be an int array")
				});
				return;
			}
			var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			var task_binds = new Gee.HashMap<string, int>();
			task_binds.set("id", task_id);
			Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
				"WHERE id = $id", task_binds, null, tasks);
			if (tasks.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown task")
				});
				return;
			}
			if (tasks.get(0).completed > 0 || !tasks.get(0).is_draft) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("task is approved")
				});
				return;
			}
			var existing = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE task_id = $id", task_binds, null, existing);
			var existing_agents = new Gee.HashMap<int, Argus.Shared.SQT.TaskTarget>();
			foreach (var row in existing) {
				existing_agents.set((int) row.agent_id, row);
			}
			var allowed = new Gee.HashMap<int, bool>();
			if (tasks.get(0).script_id > 0) {
				var enabled = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
				var enabled_binds = new Gee.HashMap<string, int>();
				enabled_binds.set("script_id", (int) tasks.get(0).script_id);
				Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere(
					"WHERE script_id = $script_id", enabled_binds, null, enabled);
				foreach (var script_agent in enabled) {
					allowed.set((int) script_agent.agent_id, true);
				}
			} else {
				var agents = new Gee.ArrayList<Argus.Shared.Agent>();
				Argus.Shared.Agent.query(this.app.db).select("WHERE status = 1", agents);
				foreach (var agent in agents) {
					allowed.set((int) agent.id, true);
				}
			}
			for (var i = 0; i < agent_ids.n_children(); i++) {
				var agent_id = agent_ids.get_child_value(i).get_int32();
				if (allowed.has_key(agent_id)) {
					continue;
				}
				var message = tasks.get(0).script_id > 0 ?
					"script is not enabled on agent " + agent_id.to_string() :
					"unknown agent " + agent_id.to_string();
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(message)
				});
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			for (var i = 0; i < agent_ids.n_children(); i++) {
				var agent_id = agent_ids.get_child_value(i).get_int32();
				if (existing_agents.has_key(agent_id)) {
					if (!rows.contains(existing_agents.get(agent_id))) {
						rows.add(existing_agents.get(agent_id));
					}
					continue;
				}
				var row = new Argus.Shared.SQT.TaskTarget() {
					task_id = task_id,
					agent_id = agent_id
				};
				Argus.Shared.SQT.TaskTarget.query(this.app.db).insert(row);
				rows.add(row);
				existing_agents.set(agent_id, row);
			}
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Set the approval state before a task reaches its schedule.
		 *
		 * @param request inbound RPC from the controller
		 * @param task_id ''task.id''
		 * @param approved true to approve, false to return to draft
		 */
		public void approve(OLLMrpc.Request request, int task_id, bool approved)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			var task_binds = new Gee.HashMap<string, int>();
			task_binds.set("id", task_id);
			Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
				"WHERE id = $id AND is_template = 0", task_binds, null, tasks);
			if (tasks.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown task")
				});
				return;
			}
			if (tasks.get(0).scheduled <= new GLib.DateTime.now_utc().to_unix()) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("task schedule has passed")
				});
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("task_id", task_id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE task_id = $task_id",
				binds, null, rows);
			if (approved && rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("task has no targets")
				});
				return;
			}
			tasks.get(0).is_draft = !approved;
			Argus.Shared.SQT.Task.query(this.app.db).updateById(tasks.get(0));
			if (!approved) {
				foreach (var row in rows) {
					row.is_watched = false;
					Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(row);
					Argus.Server.Command.unwatch((int) row.id);
				}
			}
			this.app.db.backupDB();
			this.app.scheduler.reschedule();
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Remember that this controller wants the live output for one target.
		 *
		 * @param request inbound RPC from the controller
		 * @param target_id ''task_target.id''
		 */
		public void watch(OLLMrpc.Request request, int target_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", target_id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE id = $id AND ended = 0", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown target")
				});
				return;
			}
			rows.get(0).is_watched = true;
			Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(rows.get(0));
			Argus.Server.Command.watch(target_id, request.connection);
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
		}

		/**
		 * Duplicate a task and its target selection.
		 *
		 * The task properties and target selection are copied into a new
		 * draft. Target execution state is cleared.
		 *
		 * @param request inbound RPC from the controller
		 * @param task_id source ''task.id''
		 */
		public void duplicate(OLLMrpc.Request request, int task_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", task_id);
			Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
				"WHERE id = $id", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown task")
				});
				return;
			}
			var row = new Argus.Shared.SQT.Task();
			row.copy_from(rows.get(0), { "id", "is_draft", "completed" });
			row.is_draft = true;
			Argus.Shared.SQT.Task.query(this.app.db).insert(row);
			var targets = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var target_binds = new Gee.HashMap<string, int>();
			target_binds.set("task_id", task_id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE task_id = $task_id", target_binds, null, targets);
			foreach (var target in targets) {
				Argus.Shared.SQT.TaskTarget.query(this.app.db).insert(
					new Argus.Shared.SQT.TaskTarget() {
						task_id = row.id,
						agent_id = target.agent_id
					});
			}
			this.app.db.backupDB();
			this.app.scheduler.reschedule();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", row),
				msg = "ok"
			});
		}

		/**
		 * List targets for one task.
		 *
		 * @param request inbound RPC from the controller
		 * @param task_id ''task.id''
		 */
		public void targets(OLLMrpc.Request request, int task_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("task_id", task_id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE task_id = $task_id", binds, null, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Walk the targets of one due task and send each ready one.
		 *
		 * This is the scheduler entry point. The first successful send writes
		 * {@link Argus.Shared.SQT.TaskTarget.started} and the log identifier.
		 * A machine that is already running, or has no app-socket connection,
		 * waits 60 seconds. A missing script fails that target.
		 *
		 * @param task_id ''task.id''
		 */
		public void run(int task_id)
		{
			var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			var task_binds = new Gee.HashMap<string, int>();
			var now = new GLib.DateTime.now_utc().to_unix();
			task_binds.set("id", task_id);
			task_binds.set("now", (int) now);
			Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
				"WHERE id = $id AND is_template = 0 AND is_draft = 0 " +
					"AND completed = 0 AND scheduled <= $now",
				task_binds, null, tasks);
			if (tasks.size == 0) {
				return;
			}
			var targets = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var target_binds = new Gee.HashMap<string, int>();
			target_binds.set("task_id", task_id);
			target_binds.set("now", (int) now);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE task_id = $task_id AND scheduled <= $now " +
					"AND started = 0 AND ended = 0 AND is_cancelled = 0",
				target_binds, null, targets);
			var running = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			Argus.Shared.SQT.TaskTarget.query(this.app.db).select(
				"WHERE started > 0 AND ended = 0", running);
			var busy_agents = new Gee.HashMap<int, bool>();
			foreach (var target in running) {
				busy_agents.set((int) target.agent_id, true);
			}
			var rescheduled = false;
			var started = false;
			var line_error = "";
			var line = this.command_text(tasks.get(0), out line_error);
			var sender = new Argus.Server.Command.for_rpc(this.app);
			foreach (var target in targets) {
				if (busy_agents.has_key((int) target.agent_id)) {
					target.scheduled = now + 60;
					Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
					rescheduled = true;
					continue;
				}
				if (line == null) {
					this.fail_target(target, 1, line_error);
					continue;
				}
				var order = new Argus.Server.Command() {
					command = line
				};
				OLLMrpc.Transport.Connection? controller = null;
				if (target.is_watched) {
					controller = Argus.Server.Command.watcher((int) target.id);
				}
				var send_error = "";
				if (!sender.dispatch(target.agent_id, order, controller, out send_error)) {
					if (controller != null && controller.running) {
						this.fail_target(target, 127, send_error);
					} else {
						target.scheduled = now + 60;
						Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
						rescheduled = true;
					}
					continue;
				}
				busy_agents.set((int) target.agent_id, true);
				target.started = now;
				target.identifier = order.identifier;
				Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
				started = true;
				GLib.debug("task %d target %s started %d",
					task_id, target.agent_id.to_string(), order.identifier);
			}
			if (rescheduled || started) {
				this.app.db.backupDB();
			}
		}

		/**
		 * Store the exit code for one sent target.
		 *
		 * When no target on that task is still open, the task is completed.
		 *
		 * @param identifier log identifier written by {@link run}
		 * @param exit_code process exit code
		 */
		public void finish(int identifier, int exit_code)
		{
			if (identifier < 1 || this.app == null || this.app.db == null) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("identifier", identifier);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE identifier = $identifier AND ended = 0",
				binds, null, rows);
			if (rows.size == 0) {
				return;
			}
			var now = new GLib.DateTime.now_utc().to_unix();
			rows.get(0).ended = now;
			rows.get(0).success = exit_code;
			Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(rows.get(0));
			this.complete_task((int) rows.get(0).task_id, now);
			this.app.db.backupDB();
		}

		/**
		 * Shell text for one task.
		 *
		 * A library script is the file body. A one-line command or a
		 * generated script is {@link Argus.Shared.SQT.Task.command}.
		 *
		 * @param task task being dispatched
		 * @param error reason the text could not be read
		 * @return the text, or null
		 */
		private string? command_text(Argus.Shared.SQT.Task task, out string error)
		{
			error = "";
			if (task.script_id < 1) {
				if (task.command == "") {
					error = "invalid task";
					return null;
				}
				return task.command;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", (int) task.script_id);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE id = $id", binds, null, rows);
			if (rows.size == 0) {
				error = "unknown script";
				return null;
			}
			var root = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "scripts");
			if (rows.get(0).script_repository_id > 0) {
				var repositories = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
				var repository_binds = new Gee.HashMap<string, int>();
				repository_binds.set("id", (int) rows.get(0).script_repository_id);
				Argus.Shared.SQT.ScriptRepository.query(this.app.db).selectWhere(
					"WHERE id = $id", repository_binds, null, repositories);
				if (repositories.size == 0) {
					error = "unknown repository";
					return null;
				}
				root = GLib.Path.build_filename(
					Argus.SERVER_DATA_DIR, "git", repositories.get(0).name);
			}
			var full_path = GLib.Path.build_filename(root, rows.get(0).path);
			if (GLib.FileUtils.test(full_path, GLib.FileTest.IS_SYMLINK)) {
				error = "invalid path";
				return null;
			}
			var body = "";
			try {
				GLib.FileUtils.get_contents(full_path, out body);
			} catch (GLib.Error e) {
				error = e.message;
				return null;
			}
			return body;
		}

		/**
		 * Close a target that never started and tell its controller.
		 *
		 * @param target row that will not be sent
		 * @param code value stored on {@link Argus.Shared.SQT.TaskTarget.success}
		 * @param message text for ''controller.stderr''
		 */
		private void fail_target(Argus.Shared.SQT.TaskTarget target, int code, string message)
		{
			var now = new GLib.DateTime.now_utc().to_unix();
			target.ended = now;
			target.success = code;
			Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
			var controller = target.is_watched ? Argus.Server.Command.watcher((int) target.id) : null;
			if (controller != null && controller.running) {
				var text = message.has_suffix("\n") ? message : message + "\n";
				controller.write(new OLLMrpc.Notification() {
					method = "controller.stderr",
					args = OLLMrpc.args("is", target.identifier, text)
				});
				controller.write(new OLLMrpc.Notification() {
					method = "controller.ended",
					args = OLLMrpc.args("i", target.identifier)
				});
			}
			this.complete_task((int) target.task_id, now);
			this.app.db.backupDB();
		}

		/**
		 * Write {@link Argus.Shared.SQT.Task.completed} when every target has ended.
		 *
		 * @param task_id ''task.id''
		 * @param now unix time to store
		 */
		private void complete_task(int task_id, int64 now)
		{
			var open = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("task_id", task_id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE task_id = $task_id AND ended = 0 AND is_cancelled = 0",
				binds, null, open);
			if (open.size > 0) {
				return;
			}
			var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			var task_binds = new Gee.HashMap<string, int>();
			task_binds.set("id", task_id);
			Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
				"WHERE id = $id", task_binds, null, tasks);
			if (tasks.size == 0 || tasks.get(0).completed > 0) {
				return;
			}
			tasks.get(0).completed = now;
			Argus.Shared.SQT.Task.query(this.app.db).updateById(tasks.get(0));
		}
	}
}
