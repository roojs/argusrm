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
	 * One Windows ''programs'' row.
	 */
	public class Programs : Row
	{
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Programs>(db, agent_id, rows, "programs", { "name", "identifying-number" });
		}

		/**
		 * Create ''programs''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS programs (
					id                  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id            INTEGER NOT NULL,
					name                TEXT NOT NULL DEFAULT '',
					version             TEXT NOT NULL DEFAULT '',
					install_location    TEXT NOT NULL DEFAULT '',
					install_source      TEXT NOT NULL DEFAULT '',
					language            TEXT NOT NULL DEFAULT '',
					publisher           TEXT NOT NULL DEFAULT '',
					uninstall_string    TEXT NOT NULL DEFAULT '',
					install_date        TEXT NOT NULL DEFAULT '',
					identifying_number  TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("programs create failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Programs", typeof(Programs));
		}

		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string install_location { get; set; default = ""; }
		public string install_source { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public string publisher { get; set; default = ""; }
		public string uninstall_string { get; set; default = ""; }
		public string install_date { get; set; default = ""; }
		public string identifying_number { get; set; default = ""; }
	}
}
