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
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<CpuInfo>(db, agent_id, rows, "cpu_info", { "device-id" });
		}

		public override string table_name() { return "cpu_info"; }

		public override string rpc_name() { return "CpuInfo"; }

		/**
		 * Create ''cpu_info''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			CpuInfo.db = db;
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
		 * Register this row and ''CpuInfo.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("CpuInfo", typeof(CpuInfo));
			OLLMrpc.Request.add_class(
				"CpuInfo", typeof(CpuInfo),
				"list", "i"
			);
		}

		/**
		 * Stored ''cpu_info'' rows for one agent.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''agent_id'' is not in ''agent'' or
		 * whose ''deleted_dt'' is set is absent. A caller that is not a
		 * controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<CpuInfo>();
			if (agent_id > 0) {
				var query = new SQ.Query<CpuInfo>(CpuInfo.db, "cpu_info");
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					ORDER BY
						device_id
					""".printf(agent_id), rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
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
