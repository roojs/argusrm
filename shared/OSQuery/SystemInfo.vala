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
	 * A flag on that call joins the host's ''os_version''.
	 */
	public class SystemInfo : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<SystemInfo>(db, agent_id, rows, "system_info", {});
		}

		/**
		 * Create ''system_info''.
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
		 * A caller that is not a controller is refused.
		 * ''join'' adds that host's ''os_version'' onto the row.
		 * The joined values are not stored on ''system_info''.
		 *
		 * @param request inbound RPC from a controller
		 * @param join true to include the ''os_version'' columns
		 */
		public void list(OLLMrpc.Request request, bool join)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<SystemInfo>();
			var query = SystemInfo.query(SystemInfo.db);
			if (!join) {
				query.select("", rows);
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
						os_version.arch as arch
					FROM 
						system_info
					LEFT JOIN 
						os_version
					ON 
						os_version.agent_id = system_info.agent_id
					",rows);
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
	}
}
