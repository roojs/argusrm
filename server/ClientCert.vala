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
	 * Client TLS certificate row and ''ClientCert'' handler.
	 *
	 * Adapted from ''ollmfilesd''. {@link pair} stores the pin on
	 * {@link SslListen} and publishes the app socket. {@link request_registration}
	 * signs the certificate request while that pin matches.
	 * A matching pin stores status 1, the same approved row.
	 * The table is ''client_cert'' in {@link Application.db}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * ClientCert.init_db(db);
	 * OLLMrpc.Request.register("ClientCert", new ClientCert.for_rpc(app));
	 * }}}
	 */
	public class ClientCert : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * Register the bin name and the two calls.
		 */
		public static void rpc_register()
		{
			try {
				OLLMrpc.Bin.register("ClientCert", typeof(ClientCert));
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			OLLMrpc.Request.add_class(
				"ClientCert", typeof(ClientCert),
				"request_registration", "ssss",
				"pair", "s"
			);
		}

		public Application app { get; private set; }

		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		public string requester { get; set; default = ""; }

		public ClientCert()
		{
			Object();
		}

		/**
		 * Wire dispatch singleton for ''ClientCert''.
		 *
		 * @param app Argus process
		 */
		public ClientCert.for_rpc(Application app)
		{
			Object();
			this.app = app;
			ClientCert.rpc_register();
		}

		/**
		 * Rows in ''client_cert''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<ClientCert> query(SQ.Database db)
		{
			return new SQ.Query<ClientCert>(db, "client_cert");
		}

		/**
		 * Ensure ''client_cert'' and drop pending rows older than 24 hours.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			if (Sqlite.OK != db.db.exec(
				"CREATE TABLE IF NOT EXISTS client_cert (" +
				"id INTEGER PRIMARY KEY, " +
				"fingerprint TEXT NOT NULL UNIQUE, " +
				"status INTEGER NOT NULL DEFAULT 0, " +
				"ip TEXT NOT NULL DEFAULT '', " +
				"created INT64 NOT NULL DEFAULT 0, " +
				"requester TEXT NOT NULL DEFAULT ''" +
				");",
				null, out errmsg)) {
				GLib.warning("Failed to create client_cert table: %s", db.db.errmsg());
			}
			var q = ClientCert.query(db);
			var now = new GLib.DateTime.now_utc().to_unix();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("before", (int) (now - (24 * 60 * 60)));
			int_binds.set("status", 0);
			q.deleteWhere("WHERE status = $status AND created < $before", int_binds, null);
		}

		[CCode (cname = "gnutls_x509_crt_set_crq", cheader_filename = "gnutls/x509.h")]
		private static extern int gnutls_x509_crt_set_crq(
			GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest request
		);

		/**
		 * Sign ''csr'' when ''pin'' matches {@link SslListen.pin}.
		 *
		 * The reply is a string array. Index 0 is the client
		 * certificate PEM. Index 1 is the CA PEM. Index 2 is the
		 * download socket. Index 3 is the download URL path for
		 * ''family''. Later entries are listen addresses.
		 * A wrong pin leaves the window up and writes no row.
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
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "socket registration only")
				});
				return;
			}
			var listen = this.app.ssl_listen;
			if (pin != listen.pin || listen.pin == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "number rejected")
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
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
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
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "bad csr")
				});
				return;
			}
			var crt = GnuTLS.X509.Certificate.create();
			if (gnutls_x509_crt_set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "bad csr")
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
				|| crt.set_expiration_time(now + (time_t) (3650 * 24 * 60 * 60)) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var tls_dir = GLib.Path.build_filename(LOCALSTATEDIR, "tls");
			var ca_pem = "";
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca.pem"), out ca_pem);
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(tls_dir, "ollmrpc-ca-key.pem"), out ca_key_pem);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
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
			if (ca_crt.import(ref ca_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| ca_key.import(ref key_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| crt.sign2(ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var crt_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_len);
			var crt_buf = new uint8[crt_len];
			if (crt.export(GnuTLS.X509.CertificateFormat.PEM, crt_buf, ref crt_len) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var crt_pem = (string) crt_buf;
			var fingerprint = "";
			try {
				var issued = new GLib.TlsCertificate.from_pem(crt_pem, crt_pem.length);
				fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256, issued.certificate.data);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR, "could not sign")
				});
				return;
			}
			var q = ClientCert.query(this.app.db);
			q.insert(new ClientCert() {
				fingerprint = fingerprint,
				status = 1,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester
			});
			listen.pin = "";
			this.app.publish.stop();
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
		 * The Unix socket arms the window. A non-empty pin publishes
		 * the app socket. An empty pin withdraws it. A TLS caller
		 * can only clear a pin that matches.
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
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			if (pin != listen.pin || listen.pin == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "number rejected")
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

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			this.bin_default_write_prop(ctx, prop);
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop, uint8 type_byte
		) throws GLib.Error
		{
			if (prop.name == "app") {
				return;
			}
			this.bin_default_read_prop(ctx, prop, type_byte);
		}
	}
}
