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
		private Gee.HashMap<int, Seat> seats = new Gee.HashMap<int, Seat>();

		/**
		 * Register ''Relay.join'', ''Relay.write'', ''Relay.start'',
		 * ''Relay.view'', and ''Relay.fresh''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Relay", typeof(Relay),
				"join", "s",
				"write", "ay",
				"start", "i",
				"view", "i",
				"fresh", "");
			OLLMrpc.Request.register("Relay", new Relay());
		}

		/**
		 * The seat for one agent id, creating it on first use.
		 *
		 * @param id ''agent.id''
		 * @return that seat
		 */
		private Seat seat(int id)
		{
			if (this.seats.has_key(id)) {
				return this.seats.get(id);
			}
			var created = new Seat();
			this.seats.set(id, created);
			return created;
		}

		/**
		 * The seat whose stream or view is this connection.
		 *
		 * @param conn a stream connection
		 * @return the seat, or null for the test pair
		 */
		private Seat? seat_of(OLLMrpc.Transport.Connection conn)
		{
			foreach (var seat in this.seats.values) {
				if (seat.agent_conn == conn || seat.view_conn == conn) {
					return seat;
				}
			}
			return null;
		}

		/**
		 * Ask one Windows agent to open its desktop stream.
		 *
		 * The caller is a controller. ''relay.start'' goes to that
		 * agent's app connection. ''relay.ready'' is sent here when
		 * the stream is already up, and from {@link join} when it
		 * comes up later.
		 *
		 * @param request inbound RPC
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void start(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var ssl = request.connection as Net.SslConnection;
			if (ssl == null || agent_id < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			var agent = ssl.app.ssl_listen.by_id.get(agent_id);
			if (agent == null || !agent.running) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			var seat = this.seat(agent_id);
			if (seat.agent_conn != null) {
				request.reply(new OLLMrpc.Response());
				seat.ready(request.connection, agent_id);
				return;
			}
			seat.asked = request.connection;
			agent.write(new OLLMrpc.Notification() {
				method = "relay.start"
			});
			request.reply(new OLLMrpc.Response());
		}

		/**
		 * Attach this controller stream to one agent.
		 *
		 * A stream that has already forwarded a byte is cut first.
		 * The reply waits for {@link fresh}.
		 *
		 * @param request inbound RPC, the controller's second connection
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void view(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var ssl = request.connection as Net.SslConnection;
			if (ssl == null || agent_id < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			var seat = this.seat(agent_id);
			if (!seat.attach(request)) {
				return;
			}
			var agent = ssl.app.ssl_listen.by_id.get(agent_id);
			if (agent == null || !agent.running) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			seat.holding = request;
			agent.write(new OLLMrpc.Notification() {
				method = "relay.cut"
			});
		}

		/**
		 * Mark the agent's new Windows connection as the start.
		 *
		 * The next forwarded byte is the first byte of that connection.
		 *
		 * @param request inbound RPC on the agent stream
		 */
		public void fresh(OLLMrpc.Request request)
		{
			var seat = this.seat_of(request.connection);
			request.reply(new OLLMrpc.Response());
			if (seat == null) {
				return;
			}
			seat.release();
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
			var ssl = request.connection as Net.SslConnection;
			if (ssl != null && ssl.user.id > 0 && !ssl.user.is_controller && role == "agent") {
				var id = (int) ssl.user.id;
				this.seat(id).joined(request, id);
				return;
			}
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
			var seat = this.seat_of(request.connection);
			var other = this.agent_conn;
			if (seat == null && request.connection == this.agent_conn) {
				other = this.view_conn;
			}
			request.reply(new OLLMrpc.Response());
			if (seat != null) {
				seat.forward(request.connection, chunk);
				return;
			}
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
