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
	 * One ''cpu_info'' row.
	 */
	public class CpuInfo : Row
	{
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<CpuInfo>(db, agent_id, rows, "cpu_info", { "device-id" });
		}

		/**
		 * Create ''cpu_info''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS cpu_info (
					id                  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id            INTEGER NOT NULL,
					device_id           TEXT NOT NULL DEFAULT '',
					model               TEXT NOT NULL DEFAULT '',
					manufacturer        TEXT NOT NULL DEFAULT '',
					processor_type      TEXT NOT NULL DEFAULT '',
					cpu_status          INTEGER NOT NULL DEFAULT 0,
					number_of_cores     INTEGER NOT NULL DEFAULT 0,
					logical_processors  INTEGER NOT NULL DEFAULT 0,
					address_width       INTEGER NOT NULL DEFAULT 0,
					current_clock_speed INTEGER NOT NULL DEFAULT 0,
					max_clock_speed     INTEGER NOT NULL DEFAULT 0,
					socket_designation  TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("cpu_info create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "cpu_info");
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("CpuInfo", typeof(CpuInfo));
		}

		public string device_id { get; set; default = ""; }
		public string model { get; set; default = ""; }
		public string manufacturer { get; set; default = ""; }
		public string processor_type { get; set; default = ""; }
		public int cpu_status { get; set; default = 0; }
		public int number_of_cores { get; set; default = 0; }
		public int logical_processors { get; set; default = 0; }
		public int address_width { get; set; default = 0; }
		public int current_clock_speed { get; set; default = 0; }
		public int max_clock_speed { get; set; default = 0; }
		public string socket_designation { get; set; default = ""; }
	}
}
