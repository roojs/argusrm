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

namespace Argus.Server.Net
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
	 * var rpc = new Argus.Server.Net.SslConnection(conn, app) {
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
		 * ''agent.id'' for this certificate. ''-1'' until
		 * {@link allow_request} finds an approved row.
		 * ''0'' is the Unix controller, not a TLS agent.
		 */
		public int64 agent_id { get; set; default = -1; }

		public SslConnection(GLib.SocketConnection stream, Application app)
		{
			GLib.Object(stream: stream, app: app);
		}

		/**
		 * Unknown certificates may only call
		 * ''Agent.request_registration''.
		 *
		 * A stored row with status 1 may call the other methods.
		 * A pending controller row becomes active on its first
		 * ''RPC-Daemon.hello''.
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
					error = new OLLMrpc.Error.INVALID_REQUEST("client certificate required")
				});
				return false;
			}
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			var cert_q = Argus.Shared.Agent.query(this.app.db);
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", this.cert_fingerprint);
			cert_q.selectWhere("WHERE fingerprint = $fingerprint", int_binds, text_binds, rows);
			if (rows.size > 0) {
				var row = rows.get(0);
				if (row.status == 1) {
					this.agent_id = row.id;
					return true;
				}
				if (row.status == 0 && row.is_controller &&
					request.method == "RPC-Daemon.hello") {
					row.status = 1;
					row.last_connected = new GLib.DateTime.now_utc().to_unix();
					cert_q.updateById(row);
					this.app.db.backupDB();
					this.agent_id = row.id;
					return true;
				}
			}
			this.reply(request, new OLLMrpc.Response() {
				error = new OLLMrpc.Error.CERT_NOT_REGISTERED("certificate not registered")
			});
			return false;
		}

		/**
		 * Record the close time, then stop the socket.
		 */
		public override void stop()
		{
			var tell = this.running && this.agent_id > 0;
			if (tell) {
				var rows = new Gee.ArrayList<Argus.Shared.Agent>();
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", (int) this.agent_id);
				Argus.Shared.Agent.query(this.app.db).selectWhere(
					"WHERE id = $id", int_binds, text_binds, rows);
				if (rows.size > 0) {
					rows.get(0).last_connected = new GLib.DateTime.now_utc().to_unix();
					Argus.Shared.Agent.query(this.app.db).updateById(rows.get(0));
				}
			}
			base.stop();
			if (tell) {
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.agent",
					action = "disconnected"
				});
			}
		}
	}
}
