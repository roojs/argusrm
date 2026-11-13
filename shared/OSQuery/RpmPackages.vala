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
	 * One ''rpm_packages'' row.
	 */
	public class RpmPackages : Package
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_packages<RpmPackages>(db, agent_id, rows);
		}

		public override string pkg_name() { return this.name + "\n" + this.arch; }

		public override string table_name() { return "rpm_packages"; }

		public override string rpc_name() { return "RpmPackages"; }

		/**
		 * Create ''rpm_packages''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			RpmPackages.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS rpm_packages (
					id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id      INTEGER NOT NULL,
					name          TEXT NOT NULL DEFAULT '',
					version       TEXT NOT NULL DEFAULT '',
					release       TEXT NOT NULL DEFAULT '',
					source        TEXT NOT NULL DEFAULT '',
					size          INT64 NOT NULL DEFAULT 0,
					sha1          TEXT NOT NULL DEFAULT '',
					arch          TEXT NOT NULL DEFAULT '',
					epoch         INTEGER NOT NULL DEFAULT 0,
					install_time  INT64 NOT NULL DEFAULT 0,
					vendor        TEXT NOT NULL DEFAULT '',
					package_group TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("rpm_packages create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "rpm_packages");
			var idx_query = """
				CREATE INDEX IF NOT EXISTS rpm_packages_deleted_name_agent
				ON rpm_packages (deleted_dt, name, agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_query, null, out errmsg)) {
				GLib.warning("rpm_packages index failed: %s", db.db.errmsg());
			}
			var idx_agent = """
				CREATE INDEX IF NOT EXISTS rpm_packages_agent
				ON rpm_packages (agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_agent, null, out errmsg)) {
				GLib.warning("rpm_packages agent index failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("RpmPackages", typeof(RpmPackages));
			OLLMrpc.Request.add_class(
				"RpmPackages", typeof(RpmPackages),
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
			var rows = new Gee.ArrayList<RpmPackages>();
			var query = new SQ.Query<RpmPackages>(RpmPackages.db, "rpm_packages");
			if (since > 0 && agent_id > 0) {
				query.select("""
					WHERE
						agent_id = %d
					AND
						agent_id IN (SELECT id FROM agent)
					AND
						(
							added_dt > %d
						OR
							updated_dt > %d
						OR
							deleted_dt > %d
						)
					""".printf(agent_id, since, since, since), rows);
			}
			if (since > 0 && agent_id <= 0) {
				query.select("""
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						(
							added_dt > %d
						OR
							updated_dt > %d
						OR
							deleted_dt > %d
						)
					""".printf(since, since, since), rows);
			}
			if (since <= 0 && agent_id > 0) {
				query.selectQuery("""
					SELECT
						%s,
						COALESCE(package_updates.since, 0) AS update_since
					FROM
						rpm_packages
					LEFT JOIN
						package_updates
					ON
						package_updates.agent_id = rpm_packages.agent_id
					AND
						package_updates.name = rpm_packages.name
					WHERE
						rpm_packages.agent_id = %d
					AND
						rpm_packages.deleted_dt = 0
					""".printf(
						string.joinv(", ", query.getColsExcept(null, "rpm_packages.")),
						agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						rpm_packages.name AS name,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.package_group, '')) AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.vendor, '')) AS vendor,
						MIN(rpm_packages.epoch || ':' || rpm_packages.version || '-' || rpm_packages.release) AS min_version,
						MAX(rpm_packages.epoch || ':' || rpm_packages.version || '-' || rpm_packages.release) AS max_version,
						MAX(rpm_packages.size) AS max_size,
						COUNT(DISTINCT rpm_packages.agent_id) AS installed,
						COALESCE(pkg_updates.update_since, 0) AS update_since
					FROM
						rpm_packages
					LEFT JOIN (
						SELECT
							name,
							MIN(since) AS update_since
						FROM
							package_updates
						WHERE
							agent_id IN (SELECT id FROM agent)
						GROUP BY
							name
					) AS pkg_updates
					ON
						pkg_updates.name = rpm_packages.name
					WHERE
						rpm_packages.deleted_dt = 0
					AND
						rpm_packages.agent_id IN (SELECT id FROM agent)
					GROUP BY
						rpm_packages.name
					ORDER BY
						rpm_packages.name
					""", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string release { get; set; default = ""; }
		public string source { get; set; default = ""; }
		/**
		 * Package size in bytes.
		 */
		public int64 size { get; set; default = 0; }
		public string sha1 { get; set; default = ""; }
		public string arch { get; set; default = ""; }
		public int epoch { get; set; default = 0; }
		/**
		 * Unix time the package was installed. Zero when unset.
		 */
		public int64 install_time { get; set; default = 0; }
		public string vendor { get; set; default = ""; }
		public string package_group { get; set; default = ""; }
		/**
		 * Earliest unix time an update for this package has been waiting.
		 *
		 * Filled by ''list'' from ''package_updates''. Zero when none.
		 * Not stored on ''rpm_packages''.
		 */
		public int update_since { get; set; default = 0; }
		/**
		 * Lowest epoch, version, and release for this name.
		 * The cell is epoch, version, and release. Filled by
		 * ''list''. Not stored.
		 */
		public string min_version { get; set; default = ""; }
		/**
		 * Highest epoch, version, and release for this name.
		 * Filled by ''list''. Not stored.
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
