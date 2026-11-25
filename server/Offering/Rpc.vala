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

namespace Argus.Server.Offering
{
	/**
	 * Registration RPC on the Unix socket and controller TLS.
	 *
	 * Uses {@link Network} only for the registration listener,
	 * offering firewall, and PairPublish.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.Offering.Rpc.rpc_register();
	 * OLLMrpc.Request.register("Offering",
	 *     new Argus.Server.Offering.Rpc.for_rpc(app, network));
	 * }}}
	 */
	public class Rpc : GLib.Object
	{
		public Application app { get; private set; }
		public Network network { get; private set; }

		public Rpc.for_rpc(Application app, Network network)
		{
			Object();
			this.app = app;
			this.network = network;
		}

		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Offering", typeof(Rpc),
				"open", "b",
				"close", "b",
				"enroll", "ssssbbss",
				"status", "",
				"accept", "ai",
				"reject", "ai"
			);
		}

		public void open(OLLMrpc.Request request, bool pending)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var net = this.network;
			if (pending) {
				if (!net.update_bulk(DeskState.OPEN)) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR(
							"registration socket did not bind")
					});
					return;
				}
				net.supervising_connection = request.connection;
				net.update_bulk(DeskState.ARM);
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			if (!net.update_pin(DeskState.OPEN)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(
						"registration socket did not bind")
				});
				return;
			}
			net.supervising_connection = request.connection;
			net.update_pin(DeskState.ARM);
			net.lookup_ip.begin(null, (obj, res) => {
				var ipv4 = "";
				try {
					ipv4 = net.lookup_ip.end(res);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				string[] retval = {};
				retval += net.pin;
				retval += ipv4;
				foreach (var line in net.open_lines) {
					retval += line;
				}
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("as", retval),
					msg = "ok"
				});
			});
		}

		public void close(OLLMrpc.Request request, bool pending)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var net = this.network;
			net.supervising_connection = null;
			if (pending) {
				net.update_bulk(DeskState.POLLING);
			} else {
				net.update_pin(DeskState.CLOSED);
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		public void status(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				error = new OLLMrpc.Error.INVALID_REQUEST(
					"status not implemented")
			});
		}

		public void enroll(
			OLLMrpc.Request request,
			string pin,
			string csr,
			string requester,
			string family,
			bool is_controller,
			bool batch,
			string username,
			string hostname
		) {
			var rpc = request.connection as Net.SslConnection;
			if (rpc == null) {
				GLib.warning("socket registration only");
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(
						"socket registration only")
				});
				return;
			}
			var net = this.network;
			var open = net.pin != "" || net.accepting || net.polling;
			var queued = batch && pin == "0000" && !is_controller && open;
			if (!queued && (pin != net.pin || net.pin == "")) {
				if (net.pin == "") {
					GLib.warning("number rejected because registration is closed");
				}
				if (net.pin != "") {
					GLib.warning("number rejected");
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("number rejected")
				});
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "rejected"
				});
				return;
			}
			var replaced = new Gee.ArrayList<Argus.Shared.Agent>();
			if (is_controller && username != "" && hostname != "") {
				var found_binds = new Gee.HashMap<string, int>();
				var found_text = new Gee.HashMap<string, string>();
				found_binds.set("status", 1);
				found_binds.set("is_controller", 1);
				found_text.set("username", username);
				found_text.set("hostname", hostname);
				try {
					Argus.Shared.Agent.query(this.app.db).selectWhere(
						"WHERE status = $status AND is_controller = $is_controller " +
							"AND username = $username AND hostname = $hostname",
						found_binds, found_text, replaced);
				} catch (GLib.Error e) {
					GLib.warning("could not read registration: %s", e.message);
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR(
							"could not read registration")
					});
					return;
				}
			}
			var signed = new Certificate(this.app, csr);
			if (signed.bad_csr) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("bad csr")
				});
				return;
			}
			if (signed.crt_pem == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not sign")
				});
				return;
			}
			var peer = "";
			if (rpc.stream == null) {
				GLib.warning("registration has no peer address");
			} else {
				try {
					var remote = rpc.stream.get_remote_address() as GLib.InetSocketAddress;
					if (remote == null) {
						GLib.warning("registration has no peer address");
					} else {
						peer = remote.get_address().to_string();
					}
				} catch (GLib.Error e) {
					GLib.warning("could not read registration address: %s", e.message);
				}
			}
			if (queued) {
				var pending_row = new Argus.Shared.AgentPending() {
					fingerprint = signed.fingerprint,
					ip = peer,
					created = new GLib.DateTime.now_utc().to_unix(),
					requester = requester,
					hostname = hostname,
					certificate = signed.crt_pem
				};
				pending_row.id = Argus.Shared.AgentPending.query(this.app.db)
					.insert(pending_row);
				this.app.db.backupDB();
				net.pin = "";
				net.accepting = true;
				this.enroll_success(
					request, signed, family, pending_row, null);
				return;
			}
			foreach (var old in replaced) {
				var live = this.app.ssl_listen.by_id.get((int) old.id);
				if (live != null) {
					live.write(new OLLMrpc.Notification() {
						method = "agent.removed"
					});
					live.stop();
				}
				Argus.Shared.Agent.query(this.app.db).deleteId((int) old.id);
			}
			if (replaced.size > 0) {
				GLib.warning("replaced registration %s %s", username, hostname);
			}
			var agent_row = new Argus.Shared.Agent() {
				fingerprint = signed.fingerprint,
				status = 1,
				ip = peer,
				created = new GLib.DateTime.now_utc().to_unix(),
				requester = requester,
				username = username,
				hostname = hostname,
				is_controller = is_controller
			};
			Argus.Shared.Agent.query(this.app.db).insert(agent_row);
			this.app.db.backupDB();
			net.pin = "";
			net.accepting = false;
			net.pair_publish.stop();
			net.firewall.enable();
			this.app.firewall.apply(
				SQT.Agent.allowlist(this.app.db, this.app.interfaces));
			this.app.download_listen.listen();
			this.enroll_success(request, signed, family, null, agent_row);
		}

		private void enroll_success(
			OLLMrpc.Request request,
			Certificate signed,
			string family,
			Argus.Shared.AgentPending? pending_row,
			Argus.Shared.Agent? agent_row
		)
		{
			var is_controller = agent_row != null && agent_row.is_controller;
			var path = "";
			if (!is_controller && family == "debian") {
				path = "/osquery/osquery.deb";
			}
			if (!is_controller && family == "rpm") {
				path = "/osquery/osquery.rpm";
			}
			if (!is_controller && family == "windows") {
				path = "/osquery/osquery.msi";
			}
			var mgmt_host = this.app.socket;
			var port_text = Argus.SOCKET_PORT.to_string();
			var colon = this.app.socket.last_index_of(":");
			if (colon > 0) {
				mgmt_host = this.app.socket.substring(0, colon);
				port_text = this.app.socket.substring(colon + 1);
			}
			if (mgmt_host == "") {
				mgmt_host = "0.0.0.0";
			}
			if (port_text == "") {
				port_text = Argus.SOCKET_PORT.to_string();
			}
			var packed = new Gee.ArrayList<string>();
			packed.add(signed.crt_pem);
			packed.add(signed.ca_pem);
			packed.add(path);
			if (mgmt_host == "0.0.0.0") {
				foreach (var ip in OLLMrpc.Transport.TcpListen.ifaces()) {
					packed.add(ip + ":" + port_text);
				}
			}
			if (mgmt_host != "" && mgmt_host != "0.0.0.0") {
				packed.add(mgmt_host + ":" + port_text);
			}
			var reply = new string[packed.size];
			for (var i = 0; i < packed.size; i++) {
				reply[i] = packed.get(i);
			}
			var reply_msg = "ok";
			if (pending_row != null) {
				reply_msg = "pending";
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", reply),
				msg = reply_msg
			});
			if (pending_row != null) {
				var name = pending_row.hostname;
				if (name == "") {
					name = pending_row.requester;
				}
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.pair",
					action = "pending",
					args = OLLMrpc.args(
						"iss", (int) pending_row.id, pending_row.ip, name)
				});
				return;
			}
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.pair",
				action = "done"
			});
		}

		public void reject(OLLMrpc.Request request, int[] ids)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (ids.length < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("nothing selected")
				});
				return;
			}
			foreach (var id in ids) {
				Argus.Shared.AgentPending.query(this.app.db).deleteId(id);
			}
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		public void accept(OLLMrpc.Request request, int[] ids)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (ids.length < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("nothing selected")
				});
				return;
			}
			var changed = false;
			foreach (var id in ids) {
				var rows = new Gee.ArrayList<Argus.Shared.AgentPending>();
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", id);
				Argus.Shared.AgentPending.query(this.app.db).selectWhere(
					"WHERE id = $id", int_binds, text_binds, rows);
				if (rows.size < 1) {
					continue;
				}
				var row = rows.get(0);
				var existing = new Gee.ArrayList<Argus.Shared.Agent>();
				var have_int = new Gee.HashMap<string, int>();
				var have_text = new Gee.HashMap<string, string>();
				have_text.set("fingerprint", row.fingerprint);
				Argus.Shared.Agent.query(this.app.db).selectWhere(
					"WHERE fingerprint = $fingerprint",
					have_int, have_text, existing);
				if (existing.size < 1) {
					Argus.Shared.Agent.query(this.app.db).insert(new Argus.Shared.Agent() {
						fingerprint = row.fingerprint,
						status = 1,
						ip = row.ip,
						created = new GLib.DateTime.now_utc().to_unix(),
						requester = row.requester,
						hostname = row.hostname
					});
				}
				Argus.Shared.AgentPending.query(this.app.db).deleteId(row.id);
				changed = true;
			}
			if (!changed) {
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
			this.app.db.backupDB();
			this.app.firewall.apply(
				SQT.Agent.allowlist(this.app.db, this.app.interfaces));
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.agent",
				action = "accepted"
			});
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}