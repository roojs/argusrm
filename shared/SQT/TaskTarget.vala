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

namespace Argus.Shared.SQT
{
	/**
	 * One ''task_target'' row.
	 *
	 * One machine a {@link Task} runs on. The wire alias is
	 * ''Argus.TaskTarget''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.TaskTarget.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
	 * Argus.Shared.SQT.TaskTarget.query(db).select("", rows);
	 * }}}
	 */
	public class TaskTarget : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		/**
		 * Row id in ''task_target''.
		 */
		public int64 id { get; set; default = 0; }
		/**
		 * Parent {@link Task.id}.
		 */
		public int64 task_id { get; set; default = 0; }
		/**
		 * Target machine ''agent.id''.
		 */
		public int64 agent_id { get; set; default = 0; }
		/**
		 * Per-target delay unix time, or ''0'' for no extra delay.
		 */
		public int64 scheduled { get; set; default = 0; }
		/**
		 * Unix time execution started on the agent, or ''0'' if queued.
		 */
		public int64 started { get; set; default = 0; }
		/**
		 * Unix time execution finished, or ''0'' if not yet ended.
		 */
		public int64 ended { get; set; default = 0; }
		/**
		 * Process exit code once {@link ended} is non-zero.
		 */
		public int success { get; set; default = 0; }
		/**
		 * True when this target has been cancelled.
		 */
		public bool is_cancelled { get; set; default = false; }
		/**
		 * True when a controller is streaming live output for this target.
		 */
		public bool is_watched { get; set; default = false; }
		/**
		 * Execution timeout in seconds, or ''0'' when unset.
		 */
		public int timeout { get; set; default = 0; }
		/**
		 * Command log identifier shared with ''Argus.Command''.
		 */
		public int identifier { get; set; default = 0; }
		/**
		 * Command log directory holding ''{agent_id}-{identifier}.*''.
		 */
		public string log_dir { get; set; default = ""; }

		/*
		 * The following are joined from task (task_id_*) and agent (agent_id_*).
		 * Not columns of task_target.
		 */
		public string task_id_name { get; set; default = ""; }
		public string task_id_command { get; set; default = ""; }
		public bool task_id_is_draft { get; set; default = false; }
		public int64 task_id_scheduled { get; set; default = 0; }
		public string agent_id_hostname { get; set; default = ""; }

		/**
		 * Update derived display labels when source properties change.
		 */
		construct {
			this.notify["task-id-name"].connect(() => {
				this.notify_property("display-task");
			});
			this.notify["task-id-command"].connect(() => {
				this.notify_property("display-task");
			});
			this.notify["is-cancelled"].connect(() => {
				this.notify_property("display-state");
			});
			this.notify["task-id-is-draft"].connect(() => {
				this.notify_property("display-state");
			});
			this.notify["started"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-started");
				this.notify_property("display-duration");
				this.notify_property("dimmed");
			});
			this.notify["ended"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-duration");
				this.notify_property("display-exit");
				this.notify_property("dimmed");
			});
			this.notify["success"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-exit");
			});
		}

		/**
		 * Task label shown in the grid: {@link task_id_name} or the first
		 * line of {@link task_id_command}.
		 */
		public string display_task {
			owned get {
				if (this.task_id_name != "") {
					return this.task_id_name;
				}
				var nl = this.task_id_command.index_of_char('\n');
				if (nl >= 0) {
					return this.task_id_command.substring(0, nl);
				}
				return this.task_id_command;
			}
		}

		/**
		 * Human-readable execution state for the Tasks grid.
		 */
		public string display_state {
			owned get {
				if (this.is_cancelled) {
					return "Cancelled";
				}
				if (this.ended > 0) {
					return this.success == 0 ? "Completed" : "Failed";
				}
				if (this.started > 0) {
					return "Running";
				}
				if (this.task_id_is_draft) {
					return "Draft";
				}
				return "Queued";
			}
		}

		/**
		 * Local time of {@link started} when today, date and time when
		 * earlier, or empty when not yet started.
		 */
		public string display_started {
			owned get {
				if (this.started < 1) {
					return "";
				}
				var when = new GLib.DateTime.from_unix_local(this.started);
				if (when == null) {
					return "";
				}
				var now = new GLib.DateTime.now_local();
				if (when.get_year() == now.get_year() &&
					when.get_day_of_year() == now.get_day_of_year()) {
					var today = when.format("%H:%M");
					return today != null ? today : "";
				}
				var earlier = when.format("%Y-%m-%d %H:%M");
				return earlier != null ? earlier : "";
			}
		}

		/**
		 * Elapsed time between {@link started} and {@link ended} as
		 * seconds, ''minutes.seconds'', or ''hours:minutes''. Empty
		 * until ended.
		 */
		public string display_duration {
			owned get {
				if (this.started < 1 || this.ended < this.started) {
					return "";
				}
				var elapsed = this.ended - this.started;
				if (elapsed < 60) {
					return elapsed.to_string() + "s";
				}
				if (elapsed < 3600) {
					return (elapsed / 60).to_string() + ".%02lldm".printf(elapsed % 60);
				}
				return (elapsed / 3600).to_string() + ":%02lldh".printf((elapsed % 3600) / 60);
			}
		}

		/**
		 * Exit code shown once {@link ended} is non-zero, empty otherwise.
		 */
		public string display_exit {
			owned get {
				if (this.ended < 1) {
					return "";
				}
				return this.success.to_string();
			}
		}

		/**
		 * True when this target is still waiting to run and should render
		 * dimmed in the Tasks grid.
		 */
		public bool dimmed {
			get {
				return this.started == 0 && this.ended == 0;
			}
		}

		/**
		 * Grid labels are derived. They are not stored or sent.
		 */
		public override void bin_write_prop(OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop) throws GLib.Error
		{
			if (prop.name.has_prefix("display-") || prop.name == "dimmed") {
				return;
			}
			this.bin_default_write_prop(ctx, prop);
		}

		/**
		 * Register the wire name ''Argus.TaskTarget''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.TaskTarget", typeof(TaskTarget));
		}

		/**
		 * Rows in ''task_target''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<TaskTarget> query(SQ.Database db)
		{
			return new SQ.Query<TaskTarget>(db, "task_target");
		}

		/**
		 * Create ''task_target''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS task_target (
					id           INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					task_id      INTEGER NOT NULL DEFAULT 0,
					agent_id     INTEGER NOT NULL DEFAULT 0,
					scheduled    INT64 NOT NULL DEFAULT 0,
					started      INT64 NOT NULL DEFAULT 0,
					ended        INT64 NOT NULL DEFAULT 0,
					success      INTEGER NOT NULL DEFAULT 0,
					is_cancelled INTEGER NOT NULL DEFAULT 0,
					is_watched   INTEGER NOT NULL DEFAULT 0,
					timeout      INTEGER NOT NULL DEFAULT 0,
					identifier   INTEGER NOT NULL DEFAULT 0,
					log_dir      TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("task_target create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "task_target");
			db.db.exec(
				"ALTER TABLE task_target ADD COLUMN scheduled INT64 NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE task_target ADD COLUMN is_watched INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE task_target ADD COLUMN log_dir TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
		}
	}
}
