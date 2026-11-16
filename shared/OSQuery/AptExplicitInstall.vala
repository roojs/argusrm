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
	 * One explicit apt install for an agent.
	 *
	 * The agent sends only names newer than its watermark.
	 * {@link sync} inserts a name the agent does not already
	 * have. A later row for the same name keeps the first
	 * ''installed_dt''. Names missing from the batch stay stored.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
	 * rows.add(new Argus.Shared.OSQuery.AptExplicitInstall() {
	 *     name = "libnftables-dev",
	 *     installed_dt = 1762404114
	 * });
	 * }}}
	 */
	public class AptExplicitInstall : Row
	{
		/**
		 * Insert names this agent does not already have.
		 *
		 * A name already stored is left alone, including its
		 * ''installed_dt''. An empty batch does not remove rows.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows new explicit install names
		 * @return true when every row has type {@link AptExplicitInstall}
		 */
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != typeof(AptExplicitInstall)) {
					return false;
				}
			}
			var query = new SQ.Query<AptExplicitInstall>(db, "apt_explicit_install");
			var stored = new Gee.ArrayList<AptExplicitInstall>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var have = new Gee.HashMap<string, bool>();
			foreach (var old in stored) {
				have.set(old.name, true);
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in rows) {
				var pkg = (AptExplicitInstall) row;
				if (pkg.name == "" || have.has_key(pkg.name)) {
					continue;
				}
				have.set(pkg.name, true);
				pkg.id = 0;
				pkg.agent_id = agent_id;
				pkg.added_dt = now;
				pkg.updated_dt = 0;
				pkg.deleted_dt = 0;
				query.insert(pkg);
			}
			return true;
		}

		public override string table_name() { return "apt_explicit_install"; }

		public override string rpc_name() { return "AptExplicitInstall"; }

		/**
		 * Binary package name, matching ''deb_packages.name''.
		 */
		public string name { get; set; default = ""; }

		/**
		 * Unix time of the apt history ''Start-Date'' for the
		 * first explicit install of {@link name}. ''0'' means unset.
		 */
		public int installed_dt { get; set; default = 0; }

		/**
		 * Create ''apt_explicit_install''.
		 *
		 * One row per agent and package name. {@link sync} does not
		 * set ''deleted_dt''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			db.exec("""
				CREATE TABLE IF NOT EXISTS apt_explicit_install (
					id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id        INTEGER NOT NULL,
					name            TEXT NOT NULL DEFAULT '',
					installed_dt    INTEGER NOT NULL DEFAULT 0
				);
				""");
			Argus.Shared.init_db_audit(db, "apt_explicit_install");
			db.exec("""
				CREATE UNIQUE INDEX IF NOT EXISTS apt_explicit_install_agent_name
				ON apt_explicit_install (agent_id, name);
				""");
		}

		/**
		 * Register this row for {@link OSQuery.sync}.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("AptExplicitInstall", typeof(AptExplicitInstall));
		}
	}
}
