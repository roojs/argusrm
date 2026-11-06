/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Server
{
	/**
	 * Receives osquery snapshots from registered agents.
	 */
	public class OSQuery : GLib.Object
	{
		public Application app { get; construct; }

		public OSQuery(Application app)
		{
			Object(app: app);
		}

		/**
		 * Register the shared row types and ''OSQuery.sync''.
		 */
		public static void rpc_register()
		{
			Argus.Shared.OSQuery.SystemInfo.rpc_register();
			Argus.Shared.OSQuery.CpuInfo.rpc_register();
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
			Argus.Shared.OSQuery.InterfaceAddresses.rpc_register();
			OLLMrpc.Request.add_class(
				"OSQuery", typeof(OSQuery),
				"sync", "so"
			);
		}

		/**
		 * Replace one osquery table snapshot for the calling agent.
		 *
		 * @param request inbound RPC on the app socket
		 * @param name registered RPC row name
		 * @param rows complete table snapshot
		 */
		public void sync(OLLMrpc.Request request, string name, Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> rows)
		{
			var connection = (Net.SslConnection) request.connection;
			if (OLLMrpc.Bin.alias_to_gtype == null ||
				!OLLMrpc.Bin.alias_to_gtype.has_key(name)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown osquery row class")
				});
				return;
			}
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(name);
			if (!row_type.is_a(typeof(Argus.Shared.OSQuery.Row))) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid osquery row class")
				});
				return;
			}
			var model = (Argus.Shared.OSQuery.Row) GLib.Object.new(row_type);
			if (!model.sync(this.app.db, connection.agent_id, rows)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid " + name + " row")
				});
				return;
			}
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() { 
				msg = "ok" 
			});
		}
	}
}
