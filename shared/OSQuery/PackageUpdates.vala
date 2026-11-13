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
	 * One ''package_updates'' row.
	 *
	 * Fake osquery row sent through ''OSQuery.sync'' with the
	 * package names that have an update waiting on an agent.
	 * Existing names stay with their original {@link since} time,
	 * new names are inserted, and names left out of the snapshot
	 * are deleted.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
	 * rows.add(new Argus.Shared.OSQuery.PackageUpdates() { name = "bash" });
	 * }}}
	 */
	public class PackageUpdates : Row
	{
		/**
		 * Apply one agent's pending-update snapshot to ''package_updates''.
		 *
		 * A name already stored for ''agent_id'' is left untouched so
		 * {@link since} does not change. A new name is inserted with
		 * ''since'' set to now. A stored name missing from ''rows''
		 * is deleted.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows pending package names
		 * @return true when every row has type {@link PackageUpdates}
		 */
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != typeof(PackageUpdates)) {
					return false;
				}
			}
			var query = new SQ.Query<PackageUpdates>(db, "package_updates");
			var stored = new Gee.ArrayList<PackageUpdates>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var index = new Gee.HashMap<string, PackageUpdates>();
			foreach (var old in stored) {
				if (!index.has_key(old.name)) {
					index.set(old.name, old);
					continue;
				}
				query.deleteId(old.id);
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			var seen = new Gee.HashMap<string, bool>();
			foreach (var row in rows) {
				var pkg = (PackageUpdates) row;
				if (pkg.name == "" || seen.has_key(pkg.name)) {
					continue;
				}
				seen.set(pkg.name, true);
				if (index.has_key(pkg.name)) {
					index.unset(pkg.name);
					continue;
				}
				pkg.id = 0;
				pkg.agent_id = agent_id;
				pkg.since = now;
				query.insert(pkg);
			}
			foreach (var old in index.values) {
				query.deleteId(old.id);
			}
			return true;
		}

		public override string table_name() { return "package_updates"; }

		public override string rpc_name() { return "PackageUpdates"; }

		/**
		 * Create ''package_updates''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS package_updates (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id INTEGER NOT NULL,
					name     TEXT NOT NULL DEFAULT '',
					since    INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("package_updates create failed: %s", db.db.errmsg());
			}
			var idx = """
				CREATE INDEX IF NOT EXISTS package_updates_agent_name
				ON package_updates (agent_id, name);
				""";
			if (Sqlite.OK != db.db.exec(idx, null, out errmsg)) {
				GLib.warning("package_updates index failed: %s", db.db.errmsg());
			}
			var idx_name = """
				CREATE INDEX IF NOT EXISTS package_updates_name_agent
				ON package_updates (name, agent_id, since);
				""";
			if (Sqlite.OK != db.db.exec(idx_name, null, out errmsg)) {
				GLib.warning("package_updates name index failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("PackageUpdates", typeof(PackageUpdates));
		}

		/**
		 * Package name that has an update waiting.
		 */
		public string name { get; set; default = ""; }
		/**
		 * Unix time this update was first recorded for the agent.
		 */
		public int since { get; set; default = 0; }
	}
}
