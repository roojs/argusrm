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
	 * One ''mounts'' row.
	 */
	public class Mounts : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Mounts>(db, agent_id, rows, "mounts", { "path" });
		}

		public override string table_name() { return "mounts"; }

		public override string rpc_name() { return "Mounts"; }

		/**
		 * Create ''mounts''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Mounts.db = db;
			db.exec("""
				CREATE TABLE IF NOT EXISTS mounts (
					id                INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id          INTEGER NOT NULL,
					device            TEXT NOT NULL DEFAULT '',
					device_alias      TEXT NOT NULL DEFAULT '',
					path              TEXT NOT NULL DEFAULT '',
					type              TEXT NOT NULL DEFAULT '',
					flags             TEXT NOT NULL DEFAULT '',
					blocks            INT64 NOT NULL DEFAULT 0,
					blocks_free       INT64 NOT NULL DEFAULT 0,
					blocks_available  INT64 NOT NULL DEFAULT 0,
					blocks_size       INT64 NOT NULL DEFAULT 0,
					inodes            INT64 NOT NULL DEFAULT 0,
					inodes_free       INT64 NOT NULL DEFAULT 0
				);
				""");
			Argus.Shared.init_db_audit(db, "mounts");
		}

		/**
		 * Register this row and ''Mounts.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Mounts", typeof(Mounts));
			OLLMrpc.Request.add_class(
				"Mounts", typeof(Mounts),
				"list", "i"
			);
		}

		/**
		 * Stored ''mounts'' rows for one agent.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''agent_id'' is not in ''agent'' or
		 * whose ''deleted_dt'' is set is absent. A caller that is not a
		 * controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Mounts>();
			if (agent_id > 0) {
				var query = new SQ.Query<Mounts>(Mounts.db, "mounts");
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					ORDER BY
						path
					""".printf(agent_id), rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * True for a virtual, loop, or snap mount.
		 *
		 * The Storage grid hides these until the user turns on system
		 * mounts. A disk, a pool, and a network filesystem stay visible.
		 * ''/dev'', ''/proc'', ''/sys'', ''/run'', and ''/snap'' are
		 * system paths. A ''/dev/loop'' device is a system mount.
		 *
		 * @return true when the row is not a storage volume
		 */
		public bool is_system_mount()
		{
			if (this.path == "/dev" || this.path.has_prefix("/dev/")
				|| this.path == "/proc" || this.path.has_prefix("/proc/")
				|| this.path == "/sys" || this.path.has_prefix("/sys/")
				|| this.path == "/run" || this.path.has_prefix("/run/")
				|| this.path == "/snap" || this.path.has_prefix("/snap/")) {
				return true;
			}
			if (this.device.has_prefix("/dev/loop")) {
				return true;
			}
			var kind = this.ctype.down();
			switch (kind) {
				case "autofs":
				case "binfmt_misc":
				case "bpf":
				case "cgroup":
				case "cgroup2":
				case "configfs":
				case "debugfs":
				case "devpts":
				case "devtmpfs":
				case "efivarfs":
				case "fuse.gvfsd-fuse":
				case "fuse.lxcfs":
				case "fuse.portal":
				case "fuse.snapfuse":
				case "fuse.vmware-vmblock":
				case "fusectl":
				case "hugetlbfs":
				case "mqueue":
				case "nfsd":
				case "nsfs":
				case "overlay":
				case "overlayfs":
				case "proc":
				case "pstore":
				case "ramfs":
				case "rpc_pipefs":
				case "securityfs":
				case "squashfs":
				case "sysfs":
				case "tmpfs":
				case "tracefs":
					return true;
				default:
					return false;
			}
		}

		/**
		 * Total capacity for the Storage grid (''blocks * blocks_size'').
		 */
		public int64 display_total_bytes {
			get {
				return this.blocks * this.blocks_size;
			}
		}

		/**
		 * Free space for unprivileged users (''blocks_available * blocks_size'').
		 */
		public int64 display_free_bytes {
			get {
				return this.blocks_available * this.blocks_size;
			}
		}

		/**
		 * Used bytes (total minus free) for the Storage grid.
		 */
		public int64 display_used_bytes {
			get {
				var total = this.display_total_bytes;
				var free = this.display_free_bytes;
				if (total <= free) {
					return 0;
				}
				return total - free;
			}
		}

		/**
		 * Used capacity 0–100 for the Storage grid.
		 */
		public int display_percent_full {
			get {
				var total = this.display_total_bytes;
				if (total < 1) {
					return 0;
				}
				return (int) ((double) this.display_used_bytes / (double) total * 100.0 + 0.5);
			}
		}

		public string device { get; set; default = ""; }
		public string device_alias { get; set; default = ""; }
		public string path { get; set; default = ""; }
		public string ctype { get; set; default = ""; }
		public string flags { get; set; default = ""; }
		public int64 blocks { get; set; default = 0; }
		public int64 blocks_free { get; set; default = 0; }
		public int64 blocks_available { get; set; default = 0; }
		public int64 blocks_size { get; set; default = 0; }
		public int64 inodes { get; set; default = 0; }
		public int64 inodes_free { get; set; default = 0; }
	}
}