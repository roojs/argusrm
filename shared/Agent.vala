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

namespace Argus.Shared
{
	/**
	 * One registered machine.
	 *
	 * The table is ''agent''. The wire alias is ''Argus.Agent''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.Agent.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.Agent>();
	 * Argus.Shared.Agent.query(db).select("LIMIT 20", rows);
	 * }}}
	 */
	public class Agent : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }
		public bool is_controller { get; set; default = false; }

		/**
		 * Register the wire name ''Argus.Agent''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Agent", typeof(Agent));
		}

		/**
		 * Rows in ''agent''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<Agent> query(SQ.Database db)
		{
			return new SQ.Query<Agent>(db, "agent");
		}

		/**
		 * Create ''agent'', migrating the old ''client_cert'' table.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			db.db.exec("ALTER TABLE client_cert RENAME TO agent;", null, out errmsg);
			var ddl = """
				CREATE TABLE IF NOT EXISTS agent (
					id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					fingerprint   TEXT NOT NULL UNIQUE,
					status        INTEGER NOT NULL DEFAULT 0,
					ip            TEXT NOT NULL DEFAULT '',
					created       INT64 NOT NULL DEFAULT 0,
					requester     TEXT NOT NULL DEFAULT '',
					is_controller INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("Failed to create agent table: %s", db.db.errmsg());
			}
			db.db.exec(
				"""
				ALTER TABLE agent ADD COLUMN
					is_controller INTEGER NOT NULL DEFAULT 0;
				""",
				null,
				out errmsg
			);
			var q = Agent.query(db);
			var now = new GLib.DateTime.now_utc().to_unix();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("before", (int) (now - (24 * 60 * 60)));
			int_binds.set("status", 0);
			q.deleteWhere(
				"WHERE status = $status AND created < $before",
				int_binds,
				null
			);
		}
	}
}
