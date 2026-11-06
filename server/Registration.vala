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
	 * Local controller certificate registration.
	 *
	 * The privileged controller calls {@link certificate} on ''argus.sock''.
	 * It generates a pending controller credential without writing the
	 * private key to disk. {@link deregister} removes that row on the
	 * open TLS connection, then the desktop closes that connection.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Request.register("Registration",
	 *     new Argus.Server.Registration(app));
	 * }}}
	 */
	public class Registration : GLib.Object
	{
		public Application app { get; private set; }

		public Registration(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register the local certificate RPC.
		 */
		public static void rpc_register()
		{
			Argus.Shared.Registration.Data.rpc_register();
			OLLMrpc.Request.add_class("Registration", typeof(Registration),
				"certificate", "s", "deregister", "s");
		}

		/**
		 * Generate one pending controller credential.
		 *
		 * @param request inbound RPC on the Unix socket
		 * @param username controller operating-system login name
		 */
		public void certificate(OLLMrpc.Request request, string username)
		{
			if (request.connection is Net.SslConnection) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("Unix socket only")
				});
				return;
			}
			try {
				if (request.connection.stream == null ||
					request.connection.stream.get_socket().get_credentials().get_unix_user() != 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("root is required")
					});
					return;
				}
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("root is required")
				});
				return;
			}
			if (username == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("username is required")
				});
				return;
			}
			if (GnuTLS.global_init() < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not generate certificate")
				});
				return;
			}
			var key = GnuTLS.X509.PrivateKey.create();
			var crt = GnuTLS.X509.Certificate.create();
			var hostname = GLib.Environment.get_host_name();
			var common_name = username + "@" + hostname;
			if (key.generate(GnuTLS.PKAlgorithm.RSA, 3072) < 0 ||
				crt.set_version(3) < 0 ||
				crt.set_key(key) < 0 ||
				crt.set_dn_by_oid("2.5.4.3", 0, common_name, common_name.length) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not generate certificate")
				});
				return;
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8) GLib.Random.int_range(0, 256);
			}
			var now = (time_t) (GLib.get_real_time() / 1000000);
			if (crt.set_serial(serial, serial.length) < 0 ||
				crt.set_activation_time(now) < 0 ||
				crt.set_expiration_time(now + (time_t) (3650 * 24 * 60 * 60)) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not generate certificate")
				});
				return;
			}
			var ca_pem = "";
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(this.app.tls.ca_pem_path, out ca_pem);
				GLib.FileUtils.get_contents(this.app.tls.ca_key_path, out ca_key_pem);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not read certificate authority")
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
			if (ca_crt.import(ref ca_datum, GnuTLS.X509.CertificateFormat.PEM) < 0 ||
				ca_key.import(ref key_datum, GnuTLS.X509.CertificateFormat.PEM) < 0 ||
				crt.sign2(ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign certificate")
				});
				return;
			}
			var private_key_len = (size_t) 0;
			key.export(GnuTLS.X509.CertificateFormat.PEM, null, ref private_key_len);
			var private_key_buf = new uint8[private_key_len];
			var certificate_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref certificate_len);
			var certificate_buf = new uint8[certificate_len];
			if (key.export(GnuTLS.X509.CertificateFormat.PEM, private_key_buf, ref private_key_len) < 0 ||
				crt.export(GnuTLS.X509.CertificateFormat.PEM, certificate_buf, ref certificate_len) < 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not export certificate")
				});
				return;
			}
			var data = new Argus.Shared.Registration.Data() {
				private_key = (string) private_key_buf,
				client_certificate = (string) certificate_buf,
				ca_certificate = ca_pem,
				name = hostname
			};
			var colon = this.app.socket.last_index_of(":");
			var host = this.app.socket.substring(0, colon);
			var port = 0;
			int.try_parse(this.app.socket.substring(colon + 1), out port);
			data.port = port;
			if (host == "0.0.0.0") {
				data.addresses = OLLMrpc.Transport.TcpListen.ifaces();
			}
			if (host != "0.0.0.0") {
				string[] addresses = { host };
				data.addresses = addresses;
			}
			try {
				var issued = new GLib.TlsCertificate.from_pem(data.client_certificate, data.client_certificate.length);
				var fingerprint = GLib.Checksum.compute_for_data(GLib.ChecksumType.SHA256, issued.certificate.data);
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("status", 0);
				int_binds.set("is_controller", 1);
				text_binds.set("username", username);
				text_binds.set("hostname", hostname);
				Argus.Shared.Agent.query(this.app.db).deleteWhere(
					"WHERE status = $status AND is_controller = $is_controller " +
						"AND username = $username AND hostname = $hostname",
					int_binds, text_binds);
				Argus.Shared.Agent.query(this.app.db).insert(
					new Argus.Shared.Agent() {
						fingerprint = fingerprint,
						status = 0,
						created = new GLib.DateTime.now_utc().to_unix(),
						username = username,
						hostname = hostname,
						is_controller = true
					});
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not store certificate")
				});
				return;
			}
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", data),
				msg = "ok"
			});
		}

		/**
		 * Remove this certificate's controller row.
		 *
		 * The desktop calls this on the TLS connection already open
		 * for that certificate, then closes the connection. The
		 * fingerprint must be the peer certificate. A missing row
		 * is still success. The allowlist is refreshed from the
		 * rows that remain.
		 *
		 * @param request inbound RPC on the app socket
		 * @param fingerprint SHA256 of the client certificate
		 */
		public void deregister(OLLMrpc.Request request, string fingerprint)
		{
			var ssl = request.connection as Net.SslConnection;
			if (ssl == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("TCP only")
				});
				return;
			}
			if (fingerprint == "" || ssl.cert_fingerprint == "" ||
				fingerprint != ssl.cert_fingerprint) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("fingerprint is required")
				});
				return;
			}
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds.set("is_controller", 1);
			text_binds.set("fingerprint", fingerprint);
			Argus.Shared.Agent.query(this.app.db).deleteWhere(
				"WHERE fingerprint = $fingerprint AND is_controller = $is_controller",
				int_binds, text_binds);
			this.app.db.backupDB();
			this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}
