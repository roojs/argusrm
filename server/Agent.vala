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
	 * Registered agent and its client certificate.
	 */
	public class Agent : GLib.Object
	{
		public Application app { get; private set; }

		public Agent()
		{
			Object();
		}

		public Agent.for_rpc(Application app)
		{
			Object();
			this.app = app;
			Agent.rpc_register();
		}

		/**
		 * Register the certificate and pairing calls.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Agent", typeof(Agent),
				"request_registration", "ssssbss",
				"offer", "",
				"list", "",
				"remove", "i"
			);
		}

		[CCode (cname = "gnutls_x509_crt_set_crq", cheader_filename = "gnutls/x509.h")]
		private static extern int gnutls_x509_crt_set_crq(
			GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest request
		);

		/**
		 * Pair a machine. Sign ''csr'' when ''pin'' matches
		 * {@link Application.register_listen}'s {@link Net.SslListen.pin}.
		 *
		 * This is the other half of {@link offer}. A wrong number
		 * is ''number rejected''. The matching number closes the
		 * window and tells the controller. The peer address is stored
		 * on the new row without its port. The allowlist is refreshed
		 * and the firewall enabled again.
		 *
		 * @param request inbound RPC on the app socket
		 * @param pin six digits from the offer
		 * @param csr PEM certificate request
		 * @param requester device string stored with the row
		 * @param family ''debian'', ''rpm'', ''windows'', or ''android''
		 * @param is_controller true for a controller certificate
		 * @param username controller operating-system login name
		 * @param hostname controller machine name
		 */
		public void request_registration(
			OLLMrpc.Request request,
			string pin,
			string csr,
			string requester,
			string family,
			bool is_controller,
			string username,
			string hostname
		) {
			var rpc = request.connection as Net.SslConnection;
			if (rpc == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("socket registration only")
				});
				return;
			}
			var listen = this.app.register_listen;
			if (pin != listen.pin || listen.pin == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("number rejected")
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			if (is_controller && username != "" && hostname != "") {
				var existing = new Gee.ArrayList<Argus.Shared.Agent>();
				var found_binds = new Gee.HashMap<string, int>();
				var found_text = new Gee.HashMap<string, string>();
				found_binds.set("status", 1);
				found_binds.set("is_controller", 1);
				found_text.set("username", username);
				found_text.set("hostname", hostname);
				try {
					Argus.Shared.Agent.query(this.app.db).selectWhere(
						"WHERE status = $status AND is_controller = $is_controller " +
							"AND username = $username AND hostname = $hostname",
						found_binds, found_text, existing);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("could not read registration")
					});
					return;
				}
				if (existing.size > 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(
							"This machine is already registered.")
					});
					return;
				}
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var csr_datum = GnuTLS.Datum() {
				data = csr,
				size = csr.length
			};
			var crq = GnuTLS.X509.CertificateRequest.create();
			if (crq.import(ref csr_datum, GnuTLS.X509.CertificateFormat.PEM) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("bad csr")
				});
				return;
			}
			var crt = GnuTLS.X509.Certificate.create();
			if (gnutls_x509_crt_set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("bad csr")
				});
				return;
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8) GLib.Random.int_range(0, 256);
			}
			var now = (time_t) (GLib.get_real_time() / 1000000);
			if (crt.set_serial(serial, serial.length) < 0
				|| crt.set_activation_time(now) < 0
				|| crt.set_expiration_time(
					now + (time_t) (3650 * 24 * 60 * 60)) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var ca_pem = "";
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					this.app.tls.ca_pem_path,
					out ca_pem
				);
				GLib.FileUtils.get_contents(
					this.app.tls.ca_key_path,
					out ca_key_pem
				);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var ca_datum = GnuTLS.Datum() {
				data = ca_pem,
				size = ca_pem.length
			};
			var key_datum = GnuTLS.Datum() {
				data = ca_key_pem,
				size = ca_key_pem.length
			};
			var ca_crt = GnuTLS.X509.Certificate.create();
			var ca_key = GnuTLS.X509.PrivateKey.create();
			if (ca_crt.import(
				ref ca_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| ca_key.import(
					ref key_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| crt.sign2(
					ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var crt_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_len);
			var crt_buf = new uint8[crt_len];
			if (crt.export(
				GnuTLS.X509.CertificateFormat.PEM, crt_buf, ref crt_len) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var crt_pem = (string) crt_buf;
			var fingerprint = "";
			try {
				var issued = new GLib.TlsCertificate.from_pem(
					crt_pem, crt_pem.length);
				fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256,
					issued.certificate.data
				);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var peer = "";
			if (rpc.stream == null) {
				GLib.warning("registration has no peer address");
			} else {
				try {
					var remote = rpc.stream.get_remote_address() as GLib.InetSocketAddress;
					if (remote == null) {
						GLib.warning("registration has no peer address");
					} else {
						peer = remote.get_address().to_string();
					}
				} catch (GLib.Error e) {
					GLib.warning("could not read registration address: %s", e.message);
				}
			}
			var q = Argus.Shared.Agent.query(this.app.db);
			q.insert(new Argus.Shared.Agent() {
				fingerprint = fingerprint,
				status = 1,
				ip = peer,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester,
				username = username,
				hostname = hostname,
				is_controller = is_controller
			});
			this.app.db.backupDB();
			listen.pin = "";
			this.app.publish.stop();
			this.app.register_firewall.enable();
			this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
			this.app.download_listen.listen();
			var path = "";
			if (!is_controller && family == "debian") {
				path = "/osquery/osquery.deb";
			}
			if (!is_controller && family == "rpm") {
				path = "/osquery/osquery.rpm";
			}
			if (!is_controller && family == "windows") {
				path = "/osquery/osquery.msi";
			}
			var host = this.app.socket;
			var port_text = Argus.SOCKET_PORT.to_string();
			var colon = this.app.socket.last_index_of(":");
			if (colon > 0) {
				host = this.app.socket.substring(0, colon);
				port_text = this.app.socket.substring(colon + 1);
			}
			if (host == "") {
				host = "0.0.0.0";
			}
			if (port_text == "") {
				port_text = Argus.SOCKET_PORT.to_string();
			}
			var packed = new Gee.ArrayList<string>();
			packed.add(crt_pem);
			packed.add(ca_pem);
			packed.add(this.app.download);
			packed.add(path);
			if (host == "0.0.0.0") {
				foreach (var ip in OLLMrpc.Transport.TcpListen.ifaces()) {
					packed.add(ip + ":" + port_text);
				}
			}
			if (host != "" && host != "0.0.0.0") {
				packed.add(host + ":" + port_text);
			}
			var reply = new string[packed.size];
			for (var i = 0; i < packed.size; i++) {
				reply[i] = packed.get(i);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", reply),
				msg = "ok"
			});
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
		}

		/**
		 * Offer a registration number.
		 *
		 * The controller calls this with no arguments. The reply
		 * is the six digits, then the public address. This opens
		 * the registration socket and publishes that port. The
		 * app socket and its firewall stay as they are. The
		 * download socket opens from {@link request_registration},
		 * after the machine is registered. That call is the machine
		 * that types the number. The number lasts sixty seconds,
		 * or until that call, or until this connection closes.
		 * The registration firewall is disabled while the window
		 * runs and enabled when it ends. The public address is
		 * read after the window is open, without blocking this
		 * connection.
		 *
		 * @param request inbound RPC from a controller
		 */
		public void offer(OLLMrpc.Request request)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var n = GLib.Random.int_range(0, 1000000);
			var issued = "%06d".printf(n);
			var listen = this.app.register_listen;
			listen.pin = issued;
			if (!listen.listen()) {
				listen.pin = "";
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("registration socket did not bind")
				});
				return;
			}
			var host = this.app.registration;
			var parsed = Argus.REGISTER_PORT;
			var colon = this.app.registration.last_index_of(":");
			if (colon > 0) {
				host = this.app.registration.substring(0, colon);
				int.try_parse(this.app.registration.substring(colon + 1), out parsed);
			}
			if (host == "") {
				host = "0.0.0.0";
			}
			if (parsed < 1 || parsed > 65535) {
				parsed = Argus.REGISTER_PORT;
			}
			string[] addrs = {};
			if (host == "0.0.0.0") {
				addrs = OLLMrpc.Transport.TcpListen.ifaces();
			}
			if (host != "0.0.0.0") {
				addrs = { host };
			}
			GLib.debug("publishing %s port %d", string.joinv(" ", addrs), parsed);
			this.app.publish.start(addrs, (uint16) parsed);
			this.app.register_firewall.disable();
			var owner = request.connection;
			GLib.Timeout.add_seconds(60, () => {
				if (listen.pin != issued) {
					return false;
				}
				listen.pin = "";
				this.app.publish.stop();
				this.app.register_firewall.enable();
				listen.stop();
				return false;
			});
			GLib.Timeout.add(250, () => {
				if (listen.pin != issued) {
					return false;
				}
				if (owner.running) {
					return true;
				}
				listen.pin = "";
				this.app.publish.stop();
				this.app.register_firewall.enable();
				listen.stop();
				GLib.debug("registration closed after controller disconnected");
				return false;
			});
			GLib.Resolver.get_default().lookup_by_name_with_flags_async.begin(
				"ifconfig.me",
				GLib.ResolverNameLookupFlags.IPV4_ONLY,
				null,
				(obj, res) => {
					GLib.List<GLib.InetAddress> found = new GLib.List<GLib.InetAddress>();
					try {
						found = GLib.Resolver.get_default().lookup_by_name_with_flags_async.end(res);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
					if (found.length() < 1) {
						var missed = new string[] { issued, "" };
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("as", missed),
							msg = "ok"
						});
						return;
					}
					var session = new Soup.Session.with_options(
						"remote-connectable",
						new GLib.InetSocketAddress(found.nth_data(0), 443),
						null);
					var message = new Soup.Message("GET", "https://ifconfig.me");
					message.request_headers.append("User-Agent", "argusrm");
					message.request_headers.append("Accept", "text/plain");
					session.send_and_read_async.begin(message, GLib.Priority.DEFAULT, null, (sobj, sres) => {
						var address = "";
						try {
							var body = session.send_and_read_async.end(sres);
							if (message.status_code == 200) {
								var text = ((string) body.get_data()).strip();
								var inet = new GLib.InetAddress.from_string(text);
								if (inet != null && inet.get_family() == GLib.SocketFamily.IPV4) {
									address = inet.to_string();
								}
							}
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
						}
						var reply = new string[] { issued, address };
						request.reply(new OLLMrpc.Response() {
							retval = OLLMrpc.val("as", reply),
							msg = "ok"
						});
					});
				});
		}

		/**
		 * List registered machines.
		 *
		 * {@link Argus.Shared.Agent.connected} is true while that
		 * machine's app socket is open.
		 *
		 * @param request inbound RPC on the Unix socket
		 */
		public void list(OLLMrpc.Request request)
		{
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			Argus.Shared.Agent.query(this.app.db).select("LIMIT 20", rows);
			var live = new Gee.HashMap<int, bool>();
			foreach (var connection in this.app.ssl_listen.connections) {
				if (!connection.running || connection.agent_id < 1) {
					continue;
				}
				live.set((int) connection.agent_id, true);
			}
			foreach (var row in rows) {
				row.connected = live.has_key((int) row.id);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Remove one machine.
		 *
		 * A controller calls this. The row is deleted. A connected
		 * agent is told to drop its certificate, then its app
		 * socket is closed, and the allowlist is refreshed.
		 * An unknown id is an error.
		 *
		 * @param request inbound RPC from a controller
		 * @param id ''agent.id''
		 */
		public void remove(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds.set("id", id);
			Argus.Shared.Agent.query(this.app.db).selectWhere(
				"WHERE id = $id", int_binds, text_binds, rows);
			if (rows.size < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown machine")
				});
				return;
			}
			Argus.Shared.Agent.query(this.app.db).deleteId(id);
			foreach (var connection in this.app.ssl_listen.connections) {
				if (connection.agent_id != id) {
					continue;
				}
				connection.write(new OLLMrpc.Notification() {
					method = "agent.removed"
				});
				connection.stop();
			}
			this.app.db.backupDB();
			this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Registered source addresses, plus every address on this machine.
		 *
		 * Active ''agent.ip'' values are kept when
		 * {@link Net.Interfaces.route} returns a source. A private
		 * route counts. This machine's own addresses are added after
		 * that. {@link Net.NFTables.apply} receives only these
		 * addresses.
		 *
		 * @param db agent table
		 * @param interfaces local addresses and routes
		 * @return the IPv4 and IPv6 allowlist
		 */
		public static Gee.ArrayList<GLib.InetAddress> allowlist(SQ.Database db, Net.Interfaces interfaces)
		{
			var kept = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
			var query = Argus.Shared.Agent.query(db);
			foreach (var text in query.fetchAllString(query.selectPrepare(
				"SELECT DISTINCT ip FROM agent WHERE status = 1 AND ip != ''"))) {
				var address = new GLib.InetAddress.from_string(text);
				if (address == null) {
					GLib.warning("stored address is not an IP: %s", text);
					continue;
				}
				var source = interfaces.route(address);
				if (source == null) {
					continue;
				}
				kept.add(address);
			}
			foreach (var item in interfaces.addresses) {
				if (kept.contains(item.address)) {
					continue;
				}
				kept.add(item.address);
			}
			return kept;
		}
	}
}
