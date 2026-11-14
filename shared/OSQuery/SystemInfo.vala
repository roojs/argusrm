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
	 * One ''system_info'' row.
	 *
	 * ''SystemInfo.list'' returns every stored row to a controller.
	 * A flag on that call joins the host's ''os_version''
	 * and the distinct logged-in users.
	 */
	public class SystemInfo : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<SystemInfo>(db, agent_id, rows, "system_info", {});
		}

		public override string table_name() { return "system_info"; }

		public override string rpc_name() { return "SystemInfo"; }

		/**
		 * Create ''system_info''.
		 *
		 * A row whose ''agent_id'' is not in ''agent'' is deleted.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			SystemInfo.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS system_info (
					id                 INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id           INTEGER NOT NULL,
					hostname           TEXT NOT NULL DEFAULT '',
					uuid               TEXT NOT NULL DEFAULT '',
					cpu_type           TEXT NOT NULL DEFAULT '',
					cpu_subtype        TEXT NOT NULL DEFAULT '',
					cpu_brand          TEXT NOT NULL DEFAULT '',
					cpu_physical_cores INTEGER NOT NULL DEFAULT 0,
					cpu_logical_cores  INTEGER NOT NULL DEFAULT 0,
					cpu_microcode      TEXT NOT NULL DEFAULT '',
					physical_memory    INT64 NOT NULL DEFAULT 0,
					hardware_vendor    TEXT NOT NULL DEFAULT '',
					hardware_model     TEXT NOT NULL DEFAULT '',
					hardware_version   TEXT NOT NULL DEFAULT '',
					hardware_serial    TEXT NOT NULL DEFAULT '',
					board_vendor       TEXT NOT NULL DEFAULT '',
					board_model        TEXT NOT NULL DEFAULT '',
					board_version      TEXT NOT NULL DEFAULT '',
					board_serial       TEXT NOT NULL DEFAULT '',
					computer_name      TEXT NOT NULL DEFAULT '',
					local_hostname     TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("system_info create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "system_info");
			if (Sqlite.OK != db.db.exec("""
				DELETE FROM system_info
				WHERE agent_id NOT IN (SELECT id FROM agent);
				""", null, out errmsg)) {
				GLib.warning("system_info prune failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row and ''SystemInfo.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("SystemInfo", typeof(SystemInfo));
			OLLMrpc.Request.add_class(
				"SystemInfo", typeof(SystemInfo),
				"list", "b"
			);
		}

		/**
		 * List every stored row.
		 *
		 * A controller calls this. An agent with no row is absent.
		 * A row whose ''agent_id'' is not in ''agent'' is absent.
		 * Joined ''os_version'' and logins follow that same rule.
		 * A caller that is not a controller is refused.
		 * ''join'' adds that host's ''os_version'' onto the row.
		 * The same flag adds the distinct logged-in users.
		 * Those values are not stored on ''system_info''.
		 *
		 * @param request inbound RPC from a controller
		 * @param join true adds ''os_version'' and the logins
		 */
		public void list(OLLMrpc.Request request, bool join)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<SystemInfo>();
			var query = SystemInfo.query(SystemInfo.db);
			if (!join) {
				query.select("WHERE agent_id IN (SELECT id FROM agent)", rows);
			}
			if (join) {
				var columns = string.joinv(", ", query.getColsExcept(null, "system_info."));
				query.selectQuery(@"
					SELECT 
						$(columns),
						trim(COALESCE(os_version.name, '') || ' ' ||
							COALESCE(os_version.version, '')) as operating_system,
						CAST(os_version.major AS TEXT) as major,
						CAST(os_version.minor AS TEXT) as minor,
						CAST(os_version.patch AS TEXT) as patch,
						os_version.build as build,
						os_version.platform as platform,
						os_version.platform_like as platform_like,
						os_version.codename as codename,
						os_version.arch as arch,
						COALESCE(os_version.reboot_required, 0) as reboot_required,
						COALESCE((
							SELECT MAX(updated)
							FROM os_releases
							WHERE platform = os_version.platform
						), 0) as os_updated,
						CASE
							WHEN os_releases.id IS NULL THEN -1
							WHEN os_releases.eol != '' AND os_releases.eol < date('now') THEN 0
							WHEN (
								SELECT MAX(released)
								FROM os_releases
								WHERE platform = os_version.platform
								AND released <= date('now')
							) > os_releases.released THEN 2
							ELSE 1
						END as os_status,
						COALESCE(os_releases.eol, '') as os_eol,
						COALESCE((
							SELECT version
							FROM os_releases
							WHERE platform = os_version.platform
							AND released <= date('now')
							ORDER BY released DESC
							LIMIT 1
						), '') as os_latest,
						COALESCE(os_version.pkgs_updated, 0) as pkgs_updated,
						(
							SELECT COUNT(*)
							FROM package_updates
							WHERE package_updates.agent_id = system_info.agent_id
						) as pkgs_updates,
						CASE
							WHEN os_version.id IS NULL OR os_version.pkgs_updated = 0 THEN -1
							WHEN EXISTS (
								SELECT 1
								FROM package_updates
								WHERE package_updates.agent_id = system_info.agent_id
							) THEN 0
							ELSE 1
						END as pkgs_status,
						COALESCE((
							SELECT GROUP_CONCAT(DISTINCT logged_in_users.user)
							FROM logged_in_users
							WHERE logged_in_users.agent_id = system_info.agent_id
							AND logged_in_users.agent_id IN (SELECT id FROM agent)
							AND logged_in_users.user != ''
						), '') as logged_in_users
					FROM 
						system_info
					LEFT JOIN 
						os_version
					ON 
						os_version.agent_id = system_info.agent_id
						AND os_version.deleted_dt = 0
						AND os_version.agent_id IN (SELECT id FROM agent)
					LEFT JOIN
						os_releases
					ON
						os_releases.platform = os_version.platform
						AND os_releases.major = os_version.major
						AND os_releases.minor = os_version.minor
					WHERE
						system_info.agent_id IN (SELECT id FROM agent)
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Rows in ''system_info''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<SystemInfo> query(SQ.Database db)
		{
			return new SQ.Query<SystemInfo>(db, "system_info");
		}

		/**
		 * Network hostname, including the domain.
		 */
		public string hostname { get; set; default = ""; }
		/**
		 * Unique id provided by the system.
		 */
		public string uuid { get; set; default = ""; }
		/**
		 * CPU type.
		 */
		public string cpu_type { get; set; default = ""; }
		/**
		 * CPU subtype.
		 */
		public string cpu_subtype { get; set; default = ""; }
		/**
		 * Human readable CPU name.
		 */
		public string cpu_brand { get; set; default = ""; }
		/**
		 * Physical CPU cores.
		 */
		public int cpu_physical_cores { get; set; default = 0; }
		/**
		 * Logical CPU cores.
		 */
		public int cpu_logical_cores { get; set; default = 0; }
		/**
		 * CPU microcode version.
		 */
		public string cpu_microcode { get; set; default = ""; }
		/**
		 * Total physical memory, in bytes. ''int64'' because
		 * it does not fit in ''int''.
		 */
		public int64 physical_memory { get; set; default = 0; }
		/**
		 * Machine vendor.
		 */
		public string hardware_vendor { get; set; default = ""; }
		/**
		 * Machine model.
		 */
		public string hardware_model { get; set; default = ""; }
		/**
		 * Machine version.
		 */
		public string hardware_version { get; set; default = ""; }
		/**
		 * Device serial number.
		 */
		public string hardware_serial { get; set; default = ""; }
		/**
		 * Motherboard vendor.
		 */
		public string board_vendor { get; set; default = ""; }
		/**
		 * Motherboard model.
		 */
		public string board_model { get; set; default = ""; }
		/**
		 * Motherboard version.
		 */
		public string board_version { get; set; default = ""; }
		/**
		 * Motherboard serial number.
		 */
		public string board_serial { get; set; default = ""; }
		/**
		 * Friendly computer name.
		 */
		public string computer_name { get; set; default = ""; }
		/**
		 * Local hostname.
		 */
		public string local_hostname { get; set; default = ""; }
		/*
		 * The following are overlaid from os_version.
		 * Empty when that host has no os_version row.
		 */
		public string operating_system { get; set; default = ""; }
		public string major { get; set; default = ""; }
		public string minor { get; set; default = ""; }
		public string patch { get; set; default = ""; }
		public string build { get; set; default = ""; }
		public string platform { get; set; default = ""; }
		public string platform_like { get; set; default = ""; }
		public string codename { get; set; default = ""; }
		public string arch { get; set; default = ""; }
		/**
		 * Unix time the server last synced this host's platform releases.
		 *
		 * ''0'' when unchecked or not in ''os_releases''.
		 */
		public int os_updated { get; set; default = 0; }
		/**
		 * Joined OS release status for the grid.
		 *
		 * ''1'' up to date, ''2'' update available, ''0'' EOL,
		 * and ''-1'' when unchecked or unmatched.
		 */
		public int os_status { get; set; default = -1; }
		/**
		 * Matched release end-of-life date in ''YYYY-MM-DD'' format.
		 *
		 * Empty when unknown or unmatched. Not stored on ''system_info''.
		 */
		public string os_eol { get; set; default = ""; }
		/**
		 * Latest released version string for this host's platform.
		 *
		 * Empty when unmatched. Not stored on ''system_info''.
		 */
		public string os_latest { get; set; default = ""; }
		/**
		 * Unix time this host last synced pending package updates.
		 *
		 * ''0'' when unchecked. Not stored on ''system_info''.
		 */
		public int pkgs_updated { get; set; default = 0; }
		/**
		 * Joined package update status for the grid.
		 *
		 * ''1'' up to date, ''0'' updates available, and ''-1'' when
		 * unchecked or unsupported. Not stored on ''system_info''.
		 */
		public int pkgs_status { get; set; default = -1; }
		/**
		 * Number of pending package updates stored for this host.
		 *
		 * Not stored on ''system_info''.
		 */
		public int pkgs_updates { get; set; default = 0; }
		/**
		 * Windows restart waiting on this host.
		 *
		 * ''1'' when waiting. ''0'' otherwise.
		 */
		public int reboot_required { get; set; default = 0; }
		/**
		 * Distinct logins already stored for this host.
		 *
		 * Empty when that host has no session.
		 * Not a column of ''system_info''.
		 */
		public string logged_in_users { get; set; default = ""; }

		/**
		 * Package command for this operating system.
		 *
		 * Delegates to {@link OsVersion.package_manager} using
		 * {@link platform_like} and {@link platform}.
		 *
		 * @return apt, dnf, Windows, or unknown
		 */
		public PackageManager package_manager()
		{
			return new OsVersion() {
				platform_like = this.platform_like,
				platform = this.platform
			}.package_manager();
		}
	}
}
