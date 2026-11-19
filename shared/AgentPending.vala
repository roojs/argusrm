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

namespace Argus.Shared
{
	/**
	 * One machine waiting to be accepted.
	 *
	 * The table is ''agent_pending''. A flagged ''0000'' registration
	 * appends a row and stores the temporary certificate. The row is
	 * not an ''agent'' yet, and the app firewall does not list it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var row = new Argus.Shared.AgentPending();
	 * Argus.Shared.AgentPending.query(db).insert(row);
	 * }}}
	 */
	public class AgentPending : GLib.Object, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public string hostname { get; set; default = ""; }
		public string fingerprint { get; set; default = ""; }
		public string certificate { get; set; default = ""; }
		public string requester { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		/**
		 * True when the tick on this row is on.
		 *
		 * The registration list sets this. It is not a column.
		 */
		public bool picked { get; set; default = false; }

		/**
		 * Rows in ''agent_pending''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<AgentPending> query(SQ.Database db)
		{
			return new SQ.Query<AgentPending>(db, "agent_pending");
		}

		/**
		 * Create ''agent_pending''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS agent_pending (
					id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					ip          TEXT NOT NULL DEFAULT '',
					hostname    TEXT NOT NULL DEFAULT '',
					fingerprint TEXT NOT NULL UNIQUE,
					certificate TEXT NOT NULL DEFAULT '',
					requester   TEXT NOT NULL DEFAULT '',
					created     INT64 NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("agent_pending create failed: %s", db.db.errmsg());
			}
		}
	}
}
