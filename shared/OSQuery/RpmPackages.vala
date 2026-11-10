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
	 * One ''rpm_packages'' row.
	 */
	public class RpmPackages : Row
	{
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<RpmPackages>(db, agent_id, rows, "rpm_packages", { "name", "arch" });
		}

		/**
		 * Create ''rpm_packages''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS rpm_packages (
					id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id      INTEGER NOT NULL,
					name          TEXT NOT NULL DEFAULT '',
					version       TEXT NOT NULL DEFAULT '',
					release       TEXT NOT NULL DEFAULT '',
					source        TEXT NOT NULL DEFAULT '',
					size          INT64 NOT NULL DEFAULT 0,
					sha1          TEXT NOT NULL DEFAULT '',
					arch          TEXT NOT NULL DEFAULT '',
					epoch         INTEGER NOT NULL DEFAULT 0,
					install_time  INT64 NOT NULL DEFAULT 0,
					vendor        TEXT NOT NULL DEFAULT '',
					package_group TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("rpm_packages create failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("RpmPackages", typeof(RpmPackages));
		}

		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string release { get; set; default = ""; }
		public string source { get; set; default = ""; }
		/**
		 * Package size in bytes.
		 */
		public int64 size { get; set; default = 0; }
		public string sha1 { get; set; default = ""; }
		public string arch { get; set; default = ""; }
		public int epoch { get; set; default = 0; }
		/**
		 * Unix time the package was installed. Zero when unset.
		 */
		public int64 install_time { get; set; default = 0; }
		public string vendor { get; set; default = ""; }
		public string package_group { get; set; default = ""; }
	}
}
