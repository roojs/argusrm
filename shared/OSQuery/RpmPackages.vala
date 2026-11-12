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
					package_group    TEXT NOT NULL DEFAULT '',
					update_available INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("rpm_packages create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "rpm_packages");
			db.db.exec("ALTER TABLE rpm_packages ADD COLUMN update_available INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
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
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					""".printf(agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						name,
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(package_group, '')) AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(vendor, '')) AS vendor,
						MIN(epoch || ':' || version || '-' || release) AS min_version,
						MAX(epoch || ':' || version || '-' || release) AS max_version,
						MAX(size) AS max_size,
						COUNT(DISTINCT agent_id) AS installed
					FROM
						rpm_packages
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						deleted_dt = 0
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
		 * A newer candidate is already on this host.
		 *
		 * ''1'' when an update is waiting. ''0'' when not.
		 */
		public int update_available { get; set; default = 0; }
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
