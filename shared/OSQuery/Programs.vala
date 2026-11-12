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
	 * One Windows ''programs'' row.
	 */
	public class Programs : Row
	{
		private static SQ.Database db;

		public override bool sync(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows,
			bool complete = true
		) {
			return this.sync_rows<Programs>(db, agent_id, rows,
				"programs", { "name", "identifying-number" }, complete);
		}

		/**
		 * Create ''programs''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Programs.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS programs (
					id                  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id            INTEGER NOT NULL,
					name                TEXT NOT NULL DEFAULT '',
					version             TEXT NOT NULL DEFAULT '',
					install_location    TEXT NOT NULL DEFAULT '',
					install_source      TEXT NOT NULL DEFAULT '',
					language            TEXT NOT NULL DEFAULT '',
					publisher           TEXT NOT NULL DEFAULT '',
					uninstall_string    TEXT NOT NULL DEFAULT '',
					install_date        TEXT NOT NULL DEFAULT '',
					identifying_number  TEXT NOT NULL DEFAULT '',
					added_dt            INTEGER NOT NULL DEFAULT 0,
					updated_dt          INTEGER NOT NULL DEFAULT 0,
					deleted_dt          INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("programs create failed: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE programs ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE programs ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE programs ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Programs", typeof(Programs));
			OLLMrpc.Request.add_class(
				"Programs", typeof(Programs),
				"list", "ii"
			);
		}

		/**
		 * One row per program name, or one agent's stored rows.
		 *
		 * A controller calls this. Zero lists every agent, added
		 * up by name. An ''agent_id'' greater than zero is a
		 * different query: that agent's stored rows, with no
		 * added-up columns. A row whose ''agent_id'' is not in
		 * ''agent'' is absent. A caller that is not a controller
		 * is refused. ''since'' zero leaves out a row whose
		 * ''deleted_dt'' is set. A later ''since'' returns every
		 * row changed after that time, including a deleted row.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id agent id, or zero for every agent
		 * @param since unix time, or zero for the current list
		 */
		public void list(OLLMrpc.Request request, int agent_id, int since)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Programs>();
			var query = new SQ.Query<Programs>(Programs.db, "programs");
			if (since > 0 && agent_id > 0) {
				query.select("""
					WHERE
						agent_id = %d
						AND agent_id IN (SELECT id FROM agent)
						AND (added_dt > %d OR updated_dt > %d OR deleted_dt > %d)
					""".printf(agent_id, since, since, since), rows);
			}
			if (since > 0 && agent_id <= 0) {
				query.select("""
					WHERE
						agent_id IN (SELECT id FROM agent)
						AND (added_dt > %d OR updated_dt > %d OR deleted_dt > %d)
					""".printf(since, since, since), rows);
			}
			if (since <= 0 && agent_id > 0) {
				query.select("""
					WHERE
						agent_id = %d
						AND deleted_dt = 0
						AND agent_id IN (SELECT id FROM agent)
					""".printf(agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						name,
						GROUP_CONCAT(DISTINCT NULLIF(publisher, '')) AS publisher,
						GROUP_CONCAT(DISTINCT NULLIF(language, '')) AS language,
						GROUP_CONCAT(DISTINCT NULLIF(identifying_number, '')) AS identifying_number,
						GROUP_CONCAT(DISTINCT NULLIF(install_date, '')) AS install_date,
						GROUP_CONCAT(DISTINCT NULLIF(install_location, '')) AS install_location,
						GROUP_CONCAT(DISTINCT NULLIF(install_source, '')) AS install_source,
						GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string,
						MIN(version) AS min_version,
						MAX(version) AS max_version,
						COUNT(DISTINCT agent_id) AS installed,
						COUNT(DISTINCT CASE
							WHEN uninstall_string != '' THEN agent_id
						END) AS uninstall_count
					FROM
						programs
					WHERE
						agent_id IN (SELECT id FROM agent)
						AND deleted_dt = 0
					GROUP BY
						name
					ORDER BY
						name
					""", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string install_location { get; set; default = ""; }
		public string install_source { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public string publisher { get; set; default = ""; }
		public string uninstall_string { get; set; default = ""; }
		public string install_date { get; set; default = ""; }
		public string identifying_number { get; set; default = ""; }
		/**
		 * Lowest version for this name. Filled by ''list''.
		 * Not stored.
		 */
		public string min_version { get; set; default = ""; }
		/**
		 * Highest version for this name. Filled by ''list''.
		 * Not stored.
		 */
		public string max_version { get; set; default = ""; }
		/**
		 * How many machines have this name. Filled by ''list''.
		 * Not stored.
		 */
		public int installed { get; set; default = 0; }
		/**
		 * How many of those machines have an uninstall string.
		 * Filled by ''list''. Not stored.
		 */
		public int uninstall_count { get; set; default = 0; }
	}
}
