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

		private OLLMrpc.Request? pending_pair = null;

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
				"request_registration", "ssss",
				"pair", "s",
				"list", ""
			);
		}

		[CCode (cname = "gnutls_x509_crt_set_crq", cheader_filename = "gnutls/x509.h")]
		private static extern int gnutls_x509_crt_set_crq(
			GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest request
		);

		/**
		 * Sign ''csr'' when ''pin'' matches {@link SslListen.pin}.
		 *
		 * @param request inbound RPC on the app socket
		 * @param pin six digits from the controller
		 * @param csr PEM certificate request
		 * @param requester device string stored with the row
		 * @param family ''debian'', ''rpm'', ''windows'', or ''android''
		 */
		public void request_registration(
			OLLMrpc.Request request,
			string pin,
			string csr,
			string requester,
			string family
		) {
			var rpc = request.connection as SslConnection;
			if (rpc == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"socket registration only"
					)
				});
				return;
			}
			var listen = this.app.ssl_listen;
			if (pin != listen.pin || listen.pin == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"number rejected"
					)
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			var init_ret = GnuTLS.global_init();
			if (init_ret < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"could not sign"
					)
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
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"bad csr"
					)
				});
				return;
			}
			var crt = GnuTLS.X509.Certificate.create();
			if (gnutls_x509_crt_set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"bad csr"
					)
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
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"could not sign"
					)
				});
				return;
			}
			var tls_dir = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "tls");
			var ca_pem = "";
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem"),
					out ca_pem
				);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem"),
					out ca_key_pem
				);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"could not sign"
					)
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
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"could not sign"
					)
				});
				return;
			}
			var crt_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_len);
			var crt_buf = new uint8[crt_len];
			if (crt.export(
				GnuTLS.X509.CertificateFormat.PEM, crt_buf, ref crt_len) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"could not sign"
					)
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
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR,
						"could not sign"
					)
				});
				return;
			}
			var q = Argus.Shared.Agent.query(this.app.db);
			q.insert(new Argus.Shared.Agent() {
				fingerprint = fingerprint,
				status = 1,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester,
				is_controller = false
			});
			this.app.db.backupDB();
			listen.pin = "";
			this.app.publish.stop();
			if (this.pending_pair != null) {
				this.pending_pair.reply(new OLLMrpc.Response() {
					msg = "used"
				});
				this.pending_pair = null;
			}
			var path = "";
			if (family == "debian") {
				path = "/osquery/osquery.deb";
			}
			if (family == "rpm") {
				path = "/osquery/osquery.rpm";
			}
			if (family == "windows") {
				path = "/osquery/osquery.msi";
			}
			var socket = this.app.socket;
			var colon = socket.last_index_of(":");
			var host = "";
			var port_text = "";
			if (colon > 0) {
				host = socket.substring(0, colon);
				port_text = socket.substring(colon + 1);
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
		 * Set {@link SslListen.pin} from the controller.
		 *
		 * @param request inbound RPC from the controller
		 * @param pin six digits, or empty to close the window
		 */
		public void pair(OLLMrpc.Request request, string pin)
		{
			var listen = this.app.ssl_listen;
			if (!(request.connection is SslConnection)) {
				listen.pin = pin;
				if (pin == "") {
					this.app.publish.stop();
					if (this.pending_pair != null) {
						this.pending_pair.reply(new OLLMrpc.Response() {
							msg = "ok"
						});
						this.pending_pair = null;
					}
					request.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
					return;
				}
				var socket = this.app.socket;
				var colon = socket.last_index_of(":");
				if (colon > 0) {
					var host = socket.substring(0, colon);
					var parsed = 0;
					int.try_parse(socket.substring(colon + 1), out parsed);
					if (parsed >= 1 && parsed <= 65535) {
						string[] addrs = {};
						if (host == "0.0.0.0") {
							addrs = OLLMrpc.Transport.TcpListen.ifaces();
						}
						if (host != "" && host != "0.0.0.0") {
							addrs = { host };
						}
						this.app.publish.start(addrs, (uint16) parsed);
					}
				}
				if (this.pending_pair != null) {
					this.pending_pair.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
				}
				this.pending_pair = request;
				var owner = request.connection;
				GLib.Timeout.add(250, () => {
					if (listen.pin != pin) {
						return false;
					}
					if (owner.running) {
						return true;
					}
					listen.pin = "";
					this.app.publish.stop();
					if (this.pending_pair != null) {
						this.pending_pair.reply(new OLLMrpc.Response() {
							msg = "ok"
						});
						this.pending_pair = null;
					}
					GLib.debug("registration closed after controller disconnected");
					return false;
				});
				return;
			}
			if (pin != listen.pin || listen.pin == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST,
						"number rejected"
					)
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			listen.pin = "";
			this.app.publish.stop();
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
		}

		/**
		 * List registered machines.
		 *
		 * @param request inbound RPC on the Unix socket
		 */
		public void list(OLLMrpc.Request request)
		{
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			Argus.Shared.Agent.query(this.app.db).select("LIMIT 20", rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
	}
}
