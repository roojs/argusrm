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

namespace Argus.Server.Net
{
	/**
	 * nftables allowlist for one TCP port.
	 *
	 * The object owns the ''argusrm_PORT'' inet table. Mutable IPv4 and
	 * IPv6 sets hold the allowed source addresses. The fixed chains accept
	 * set members and reject other traffic sent to {@link port}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var firewall = new Argus.Server.Net.NFTables(817);
	 * var addresses = new Gee.ArrayList<GLib.InetAddress>();
	 * addresses.add(new GLib.InetAddress.from_string("192.0.2.10"));
	 * firewall.apply(addresses);
	 * }}}
	 */
	public class NFTables : GLib.Object
	{
		/**
		 * TCP port protected by this table.
		 */
		public uint16 port { get; private set; default = 0; }

		/**
		 * True while the input chain jumps into the allowlist.
		 */
		public bool enabled { get; private set; default = false; }

		private string table = "";
		private bool ready = false;
		private bool loaded = false;
		private Nft.Context context;
		private Gee.ArrayList<GLib.InetAddress> addresses {
			get; set; default = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
		}

		/**
		 * Create and reconcile the Argus table for one TCP port.
		 *
		 * Construction creates the table, chains, named sets, and the
		 * fixed accept and reject rules. {@link apply} loads existing
		 * set members and changes them.
		 *
		 * @param port TCP port protected by this table
		 */
		public NFTables(uint16 port)
		{
			GLib.Object();
			this.port = port;
			this.table = "argusrm_" + port.to_string();
			this.context = new Nft.Context();
			if (this.context.buffer_output() != 0 || this.context.buffer_error() != 0) {
				GLib.warning("could not buffer nftables output for port %u", (uint) this.port);
				return;
			}
			var setup = """
add table inet %s
add set inet %s allowed_ipv4 { type ipv4_addr; }
add set inet %s allowed_ipv6 { type ipv6_addr; }
add chain inet %s input { type filter hook input priority filter; policy accept; }
add chain inet %s allowlist
""".printf(this.table, this.table, this.table, this.table, this.table);
			if (this.context.run_cmd_from_buffer(setup) != 0) {
				GLib.warning("could not create nftables structure for port %u: %s",
					(uint) this.port, this.context.get_error_buffer().strip());
				return;
			}
			if (this.context.unbuffer_output() != 0 || this.context.buffer_output() != 0 ||
				this.context.run_cmd_from_buffer("list chain inet " + this.table +
					" allowlist") != 0) {
				GLib.warning("could not read nftables rules for port %u: %s",
					(uint) this.port, this.context.get_error_buffer().strip());
				return;
			}
			var existing_rules = this.context.get_output_buffer();
			var rules = "";
			if (!existing_rules.contains("comment \"argusrm-ipv4\"")) {
				rules += "add rule inet " + this.table + " allowlist ip saddr @allowed_ipv4 accept" +
					" comment \"argusrm-ipv4\"\n";
			}
			if (!existing_rules.contains("comment \"argusrm-ipv6\"")) {
				rules += "add rule inet " + this.table + " allowlist ip6 saddr @allowed_ipv6 accept" +
					" comment \"argusrm-ipv6\"\n";
			}
			if (!existing_rules.contains("comment \"argusrm-reject\"")) {
				rules += "add rule inet " + this.table + " allowlist reject comment \"argusrm-reject\"\n";
			}
			if (rules != "" && this.context.run_cmd_from_buffer(rules) != 0) {
				GLib.warning("could not create nftables rules for port %u: %s",
					(uint) this.port, this.context.get_error_buffer().strip());
				return;
			}
			this.ready = true;
		}

		/**
		 * Reconcile the complete source-address allowlist.
		 *
		 * The first call loads existing set members. One libnftables
		 * transaction then adds and removes only changed set elements.
		 * A failed transaction is logged and leaves the retained list
		 * unchanged.
		 *
		 * @param addresses complete IPv4 and IPv6 allowlist
		 * @return true when the retained list matches the kernel sets
		 */
		public bool apply(Gee.ArrayList<GLib.InetAddress> addresses)
		{
			if (!this.ready) {
				return false;
			}
			if (!this.load()) {
				return false;
			}
			var updated = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
			updated.add_all(addresses);
			var commands = "";
			foreach (var address in this.addresses) {
				if (updated.contains(address)) {
					continue;
				}
				if (address.get_family() == GLib.SocketFamily.IPV4) {
					commands += "delete element inet %s allowed_ipv4 { %s }\n".printf(this.table, address.to_string());
					continue;
				}
				commands += "delete element inet %s allowed_ipv6 { %s }\n".printf(this.table, address.to_string());
			}
			foreach (var address in updated) {
				if (this.addresses.contains(address)) {
					continue;
				}
				if (address.get_family() == GLib.SocketFamily.IPV4) {
					commands += "add element inet %s allowed_ipv4 { %s }\n".printf(this.table, address.to_string());
					continue;
				}
				commands += "add element inet %s allowed_ipv6 { %s }\n".printf(this.table, address.to_string());
			}
			if (commands.length == 0) {
				return true;
			}
			if (this.context.run_cmd_from_buffer(commands) != 0) {
				GLib.warning("could not update nftables allowlist for port %u: %s",
					(uint) this.port, this.context.get_error_buffer().strip());
				return false;
			}
			this.addresses = updated;
			return true;
		}

		/**
		 * Read existing set members into the retained allowlist.
		 *
		 * The first {@link apply} reads the sets. A later call
		 * returns without reading them again. An empty set stays
		 * empty. Failure does not mark the sets loaded.
		 *
		 * @return true when the sets are already loaded or were read
		 */
		private bool load()
		{
			if (this.loaded) {
				return true;
			}
			string[] set_names = { "allowed_ipv4", "allowed_ipv6" };
			foreach (var set_name in set_names) {
				if (this.context.unbuffer_output() != 0 || this.context.buffer_output() != 0 ||
					this.context.run_cmd_from_buffer("list set inet " + this.table + " " +
						set_name) != 0) {
					GLib.warning("could not read nftables set for port %u: %s",
						(uint) this.port, this.context.get_error_buffer().strip());
					return false;
				}
				var output = this.context.get_output_buffer();
				var marker = "elements = {";
				var start = output.index_of(marker);
				if (start < 0) {
					continue;
				}
				start += marker.length;
				var end = output.index_of("}", start);
				if (end < start) {
					GLib.warning("invalid nftables set output for port %u", (uint) this.port);
					return false;
				}
				foreach (var value in output.substring(start, end - start).split(",")) {
					var address = new GLib.InetAddress.from_string(value.strip());
					if (address == null) {
						GLib.warning("invalid address in nftables set for port %u", (uint) this.port);
						return false;
					}
					if (!this.addresses.contains(address)) {
						this.addresses.add(address);
					}
				}
			}
			this.loaded = true;
			return true;
		}

		/**
		 * Enforce the retained allowlist on this port.
		 *
		 * Repeated calls leave one jump rule in the input chain.
		 */
		public void enable()
		{
			if (!this.ready || this.enabled) {
				return;
			}
			var command = "flush chain inet " + this.table + " input\n" +
				"add rule inet " + this.table + " input tcp dport " + this.port.to_string() +
				" jump allowlist\n";
			if (this.context.run_cmd_from_buffer(command) != 0) {
				GLib.warning("could not enable nftables for port %u: %s",
					(uint) this.port, this.context.get_error_buffer().strip());
				return;
			}
			this.enabled = true;
		}

		/**
		 * Stop enforcing the allowlist without destroying its sets.
		 *
		 * Repeated calls leave the input chain empty.
		 */
		public void disable()
		{
			if (!this.ready || !this.enabled) {
				return;
			}
			if (this.context.run_cmd_from_buffer("flush chain inet " + this.table + " input") != 0) {
				GLib.warning("could not disable nftables for port %u: %s",
					(uint) this.port, this.context.get_error_buffer().strip());
				return;
			}
			this.enabled = false;
		}
	}
}
