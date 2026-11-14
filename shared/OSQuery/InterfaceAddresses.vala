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
		private static SQ.Database db;

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
			InterfaceAddresses.db = db;
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
		 * Register this row and ''InterfaceAddresses.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("InterfaceAddresses", typeof(InterfaceAddresses));
			OLLMrpc.Request.add_class(
				"InterfaceAddresses", typeof(InterfaceAddresses),
				"list", "i"
			);
		}

		/**
		 * Stored ''interface_addresses'' rows for one agent.
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
			var rows = new Gee.ArrayList<InterfaceAddresses>();
			if (agent_id > 0) {
				var query = new SQ.Query<InterfaceAddresses>(
					InterfaceAddresses.db, "interface_addresses");
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					ORDER BY
						interface,
						address
					""".printf(agent_id), rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public string @interface { get; set; default = ""; }
		public string address { get; set; default = ""; }
		public string mask { get; set; default = ""; }
		public string broadcast { get; set; default = ""; }
		public string point_to_point { get; set; default = ""; }
		public string ctype { get; set; default = ""; }
	}
}
