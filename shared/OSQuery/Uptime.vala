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
	 * One ''uptime'' row per host.
	 */
	public class Uptime : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Uptime>(db, agent_id, rows, "uptime", {});
		}

		public override string table_name() { return "uptime"; }

		public override string rpc_name() { return "Uptime"; }

		/**
		 * Create ''uptime''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Uptime.db = db;
			db.exec("""
				CREATE TABLE IF NOT EXISTS uptime (
					id             INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id       INTEGER NOT NULL,
					days           INTEGER NOT NULL DEFAULT 0,
					hours          INTEGER NOT NULL DEFAULT 0,
					minutes        INTEGER NOT NULL DEFAULT 0,
					seconds        INTEGER NOT NULL DEFAULT 0,
					total_seconds  INT64 NOT NULL DEFAULT 0
				);
				""");
			Argus.Shared.init_db_audit(db, "uptime");
		}

		/**
		 * Register this row and ''Uptime.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Uptime", typeof(Uptime));
			OLLMrpc.Request.add_class(
				"Uptime", typeof(Uptime),
				"list", "i"
			);
		}

		/**
		 * Stored ''uptime'' rows for one agent.
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
			var rows = new Gee.ArrayList<Uptime>();
			if (agent_id > 0) {
				var query = new SQ.Query<Uptime>(Uptime.db, "uptime");
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					""".printf(agent_id), rows);
			}
			var response = new OLLMrpc.Response() {
				msg = "ok"
			};
			if (rows.size > 0) {
				response.retval = OLLMrpc.val("o", rows);
			}
			request.reply(response);
		}

		public int days { get; set; default = 0; }
		public int hours { get; set; default = 0; }
		public int minutes { get; set; default = 0; }
		public int seconds { get; set; default = 0; }
		public int64 total_seconds { get; set; default = 0; }
	}
}