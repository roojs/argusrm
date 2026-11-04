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
	 * Bin connection on the app socket.
	 *
	 * {@link SslListen} constructs one after the TLS handshake.
	 * An unknown certificate may only call
	 * ''Agent.request_registration''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rpc = new Argus.Server.SslConnection(conn, app) {
	 *     io = tls,
	 *     cert_fingerprint = fingerprint
	 * };
	 * rpc.start();
	 * }}}
	 */
	public class SslConnection : OLLMrpc.Transport.Connection
	{
		public Application app { get; construct; }

		/**
		 * ''agent.id'' for this certificate. Zero until
		 * {@link allow_request} finds an approved row.
		 */
		public int64 agent_id { get; private set; default = 0; }

		public SslConnection(GLib.SocketConnection stream, Application app)
		{
			GLib.Object(stream: stream, app: app);
		}

		/**
		 * Unknown certificates may only call
		 * ''Agent.request_registration''.
		 *
		 * A stored row with status 1 may call the other methods.
		 *
		 * @param request inbound RPC
		 * @return true when the method may run
		 */
		public override bool allow_request(OLLMrpc.Request request)
		{
			if (request.method == "Agent.request_registration") {
				return true;
			}
			if (this.cert_fingerprint == "") {
				this.reply(request, new OLLMrpc.Response() {
					error = new OLLMrpc.Error(
						(int) OLLMrpc.RpcErrorCode.INVALID_REQUEST, "client certificate required")
				});
				return false;
			}
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			var cert_q = Argus.Shared.Agent.query(this.app.db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", this.cert_fingerprint);
			cert_q.selectWhere("WHERE fingerprint = $fingerprint AND status = 1",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				this.agent_id = rows.get(0).id;
				return true;
			}
			this.reply(request, new OLLMrpc.Response() {
				error = new OLLMrpc.Error((int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED,
					"certificate not registered")
			});
			return false;
		}
	}
}
