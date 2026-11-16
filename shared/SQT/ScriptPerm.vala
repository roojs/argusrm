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
	 * One ''script_perm'' row.
	 *
	 * Permits a {@link Script} on a machine when {@link Script.allow_all}
	 * is false. The wire alias is ''Argus.ScriptPerm''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.ScriptPerm.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptPerm>();
	 * Argus.Shared.SQT.ScriptPerm.query(db).select("", rows);
	 * }}}
	 */
	public class ScriptPerm : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public int64 script_id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }

		/**
		 * Register the wire name ''Argus.ScriptPerm''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.ScriptPerm", typeof(ScriptPerm));
		}

		/**
		 * Rows in ''script_perm''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<ScriptPerm> query(SQ.Database db)
		{
			return new SQ.Query<ScriptPerm>(db, "script_perm");
		}

		/**
		 * Create ''script_perm'', migrating ''script_agent'' if present.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			db.db.exec("ALTER TABLE script_agent RENAME TO script_perm;", null, out errmsg);
			var ddl = """
				CREATE TABLE IF NOT EXISTS script_perm (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_id  INTEGER NOT NULL DEFAULT 0,
					agent_id   INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script_perm create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "script_perm");
		}
	}
}
