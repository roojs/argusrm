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
	 * One ''users'' row.
	 *
	 * Account list from osquery. Joined fields on {@link list} are not
	 * columns of ''users''.
	 */
	public class Users : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Users>(db, agent_id, rows, "users",
				{ "uid", "username", "uuid" });
		}

		public override string table_name() { return "users"; }

		public override string rpc_name() { return "Users"; }

		/**
		 * Create ''users''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Users.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS users (
					id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id    INTEGER NOT NULL,
					uid         INTEGER NOT NULL DEFAULT 0,
					gid         INTEGER NOT NULL DEFAULT 0,
					uid_signed  INTEGER NOT NULL DEFAULT 0,
					gid_signed  INTEGER NOT NULL DEFAULT 0,
					username    TEXT NOT NULL DEFAULT '',
					description TEXT NOT NULL DEFAULT '',
					directory   TEXT NOT NULL DEFAULT '',
					shell       TEXT NOT NULL DEFAULT '',
					uuid        TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("users create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "users");
		}

		/**
		 * Register this row and ''Users.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Users", typeof(Users));
			OLLMrpc.Request.add_class(
				"Users", typeof(Users),
				"list", "i"
			);
		}

		/**
		 * Stored ''users'' rows for one agent, with joined fields.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''agent_id'' is not in ''agent'' or
		 * whose ''deleted_dt'' is set is absent. Joined fields:
		 * {@link gid_groupname}, {@link logged_in_users_time},
		 * {@link groups_groupnames}. A caller that is not a controller
		 * is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Users>();
			if (agent_id > 0) {
				var query = new SQ.Query<Users>(Users.db, "users");
				var columns = string.joinv(", ", query.getColsExcept(null, "users."));
				query.selectQuery(@"
					SELECT
						$(columns),
						COALESCE((
							SELECT
								groups.groupname
							FROM
								groups
							WHERE
								groups.agent_id = users.agent_id
							AND
								groups.gid = users.gid
							AND
								groups.deleted_dt = 0
							LIMIT
								1
						), '') AS gid_groupname,
						COALESCE((
							SELECT
								MAX(logged_in_users.time)
							FROM
								logged_in_users
							WHERE
								logged_in_users.agent_id = users.agent_id
							AND
								logged_in_users.user = users.username
							AND
								logged_in_users.deleted_dt = 0
						), 0) AS logged_in_users_time,
						COALESCE((
							SELECT
								GROUP_CONCAT(DISTINCT groups.groupname)
							FROM
								user_groups
							INNER JOIN
								groups
							ON
								groups.agent_id = user_groups.agent_id
							AND
								groups.gid = user_groups.gid
							AND
								groups.deleted_dt = 0
							WHERE
								user_groups.agent_id = users.agent_id
							AND
								user_groups.uid = users.uid
							AND
								user_groups.deleted_dt = 0
						), '') AS groups_groupnames
					FROM
						users
					WHERE
						users.agent_id = $(agent_id)
					AND
						users.deleted_dt = 0
					AND
						users.agent_id IN (SELECT id FROM agent)
					ORDER BY
						users.uid,
						users.username
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public int64 uid { get; set; default = 0; }
		public int64 gid { get; set; default = 0; }
		public int64 uid_signed { get; set; default = 0; }
		public int64 gid_signed { get; set; default = 0; }
		public string username { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public string directory { get; set; default = ""; }
		public string shell { get; set; default = ""; }
		public string uuid { get; set; default = ""; }

		/*
		 * Joined / derived. Not columns of users.
		 */
		public string gid_groupname { get; set; default = ""; }
		public int64 logged_in_users_time { get; set; default = 0; }
		public string groups_groupnames { get; set; default = ""; }
	}
}
