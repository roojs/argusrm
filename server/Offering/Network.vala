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

namespace Argus.Server.Offering
{
	public enum DeskState
	{
		OPEN,
		ARM,
		POLLING,
		CLOSED
	}

	/**
	 * Registration socket, its nftables rules, and PairPublish.
	 *
	 * {@link Argus.Server.Offering.Rpc} drives this type only — do not
	 * call legacy {@link Application} registration fields or
	 * ''Agent.offer'' from new code. The management TLS socket and app
	 * firewall stay on {@link Application}.
	 *
	 * {@link firewall} is constructed for the registration port from
	 * {@link Application.registration}. {@link firewall.apply} and
	 * {@link firewall.enable} are the caller's job at startup.
	 */
	public class Network : GLib.Object
	{
		public Application app { get; private set; }

		public Net.SslListen listen { get; private set; }

		public Net.NFTables firewall { get; private set; }

		public OLLMrpc.Transport.PairPublish pair_publish {
			get; set; default = new OLLMrpc.Transport.PairPublish() {
				min_port = 1
			};
		}

		private string endpoint_value = "";

		public string endpoint {
			get {
				return this.endpoint_value;
			}
			set {
				this.endpoint_value = value;
				this.listen.endpoint = value;
			}
		}

		public bool pending { get; internal set; default = false; }

		public bool polling { get; set; default = false; }

		public string pin {
			get {
				return this.listen.pin;
			}
			set {
				this.listen.pin = value;
			}
		}

		public bool accepting {
			get {
				return this.listen.accepting;
			}
			set {
				this.listen.accepting = value;
			}
		}

		public OLLMrpc.Transport.Connection? supervising_connection {
			get; set;
		}

		public string[] open_lines { get; private set; }

		private string armed_pin = "";

		construct {
			this.pair_publish.failed.connect(() => {
				GLib.warning("Could not publish the pairing service");
			});
		}

		public Network(Application app)
		{
			Object();
			this.app = app;
			var registration = app.registration;
			if (registration == "") {
				registration = "0.0.0.0:" + Argus.REGISTER_PORT.to_string();
			}
			this.listen = new Net.SslListen(app) {
				registration = true
			};
			this.endpoint_value = registration;
			this.listen.endpoint = registration;
			var register_port = Argus.REGISTER_PORT;
			var colon = registration.last_index_of(":");
			if (colon > 0) {
				int.try_parse(registration.substring(colon + 1), out register_port);
			}
			if (register_port < 1 || register_port > 65535) {
				register_port = Argus.REGISTER_PORT;
			}
			this.firewall = new Net.NFTables((uint16) register_port) {
				established = true
			};
		}

		public bool update_listener(bool up)
		{
			if (up) {
				return this.listen.listen();
			}
			this.listen.stop();
			return true;
		}

		/**
		 * Resolve ''ifconfig.me'' and read the public IPv4 address.
		 *
		 * @param cancel optional cancellation
		 * @return address text, or empty when lookup or HTTP fails
		 */
		public async string lookup_ip(GLib.Cancellable? cancel = null)
		{
			GLib.List<GLib.InetAddress> found;
			try {
				found = yield GLib.Resolver.get_default()
					.lookup_by_name_with_flags_async(
					"ifconfig.me",
					GLib.ResolverNameLookupFlags.IPV4_ONLY,
					cancel);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return "";
			}
			if (found.length() < 1) {
				return "";
			}
			var session = new Soup.Session.with_options(
				"remote-connectable",
				new GLib.InetSocketAddress(found.nth_data(0), 443),
				null);
			var message = new Soup.Message("GET", "https://ifconfig.me");
			message.accept_certificate.connect((peer_cert, errors) => {
				return peer_cert != null &&
					(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			message.request_headers.append("User-Agent", "argusrm");
			message.request_headers.append("Accept", "text/plain");
			try {
				var body = yield session.send_and_read_async(
					message, GLib.Priority.DEFAULT, cancel);
				if (message.status_code != 200) {
					return "";
				}
				var text = ((string) body.get_data()).strip();
				var inet = new GLib.InetAddress.from_string(text);
				if (inet == null ||
					inet.get_family() != GLib.SocketFamily.IPV4) {
					return "";
				}
				return inet.to_string();
			} catch (GLib.Error e) {
				GLib.debug("public IPv4 lookup failed: %s", e.message);
				return "";
			}
		}

		public bool update_pin(DeskState state)
		{
			switch (state) {
				case DeskState.OPEN:
					this.pending = false;
					this.polling = false;
					this.accepting = false;
					this.pin = "";
					var n = GLib.Random.int_range(0, 1000000);
					this.pin = "%06d".printf(n);
					if (!this.update_listener(true)) {
						this.pin = "";
						return false;
					}
					var host = this.endpoint;
					var colon = host.last_index_of(":");
					if (colon > 0) {
						host = host.substring(0, colon);
					}
					if (host == "") {
						host = "0.0.0.0";
					}
					string[] addrs = {};
					if (host == "0.0.0.0") {
						addrs = OLLMrpc.Transport.TcpListen.ifaces();
					}
					if (host != "0.0.0.0") {
						addrs = { host };
					}
					GLib.debug("publishing %s port %d",
						string.joinv(" ", addrs), Argus.REGISTER_PORT);
					this.pair_publish.start(addrs, (uint16) Argus.REGISTER_PORT);
					this.firewall.disable();
					string[] nets = {};
					Linux.Network.IfAddrs listed;
					if (Linux.Network.getifaddrs(out listed) != 0) {
						foreach (var published in addrs) {
							nets += published;
						}
						this.open_lines = nets;
						return true;
					}
					for (unowned var iface = listed; iface != null;
						iface = iface.ifa_next) {
						if (iface.ifa_addr == null) {
							continue;
						}
						if (iface.ifa_addr.sa_family != Posix.AF_INET) {
							continue;
						}
						var sin = (Posix.SockAddrIn*) iface.ifa_addr;
						var buf = new uint8[Posix.INET_ADDRSTRLEN];
						var ip = Posix.inet_ntop(
							Posix.AF_INET, &sin.sin_addr, buf);
						if (ip == null || ip == "") {
							continue;
						}
						var chosen = false;
						foreach (var published in addrs) {
							if (published != ip) {
								continue;
							}
							chosen = true;
							break;
						}
						if (!chosen) {
							continue;
						}
						nets += iface.ifa_name + " " + ip;
					}
					if (nets.length == 0) {
						foreach (var published in addrs) {
							nets += published;
						}
					}
					this.open_lines = nets;
					return true;

				case DeskState.ARM:
					this.armed_pin = this.pin;
					var armed = this.armed_pin;
					GLib.Timeout.add_seconds(60, () => {
						if (this.pin != armed) {
							return false;
						}
						this.update_pin(DeskState.CLOSED);
						return false;
					});
					GLib.Timeout.add(250, () => {
						if (this.pin == "" && !this.accepting) {
							return false;
						}
						var owner = this.supervising_connection;
						if (owner != null && owner.running) {
							return true;
						}
						this.update_pin(DeskState.CLOSED);
						GLib.debug(
							"registration closed after controller disconnected");
						return false;
					});
					return true;

				case DeskState.CLOSED:
					this.pin = "";
					this.accepting = false;
					this.pending = false;
					this.polling = false;
					this.armed_pin = "";
					this.open_lines = {};
					this.pair_publish.stop();
					this.firewall.enable();
					this.update_listener(false);
					return true;

				default:
					GLib.warning("unexpected desk state for pin: %d",
						(int) state);
					return false;
			}
		}

		public bool update_bulk(DeskState state)
		{
			switch (state) {
				case DeskState.OPEN:
					this.pending = true;
					this.polling = false;
					this.accepting = false;
					this.pin = "";
					this.accepting = true;
					this.open_lines = {};
					if (!this.update_listener(true)) {
						this.pin = "";
						this.accepting = false;
						this.pending = false;
						return false;
					}
					var host = this.endpoint;
					var colon = host.last_index_of(":");
					if (colon > 0) {
						host = host.substring(0, colon);
					}
					if (host == "") {
						host = "0.0.0.0";
					}
					string[] addrs = {};
					if (host == "0.0.0.0") {
						addrs = OLLMrpc.Transport.TcpListen.ifaces();
					}
					if (host != "0.0.0.0") {
						addrs = { host };
					}
					GLib.debug("publishing %s port %d",
						string.joinv(" ", addrs), Argus.REGISTER_PORT);
					this.pair_publish.start(addrs, (uint16) Argus.REGISTER_PORT);
					this.firewall.disable();
					return true;

				case DeskState.ARM:
					GLib.Timeout.add(250, () => {
						if (this.pin == "" && !this.accepting) {
							return false;
						}
						var owner = this.supervising_connection;
						if (owner != null && owner.running) {
							return true;
						}
						var pending_rows = new Gee.ArrayList<Argus.Shared.AgentPending>();
						Argus.Shared.AgentPending.query(this.app.db).select("", pending_rows);
						this.update_bulk(pending_rows.size > 0 ? DeskState.POLLING : DeskState.CLOSED);
						GLib.debug("registration closed after controller disconnected");
						return false;
					});
					return true;

				case DeskState.POLLING:
					this.accepting = false;
					this.pending = false;
					this.polling = true;
					this.pair_publish.stop();
					this.firewall.enable();
					return true;

				case DeskState.CLOSED:
					this.pin = "";
					this.accepting = false;
					this.pending = false;
					this.polling = false;
					this.armed_pin = "";
					this.open_lines = {};
					this.pair_publish.stop();
					this.firewall.enable();
					this.update_listener(false);
					return true;

				default:
					GLib.warning("unexpected desk state for bulk: %d",
						(int) state);
					return false;
			}
		}
	}
}