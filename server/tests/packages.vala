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
	 * Run the package list queries against a temporary database.
	 *
	 * A query that SQLite will not prepare used to abort the
	 * server inside {@link Argus.Shared.OSQuery.DebPackages.list}.
	 * This calls that list, and the RPM and Windows lists.
	 */
	class PackagesTest
	{
		static int main()
		{
			var dir = "";
			try {
				dir = GLib.DirUtils.make_tmp("argus-packages-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temporary database: %s\n", e.message);
				return 1;
			}
			var path = GLib.Path.build_filename(dir, "packages.sqlite");
			var db = new SQ.Database(path, true);
			Argus.Shared.Agent.init_db(db);
			Argus.Shared.OSQuery.init_db(db);
			var first = Argus.Shared.Agent.query(db).insert(new Argus.Shared.Agent() {
				fingerprint = "host-a",
				status = 1,
				hostname = "host-a"
			});
			var second = Argus.Shared.Agent.query(db).insert(new Argus.Shared.Agent() {
				fingerprint = "host-b",
				status = 1,
				hostname = "host-b"
			});
			if (first < 1 || second < 1) {
				GLib.printerr("fail insert agent\n");
				return 1;
			}
			var debs = new SQ.Query<Argus.Shared.OSQuery.DebPackages>(db, "deb_packages");
			if (debs.insert(new Argus.Shared.OSQuery.DebPackages() {
				agent_id = first,
				name = "bash",
				version = "5.2",
				revision = "1",
				arch = "amd64",
				section = "shells",
				priority = "required",
				source = "bash",
				maintainer = "Debian",
				status = "install ok installed",
				size = 100
			}) < 1) {
				GLib.printerr("fail insert deb\n");
				return 1;
			}
			if (debs.insert(new Argus.Shared.OSQuery.DebPackages() {
				agent_id = second,
				name = "bash",
				version = "5.1",
				revision = "2",
				arch = "arm64",
				section = "shells",
				priority = "required",
				source = "bash",
				maintainer = "Debian",
				status = "install ok installed",
				size = 90
			}) < 1) {
				GLib.printerr("fail insert second deb\n");
				return 1;
			}
			var rpms = new SQ.Query<Argus.Shared.OSQuery.RpmPackages>(db, "rpm_packages");
			if (rpms.insert(new Argus.Shared.OSQuery.RpmPackages() {
				agent_id = first,
				name = "bash",
				version = "5.2",
				release = "1",
				arch = "x86_64",
				size = 80
			}) < 1) {
				GLib.printerr("fail insert rpm\n");
				return 1;
			}
			var programs = new SQ.Query<Argus.Shared.OSQuery.Programs>(db, "programs");
			if (programs.insert(new Argus.Shared.OSQuery.Programs() {
				agent_id = first,
				name = "Editor",
				version = "1.0",
				publisher = "Desk",
				identifying_number = "{1}"
			}) < 1) {
				GLib.printerr("fail insert program\n");
				return 1;
			}
			var request = new OLLMrpc.Request();
			request.connection = new OLLMrpc.Transport.Connection();
			new Argus.Shared.OSQuery.DebPackages().list(request, 0);
			new Argus.Shared.OSQuery.DebPackages().list(request, (int) first);
			new Argus.Shared.OSQuery.RpmPackages().list(request, 0);
			new Argus.Shared.OSQuery.Programs().list(request, 0);
			GLib.print("ok package lists\n");
			return 0;
		}
	}
}
