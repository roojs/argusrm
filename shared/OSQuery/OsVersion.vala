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
	 * Which package command this operating system uses.
	 *
	 * {@link OsVersion.package_manager} returns one of these.
	 * ''UNKNOWN'' is a family with no command yet, including SUSE.
	 */
	public enum PackageManager {
		APT,
		DNF,
		WIN,
		UNKNOWN,
	}

	/**
	 * One ''os_version'' row.
	 *
	 * This is the operating system on the agent. Assets treats
	 * it as software, not as a column on the machine.
	 */
	public class OsVersion : Row
	{
		public override bool sync(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows,
			bool complete = true
		) {
			return this.sync_rows<OsVersion>(db, agent_id, rows,
				"os_version", { "name", "arch" }, complete);
		}

		/**
		 * Create ''os_version''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS os_version (
					id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id      INTEGER NOT NULL,
					name          TEXT NOT NULL DEFAULT '',
					version       TEXT NOT NULL DEFAULT '',
					major         INTEGER NOT NULL DEFAULT 0,
					minor         INTEGER NOT NULL DEFAULT 0,
					patch         INTEGER NOT NULL DEFAULT 0,
					build         TEXT NOT NULL DEFAULT '',
					platform      TEXT NOT NULL DEFAULT '',
					platform_like TEXT NOT NULL DEFAULT '',
					codename      TEXT NOT NULL DEFAULT '',
					arch          TEXT NOT NULL DEFAULT '',
					added_dt      INTEGER NOT NULL DEFAULT 0,
					updated_dt    INTEGER NOT NULL DEFAULT 0,
					deleted_dt    INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("os_version create failed: %s", db.db.errmsg());
			}
			db.db.exec(
				"ALTER TABLE os_version ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE os_version ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE os_version ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("OsVersion", typeof(OsVersion));
		}

		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public int major { get; set; default = 0; }
		public int minor { get; set; default = 0; }
		public int patch { get; set; default = 0; }
		public string build { get; set; default = ""; }
		public string platform { get; set; default = ""; }
		public string platform_like { get; set; default = ""; }
		public string codename { get; set; default = ""; }
		public string arch { get; set; default = ""; }

		/**
		 * Package command for this operating system.
		 *
		 * ''platform_like'' decides when it is set. ''platform''
		 * decides when that is empty. SUSE returns
		 * {@link PackageManager.UNKNOWN}.
		 *
		 * @return apt, dnf, Windows, or unknown
		 */
		public PackageManager package_manager()
		{
			switch (this.platform_like) {
				case "debian":
					return PackageManager.APT;
				case "rhel":
					return PackageManager.DNF;
				case "windows":
					return PackageManager.WIN;
				default:
					break;
			}
			switch (this.platform) {
				case "debian":
				case "ubuntu":
				case "elxr":
					return PackageManager.APT;
				case "rhel":
				case "fedora":
				case "centos":
					return PackageManager.DNF;
				case "windows":
					return PackageManager.WIN;
				default:
					return PackageManager.UNKNOWN;
			}
		}
	}
}
