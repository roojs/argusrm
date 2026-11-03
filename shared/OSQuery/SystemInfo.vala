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
	 * One ''system_info'' row.
	 */
	public class SystemInfo : Row
	{
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<SystemInfo>(db, agent_id, rows, "system_info", {});
		}

		/**
		 * Create ''system_info''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS system_info (
					id                 INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id           INTEGER NOT NULL,
					hostname           TEXT NOT NULL DEFAULT '',
					uuid               TEXT NOT NULL DEFAULT '',
					cpu_type           TEXT NOT NULL DEFAULT '',
					cpu_subtype        TEXT NOT NULL DEFAULT '',
					cpu_brand          TEXT NOT NULL DEFAULT '',
					cpu_physical_cores INTEGER NOT NULL DEFAULT 0,
					cpu_logical_cores  INTEGER NOT NULL DEFAULT 0,
					cpu_microcode      TEXT NOT NULL DEFAULT '',
					physical_memory    INT64 NOT NULL DEFAULT 0,
					hardware_vendor    TEXT NOT NULL DEFAULT '',
					hardware_model     TEXT NOT NULL DEFAULT '',
					hardware_version   TEXT NOT NULL DEFAULT '',
					hardware_serial    TEXT NOT NULL DEFAULT '',
					board_vendor       TEXT NOT NULL DEFAULT '',
					board_model        TEXT NOT NULL DEFAULT '',
					board_version      TEXT NOT NULL DEFAULT '',
					board_serial       TEXT NOT NULL DEFAULT '',
					computer_name      TEXT NOT NULL DEFAULT '',
					local_hostname     TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("system_info create failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("SystemInfo", typeof(SystemInfo));
		}

		public string hostname { get; set; default = ""; }
		public string uuid { get; set; default = ""; }
		public string cpu_type { get; set; default = ""; }
		public string cpu_subtype { get; set; default = ""; }
		public string cpu_brand { get; set; default = ""; }
		public int cpu_physical_cores { get; set; default = 0; }
		public int cpu_logical_cores { get; set; default = 0; }
		public string cpu_microcode { get; set; default = ""; }
		/**
		 * Byte count. ''int64'' because it does not fit in ''int''.
		 */
		public int64 physical_memory { get; set; default = 0; }
		public string hardware_vendor { get; set; default = ""; }
		public string hardware_model { get; set; default = ""; }
		public string hardware_version { get; set; default = ""; }
		public string hardware_serial { get; set; default = ""; }
		public string board_vendor { get; set; default = ""; }
		public string board_model { get; set; default = ""; }
		public string board_version { get; set; default = ""; }
		public string board_serial { get; set; default = ""; }
		public string computer_name { get; set; default = ""; }
		public string local_hostname { get; set; default = ""; }
	}
}
