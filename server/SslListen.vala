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
	 * TLS bin listener for the app socket.
	 *
	 * Binds {@link Application.socket}. Registration, commands,
	 * identity, and warnings stay on this socket. The handshake
	 * requires a client certificate, unless {@link pin} is set.
	 * Same product CA as {@link Download}. This is not the file daemon.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var ssl = new Argus.Server.SslListen(app);
	 * if (ssl.listen()) {
	 *     // bound
	 * }
	 * }}}
	 */
	public class SslListen : GLib.Object
	{
		public Application app { get; private set; }

		private GLib.SocketService service {
			get; set; default = new GLib.SocketService();
		}
		private bool listening = false;
		/**
		 * App-socket connections. {@link Command} writes one
		 * notification to the connection for that agent.
		 */
		internal Gee.ArrayList<SslConnection> connections {
			get; set; default = new Gee.ArrayList<SslConnection>();
		}

		/**
		 * Six digits from {@link Agent.offer}. Empty unless
		 * the registration window is open.
		 */
		public string pin { get; set; default = ""; }

		public SslListen(Application app)
		{
			this.app = app;
		}

		/**
		 * Bind the TLS bin socket from {@link Application.socket}.
		 *
		 * A missing port uses {@link Argus.SOCKET_PORT}. Returns
		 * false when that port is outside 1–65535. Bind failure
		 * logs a warning and returns
		 * false. A client certificate is required unless
		 * {@link pin} is set. A bad identity flag alone is
		 * ignored, the same as ''ollmfilesd''.
		 *
		 * @return true when the app socket is up
		 */
		public bool listen()
		{
			if (this.listening) {
				return true;
			}
			var socket = this.app.socket;
			var colon = socket.last_index_of(":");
			var host = socket;
			var port = Argus.SOCKET_PORT;
			if (colon > 0) {
				host = socket.substring(0, colon);
				int.try_parse(socket.substring(colon + 1), out port);
			}
			if (host == "") {
				host = "0.0.0.0";
			}
			if (port < 1 || port > 65535) {
				return false;
			}
			var parsed = new GLib.InetSocketAddress.from_string(host, (uint16) port);
			if (parsed == null) {
				return false;
			}
			var server_cert = this.app.tls.certificate;
			this.service = new GLib.SocketService();
			var effective = (GLib.SocketAddress) parsed;
			try {
				this.service.add_address(
					effective,
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.TCP,
					null,
					out effective
				);
			} catch (GLib.Error e) {
				GLib.warning("failed to bind SSL listener %s:%u: %s",
					host, (uint) port, e.message);
				return false;
			}
			this.service.incoming.connect((conn) => {
				GLib.TlsServerConnection tls;
				try {
					tls = GLib.TlsServerConnection.@new(conn, server_cert);
				} catch (GLib.Error e) {
					GLib.warning("ssl accept failed: %s", e.message);
					return true;
				}
				if (this.app.tls.trust != null) {
					tls.database = this.app.tls.trust;
				}
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUIRED;
				if (this.pin != "") {
					tls.authentication_mode = GLib.TlsAuthenticationMode.REQUESTED;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					if (this.pin != "") {
						return true;
					}
					if (peer_cert == null) {
						return false;
					}
					return (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
				tls.handshake_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
					try {
						tls.handshake_async.end(res);
					} catch (GLib.Error e) {
						GLib.warning("ssl handshake failed: %s", e.message);
						return;
					}
					var fingerprint = "";
					var peer = tls.get_peer_certificate();
					if (peer != null) {
						fingerprint = GLib.Checksum.compute_for_data(
							GLib.ChecksumType.SHA256, peer.certificate.data);
					}
					var rpc = new SslConnection(conn, this.app) {
						io = tls,
						cert_fingerprint = fingerprint
					};
					var rows = new Gee.ArrayList<Argus.Shared.Agent>();
					var int_binds = new Gee.HashMap<string, int>();
					var text_binds = new Gee.HashMap<string, string>();
					text_binds.set("fingerprint", fingerprint);
					Argus.Shared.Agent.query(this.app.db).selectWhere(
						"WHERE fingerprint = $fingerprint AND status = 1",
						int_binds, text_binds, rows);
					if (rows.size > 0) {
						rpc.agent_id = rows.get(0).id;
					}
					rpc.start();
					this.connections.add(rpc);
				});
				return true;
			});
			this.service.start();
			this.listening = true;
			GLib.debug("SSL listening on %s:%u", host, (uint) port);
			return true;
		}

		/**
		 * Send one notification on every app-socket connection.
		 *
		 * @param notification bin notification
		 */
		public void broadcast(GLib.Object notification)
		{
			foreach (var connection in this.connections) {
				connection.write(notification);
			}
		}

		/**
		 * Unbind the socket and stop each bin connection.
		 *
		 * No-op when {@link listen} did not bind.
		 */
		public void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.service.stop();
			this.service = new GLib.SocketService();
			foreach (var connection in this.connections) {
				connection.stop();
			}
			this.connections.clear();
		}
	}
}
