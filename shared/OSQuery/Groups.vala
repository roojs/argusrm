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
	 * One ''groups'' row.
	 *
	 * Group list from osquery. {@link member_count} on {@link list} is
	 * not a column of ''groups''.
	 */
	public class Groups : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Groups>(db, agent_id, rows, "groups",
				{ "gid", "groupname" });
		}

		public override string table_name() { return "groups"; }

		public override string rpc_name() { return "Groups"; }

		/**
		 * Create ''groups''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Groups.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS groups (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id   INTEGER NOT NULL,
					gid        INTEGER NOT NULL DEFAULT 0,
					gid_signed INTEGER NOT NULL DEFAULT 0,
					groupname  TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("groups create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "groups");
		}

		/**
		 * Register this row and ''Groups.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Groups", typeof(Groups));
			OLLMrpc.Request.add_class(
				"Groups", typeof(Groups),
				"list", "i"
			);
		}

		/**
		 * Stored ''groups'' rows for one agent, with {@link member_count}.
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
			var rows = new Gee.ArrayList<Groups>();
			if (agent_id > 0) {
				var query = new SQ.Query<Groups>(Groups.db, "groups");
				var columns = string.joinv(", ", query.getColsExcept(null, "groups."));
				query.selectQuery(@"
					SELECT
						$(columns),
						COALESCE((
							SELECT
								COUNT(DISTINCT user_groups.uid)
							FROM
								user_groups
							INNER JOIN
								users
							ON
								users.agent_id = user_groups.agent_id
							AND
								users.uid = user_groups.uid
							AND
								users.deleted_dt = 0
							WHERE
								user_groups.agent_id = groups.agent_id
							AND
								user_groups.gid = groups.gid
							AND
								user_groups.deleted_dt = 0
						), 0) AS member_count,
						COALESCE((
							SELECT
								COUNT(DISTINCT user_groups.uid)
							FROM
								user_groups
							INNER JOIN
								users
							ON
								users.agent_id = user_groups.agent_id
							AND
								users.uid = user_groups.uid
							AND
								users.deleted_dt = 0
							WHERE
								user_groups.agent_id = groups.agent_id
							AND
								user_groups.gid = groups.gid
							AND
								user_groups.deleted_dt = 0
							AND
								users.uid >= 1000
							AND
								users.uid != 65534
						), 0) AS users_uid_ge_1000_member_count
					FROM
						groups
					WHERE
						groups.agent_id = $(agent_id)
					AND
						groups.deleted_dt = 0
					AND
						groups.agent_id IN (SELECT id FROM agent)
					ORDER BY
						groups.gid,
						groups.groupname
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public int64 gid { get; set; default = 0; }
		public int64 gid_signed { get; set; default = 0; }
		public string groupname { get; set; default = ""; }

		/*
		 * Derived. Not a column of groups.
		 */
		public int64 member_count { get; set; default = 0; }
		/**
		 * Live members with ''uid >= 1000'' and not ''nobody''. Filled by
		 * {@link list}. Used by the groups list filter when system groups
		 * are hidden.
		 */
		public int64 users_uid_ge_1000_member_count { get; set; default = 0; }
	}
}
