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

namespace Argus.Server
{
	/**
	 * ''apt_explicit_install'' insert-only sync (offline).
	 */
	class AptExplicitInstallTest
	{
		static int main()
		{
			var dir = "";
			try {
				dir = GLib.DirUtils.make_tmp("argus-apt-explicit-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temporary database: %s\n", e.message);
				return 1;
			}
			var db = new SQ.Database(
				GLib.Path.build_filename(dir, "explicit.sqlite"), true);
			Argus.Shared.OSQuery.AptExplicitInstall.init_db(db);
			var model = new Argus.Shared.OSQuery.AptExplicitInstall();
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			rows.add(new Argus.Shared.OSQuery.AptExplicitInstall() {
				name = "libnftables-dev",
				installed_dt = 100
			});
			rows.add(new Argus.Shared.OSQuery.AptExplicitInstall() {
				name = "libnftables-dev",
				installed_dt = 200
			});
			if (!model.sync(db, 7, rows)) {
				GLib.printerr("fail first sync\n");
				return 1;
			}
			var later = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			later.add(new Argus.Shared.OSQuery.AptExplicitInstall() {
				name = "libnl-3-dev",
				installed_dt = 300
			});
			if (!model.sync(db, 7, later)) {
				GLib.printerr("fail second sync\n");
				return 1;
			}
			var empty = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			if (!model.sync(db, 7, empty)) {
				GLib.printerr("fail empty sync\n");
				return 1;
			}
			var bad = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			bad.add(new Argus.Shared.OSQuery.DebPackages());
			if (model.sync(db, 7, bad)) {
				GLib.printerr("fail wrong row type was accepted\n");
				return 1;
			}
			var stored = new Gee.ArrayList<Argus.Shared.OSQuery.AptExplicitInstall>();
			new SQ.Query<Argus.Shared.OSQuery.AptExplicitInstall>(
				db, "apt_explicit_install").select("WHERE agent_id = 7", stored);
			if (stored.size != 2) {
				GLib.printerr("fail row count %d\n", stored.size);
				return 1;
			}
			foreach (var row in stored) {
				if (row.name == "libnftables-dev" && row.installed_dt != 100) {
					GLib.printerr("fail first date changed %d\n", row.installed_dt);
					return 1;
				}
				if (row.name == "libnl-3-dev" && row.installed_dt != 300) {
					GLib.printerr("fail second date %d\n", row.installed_dt);
					return 1;
				}
				if (row.deleted_dt != 0) {
					GLib.printerr("fail tombstone on %s\n", row.name);
					return 1;
				}
			}
			return 0;
		}
	}
}
