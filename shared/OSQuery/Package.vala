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
	 * One installed package row.
	 *
	 * {@link DebPackages}, {@link RpmPackages}, and
	 * {@link Programs} extend this. {@link pkg_name} is the
	 * hash key. {@link sync_packages} applies one snapshot.
	 */
	public abstract class Package : Row
	{
		/**
		 * Key for the package hash.
		 *
		 * @return the fields that identify this package
		 */
		public abstract string pkg_name();

		/**
		 * Apply one package snapshot.
		 *
		 * ''T'' is the concrete row class. {@link Row.table_name} is
		 * the stored table. {@link pkg_name} is the hash key.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows complete table snapshot
		 * @return true when every row has type ''T''
		 */
		protected bool sync_packages<T>(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != typeof(T)) {
					return false;
				}
			}
			var query = new SQ.Query<T>(db, this.table_name());
			var stored = new Gee.ArrayList<T>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var index = new Gee.HashMap<string, Package>();
			foreach (var old in stored) {
				var pkg = (Package) old;
				var key = pkg.pkg_name();
				if (!index.has_key(key)) {
					index.set(key, pkg);
				}
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in rows) {
				var pkg = (Package) row;
				var key = pkg.pkg_name();
				var old = index.get(key);
				var newer = (Row) row;
				newer.agent_id = agent_id;
				if (old == null) {
					newer.id = 0;
					newer.added_dt = now;
					newer.updated_dt = 0;
					newer.deleted_dt = 0;
					query.insert((T) row);
					continue;
				}
				newer.id = old.id;
				newer.added_dt = old.added_dt;
				if (old.deleted_dt != 0) {
					newer.deleted_dt = 0;
					newer.updated_dt = now;
					query.updateOld((T) old, (T) row);
					index.unset(key);
					continue;
				}
				newer.deleted_dt = 0;
				if (!old.compare(newer)) {
					newer.updated_dt = now;
					query.updateOld((T) old, (T) row);
				}
				index.unset(key);
			}
			foreach (var old in index.values) {
				if (old.deleted_dt != 0) {
					continue;
				}
				old.deleted_dt = now;
				query.updateById((T) old);
			}
			return true;
		}
	}
}
