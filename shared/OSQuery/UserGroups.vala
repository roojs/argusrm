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
	 * One ''user_groups'' row.
	 *
	 * Membership pairs from osquery. Used by {@link Users.list} and
	 * {@link Groups.list}. No list RPC.
	 */
	public class UserGroups : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<UserGroups>(db, agent_id, rows, "user_groups",
				{ "uid", "gid" });
		}

		public override string table_name() { return "user_groups"; }

		public override string rpc_name() { return "UserGroups"; }

		/**
		 * Create ''user_groups''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			UserGroups.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS user_groups (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id INTEGER NOT NULL,
					uid      INTEGER NOT NULL DEFAULT 0,
					gid      INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("user_groups create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "user_groups");
		}

		/**
		 * Register this row for ''OSQuery.sync''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("UserGroups", typeof(UserGroups));
		}

		public int64 uid { get; set; default = 0; }
		public int64 gid { get; set; default = 0; }
	}
}
