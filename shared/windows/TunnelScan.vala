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

namespace Argus.Shared
{
	/**
	 * Windows placeholder for VPN tunnel registration scan.
	 *
	 * {@link has_tunnel} is always false and {@link start} does
	 * nothing. The Linux implementation is ''shared/TunnelScan.vala''.
	 */
	public class TunnelScan : GLib.Object
	{
		/**
		 * Scan phase shown in the registration dialog.
		 */
		public enum Step
		{
			IDLE,
			SCANNING,
			CHECKING_PORTS,
			FOUND
		}

		public Step step { get; private set; default = Step.IDLE; }

		public string tunnel_interface { get; private set; default = ""; }

		public string tunnel_address { get; private set; default = ""; }

		public signal void server_found(string host, uint16 port);

		public bool has_tunnel()
		{
			this.tunnel_interface = "";
			this.tunnel_address = "";
			return false;
		}

		public void start(uint16 port = (uint16) Argus.REGISTER_PORT)
		{
		}

		public void stop()
		{
			if (this.step == Step.IDLE) {
				return;
			}
			this.step = Step.IDLE;
		}
	}
}