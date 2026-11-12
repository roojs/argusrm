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
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<InterfaceAddresses>(db, agent_id, rows, "interface_addresses", { "interface", "address" });
		}

		public override string table_name() { return "interface_addresses"; }

		public override string rpc_name() { return "InterfaceAddresses"; }

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
					type           TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("interface_addresses create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "interface_addresses");
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
