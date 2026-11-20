/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Shared.Net
{
	/**
	 * Kernel route lookups (Linux netlink).
	 */
	public class Route : GLib.Object
	{
		/**
		 * @param host destination hostname or IP
		 * @return false when there is no routable path (Linux); always true elsewhere
		 */
		public static bool can_route_to(string host)
		{
#if LINUX
			if (host == "") {
				return false;
			}
			GLib.InetAddress? address = new GLib.InetAddress.from_string(host);
			if (address == null) {
				try {
					var resolved = GLib.Resolver.get_default().lookup_by_name(host);
					if (resolved.length() == 0) {
						return false;
					}
					address = resolved.nth_data(0);
				} catch (GLib.Error e) {
					return false;
				}
			}
			return Route.preferred_source(address) != null;
#else
			return true;
#endif
		}

		/**
		 * Preferred source the kernel would use toward ''destination''.
		 *
		 * Same netlink lookup as {@link Argus.Server.Net.Interfaces.route}; no
		 * check that the source is a local {@link Argus.Server.Net.Address}.
		 *
		 * @return the source, or null when there is no route (Linux only)
		 */
		public static GLib.InetAddress? preferred_source(GLib.InetAddress destination)
		{
#if LINUX
			if (destination == null) {
				return null;
			}
			var sock = new Nl.Socket();
			if (sock.connect(Nl.NETLINK_ROUTE) != 0) {
				return null;
			}
			var key = destination.to_string();
			if (destination.get_family() != GLib.SocketFamily.IPV4 &&
				destination.get_family() != GLib.SocketFamily.IPV6) {
				return null;
			}
			var af = destination.get_family() == GLib.SocketFamily.IPV6 ?
				Posix.AF_INET6 : Posix.AF_INET;
			var length = af == Posix.AF_INET6 ? 16 : 4;
			var raw = new uint8[length];
			uint8* packed = raw;
			if (Posix.inet_pton(af, key, packed) != 1) {
				return null;
			}
			var dest = new Nl.Address(af, raw);
			unowned Nl.Route? found = null;
			if (Nl.Route.lookup(sock, dest, out found) != 0 || found == null) {
				return null;
			}
			unowned Nl.Address? src = found.get_pref_src();
			if (src == null || (src.get_family() != Posix.AF_INET &&
				src.get_family() != Posix.AF_INET6) ||
				(src.get_len() != 4 && src.get_len() != 16)) {
				found.unref();
				return null;
			}
			var family = src.get_family() == Posix.AF_INET6 ?
				GLib.SocketFamily.IPV6 : GLib.SocketFamily.IPV4;
			var copy = new uint8[(int) src.get_len()];
			GLib.Memory.copy((void*) copy, src.binary(), src.get_len());
			found.unref();
			return new GLib.InetAddress.from_bytes(copy, family);
#else
			return null;
#endif
		}
	}
}