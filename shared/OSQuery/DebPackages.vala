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
	 * One ''deb_packages'' row.
	 */
	public class DebPackages : Row
	{
		private static SQ.Database db;

		public override bool sync(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows,
			bool complete = true
		) {
			return this.sync_rows<DebPackages>(db, agent_id, rows,
				"deb_packages", { "name", "arch" }, complete);
		}

		/**
		 * Create ''deb_packages''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			DebPackages.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS deb_packages (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id   INTEGER NOT NULL,
					name       TEXT NOT NULL DEFAULT '',
					version    TEXT NOT NULL DEFAULT '',
					source     TEXT NOT NULL DEFAULT '',
					size       INT64 NOT NULL DEFAULT 0,
					arch       TEXT NOT NULL DEFAULT '',
					revision   TEXT NOT NULL DEFAULT '',
					status     TEXT NOT NULL DEFAULT '',
					maintainer TEXT NOT NULL DEFAULT '',
					section    TEXT NOT NULL DEFAULT '',
					priority   TEXT NOT NULL DEFAULT '',
					added_dt   INTEGER NOT NULL DEFAULT 0,
					updated_dt INTEGER NOT NULL DEFAULT 0,
					deleted_dt INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("deb_packages create failed: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE deb_packages ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE deb_packages ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE deb_packages ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("DebPackages", typeof(DebPackages));
			OLLMrpc.Request.add_class(
				"DebPackages", typeof(DebPackages),
				"list", "ii"
			);
		}

		/**
		 * One row per package name, or one agent's stored rows.
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
			var rows = new Gee.ArrayList<DebPackages>();
			var query = new SQ.Query<DebPackages>(DebPackages.db, "deb_packages");
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
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(section, '')) AS section,
						GROUP_CONCAT(DISTINCT NULLIF(priority, '')) AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(maintainer, '')) AS maintainer,
						(
							SELECT CASE
								WHEN revision = '' THEN version
								ELSE version || '-' || revision
							END
							FROM deb_packages AS low
							WHERE low.name = deb_packages.name
							AND low.agent_id IN (SELECT id FROM agent)
							AND low.deleted_dt = 0
							ORDER BY low.version ASC, low.revision ASC
							LIMIT 1
						) AS min_version,
						(
							SELECT CASE
								WHEN revision = '' THEN version
								ELSE version || '-' || revision
							END
							FROM deb_packages AS high
							WHERE high.name = deb_packages.name
							AND high.agent_id IN (SELECT id FROM agent)
							AND high.deleted_dt = 0
							ORDER BY high.version DESC, high.revision DESC
							LIMIT 1
						) AS max_version,
						MAX(size) AS max_size,
						COUNT(DISTINCT agent_id) AS installed
					FROM
						deb_packages
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
		public string source { get; set; default = ""; }
		/**
		 * Package size in bytes.
		 */
		public int64 size { get; set; default = 0; }
		public string arch { get; set; default = ""; }
		public string revision { get; set; default = ""; }
		public string status { get; set; default = ""; }
		public string maintainer { get; set; default = ""; }
		public string section { get; set; default = ""; }
		public string priority { get; set; default = ""; }
		/**
		 * Lowest version for this name, with the lowest revision
		 * of that version. Filled by ''list''. Not stored.
		 */
		public string min_version { get; set; default = ""; }
		/**
		 * Highest version for this name, with the highest revision
		 * of that version. Filled by ''list''. Not stored.
		 */
		public string max_version { get; set; default = ""; }
		/**
		 * Largest installed size for this name, in bytes.
		 * Filled by ''list''. Not stored.
		 */
		public int64 max_size { get; set; default = 0; }
		/**
		 * How many machines have this name. Filled by ''list''.
		 * Not stored.
		 */
		public int installed { get; set; default = 0; }
	}
}
