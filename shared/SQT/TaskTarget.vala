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
		public int64 id { get; set; default = 0; }
		public int64 task_id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }
		public int64 scheduled { get; set; default = 0; }
		public int64 started { get; set; default = 0; }
		public int64 ended { get; set; default = 0; }
		public int success { get; set; default = 0; }
		public bool is_cancelled { get; set; default = false; }
		public int timeout { get; set; default = 0; }
		public int identifier { get; set; default = 0; }

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
					timeout      INTEGER NOT NULL DEFAULT 0,
					identifier   INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("task_target create failed: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE task_target ADD COLUMN scheduled INT64 NOT NULL DEFAULT 0;",
				null, out errmsg);
		}
	}
}
