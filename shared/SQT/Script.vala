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
	 * One ''script'' row.
	 *
	 * A file in the library. ''script_repository_id'' 0 is a file
	 * under ''scripts/''. The wire alias is ''Argus.Script''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.Script.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
	 * Argus.Shared.SQT.Script.query(db).select("", rows);
	 * }}}
	 */
	public class Script : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable, Json.Serializable
	{
		public int64 id { get; set; default = 0; }
		public int64 script_repository_id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string filetype { get; set; default = ""; }
		/**
		 * Target OS family, e.g. ''linux'' or ''windows''.
		 */
		public string platform { get; set; default = ""; }
		/**
		 * Target tool or subsystem, e.g. ''apt'' or ''dnf''.
		 */
		public string app { get; set; default = ""; }
		/**
		 * Action verb, e.g. ''update'' or ''upgrade''.
		 */
		public string action { get; set; default = ""; }
		/**
		 * Script body stored in the database when {@link filetype} is ''inline''.
		 */
		public string body { get; set; default = ""; }
		/**
		 * True when any active agent may run this script without a {@link ScriptPerm} row.
		 */
		public bool allow_all { get; set; default = false; }
		/**
		 * Unix time this row was inserted.
		 */
		public int added_dt { get; set; default = 0; }
		/**
		 * Unix time this row was last updated.
		 */
		public int updated_dt { get; set; default = 0; }
		/**
		 * Unix time this row was soft-deleted, or ''0'' when active.
		 */
		public int deleted_dt { get; set; default = 0; }

		/**
		 * Register the wire name ''Argus.Script''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Script", typeof(Script));
		}

		/**
		 * Rows in ''script''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<Script> query(SQ.Database db)
		{
			return new SQ.Query<Script>(db, "script");
		}

		/**
		 * Create ''script''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS script (
					id                    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_repository_id  INTEGER NOT NULL DEFAULT 0,
					path                  TEXT NOT NULL DEFAULT '',
					filetype              TEXT NOT NULL DEFAULT '',
					platform              TEXT NOT NULL DEFAULT '',
					app                   TEXT NOT NULL DEFAULT '',
					action                TEXT NOT NULL DEFAULT '',
					body                  TEXT NOT NULL DEFAULT '',
					allow_all             INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "script");
			db.db.exec(
				"ALTER TABLE script ADD COLUMN platform TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN app TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN action TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN body TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN allow_all INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
		}
	}
}
