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
	 * Local addresses for this server.
	 *
	 * {@link Application} holds the one instance.
	 *
	 * Construction reads the addresses on this machine and marks each
	 * one public or internal. {@link route} asks netlink which of those
	 * addresses the kernel would use as the source and remembers the answer.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var source = app.interfaces.route(address);
	 * }}}
	 */
	public class Interfaces : GLib.Object
	{
		/**
		 * Addresses on this machine.
		 */
		public Gee.ArrayList<Address> addresses {
			get; set; default = new Gee.ArrayList<Address>((a, b) => {
				return a.address.equal(b.address);
			});
		}

		private Nl.Socket sock;
		private bool ready = false;
		private Gee.HashMap<string, Address> routes {
			get; set; default = new Gee.HashMap<string, Address>();
		}
		private Gee.HashSet<string> unrouted {
			get; set; default = new Gee.HashSet<string>();
		}

		/**
		 * Read this machine's addresses.
		 */
		public Interfaces()
		{
			GLib.Object();
			this.sock = new Nl.Socket();
			var connected = this.sock.connect(Nl.NETLINK_ROUTE);
			if (connected != 0) {
				GLib.warning("could not open netlink: %s", Nl.strerror(connected));
				return;
			}
			this.ready = true;
			Nl.Cache? found = null;
			if (Nl.Addr.read(this.sock, out found) != 0 || found == null) {
				GLib.warning("could not read interface addresses");
				return;
			}
			unowned Nl.Addr? addr = Nl.Addr.first(found);
			while (addr != null) {
				unowned Nl.Address? local = addr.get_local();
				addr = addr.next();
				if (local == null) {
					continue;
				}
				if (local.get_family() != Posix.AF_INET && local.get_family() != Posix.AF_INET6) {
					continue;
				}
				if (local.get_len() != 4 && local.get_len() != 16) {
					continue;
				}
				var family = GLib.SocketFamily.IPV4;
				if (local.get_family() == Posix.AF_INET6) {
					family = GLib.SocketFamily.IPV6;
				}
				var copy = new uint8[(int) local.get_len()];
				GLib.Memory.copy((void*) copy, local.binary(), local.get_len());
				var item = new Address();
				item.address = new GLib.InetAddress.from_bytes(copy, family);
				if (this.addresses.contains(item)) {
					continue;
				}
				this.addresses.add(item);
			}
			foreach (var item in this.addresses) {
				var inet = item.address;
				if (inet.is_loopback || inet.is_link_local || inet.is_any || inet.is_multicast) {
					continue;
				}
				unowned uint8[] bytes = inet.to_bytes();
				if (inet.get_family() == GLib.SocketFamily.IPV4 &&
					(bytes[0] == 10 ||
					(bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
					(bytes[0] == 192 && bytes[1] == 168))) {
					continue;
				}
				if (inet.get_family() == GLib.SocketFamily.IPV6 &&
					(bytes[0] == 0xfc || bytes[0] == 0xfd)) {
					continue;
				}
				item.is_internal = false;
			}
		}

		/**
		 * Local address the kernel would use as the source.
		 *
		 * The choice is remembered. A missing route, or a source that is
		 * not one of {@link addresses}, returns null.
		 *
		 * @param address destination
		 * @return the preferred source, or null when no route exists
		 */
		public Address? route(GLib.InetAddress address)
		{
			var key = address.to_string();
			if (this.routes.has_key(key)) {
				return this.routes.get(key);
			}
			if (this.unrouted.contains(key) || !this.ready) {
				return null;
			}
			var af = Posix.AF_INET;
			if (address.get_family() == GLib.SocketFamily.IPV6) {
				af = Posix.AF_INET6;
			} else if (address.get_family() != GLib.SocketFamily.IPV4) {
				this.unrouted.add(key);
				return null;
			}
			var length = 4;
			if (af == Posix.AF_INET6) {
				length = 16;
			}
			var raw = new uint8[length];
			uint8* packed = raw;
			if (Posix.inet_pton(af, key, packed) != 1) {
				this.unrouted.add(key);
				return null;
			}
			var destination = new Nl.Address(af, raw);
			unowned Nl.Route? found = null;
			if (Nl.Route.lookup(this.sock, destination, out found) != 0 || found == null) {
				this.unrouted.add(key);
				return null;
			}
			unowned Nl.Address? source = found.get_pref_src();
			if (source == null || (source.get_family() != Posix.AF_INET &&
				source.get_family() != Posix.AF_INET6) ||
				(source.get_len() != 4 && source.get_len() != 16)) {
				found.unref();
				this.unrouted.add(key);
				return null;
			}
			var family = GLib.SocketFamily.IPV4;
			if (source.get_family() == Posix.AF_INET6) {
				family = GLib.SocketFamily.IPV6;
			}
			var copy = new uint8[(int) source.get_len()];
			GLib.Memory.copy((void*) copy, source.binary(), source.get_len());
			found.unref();
			var inet = new GLib.InetAddress.from_bytes(copy, family);
			foreach (var item in this.addresses) {
				if (!item.address.equal(inet)) {
					continue;
				}
				this.routes.set(key, item);
				return item;
			}
			this.unrouted.add(key);
			return null;
		}
	}
}
