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
	 * VPN tunnel scan for an open registration port.
	 *
	 * Linux and Android share this file. When a tunnel interface is
	 * up, the registration dialog tries {@link Argus.REGISTER_PORT}
	 * on the local /24 every twenty seconds. Browse can continue
	 * until a port answers; the dialog then moves to the PIN step
	 * on that host. Windows is ''shared/windows/TunnelScan.vala''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var scan = new Argus.Shared.TunnelScan();
	 * if (!scan.has_tunnel()) {
	 *     return;
	 * }
	 * scan.notify["step"].connect(() => { ... });
	 * scan.server_found.connect((host, port) => {
	 *     reg.adopt_probed_server(host, port);
	 * });
	 * scan.start();
	 * }}}
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

		/**
		 * Current {@link Step}.
		 */
		public Step step { get; private set; default = Step.IDLE; }

		/**
		 * Tunnel interface name when {@link has_tunnel} succeeded.
		 */
		public string tunnel_interface { get; private set; default = ""; }

		/**
		 * Local IPv4 on the tunnel when {@link has_tunnel} succeeded.
		 */
		public string tunnel_address { get; private set; default = ""; }

		private uint timeout_id = 0;
		/**
		 * Bumped on {@link start}, {@link stop}, and a successful
		 * connect so the twenty-second timer and {@link scan_round}
		 * from an older scan are ignored.
		 */
		private int scan_num = 0;
		/**
		 * Bumped at each {@link scan_round} so async connects from a
		 * previous pass over the /24 are ignored.
		 */
		private int round_num = 0;
		private bool running = false;
		private uint16 registration_port = (uint16) Argus.REGISTER_PORT;

		/**
		 * Registration port answered on ''host''.
		 */
		public signal void server_found(string host, uint16 port);

		/**
		 * Whether an up tunnel interface with an IPv4 address exists.
		 *
		 * Sets {@link tunnel_interface} and {@link tunnel_address}.
		 */
		public bool has_tunnel()
		{
			this.tunnel_interface = "";
			this.tunnel_address = "";
			Linux.Network.IfAddrs listed;
			if (Linux.Network.getifaddrs(out listed) != 0) {
				return false;
			}
			for (unowned var iface = listed; iface != null;
				iface = iface.ifa_next) {
				if (iface.ifa_addr == null || iface.ifa_name == null ||
					iface.ifa_addr.sa_family != Posix.AF_INET ||
					(iface.ifa_flags & Linux.Network.IfFlag.UP) == 0 ||
					(!iface.ifa_name.has_prefix("tun") &&
					!iface.ifa_name.has_prefix("tap") &&
					!iface.ifa_name.has_prefix("wg"))) {
					continue;
				}
				var sin = (Posix.SockAddrIn*) iface.ifa_addr;
				var buf = new uint8[Posix.INET_ADDRSTRLEN];
				var ip = Posix.inet_ntop(Posix.AF_INET, &sin.sin_addr, buf);
				if (ip == null || ip == "" || ip == "127.0.0.1") {
					continue;
				}
				this.tunnel_interface = iface.ifa_name;
				this.tunnel_address = ip;
				return true;
			}
			return false;
		}

		/**
		 * Probe the tunnel /24 for the registration port.
		 *
		 * No-op when {@link has_tunnel} would be false.
		 */
		public void start(uint16 port = (uint16) Argus.REGISTER_PORT)
		{
			if (!this.has_tunnel()) {
				return;
			}
			this.running = false;
			this.scan_num++;
			this.round_num++;
			if (this.timeout_id != 0) {
				GLib.Source.remove(this.timeout_id);
				this.timeout_id = 0;
			}
			this.running = true;
			this.registration_port = port;
			var num = this.scan_num;
			this.step = Step.SCANNING;
			this.timeout_id = GLib.Timeout.add_seconds(
				20, () => this.scan_round(num));
			this.scan_round(num);
		}

		/**
		 * Stop port probes.
		 */
		public void stop()
		{
			this.running = false;
			this.scan_num++;
			this.round_num++;
			if (this.timeout_id != 0) {
				GLib.Source.remove(this.timeout_id);
				this.timeout_id = 0;
			}
			if (this.step != Step.IDLE) {
				this.step = Step.IDLE;
			}
		}

		private bool scan_round(int scan_num)
		{
			if (!this.running || scan_num != this.scan_num) {
				return false;
			}
			if (this.step != Step.CHECKING_PORTS) {
				this.step = Step.CHECKING_PORTS;
			}
			this.round_num++;
			var round_num = this.round_num;
			var parts = this.tunnel_address.split(".");
			if (parts.length != 4) {
				return true;
			}
			var prefix = parts[0] + "." + parts[1] + "." + parts[2] + ".";
			var port = this.registration_port;
			for (var last = 1; last <= 254; last++) {
				if (!this.running || scan_num != this.scan_num) {
					return false;
				}
				var host = prefix + last.to_string();
				if (host == this.tunnel_address) {
					continue;
				}
				this.connect(host, port, scan_num, round_num);
			}
			return true;
		}

		private void connect(
			string host, uint16 port, int scan_num, int round_num)
		{
			var client = new GLib.SocketClient() {
				timeout = 5
			};
			client.connect_to_host_async.begin(host, port, null, (obj, res) => {
				if (!this.running ||
					scan_num != this.scan_num ||
					round_num != this.round_num) {
					return;
				}
				GLib.SocketConnection? conn = null;
				try {
					conn = client.connect_to_host_async.end(res);
				} catch (GLib.Error e) {
					return;
				}
				if (conn == null) {
					return;
				}
				try {
					conn.close();
				} catch (GLib.Error close_error) {
					GLib.warning("%s", close_error.message);
				}
				this.running = false;
				this.scan_num++;
				this.round_num++;
				if (this.timeout_id != 0) {
					GLib.Source.remove(this.timeout_id);
					this.timeout_id = 0;
				}
				this.step = Step.FOUND;
				this.server_found(host, port);
			});
		}
	}
}