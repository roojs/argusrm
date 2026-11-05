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
			if (tasks.size == 0 || tasks.get(0).script_id < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown task or task has no enabled script")
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
			var enabled = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
			var enabled_binds = new Gee.HashMap<string, int>();
			enabled_binds.set("script_id", (int) tasks.get(0).script_id);
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere(
				"WHERE script_id = $script_id", enabled_binds, null, enabled);
			var enabled_agents = new Gee.HashMap<int, bool>();
			foreach (var script_agent in enabled) {
				enabled_agents.set((int) script_agent.agent_id, true);
			}
			for (var i = 0; i < agent_ids.n_children(); i++) {
				var agent_id = agent_ids.get_child_value(i).get_int32();
				if (!enabled_agents.has_key(agent_id)) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(
							"script is not enabled on agent " + agent_id.to_string())
					});
					return;
				}
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
			this.app.db.backupDB();
			this.app.scheduler.reschedule();
			request.reply(new OLLMrpc.Response() {
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
		 * Walk the targets of one due task.
		 *
		 * This is the scheduler entry point. Command dispatch is deliberately
		 * still a placeholder: ready targets are identified and logged, but
		 * are not marked started until the real command has been sent.
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
			foreach (var target in targets) {
				if (busy_agents.has_key((int) target.agent_id)) {
					target.scheduled = now + 60;
					Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
					rescheduled = true;
					continue;
				}
				busy_agents.set((int) target.agent_id, true);
				GLib.debug("task %d target %s ready",
					task_id, target.agent_id.to_string());
			}
			if (rescheduled) {
				this.app.db.backupDB();
			}
		}
	}
}
