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

namespace Argus.Server.Rdp
{
	/**
	 * Pairs the agent tunnel with the controller viewer.
	 *
	 * {@link Argus.Agent.Rdp.Tunnel} and
	 * {@link Argus.Controller.Rdp.Viewer} each open a
	 * {@link OLLMrpc.Transport.TlsClient}. ''Relay.join'' stores
	 * that connection. ''Relay.write'' replies, then sends the
	 * chunk to the other connection as ''relay.data''. The second
	 * connection on the app socket calls these. {@link listen} is
	 * the test listen.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var relay = new Argus.Server.Rdp.Relay();
	 * return relay.listen(dir, port);
	 * }}}
	 */
	public class Relay : GLib.Object
	{
		public OLLMrpc.Transport.Connection? agent_conn;
		public OLLMrpc.Transport.Connection? view_conn;

		/**
		 * Register ''Relay.join'' and ''Relay.write''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Relay", typeof(Relay),
				"join", "s",
				"write", "ay");
			OLLMrpc.Request.register("Relay", new Relay());
		}

		/**
		 * Register ''Relay.join'' and ''Relay.write'', then accept clients.
		 *
		 * A handshake is kept only when the peer certificate is signed
		 * by ca.crt in ''dir''. The connection is stored so it is not
		 * destroyed when the handshake callback returns.
		 *
		 * @param dir directory of the server certificate and ca.crt
		 * @param port loopback listen port
		 * @return 0 when the listen loop ends
		 */
		public int listen(string dir, uint16 port) throws GLib.Error
		{
			Relay.rpc_register();
			var server_cert = new GLib.TlsCertificate.from_files(
				GLib.Path.build_filename(dir, "server.crt"),
				GLib.Path.build_filename(dir, "server.key"));
			GLib.TlsDatabase trust = GLib.TlsFileDatabase.new(
				GLib.Path.build_filename(dir, "ca.crt"));
			var service = new GLib.SocketService();
			var where = new GLib.InetSocketAddress(
				new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), port);
			service.add_address(where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, null);
			var live = new Gee.ArrayList<OLLMrpc.Transport.Connection>();
			service.incoming.connect((conn) => {
				try {
					conn.socket.set_option(6, 1, 1);
				} catch (GLib.Error e) {
					stderr.printf("nodelay: %s\n", e.message);
				}
				GLib.TlsServerConnection tls;
				try {
					tls = GLib.TlsServerConnection.@new(conn, server_cert);
				} catch (GLib.Error e) {
					stderr.printf("tls: %s\n", e.message);
					return true;
				}
				tls.database = trust;
				tls.authentication_mode = GLib.TlsAuthenticationMode.REQUIRED;
				tls.accept_certificate.connect((peer, errors) => {
					return peer != null &&
						(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
				tls.handshake_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
					try {
						tls.handshake_async.end(res);
					} catch (GLib.Error e) {
						stderr.printf("handshake: %s\n", e.message);
						return;
					}
					var rpc = new OLLMrpc.Transport.Connection(conn) {
						io = tls
					};
					live.add(rpc);
					rpc.start();
					stderr.printf("rpc connected\n");
				});
				return true;
			});
			service.start();
			stderr.printf("relay listening %u\n", port);
			new GLib.MainLoop().run();
			return 0;
		}

		/**
		 * Remember this connection as the agent or the viewer.
		 *
		 * @param request inbound RPC
		 * @param role ''agent'' or ''view''
		 */
		public void join(OLLMrpc.Request request, string role)
		{
			if (role == "agent") {
				this.agent_conn = request.connection;
			} else {
				this.view_conn = request.connection;
			}
			stderr.printf("joined %s\n", role);
			request.reply(new OLLMrpc.Response());
		}

		/**
		 * Copy one chunk to the other paired connection.
		 *
		 * @param request inbound RPC
		 * @param chunk desktop bytes from the caller
		 */
		public void write(OLLMrpc.Request request, GLib.Bytes chunk)
		{
			var other = this.agent_conn;
			if (request.connection == this.agent_conn) {
				other = this.view_conn;
			}
			request.reply(new OLLMrpc.Response());
			if (other == null || chunk.get_size() == 0) {
				return;
			}
			var held = GLib.Value(typeof(GLib.Bytes));
			held.set_boxed(chunk);
			var note = new OLLMrpc.Notification() {
				method = "relay.data"
			};
			note.args.add(held);
			other.write(note);
		}
	}
}
