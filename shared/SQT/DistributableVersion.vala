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
	 * One ''distributable_version'' row.
	 *
	 * One uploaded file for a {@link Distributable}. The bytes live
	 * under ''packages/'' at {@link path}. The wire alias is
	 * ''Argus.DistributableVersion''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.DistributableVersion.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.DistributableVersion>();
	 * Argus.Shared.SQT.DistributableVersion.query(db).select("", rows);
	 * }}}
	 */
	public class DistributableVersion : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		/**
		 * Row id in ''distributable_version''.
		 */
		public int64 id { get; set; default = 0; }
		/**
		 * {@link Distributable.id} this file belongs to.
		 */
		public int64 distributable_id { get; set; default = 0; }
		/**
		 * Version string. ''ProductVersion'', or the version the user typed.
		 */
		public string version { get; set; default = ""; }
		/**
		 * SHA-256 hex digest of the file bytes.
		 */
		public string sha256 { get; set; default = ""; }
		/**
		 * Original file name.
		 */
		public string filename { get; set; default = ""; }
		/**
		 * Path relative to ''packages/'', e.g. ''distributables/{sha256}.exe''.
		 */
		public string path { get; set; default = ""; }
		/**
		 * File size in bytes.
		 */
		public int64 size { get; set; default = 0; }
		/**
		 * ''agent.id'' of the controller that uploaded this file.
		 *
		 * ''0'' is the local Unix socket, which has no agent row.
		 */
		public int64 uploaded_by { get; set; default = 0; }
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
		 * Register the wire name ''Argus.DistributableVersion''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.DistributableVersion", typeof(DistributableVersion));
		}

		/**
		 * Rows in ''distributable_version''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<DistributableVersion> query(SQ.Database db)
		{
			return new SQ.Query<DistributableVersion>(db, "distributable_version");
		}

		/**
		 * Create ''distributable_version''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS distributable_version (
					id                INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					distributable_id  INTEGER NOT NULL DEFAULT 0,
					version           TEXT NOT NULL DEFAULT '',
					sha256            TEXT NOT NULL DEFAULT '',
					filename          TEXT NOT NULL DEFAULT '',
					path              TEXT NOT NULL DEFAULT '',
					size              INTEGER NOT NULL DEFAULT 0,
					uploaded_by       INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("distributable_version create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "distributable_version");
			db.db.exec(
				"ALTER TABLE distributable_version ADD COLUMN uploaded_by INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec("""
				CREATE INDEX IF NOT EXISTS distributable_version_distributable
				ON distributable_version (distributable_id, deleted_dt);
				""", null, out errmsg);
		}
	}
}
