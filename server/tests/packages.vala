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
			var snap = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			snap.add(new Argus.Shared.OSQuery.DebPackages() {
				name = "coreutils",
				arch = "amd64",
				version = "9.1"
			});
			if (!new Argus.Shared.OSQuery.DebPackages().sync(db, first, snap)) {
				GLib.printerr("fail sync insert\n");
				return 1;
			}
			var stored = new Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>();
			debs.select("WHERE agent_id = %d".printf((int) first), stored);
			var core_added = 0;
			var found_core = false;
			var found_bash = false;
			foreach (var row in stored) {
				if (row.name == "coreutils") {
					found_core = true;
					core_added = row.added_dt;
					if (row.added_dt == 0 || row.updated_dt != 0 || row.deleted_dt != 0) {
						GLib.printerr("fail coreutils insert times\n");
						return 1;
					}
				}
				if (row.name == "bash" && row.arch == "amd64") {
					found_bash = true;
					if (row.deleted_dt == 0) {
						GLib.printerr("fail bash still live\n");
						return 1;
					}
				}
			}
			if (!found_core || !found_bash || core_added == 0) {
				GLib.printerr("fail sync rows\n");
				return 1;
			}
			snap.clear();
			snap.add(new Argus.Shared.OSQuery.DebPackages() {
				name = "coreutils",
				arch = "amd64",
				version = "9.1"
			});
			snap.add(new Argus.Shared.OSQuery.DebPackages() {
				name = "bash",
				arch = "amd64",
				version = "5.2",
				revision = "1"
			});
			if (!new Argus.Shared.OSQuery.DebPackages().sync(db, first, snap)) {
				GLib.printerr("fail sync return\n");
				return 1;
			}
			stored.clear();
			debs.select("WHERE agent_id = %d".printf((int) first), stored);
			found_core = false;
			found_bash = false;
			foreach (var row in stored) {
				if (row.name == "coreutils") {
					found_core = true;
					if (row.added_dt != core_added || row.updated_dt != 0 || row.deleted_dt != 0) {
						GLib.printerr("fail coreutils unchanged\n");
						return 1;
					}
				}
				if (row.name == "bash" && row.arch == "amd64") {
					found_bash = true;
					if (row.deleted_dt != 0 || row.updated_dt == 0 || row.added_dt != 0) {
						GLib.printerr("fail bash returned\n");
						return 1;
					}
				}
			}
			if (!found_core || !found_bash) {
				GLib.printerr("fail return rows\n");
				return 1;
			}
			snap.clear();
			snap.add(new Argus.Shared.OSQuery.DebPackages() {
				name = "coreutils",
				arch = "amd64",
				version = "9.4"
			});
			snap.add(new Argus.Shared.OSQuery.DebPackages() {
				name = "bash",
				arch = "amd64",
				version = "5.2",
				revision = "1"
			});
			if (!new Argus.Shared.OSQuery.DebPackages().sync(db, first, snap)) {
				GLib.printerr("fail sync change\n");
				return 1;
			}
			stored.clear();
			debs.select("WHERE agent_id = %d".printf((int) first), stored);
			found_core = false;
			found_bash = false;
			foreach (var row in stored) {
				if (row.name == "coreutils") {
					found_core = true;
					if (row.added_dt != core_added || row.updated_dt == 0 ||
						row.deleted_dt != 0 || row.version != "9.4") {
						GLib.printerr("fail coreutils changed\n");
						return 1;
					}
				}
				if (row.name == "bash" && row.arch == "amd64") {
					found_bash = true;
					if (row.deleted_dt != 0 || row.version != "5.2") {
						GLib.printerr("fail bash kept\n");
						return 1;
					}
				}
			}
			if (!found_core || !found_bash) {
				GLib.printerr("fail change rows\n");
				return 1;
			}
			var request = new OLLMrpc.Request();
			request.connection = new OLLMrpc.Transport.Connection();
			new Argus.Shared.OSQuery.DebPackages().list(request, 0, 0);
			new Argus.Shared.OSQuery.DebPackages().list(request, (int) first, 0);
			new Argus.Shared.OSQuery.DebPackages().list(request, (int) first, core_added - 1);
			new Argus.Shared.OSQuery.RpmPackages().list(request, 0, 0);
			new Argus.Shared.OSQuery.Programs().list(request, 0, 0);
			GLib.print("ok package lists\n");
			return 0;
		}
	}
}
