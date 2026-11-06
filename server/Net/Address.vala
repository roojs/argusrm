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
	 * One local address on this machine.
	 *
	 * {@link Interfaces} reads these during construction and sets
	 * {@link is_internal}. Loopback, link-local, private IPv4, and
	 * unique-local IPv6 stay internal.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var local = new Argus.Server.Net.Address();
	 * local.address = new GLib.InetAddress.from_string("192.0.2.10");
	 * }}}
	 */
	public class Address : GLib.Object
	{
		/**
		 * Address configured on this machine.
		 */
		public GLib.InetAddress address {
			get; set; default = new GLib.InetAddress.any(GLib.SocketFamily.IPV4);
		}

		/**
		 * True for loopback, link-local, private IPv4, and unique-local IPv6.
		 */
		public bool is_internal { get; set; default = true; }
	}
}
