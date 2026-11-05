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
	 * One ''script_agent'' row.
	 *
	 * A {@link Script} enabled on a machine. The wire alias is
	 * ''Argus.ScriptAgent''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.ScriptAgent.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
	 * Argus.Shared.SQT.ScriptAgent.query(db).select("", rows);
	 * }}}
	 */
	public class ScriptAgent : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public int64 script_id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }

		/**
		 * Register the wire name ''Argus.ScriptAgent''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.ScriptAgent", typeof(ScriptAgent));
		}

		/**
		 * Rows in ''script_agent''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<ScriptAgent> query(SQ.Database db)
		{
			return new SQ.Query<ScriptAgent>(db, "script_agent");
		}

		/**
		 * Create ''script_agent''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS script_agent (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_id  INTEGER NOT NULL DEFAULT 0,
					agent_id   INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script_agent create failed: %s", db.db.errmsg());
			}
		}
	}
}
