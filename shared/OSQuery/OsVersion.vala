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
	public enum PackageManager
	{
		APT,
		DNF,
		WIN,
		UNKNOWN
	}

	/**
	 * One ''os_version'' row.
	 *
	 * Each registered agent stores one operating-system row,
	 * joined onto {@link SystemInfo.list} for the Machines
	 * page.
	 */
	public class OsVersion : Row
	{
		private static SQ.Database db;

		/**
		 * Store one agent's ''os_version'' row.
		 *
		 * Each agent has one operating-system row. A snapshot
		 * that does not carry a single {@link OsVersion} is
		 * rejected. Stored package check fields stay.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows single-row ''os_version'' snapshot
		 * @return true when ''rows'' has one ''OsVersion'' row
		 */
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			if (rows.size != 1 || rows.get(0).get_type() != typeof(OsVersion)) {
				return false;
			}
			var newer = (OsVersion) rows.get(0);
			newer.agent_id = agent_id;
			var query = new SQ.Query<OsVersion>(db, "os_version");
			var stored = new Gee.ArrayList<OsVersion>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			if (stored.size == 0) {
				newer.id = 0;
				newer.added_dt = now;
				newer.updated_dt = 0;
				newer.deleted_dt = 0;
				query.insert(newer);
				return true;
			}
			var old = stored.get(0);
			if (old.deleted_dt == 0 && old.compare(newer)) {
				return true;
			}
			var updated = new OsVersion();
			updated.copy_from(old, {});
			string[] keep = {
				"id", "added-dt", "updated-dt", "deleted-dt",
				"pkgs-updated", "pkgs-status"
			};
			updated.copy_from(newer, keep);
			updated.deleted_dt = 0;
			updated.updated_dt = now;
			query.updateOld(old, updated);
			return true;
		}

		public override string table_name() { return "os_version"; }

		public override string rpc_name() { return "OsVersion"; }

		/**
		 * Create ''os_version''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			OsVersion.db = db;
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
					codename        TEXT NOT NULL DEFAULT '',
					arch            TEXT NOT NULL DEFAULT '',
					pkgs_updated    INTEGER NOT NULL DEFAULT 0,
					pkgs_status     INTEGER NOT NULL DEFAULT 0,
					reboot_required INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("os_version create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "os_version");
			db.db.exec("ALTER TABLE os_version ADD COLUMN pkgs_updated INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN pkgs_status INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN reboot_required INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
		}

		/**
		 * Register this row and ''OsVersion.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("OsVersion", typeof(OsVersion));
			OLLMrpc.Request.add_class(
				"OsVersion", typeof(OsVersion),
				"list", "i"
			);
		}

		/**
		 * Stored ''os_version'' row for one agent.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''deleted_dt'' is set is absent. A
		 * caller that is not a controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<OsVersion>();
			if (agent_id > 0) {
				var query = new SQ.Query<OsVersion>(OsVersion.db, "os_version");
				var columns = string.joinv(", ",
					query.getColsExcept({ "pkgs-status" }, "os_version."));
				query.selectQuery(@"
					SELECT
						$(columns),
						CASE
							WHEN os_version.pkgs_updated = 0 THEN -1
							ELSE os_version.pkgs_status
						END as pkgs_status
					FROM
						os_version
					WHERE
						os_version.agent_id = $(agent_id)
					AND
						os_version.deleted_dt = 0
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
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
		 * Unix time this host last checked installed packages.
		 *
		 * ''0'' means that check has not happened.
		 */
		public int pkgs_updated { get; set; default = 0; }
		/**
		 * Installed packages are up to date.
		 *
		 * ''1'' when they are. ''0'' when an update is waiting.
		 */
		public int pkgs_status { get; set; default = 0; }
		/**
		 * Status text for {@link pkgs_status}.
		 *
		 * Derived from {@link pkgs_updated} and {@link pkgs_status}.
		 * Not stored or sent on the wire.
		 */
		public string tooltip_pkgs_status {
			owned get {
				if (this.pkgs_updated == 0) {
					return "";
				}
				switch (this.pkgs_status) {
					case 0:
						return "Package updates waiting";

					case 1:
						return "Packages up to date";

					default:
						return "";
				}
			}
		}
		/**
		 * A system restart is waiting on this host.
		 *
		 * ''1'' when waiting. ''0'' when not.
		 */
		public int reboot_required { get; set; default = 0; }

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
