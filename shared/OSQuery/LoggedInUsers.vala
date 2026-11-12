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

namespace Argus.Shared.OSQuery
{
	/**
	 * One ''logged_in_users'' row.
	 */
	public class LoggedInUsers : Row
	{
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<LoggedInUsers>(db, agent_id, rows, "logged_in_users", { "pid" });
		}

		public override string table_name() { return "logged_in_users"; }

		public override string rpc_name() { return "LoggedInUsers"; }

		/**
		 * Create ''logged_in_users''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS logged_in_users (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id INTEGER NOT NULL,
					type     TEXT NOT NULL DEFAULT '',
					user     TEXT NOT NULL DEFAULT '',
					tty      TEXT NOT NULL DEFAULT '',
					host     TEXT NOT NULL DEFAULT '',
					time     INTEGER NOT NULL DEFAULT 0,
					pid      INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("logged_in_users create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "logged_in_users");
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("LoggedInUsers", typeof(LoggedInUsers));
		}

		public string ctype { get; set; default = ""; }
		public string user { get; set; default = ""; }
		public string tty { get; set; default = ""; }
		public string host { get; set; default = ""; }
		public int time { get; set; default = 0; }
		public int pid { get; set; default = 0; }
	}
}
