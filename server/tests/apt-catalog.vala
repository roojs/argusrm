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
	 * Import Ubuntu ''main'' {@code Packages.gz} into a temporary database.
	 */
	class AptCatalogTest
	{
		private static bool has_pkg_name(SQ.Database db, string name)
		{
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("name", name);
			var found = new Gee.ArrayList<Argus.Shared.SQT.AptPkg>();
			Argus.Shared.SQT.AptPkg.query(db).selectWhere(
				"WHERE name = $name",
				new Gee.HashMap<string, int>(),
				text_binds,
				found);
			return found.size > 0;
		}

		static int main()
		{
			var dir = "";
			try {
				dir = GLib.DirUtils.make_tmp("argus-apt-catalog-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temporary database: %s\n", e.message);
				return 1;
			}
			var db = new SQ.Database(
				GLib.Path.build_filename(dir, "apt.sqlite"), true);
			Argus.Shared.SQT.init_db(db);

			var url = new Argus.Shared.SQT.AptUrl() {
				url_key = "ubuntu-main-amd64",
				base_uri = "http://archive.ubuntu.com/ubuntu",
				suite = "noble",
				components = "main",
				arch = "amd64",
			};
			Argus.Shared.SQT.AptUrl.query(db).insert(url);
			if (url.id < 1) {
				GLib.printerr("fail insert apt_url\n");
				return 1;
			}

			var catalog = new Argus.Server.Apt.CatalogImport(db, url);
			if (!catalog.import()) {
				GLib.printerr(
					"fail catalog import last_error=%s\n",
					url.last_error);
				return 1;
			}
			if (url.last_synced_dt < 1) {
				GLib.printerr("fail last_synced_dt not set\n");
				return 1;
			}

			if (!has_pkg_name(db, "libc6")) {
				GLib.printerr("fail libc6 not in apt_pkg\n");
				return 1;
			}

			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("apt_url_id", (int) url.id);
			var edges = new Gee.ArrayList<Argus.Shared.SQT.AptPkgDepends>();
			Argus.Shared.SQT.AptPkgDepends.query(db).selectWhere(
				"WHERE apt_url_id = $apt_url_id",
				int_binds,
				new Gee.HashMap<string, string>(),
				edges);
			if (edges.size < 500) {
				GLib.printerr(
					"fail too few apt_pkg_depends rows: %u\n",
					edges.size);
				return 1;
			}

			GLib.print(
				"apt catalog import ok: ubuntu noble main amd64 (%u depends edges)\n",
				edges.size);
			return 0;
		}
	}
}