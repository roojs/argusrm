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
	 * ''Offering.enroll'' and ''Offering.status''.
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
		 * Approved ''agent'' row for this certificate.
		 *
		 * ''id'' is ''0'' until {@link SslListen} or
		 * {@link allow_request} finds an approved row.
		 */
		public Argus.Shared.Agent user {
			get; set; default = new Argus.Shared.Agent();
		}

		private bool closing = false;

		public SslConnection(GLib.SocketConnection stream, Application app)
		{
			GLib.Object(stream: stream, app: app);
			this.notify["user"].connect(() => {
				this.set_data("argus-user", this.user);
				if (this.user.id < 1) {
					return;
				}
				var listen = this.get_data<SslListen>("argus-listen");
				if (listen == null || listen.registration) {
					return;
				}
				var existing = listen.by_id.get((int) this.user.id);
				if (existing == null || !existing.running) {
					listen.by_id.set((int) this.user.id, this);
				}
			});
		}

		/**
		 * Unknown certificates may only call
		 * ''Offering.enroll'' and ''Offering.status''.
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
			if (request.method == "Offering.enroll" ||
				request.method == "Offering.status") {
				return true;
			}
			if (this.cert_fingerprint == "") {
				GLib.debug("closing connection without client certificate (%s)", request.method);
				this.app.firewall.apply(
					SQT.Agent.allowlist(this.app.db, this.app.interfaces));
				this.stop();
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
					this.user = row;
					return true;
				}
				if (row.status == 0 && row.is_controller &&
					request.method == "RPC-Daemon.hello") {
					row.status = 1;
					row.last_connected = new GLib.DateTime.now_utc().to_unix();
					cert_q.updateById(row);
					this.app.db.backupDB();
					this.user = row;
					return true;
				}
			}
			GLib.debug("closing connection for failed certificate %s (%s)",
				this.cert_fingerprint, request.method);
			this.app.firewall.apply(
				SQT.Agent.allowlist(this.app.db, this.app.interfaces));
			this.stop();
			return false;
		}

		/**
		 * Record the close time, then stop the socket.
		 *
		 * Holds a reference across the parent close. Closing the
		 * socket can drop the last external reference, and the rest
		 * of this method still reads {@link user}. A second call
		 * while that close is in progress returns.
		 */
		public override void stop()
		{
			if (this.closing) {
				GLib.warning("connection close already in progress");
				return;
			}
			this.closing = true;
			this.ref();
			var user_id = this.user.id;
			var controller = this.user.is_controller;
			var tell = this.running && user_id > 0;
			GLib.debug("closing connection %s", user_id.to_string());
			if (tell) {
				var rows = new Gee.ArrayList<Argus.Shared.Agent>();
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", (int) user_id);
				Argus.Shared.Agent.query(this.app.db).selectWhere(
					"WHERE id = $id", int_binds, text_binds, rows);
				if (rows.size > 0) {
					rows.get(0).last_connected = new GLib.DateTime.now_utc().to_unix();
					Argus.Shared.Agent.query(this.app.db).updateById(rows.get(0));
				}
			}
			if (tell && !controller) {
				new Argus.Server.SQT.Task.for_rpc(this.app).connection_lost(user_id);
			}
			base.stop();
			if (tell) {
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.agent",
					action = "disconnected"
				});
			}
			var listen = this.get_data<SslListen>("argus-listen");
			if (listen == null) {
				this.unref();
				return;
			}
			listen.connections.remove(this);
			if (user_id < 1 || listen.by_id.get((int) user_id) != this) {
				this.unref();
				return;
			}
			listen.by_id.unset((int) user_id);
			this.unref();
		}
	}
}
