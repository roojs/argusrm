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
	 * One ''task'' row.
	 *
	 * The activity. A script or a command. The machines it runs on
	 * are {@link TaskTarget}. The wire alias is ''Argus.Task''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.Task.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.Task>();
	 * Argus.Shared.SQT.Task.query(db).select("", rows);
	 * }}}
	 */
	public class Task : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string name { get; set; default = ""; }
		public bool is_script { get; set; default = false; }
		public string command { get; set; default = ""; }
		public int64 script_id { get; set; default = 0; }
		public string run_as { get; set; default = ""; }
		public bool is_template { get; set; default = false; }
		public bool is_draft { get; set; default = true; }
		public int64 scheduled { get; set; default = 0; }
		public int64 completed { get; set; default = 0; }

		/**
		 * Register the wire name ''Argus.Task''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Task", typeof(Task));
		}

		/**
		 * Rows in ''task''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<Task> query(SQ.Database db)
		{
			return new SQ.Query<Task>(db, "task");
		}

		/**
		 * Create ''task''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS task (
					id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					name        TEXT NOT NULL DEFAULT '',
					is_script   INTEGER NOT NULL DEFAULT 0,
					command     TEXT NOT NULL DEFAULT '',
					script_id   INTEGER NOT NULL DEFAULT 0,
					run_as      TEXT NOT NULL DEFAULT '',
					is_template INTEGER NOT NULL DEFAULT 0,
					is_draft    INTEGER NOT NULL DEFAULT 1,
					scheduled   INT64 NOT NULL DEFAULT 0,
					completed   INT64 NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("task create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "task");
			db.db.exec(
				"ALTER TABLE task ADD COLUMN is_draft INTEGER NOT NULL DEFAULT 1;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE task ADD COLUMN run_as TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"UPDATE task SET is_draft = 0 WHERE id IN " +
					"(SELECT task_id FROM task_target WHERE is_draft = 0);",
				null, out errmsg);
		}
	}
}
