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
	 * One ''apt_pkg_depends'' row.
	 *
	 * A Depends or Pre-Depends edge for one {@link AptUrl} index snapshot.
	 */
	public class AptPkgDepends : GLib.Object, SQ.Interface
	{
		public int64 apt_url_id { get; set; default = 0; }
		public int64 pkg_id { get; set; default = 0; }
		public int64 depends_pkg_id { get; set; default = 0; }
		/**
		 * Parenthetical constraint from the ''Packages'' field, when present.
		 * Not used by import or UI in v1.
		 */
		public string constraint_text { get; set; default = ""; }

		/**
		 * Rows in ''apt_pkg_depends''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<AptPkgDepends> query(SQ.Database db)
		{
			return new SQ.Query<AptPkgDepends>(db, "apt_pkg_depends");
		}

		/**
		 * Create ''apt_pkg_depends''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS apt_pkg_depends (
					apt_url_id       INTEGER NOT NULL,
					pkg_id           INTEGER NOT NULL,
					depends_pkg_id   INTEGER NOT NULL,
					constraint_text  TEXT NOT NULL DEFAULT '',
					PRIMARY KEY (apt_url_id, pkg_id, depends_pkg_id)
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("apt_pkg_depends create failed: %s", db.db.errmsg());
			}
			var idx = """
				CREATE INDEX IF NOT EXISTS apt_pkg_depends_reverse
				ON apt_pkg_depends (apt_url_id, depends_pkg_id);
				""";
			if (Sqlite.OK != db.db.exec(idx, null, out errmsg)) {
				GLib.warning("apt_pkg_depends index failed: %s", db.db.errmsg());
			}
		}
	}
}