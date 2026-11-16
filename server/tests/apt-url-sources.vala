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
	 * ''apt_sources_catalog'' reconcile into ''apt_url'' (offline).
	 */
	class AptUrlSourcesTest
	{
		static int main()
		{
			var dir = "";
			try {
				dir = GLib.DirUtils.make_tmp("argus-apt-url-sources-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temporary database: %s\n", e.message);
				return 1;
			}
			var db = new SQ.Database(
				GLib.Path.build_filename(dir, "sources.sqlite"), true);
			Argus.Shared.Agent.init_db(db);
			Argus.Shared.OSQuery.init_db(db);
			Argus.Shared.SQT.init_db(db);
			Argus.Shared.OSQuery.AptSources.init_db(db);

			var agent_id = Argus.Shared.Agent.query(db).insert(
				new Argus.Shared.Agent() {
					fingerprint = "apt-host",
					status = 1,
					hostname = "apt-host",
				});
			if (agent_id < 1) {
				GLib.printerr("fail insert agent\n");
				return 1;
			}

			var expected_key =
				"http://archive.ubuntu.com/ubuntu|noble|main|amd64";
			var apt = new SQ.Query<Argus.Shared.OSQuery.AptSources>(
				db, "apt_sources");
			if (apt.insert(new Argus.Shared.OSQuery.AptSources() {
				agent_id = agent_id,
				name = "ubuntu",
				source = "deb",
				base_uri = "http://archive.ubuntu.com/ubuntu",
				release = "noble",
				components = "main",
				architectures = "amd64 arm64",
			}) < 1) {
				GLib.printerr("fail insert apt_sources\n");
				return 1;
			}

			Argus.Shared.OSQuery.AptSources.reconcile_apt_url(db);

			var urls = new Gee.ArrayList<Argus.Shared.SQT.AptUrl>();
			Argus.Shared.SQT.AptUrl.query(db).select("", urls);
			if (urls.size != 1) {
				GLib.printerr(
					"fail apt_url count %u expected 1\n",
					urls.size);
				return 1;
			}
			if (urls[0].url_key != expected_key) {
				GLib.printerr(
					"fail url_key `%s` expected `%s`\n",
					urls[0].url_key,
					expected_key);
				return 1;
			}
			if (urls[0].base_uri != "http://archive.ubuntu.com/ubuntu"
					|| urls[0].suite != "noble"
					|| urls[0].components != "main"
					|| urls[0].arch != "amd64") {
				GLib.printerr("fail apt_url columns\n");
				return 1;
			}

			urls[0].packages_etag = "keep-me";
			Argus.Shared.SQT.AptUrl.query(db).updateById(urls[0]);
			Argus.Shared.OSQuery.AptSources.reconcile_apt_url(db);
			var again = new Gee.ArrayList<Argus.Shared.SQT.AptUrl>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("url_key", expected_key);
			Argus.Shared.SQT.AptUrl.query(db).selectWhere(
				"WHERE url_key = $url_key",
				new Gee.HashMap<string, int>(),
				text_binds,
				again);
			if (again.size != 1 || again[0].packages_etag != "keep-me") {
				GLib.printerr("fail INSERT OR IGNORE clobbered row\n");
				return 1;
			}

			return 0;
		}
	}
}