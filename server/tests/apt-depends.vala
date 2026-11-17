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
	 * All dependents of a known package set. No network.
	 */
	class AptDependsTest
	{
		private static int64 add_pkg(SQ.Database db, string name)
		{
			var pkg = new Argus.Shared.SQT.AptPkg() {
				name = name
			};
			Argus.Shared.SQT.AptPkg.query(db).insert(pkg);
			return pkg.id;
		}

		private static void add_edge(
			SQ.Database db,
			int64 pkg_id,
			int64 depends_pkg_id,
			int64 apt_url_id
		) {
			Argus.Shared.SQT.AptPkgDepends.query(db).insert(new Argus.Shared.SQT.AptPkgDepends() {
				apt_url_id = apt_url_id,
				pkg_id = pkg_id,
				depends_pkg_id = depends_pkg_id
			});
		}

		private static bool has_name(Gee.ArrayList<Argus.Shared.SQV.AptDepends> rows, string name)
		{
			foreach (var row in rows) {
				if (row.name == name) {
					return true;
				}
			}
			return false;
		}

		static int main()
		{
			var dir = "";
			try {
				dir = GLib.DirUtils.make_tmp("argus-apt-depends-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temporary database: %s\n", e.message);
				return 1;
			}
			var db = new SQ.Database(
				GLib.Path.build_filename(dir, "depends.sqlite"), true);
			Argus.Shared.SQT.init_db(db);
			var libc6 = add_pkg(db, "libc6");
			var libfoo = add_pkg(db, "libfoo");
			var libbar = add_pkg(db, "libbar");
			var app = add_pkg(db, "app");
			var other = add_pkg(db, "other");
			var plugin = add_pkg(db, "plugin");
			var left = add_pkg(db, "left");
			var right = add_pkg(db, "right");
			if (libc6 < 1 || libfoo < 1 || app < 1) {
				GLib.printerr("fail insert apt_pkg\n");
				return 1;
			}
			add_edge(db, libfoo, libc6, 1);
			add_edge(db, libfoo, libc6, 2);
			add_edge(db, libbar, libfoo, 1);
			add_edge(db, app, libbar, 1);
			add_edge(db, other, libc6, 1);
			add_edge(db, plugin, libfoo, 1);
			add_edge(db, left, right, 1);
			add_edge(db, right, left, 1);
			var removed = Argus.Server.SQV.AptDepends.dependents(db, "libc6");
			if (removed.size != 5 ||
				!has_name(removed, "app") ||
				!has_name(removed, "libbar") ||
				!has_name(removed, "libfoo") ||
				!has_name(removed, "other") ||
				!has_name(removed, "plugin") ||
				has_name(removed, "libc6")) {
				GLib.printerr("fail libc6 dependents\n");
				return 1;
			}
			var from_foo = Argus.Server.SQV.AptDepends.dependents(db, "libfoo");
			if (from_foo.size != 3 ||
				!has_name(from_foo, "libbar") ||
				!has_name(from_foo, "app") ||
				!has_name(from_foo, "plugin")) {
				GLib.printerr("fail libfoo dependents\n");
				return 1;
			}
			var from_app = Argus.Server.SQV.AptDepends.dependents(db, "app");
			if (from_app.size != 0) {
				GLib.printerr("fail app dependents size %d\n", from_app.size);
				return 1;
			}
			var missing = Argus.Server.SQV.AptDepends.dependents(db, "missing");
			if (missing.size != 0) {
				GLib.printerr("fail missing dependents size %d\n", missing.size);
				return 1;
			}
			var cycle = Argus.Server.SQV.AptDepends.dependents(db, "left");
			if (cycle.size != 1 || cycle.get(0).name != "right") {
				GLib.printerr("fail cycle dependents\n");
				return 1;
			}
			GLib.print("apt dependents ok\n");
			return 0;
		}
	}
}
