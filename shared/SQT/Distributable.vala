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
	 * One ''distributable'' row.
	 *
	 * A product we can install. ''name'' matches ''programs.name''
	 * on that ''platform''. One live row per platform and name.
	 * Versions are {@link DistributableVersion}. The wire alias is
	 * ''Argus.Distributable''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.Distributable.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
	 * Argus.Shared.SQT.Distributable.query(db).select("", rows);
	 * }}}
	 */
	public class Distributable : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		/**
		 * Row id in ''distributable''.
		 */
		public int64 id { get; set; default = 0; }
		/**
		 * ''programs.name'' match. The Windows uninstall ''DisplayName''.
		 */
		public string name { get; set; default = ""; }
		/**
		 * Target OS family, e.g. ''windows''.
		 */
		public string platform { get; set; default = ""; }
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
		 * Latest live {@link DistributableVersion.version}. Not a column.
		 * The list call fills it.
		 */
		public string version { get; set; default = ""; }
		/**
		 * Latest live file size in bytes. Not a column.
		 */
		public int64 size { get; set; default = 0; }
		/**
		 * Latest live {@link DistributableVersion.id}. Not a column. ''0'' when none.
		 */
		public int64 version_id { get; set; default = 0; }

		/**
		 * Register the wire name ''Argus.Distributable''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Distributable", typeof(Distributable));
		}

		/**
		 * Rows in ''distributable''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<Distributable> query(SQ.Database db)
		{
			return new SQ.Query<Distributable>(db, "distributable");
		}

		/**
		 * Create ''distributable''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS distributable (
					id        INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					name      TEXT NOT NULL DEFAULT '',
					platform  TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("distributable create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "distributable");
			db.db.exec("""
				CREATE UNIQUE INDEX IF NOT EXISTS distributable_live_name
				ON distributable (platform, name)
				WHERE deleted_dt = 0;
				""", null, out errmsg);
		}
	}
}
