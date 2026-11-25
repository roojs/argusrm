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

namespace Argus.Server.SQT
{
	/**
	 * Registered fleet rows on the app socket.
	 *
	 * {@link list} and {@link remove} are the wire surface for
	 * table ''agent''. {@link allowlist} feeds the app-port
	 * firewall; it is not an RPC.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQT.Agent.rpc_register();
	 * OLLMrpc.Request.register("Agent",
	 *     new Argus.Server.SQT.Agent.for_rpc(app));
	 * }}}
	 */
	public class Agent : Argus.Shared.Agent
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public Agent()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public Agent.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register fleet list and remove on wire ''Agent''.
		 */
		public static new void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"Agent", typeof(Agent),
				"list", "i",
				"remove", "i");
		}

		/**
		 * List registered machines.
		 *
		 * {@link Argus.Shared.Agent.connected} is true while that
		 * machine's app socket is open.
		 *
		 * When ''agent_id'' is less than one, every registered row
		 * is returned. Otherwise zero or one row for that id.
		 *
		 * @param request inbound RPC on the Unix socket
		 * @param agent_id ''agent.id'', or zero for the full list
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			if (agent_id > 0) {
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", agent_id);
				Argus.Shared.Agent.query(this.app.db).selectWhere(
					"WHERE id = $id", int_binds, text_binds, rows);
			} else {
				Argus.Shared.Agent.query(this.app.db).select("", rows);
			}
			foreach (var row in rows) {
				var open = this.app.ssl_listen.by_id.get((int) row.id);
				row.connected = open != null && open.running;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Remove one machine.
		 *
		 * A controller calls this. The row is deleted. A connected
		 * agent is told to drop its certificate, then its app
		 * socket is closed, and the allowlist is refreshed.
		 * An unknown id is an error.
		 *
		 * @param request inbound RPC from a controller
		 * @param id ''agent.id''
		 */
		public void remove(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds.set("id", id);
			Argus.Shared.Agent.query(this.app.db).selectWhere(
				"WHERE id = $id", int_binds, text_binds, rows);
			if (rows.size < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown machine")
				});
				return;
			}
			Argus.Shared.Agent.query(this.app.db).deleteId(id);
			var open = this.app.ssl_listen.by_id.get(id);
			if (open != null) {
				open.write(new OLLMrpc.Notification() {
					method = "agent.removed"
				});
				open.stop();
			}
			this.app.db.backupDB();
			this.app.firewall.apply(
				allowlist(this.app.db, this.app.interfaces));
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Registered source addresses, plus every address on this machine.
		 *
		 * Active ''agent.ip'' values are kept when
		 * {@link Net.Interfaces.route} returns a source. A private
		 * route counts. This machine's own addresses are added after
		 * that. {@link Net.NFTables.apply} receives only these
		 * addresses.
		 *
		 * @param db agent table
		 * @param interfaces local addresses and routes
		 * @return the IPv4 and IPv6 allowlist
		 */
		public static Gee.ArrayList<GLib.InetAddress> allowlist(
			SQ.Database db, Net.Interfaces interfaces)
		{
			var kept = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
			var query = Argus.Shared.Agent.query(db);
			foreach (var text in query.fetchAllString(query.selectPrepare(
				"SELECT DISTINCT ip FROM agent WHERE status = 1 AND ip != ''"))) {
				var address = new GLib.InetAddress.from_string(text);
				if (address == null) {
					GLib.warning("stored address is not an IP: %s", text);
					continue;
				}
				var source = interfaces.route(address);
				if (source == null) {
					continue;
				}
				kept.add(address);
			}
			foreach (var item in interfaces.addresses) {
				if (kept.contains(item.address)) {
					continue;
				}
				kept.add(item.address);
			}
			return kept;
		}
	}
}