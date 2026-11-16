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
	 * One ''os_releases'' row.
	 *
	 * Stores one operating-system release loaded by the server from
	 * ''osinfo-query'' for platforms active in ''os_version''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rows = new Gee.ArrayList<Argus.Shared.OsReleases>();
	 * Argus.Shared.OsReleases.query(db).select("ORDER BY id ASC", rows);
	 * }}}
	 */
	public class OsReleases : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		private static SQ.Database db;

		public int64 id { get; set; default = 0; }
		/**
		 * Unique ''osinfo-query'' short identifier (e.g. ''debian12'').
		 */
		public string short_id { get; set; default = ""; }
		/**
		 * ''osinfo-query'' distribution key (e.g. ''debian'', ''win'').
		 */
		public string distro { get; set; default = ""; }
		/**
		 * Normalized ''os_version.platform'' (e.g. ''debian'', ''windows'').
		 */
		public string platform { get; set; default = ""; }
		/**
		 * Kernel/OS family from ''osinfo-query'' (e.g. ''linux'', ''winnt'').
		 */
		public string family { get; set; default = ""; }
		/**
		 * Full OS release name (e.g. ''Ubuntu 24.04 LTS'').
		 */
		public string name { get; set; default = ""; }
		/**
		 * Release version string (e.g. ''12'', ''24.04'', ''9.5'').
		 */
		public string version { get; set; default = ""; }
		/**
		 * Numeric major version parsed from {@link version}.
		 */
		public int major { get; set; default = 0; }
		/**
		 * Numeric minor version parsed from {@link version}.
		 */
		public int minor { get; set; default = 0; }
		/**
		 * Release codename from ''osinfo-query'' (e.g. ''bookworm'').
		 */
		public string codename { get; set; default = ""; }
		/**
		 * Release date in ''YYYY-MM-DD'' format, or empty when unreleased.
		 */
		public string released { get; set; default = ""; }
		/**
		 * End-of-life date in ''YYYY-MM-DD'' format, or empty when unset.
		 */
		public string eol { get; set; default = ""; }
		/**
		 * ''1'' when marked LTS in {@link name}, ''0'' otherwise.
		 */
		public int is_lts { get; set; default = 0; }
		/**
		 * Unix time this distribution's rows were last synced.
		 */
		public int updated { get; set; default = 0; }

		/**
		 * Rows in ''os_releases''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<OsReleases> query(SQ.Database db)
		{
			return new SQ.Query<OsReleases>(db, "os_releases");
		}

		/**
		 * Register this row and ''OsReleases.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("OsReleases", typeof(OsReleases));
			OLLMrpc.Request.add_class(
				"OsReleases", typeof(OsReleases),
				"list", "i"
			);
		}

		/**
		 * Stored ''os_releases'' row matching one agent's ''os_version''.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A caller that is not a controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<OsReleases>();
			if (agent_id > 0) {
				var query = OsReleases.query(OsReleases.db);
				var columns = string.joinv(", ", query.getColsExcept(null, "os_releases."));
				query.selectQuery(@"
					SELECT
						$(columns)
					FROM
						os_releases
					JOIN
						os_version
					ON
						os_version.platform = os_releases.platform
						AND os_version.major = os_releases.major
						AND os_version.minor = os_releases.minor
					WHERE
						os_version.agent_id = $(agent_id)
						AND os_version.deleted_dt = 0
					LIMIT 1
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Create ''os_releases''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			OsReleases.db = db;
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS os_releases (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					short_id TEXT NOT NULL DEFAULT '',
					distro   TEXT NOT NULL DEFAULT '',
					platform TEXT NOT NULL DEFAULT '',
					family   TEXT NOT NULL DEFAULT '',
					name     TEXT NOT NULL DEFAULT '',
					version  TEXT NOT NULL DEFAULT '',
					major    INTEGER NOT NULL DEFAULT 0,
					minor    INTEGER NOT NULL DEFAULT 0,
					codename TEXT NOT NULL DEFAULT '',
					released TEXT NOT NULL DEFAULT '',
					eol      TEXT NOT NULL DEFAULT '',
					is_lts   INTEGER NOT NULL DEFAULT 0,
					updated  INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("os_releases create failed: %s", db.db.errmsg());
			}
			db.db.exec("ALTER TABLE os_releases ADD COLUMN major INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_releases ADD COLUMN minor INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			var idx = """
				CREATE UNIQUE INDEX IF NOT EXISTS os_releases_short_id
				ON os_releases (short_id);
				""";
			if (Sqlite.OK != db.db.exec(idx, null, out errmsg)) {
				GLib.warning("os_releases index failed: %s", db.db.errmsg());
			}
			var platform_idx = """
				CREATE INDEX IF NOT EXISTS os_releases_platform
				ON os_releases (platform);
				""";
			if (Sqlite.OK != db.db.exec(platform_idx, null, out errmsg)) {
				GLib.warning("os_releases platform index failed: %s", db.db.errmsg());
			}
		}
	}
}
