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
	 * Manual check for {@link Net.NFTables}.
	 *
	 * Run this as root. It creates table inet argusrm_59917, changes that
	 * table, and deletes it before exiting. It is not part of the automatic
	 * test suite.
	 */
	class NftablesTest
	{
		const uint16 PORT = 59917;
		static Nft.Context reader;
		static string table = "";
		static string warnings = "";
		static string last_error = "";
		static int failures = 0;

		/**
		 * Record warnings from the firewall class.
		 */
		static void capture_log(string? domain, GLib.LogLevelFlags levels, string message)
		{
			if ((levels & GLib.LogLevelFlags.LEVEL_WARNING) == 0 &&
				(levels & GLib.LogLevelFlags.LEVEL_CRITICAL) == 0) {
				return;
			}
			if (domain != null && domain != "") {
				warnings += domain + ": " + message + "\n";
				GLib.printerr("%s: %s\n", domain, message);
				return;
			}
			warnings += message + "\n";
			GLib.printerr("%s\n", message);
		}

		static bool prepare()
		{
			return reader.unbuffer_output() == 0 && reader.buffer_output() == 0 &&
				reader.unbuffer_error() == 0 && reader.buffer_error() == 0;
		}

		static string query(string command)
		{
			last_error = "";
			if (!prepare() || reader.run_cmd_from_buffer(command) != 0) {
				last_error = reader.get_error_buffer().strip();
				return "";
			}
			return reader.get_output_buffer();
		}

		static bool change(string command)
		{
			if (!prepare() || reader.run_cmd_from_buffer(command) != 0) {
				last_error = reader.get_error_buffer().strip();
				GLib.printerr("nft: %s\n", last_error);
				return false;
			}
			return true;
		}

		static void remove_table()
		{
			if (!prepare()) {
				return;
			}
			reader.run_cmd_from_buffer("delete table inet " + table);
		}

		static void check(bool ok, string message, string detail)
		{
			if (ok) {
				GLib.print("ok %s\n", message);
				return;
			}
			failures++;
			GLib.printerr("fail %s\n%s\n", message, detail);
		}

		static Gee.ArrayList<GLib.InetAddress> allowlist(string[] values)
		{
			var list = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
			foreach (var value in values) {
				var address = new GLib.InetAddress.from_string(value);
				if (address == null) {
					failures++;
					GLib.printerr("invalid test address %s\n", value);
					continue;
				}
				list.add(address);
			}
			return list;
		}

		static void expect_quiet(string message)
		{
			var logged = warnings;
			warnings = "";
			check(logged == "", message, logged);
		}

		static void expect_warning(string message)
		{
			var logged = warnings;
			warnings = "";
			check(logged.length > 0, message, "no warning was logged");
		}

		static void expect_fixed_rules()
		{
			var output = query("list chain inet " + table + " allowlist");
			var detail = output + last_error;
			check(output.split("comment \"argusrm-ipv4\"").length - 1 == 1, "one ipv4 accept rule", detail);
			check(output.split("comment \"argusrm-ipv6\"").length - 1 == 1, "one ipv6 accept rule", detail);
			check(output.split("comment \"argusrm-reject\"").length - 1 == 1, "one reject rule", detail);
		}

		static void expect_structure()
		{
			var output = query("list table inet " + table);
			var detail = output + last_error;
			check(output.index_of("set allowed_ipv4") >= 0, "ipv4 set exists", detail);
			check(output.index_of("set allowed_ipv6") >= 0, "ipv6 set exists", detail);
			check(output.index_of("chain input") >= 0, "input chain exists", detail);
			check(output.index_of("chain allowlist") >= 0, "allowlist chain exists", detail);
			check(output.index_of("policy accept") >= 0, "input policy stays accept", detail);
			expect_fixed_rules();
		}

		static void expect_member(string set_name, string address, bool present)
		{
			var output = query("list set inet " + table + " " + set_name);
			var found = output.index_of(address) >= 0;
			var detail = output + last_error;
			if (present) {
				check(found, set_name + " contains " + address, detail);
				return;
			}
			check(!found, set_name + " omits " + address, detail);
		}

		static void expect_jump(bool present)
		{
			var output = query("list chain inet " + table + " input");
			var jumps = output.split("jump allowlist").length - 1;
			var detail = output + last_error;
			if (present) {
				check(jumps == 1, "one allowlist jump", detail);
				return;
			}
			check(jumps == 0, "port is not restricted", detail);
		}

		static int finish()
		{
			remove_table();
			var gone = query("list table inet " + table);
			check(gone == "", "test table is removed", gone);
			if (failures == 0) {
				GLib.print("ok nftables firewall\n");
				return 0;
			}
			GLib.printerr("%d nftables checks failed\n", failures);
			return 1;
		}

		/**
		 * Create the test table and verify allowlist changes against it.
		 */
		public static int run()
		{
			if (Posix.geteuid() != 0) {
				GLib.printerr("nftables test needs root\n");
				return 1;
			}
			GLib.Log.set_default_handler(capture_log);
			reader = new Nft.Context();
			if (reader.buffer_output() != 0 || reader.buffer_error() != 0) {
				GLib.printerr("could not buffer nftables output\n");
				return 1;
			}
			table = "argusrm_" + PORT.to_string();
			remove_table();
			warnings = "";
			var created = new Argus.Server.Net.NFTables(PORT);
			check(created.port == PORT, "table is bound to the test port", "");
			expect_quiet("construction is quiet");
			expect_structure();
			if (failures > 0) {
				return finish();
			}
			var repeated = new Argus.Server.Net.NFTables(PORT);
			check(repeated.port == PORT, "second table uses the same port", "");
			expect_quiet("reconstructing an existing table is quiet");
			expect_fixed_rules();
			if (!change("add element inet " + table + " allowed_ipv4 { 192.0.2.50 }")) {
				return finish();
			}
			var restarted = new Argus.Server.Net.NFTables(PORT);
			expect_quiet("restart construction does not rewrite fixed rules");
			expect_fixed_rules();
			restarted.apply(allowlist({ "192.0.2.50", "2001:db8::50" }));
			expect_quiet("first apply loads the existing address");
			expect_member("allowed_ipv4", "192.0.2.50", true);
			expect_member("allowed_ipv6", "2001:db8::50", true);
			expect_fixed_rules();
			restarted.apply(allowlist({ "192.0.2.51", "2001:db8::51" }));
			expect_quiet("changed allowlist applies");
			expect_member("allowed_ipv4", "192.0.2.51", true);
			expect_member("allowed_ipv4", "192.0.2.50", false);
			expect_member("allowed_ipv6", "2001:db8::51", true);
			expect_member("allowed_ipv6", "2001:db8::50", false);
			var before = query("list table inet " + table);
			restarted.apply(allowlist({ "192.0.2.51", "2001:db8::51" }));
			var after = query("list table inet " + table);
			expect_quiet("reapplying the same allowlist sends no mutation");
			check(before == after && before != "", "ruleset is unchanged by reapply", after + last_error);
			expect_jump(false);
			restarted.enable();
			expect_quiet("enable installs the port jump");
			expect_jump(true);
			expect_member("allowed_ipv4", "192.0.2.51", true);
			expect_member("allowed_ipv6", "2001:db8::51", true);
			restarted.enable();
			expect_quiet("repeating enable leaves the jump alone");
			expect_jump(true);
			expect_fixed_rules();
			restarted.disable();
			expect_quiet("disable removes the port jump");
			expect_jump(false);
			expect_member("allowed_ipv4", "192.0.2.51", true);
			expect_fixed_rules();
			restarted.disable();
			expect_quiet("repeating disable leaves the table alone");
			expect_jump(false);
			expect_fixed_rules();
			restarted.enable();
			expect_quiet("enable restores the retained allowlist");
			expect_jump(true);
			expect_member("allowed_ipv4", "192.0.2.51", true);
			expect_member("allowed_ipv6", "2001:db8::51", true);
			if (!change("delete element inet " + table + " allowed_ipv4 { 192.0.2.51 }")) {
				return finish();
			}
			restarted.apply(allowlist({ "192.0.2.52", "2001:db8::51" }));
			expect_warning("failed transaction is logged");
			expect_member("allowed_ipv4", "192.0.2.52", false);
			expect_member("allowed_ipv4", "192.0.2.51", false);
			expect_member("allowed_ipv6", "2001:db8::51", true);
			restarted.apply(allowlist({ "192.0.2.51", "192.0.2.53", "2001:db8::51" }));
			expect_quiet("retained address is not sent again");
			expect_member("allowed_ipv4", "192.0.2.53", true);
			expect_member("allowed_ipv4", "192.0.2.51", false);
			expect_member("allowed_ipv4", "192.0.2.52", false);
			expect_member("allowed_ipv6", "2001:db8::51", true);
			return finish();
		}
	}

	static int main()
	{
		return NftablesTest.run();
	}
}
