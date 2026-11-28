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
	public class DebPackages : Package
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_packages<DebPackages>(db, agent_id, rows);
		}

		public override string pkg_name() { return this.name + "\n" + this.arch; }

		public override string table_name() { return "deb_packages"; }

		public override string rpc_name() { return "DebPackages"; }

		/**
		 * Create ''deb_packages''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			DebPackages.db = db;
			db.exec("""
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
					priority   TEXT NOT NULL DEFAULT ''
				);
				""");
			Argus.Shared.init_db_audit(db, "deb_packages");
			db.exec("""
				CREATE INDEX IF NOT EXISTS deb_packages_deleted_name_agent
				ON deb_packages (deleted_dt, name, agent_id);
				""");
			db.exec("""
				CREATE INDEX IF NOT EXISTS deb_packages_agent
				ON deb_packages (agent_id);
				""");
			db.exec("""
				CREATE INDEX IF NOT EXISTS deb_packages_agent_name
				ON deb_packages (agent_id, name);
				""");
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
		 * ''deleted_dt'' is set, and fills ''explicit'' and ''leaf''.
		 * One machine also fills ''installed_dt''.
		 * A later ''since'' returns every row changed after that
		 * time, including a deleted row, without those flags.
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
						COALESCE(package_updates.since, 0) AS update_since,
						COALESCE(apt_explicit_install.installed_dt, 0) AS installed_dt,
						CASE
							WHEN apt_explicit_install.name IS NULL THEN 0
							ELSE 1
						END AS explicit,
						CASE
							WHEN depended.name IS NULL THEN 1
							ELSE 0
						END AS leaf
					FROM
						deb_packages
					LEFT JOIN
						package_updates
					ON
						package_updates.agent_id = deb_packages.agent_id
					AND
						package_updates.name = deb_packages.name
					LEFT JOIN
						apt_explicit_install
					ON
						apt_explicit_install.agent_id = deb_packages.agent_id
					AND
						apt_explicit_install.name = deb_packages.name
					LEFT JOIN (
						SELECT DISTINCT
							child.name AS name
						FROM (
							SELECT
								apt_url.id AS apt_url_id
							FROM
								apt_sources_catalog
							JOIN
								apt_url
							ON
								apt_url.url_key = apt_sources_catalog.url_key
							WHERE
								apt_sources_catalog.agent_id = %d
						) AS source
						JOIN
							apt_pkg_depends
						ON
							apt_pkg_depends.apt_url_id = source.apt_url_id
						JOIN
							apt_pkg AS parent
						ON
							parent.id = apt_pkg_depends.pkg_id
						JOIN
							deb_packages AS needed
						ON
							needed.agent_id = %d
						AND
							needed.name = parent.name
						AND
							needed.deleted_dt = 0
						JOIN
							apt_pkg AS child
						ON
							child.id = apt_pkg_depends.depends_pkg_id
					) AS depended
					ON
						depended.name = deb_packages.name
					WHERE
						deb_packages.agent_id = %d
					AND
						deb_packages.deleted_dt = 0
					""".printf(
						string.joinv(", ", query.getColsExcept(null, "deb_packages.")),
						agent_id,
						agent_id,
						agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						deb_packages.name AS name,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.section, '')) AS section,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.priority, '')) AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.maintainer, '')) AS maintainer,
						MIN(deb_packages.version || '-' || deb_packages.revision) AS min_version,
						MAX(deb_packages.version || '-' || deb_packages.revision) AS max_version,
						MAX(deb_packages.size) AS max_size,
						COUNT(DISTINCT deb_packages.agent_id) AS installed,
						COALESCE(pkg_updates.update_since, 0) AS update_since,
						MAX(
							CASE
								WHEN explicit_names.name IS NULL THEN 0
								ELSE 1
							END
						) AS explicit,
						MAX(
							CASE
								WHEN leaf_names.name IS NULL THEN 0
								ELSE 1
							END
						) AS leaf
					FROM
						deb_packages
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
						pkg_updates.name = deb_packages.name
					LEFT JOIN (
						SELECT DISTINCT
							deb_packages.name AS name
						FROM
							apt_explicit_install
						JOIN
							deb_packages
						ON
							deb_packages.agent_id = apt_explicit_install.agent_id
						AND
							deb_packages.name = apt_explicit_install.name
						AND
							deb_packages.deleted_dt = 0
						WHERE
							deb_packages.agent_id IN (SELECT id FROM agent)
					) AS explicit_names
					ON
						explicit_names.name = deb_packages.name
					LEFT JOIN (
						SELECT DISTINCT
							installed.name AS name
						FROM
							deb_packages AS installed
						LEFT JOIN (
							SELECT DISTINCT
								source.agent_id AS agent_id,
								child.name AS name
							FROM (
								SELECT
									apt_sources_catalog.agent_id AS agent_id,
									apt_url.id AS apt_url_id
								FROM
									apt_sources_catalog
								JOIN
									apt_url
								ON
									apt_url.url_key = apt_sources_catalog.url_key
								WHERE
									apt_sources_catalog.agent_id IN (
										SELECT
											id
										FROM
											agent
									)
							) AS source
							JOIN
								apt_pkg_depends
							ON
								apt_pkg_depends.apt_url_id = source.apt_url_id
							JOIN
								apt_pkg AS parent
							ON
								parent.id = apt_pkg_depends.pkg_id
							JOIN
								deb_packages AS needed
							ON
								needed.agent_id = source.agent_id
							AND
								needed.name = parent.name
							AND
								needed.deleted_dt = 0
							JOIN
								apt_pkg AS child
							ON
								child.id = apt_pkg_depends.depends_pkg_id
						) AS depended
						ON
							depended.agent_id = installed.agent_id
						AND
							depended.name = installed.name
						WHERE
							installed.deleted_dt = 0
						AND
							installed.agent_id IN (SELECT id FROM agent)
						AND
							depended.name IS NULL
					) AS leaf_names
					ON
						leaf_names.name = deb_packages.name
					WHERE
						deb_packages.deleted_dt = 0
					AND
						deb_packages.agent_id IN (SELECT id FROM agent)
					GROUP BY
						deb_packages.name
					ORDER BY
						deb_packages.name
					""", rows);
			}
			var response = new OLLMrpc.Response() {
				msg = "ok"
			};
			if (rows.size > 0) {
				response.retval = OLLMrpc.val("o", rows);
			}
			request.reply(response);
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
		 * Earliest unix time an update for this package has been waiting.
		 *
		 * Filled by ''list'' from ''package_updates''. Zero when none.
		 * Not stored on ''deb_packages''.
		 */
		public int update_since { get; set; default = 0; }
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
		/**
		 * ''1'' when this name was an explicit apt install.
		 *
		 * For one machine, that is a row in ''apt_explicit_install''.
		 * For every machine, any machine that still has the package
		 * installed counts. Filled by ''list'' when ''since'' is zero.
		 * Not stored.
		 */
		public int explicit { get; set; default = 0; }
		/**
		 * Unix time of the first explicit apt install of this name.
		 *
		 * Filled by ''list'' for one machine when ''since'' is zero,
		 * from ''apt_explicit_install''. Zero when this name was not
		 * an explicit install. Not stored on ''deb_packages''.
		 */
		public int installed_dt { get; set; default = 0; }
		/**
		 * ''1'' when nothing else installed depends on this name.
		 *
		 * For one machine, no other installed package on that machine
		 * has a catalog Depends or Pre-Depends edge onto it. For every
		 * machine, any such machine counts. A name with no catalog row
		 * is a leaf. Filled by ''list'' when ''since'' is zero. Not stored.
		 */
		public int leaf { get; set; default = 0; }
	}
}
