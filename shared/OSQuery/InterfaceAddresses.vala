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
	 * One ''interface_addresses'' row.
	 */
	public class InterfaceAddresses : Row
	{
		public override bool sync(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows,
			bool complete = true
		) {
			return this.sync_rows<InterfaceAddresses>(db, agent_id, rows,
				"interface_addresses", { "interface", "address" }, complete);
		}

		/**
		 * Create ''interface_addresses''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS interface_addresses (
					id             INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id       INTEGER NOT NULL,
					interface      TEXT NOT NULL DEFAULT '',
					address        TEXT NOT NULL DEFAULT '',
					mask           TEXT NOT NULL DEFAULT '',
					broadcast      TEXT NOT NULL DEFAULT '',
					point_to_point TEXT NOT NULL DEFAULT '',
					type           TEXT NOT NULL DEFAULT '',
					added_dt       INTEGER NOT NULL DEFAULT 0,
					updated_dt     INTEGER NOT NULL DEFAULT 0,
					deleted_dt     INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("interface_addresses create failed: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE interface_addresses ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE interface_addresses ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE interface_addresses ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("InterfaceAddresses", typeof(InterfaceAddresses));
		}

		public string @interface { get; set; default = ""; }
		public string address { get; set; default = ""; }
		public string mask { get; set; default = ""; }
		public string broadcast { get; set; default = ""; }
		public string point_to_point { get; set; default = ""; }
		public string ctype { get; set; default = ""; }
	}
}
