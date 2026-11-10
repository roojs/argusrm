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
	 * One ''deb_packages'' row.
	 */
	public class DebPackages : Row
	{
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<DebPackages>(db, agent_id, rows, "deb_packages", { "name", "arch" });
		}

		/**
		 * Create ''deb_packages''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS deb_packages (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id   INTEGER NOT NULL,
					name       TEXT NOT NULL DEFAULT '',
					version    TEXT NOT NULL DEFAULT '',
					source     TEXT NOT NULL DEFAULT '',
					size       INT64 NOT NULL DEFAULT 0,
					arch       TEXT NOT NULL DEFAULT '',
					revision   TEXT NOT NULL DEFAULT '',
					status     TEXT NOT NULL DEFAULT '',
					maintainer TEXT NOT NULL DEFAULT '',
					section    TEXT NOT NULL DEFAULT '',
					priority   TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("deb_packages create failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("DebPackages", typeof(DebPackages));
		}

		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string source { get; set; default = ""; }
		/**
		 * Package size in bytes.
		 */
		public int64 size { get; set; default = 0; }
		public string arch { get; set; default = ""; }
		public string revision { get; set; default = ""; }
		public string status { get; set; default = ""; }
		public string maintainer { get; set; default = ""; }
		public string section { get; set; default = ""; }
		public string priority { get; set; default = ""; }
	}
}
