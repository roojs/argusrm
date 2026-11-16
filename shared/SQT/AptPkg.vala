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
	 * One ''apt_pkg'' row.
	 *
	 * Canonical binary package name in the server dependency catalog.
	 */
	public class AptPkg : GLib.Object, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
		public string name { get; set; default = ""; }

		/**
		 * Rows in ''apt_pkg''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<AptPkg> query(SQ.Database db)
		{
			return new SQ.Query<AptPkg>(db, "apt_pkg");
		}

		/**
		 * Create ''apt_pkg''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS apt_pkg (
					id   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					name TEXT NOT NULL UNIQUE
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("apt_pkg create failed: %s", db.db.errmsg());
			}
		}
	}
}