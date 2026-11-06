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
	 * Check {@link Agent.allowlist} against a temporary agent table
	 * and this machine's routes.
	 *
	 * No socket is opened and nftables is not changed. A stored
	 * address is kept when this machine has a route to it, private
	 * or public. No route leaves it out.
	 */
	class AllowlistTest
	{
		static string warnings = "";
		static int failures = 0;

		static void note(bool ok, string message, string detail)
		{
			if (ok) {
				GLib.print("ok %s\n", message);
				return;
			}
			failures++;
			GLib.printerr("fail %s\n%s\n", message, detail);
		}

		static int main()
		{
			GLib.Log.set_default_handler((domain, levels, message) => {
				if ((levels & GLib.LogLevelFlags.LEVEL_WARNING) == 0) {
					return;
				}
				warnings += message + "\n";
				GLib.printerr("%s\n", message);
			});
			var dir = "";
			try {
				dir = GLib.DirUtils.make_tmp("argus-allowlist-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temporary database: %s\n", e.message);
				return 1;
			}
			var path = GLib.Path.build_filename(dir, "agent.sqlite");
			var db = new SQ.Database(path, true);
			Argus.Shared.Agent.init_db(db);
			var interfaces = new Net.Interfaces();
			note(interfaces.addresses.size > 0, "local addresses loaded", "none");
			note(Agent.allowlist(db, interfaces).size == 0, "empty table", "");
			var now = new GLib.DateTime.now_utc().to_unix();
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "inactive", status = 0, ip = "203.0.113.10", created = now
			});
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "blank", status = 1, ip = "", created = now
			});
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "bad", status = 1, ip = "not-an-ip", created = now
			});
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "v4a", status = 1, ip = "1.1.1.1", created = now
			});
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "v4b", status = 1, ip = "1.1.1.1", created = now
			});
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "v6", status = 1, ip = "2001:db8::1", created = now
			});
			rows.add(new Argus.Shared.Agent() {
				fingerprint = "v4c", status = 1, ip = "198.51.100.20", created = now
			});
			foreach (var row in rows) {
				if (Argus.Shared.Agent.query(db).insert(row) > 0) {
					continue;
				}
				note(false, "insert " + row.fingerprint, row.ip);
			}
			warnings = "";
			var list = Agent.allowlist(db, interfaces);
			note(warnings.contains("not-an-ip"), "malformed stored address", warnings);
			var inactive = new GLib.InetAddress.from_string("203.0.113.10");
			var inactive_copies = 0;
			foreach (var item in list) {
				if (!item.equal(inactive)) {
					continue;
				}
				inactive_copies++;
			}
			note(inactive_copies == 0, "inactive address omitted", inactive_copies.to_string());
			string[] probes = { "1.1.1.1", "2001:db8::1", "198.51.100.20" };
			var routed = 0;
			var included = 0;
			foreach (var text in probes) {
				var address = new GLib.InetAddress.from_string(text);
				if (address == null) {
					note(false, "probe " + text, "");
					continue;
				}
				var source = interfaces.route(address);
				var expect = false;
				if (source == null) {
					GLib.print("route %s source none\n", text);
				}
				if (source != null) {
					routed++;
					included++;
					expect = true;
					GLib.print("route %s source %s internal %s\n",
						text, source.address.to_string(), source.is_internal ? "yes" : "no");
				}
				var copies = 0;
				foreach (var item in list) {
					if (!item.equal(address)) {
						continue;
					}
					copies++;
				}
				if (expect && copies == 1) {
					GLib.print("ok kept %s\n", text);
					continue;
				}
				if (!expect && copies == 0) {
					GLib.print("ok omitted %s\n", text);
					continue;
				}
				note(false, text, copies.to_string());
			}
			note(routed > 0, "at least one probe has a route", "");
			note(list.size == included, "allowlist size matches routed addresses", list.size.to_string());
			GLib.FileUtils.remove(path);
			GLib.FileUtils.remove(path + "-wal");
			GLib.FileUtils.remove(path + "-shm");
			GLib.DirUtils.remove(dir);
			if (failures == 0) {
				return 0;
			}
			return 1;
		}
	}
}
