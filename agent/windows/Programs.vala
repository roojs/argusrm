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

namespace Argus.Agent.OSQuery
{
	/**
	 * Windows agent ''programs'' row.
	 *
	 * Extends {@link Argus.Shared.OSQuery.Programs} and
	 * implements {@link Package}. The Linux agent compiles a
	 * placeholder and does not query this table.
	 */
	public class Programs : Argus.Shared.OSQuery.Programs, Package
	{
		/**
		 * Query installed software and post the snapshot.
		 *
		 * {@link Argus.Shared.OSQuery.Programs.snapshot_sql} is
		 * the union of registry programs, Store packages, Chocolatey,
		 * third-party services, and startup items. PE hash and
		 * Authenticode are filled before the post.
		 *
		 * @param application agent that holds the connection and
		 *   {@link Application.packages_sent}
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public int send(Application application)
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return 0;
			}
			var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			application.osquery.select(OLLMrpc.Bin.alias_to_gtype.get(this.rpc_name()),
				Argus.Shared.OSQuery.Programs.snapshot_sql(), fresh);
			if (fresh.size > 0) {
				if (application.ensure_client_db()) {
					Argus.Agent.SQT.WinFileIdentity.init_db(application.client_db);
					var programs = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
					foreach (var row in fresh) {
						if (row is Argus.Shared.OSQuery.Programs) {
							programs.add((Argus.Shared.OSQuery.Programs) row);
						}
					}
					var enrichment = new Argus.Agent.Windows.ExeEnrichment();
					enrichment.locate(programs);
					enrichment.enrich(programs, application.client_db);
					enrichment.attach(programs);
				} else {
					GLib.warning("programs send without PE enrichment: client db unavailable");
				}
			}
			if (application.packages_sent && fresh.size == 0) {
				return 0;
			}
			var connection = application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				var response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", this.rpc_name(), fresh)
				});
				if (response.error != null) {
					GLib.debug("%s send failed %s", this.table_name(), response.error.message);
					return response.error.code;
				}
			} catch (GLib.Error e) {
				Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			application.packages_sent = true;
			return 0;
		}
	}
}
