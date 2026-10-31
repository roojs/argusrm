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
	 * Certificate registration with Argus.
	 *
	 * Adapts the registration half of ''FilesdClient.try_connection'':
	 * a TLS connection, ''ClientCert.request_registration'', then
	 * {@link OLLMrpc.Transport.Cert} files under the user data
	 * directory ''argus''. The reply string array is the client
	 * certificate, the CA, the download socket, then listen addresses.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var registration = new Argus.Shared.Register();
	 * var code = registration.try_connection(host, port, pin, "desktop");
	 * }}}
	 */
	public class Register : GLib.Object
	{
		/**
		 * Download socket from the registration reply, ''host:port''.
		 *
		 * Empty until a reply stores it. Also written as ''download''
		 * next to the certificate files.
		 */
		public string download = "";

		/**
		 * Listen addresses from the registration reply, one per line.
		 *
		 * Empty when the reply has none after the download socket.
		 */
		public string addresses = "";

		/**
		 * Register this machine while the Argus window is open.
		 *
		 * Sends ''pin'', the certificate request, and ''requester''.
		 * Stores the signed certificate, the CA, and the download
		 * socket. A stored certificate is replaced.
		 *
		 * @param host Argus address
		 * @param port Argus port
		 * @param pin number from the registration window
		 * @param requester device string stored with the machine
		 * @return zero when registration succeeds, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int try_connection(string host, uint16 port, string pin, string requester)
		{
			OLLMrpc.rpc_register();
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
			var csr = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "client.csr"), out csr);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var client = new GLib.SocketClient() {
				timeout = 10
			};
			GLib.SocketConnection conn;
			try {
				conn = client.connect_to_host(host, port);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			conn.socket.blocking = true;
			GLib.TlsClientConnection tls;
			try {
				tls = GLib.TlsClientConnection.@new(conn, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls.accept_certificate.connect((peer_cert, errors) => {
				return true;
			});
			try {
				tls.handshake();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var bin = new OLLMrpc.Bin.Stream(
				new GLib.DataInputStream(tls.get_input_stream()),
				new GLib.DataOutputStream(tls.get_output_stream())
			);
			try {
				bin.write(new OLLMrpc.Request() {
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("sss", pin, csr, requester)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Bin.Serializable parsed;
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					parsed = bin.parse();
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK || GLib.get_monotonic_time() >= reply_wait) {
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = conn.socket.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
					continue;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (!(parsed is OLLMrpc.Response)) {
					continue;
				}
				break;
			}
			var response = (OLLMrpc.Response) parsed;
			if (response.error != null) {
				return response.error.code;
			}
			var packed = (string[]) response.retval;
			if (packed.length < 3) {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "client.pem"), packed[0]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download"), packed[2]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls_files.ensure();
			this.download = packed[2];
			if (packed.length > 3) {
				this.addresses = string.joinv("\n", packed[3:packed.length]);
			}
			return 0;
		}
	}
}
