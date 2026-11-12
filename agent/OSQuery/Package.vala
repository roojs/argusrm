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
	 * Post one package snapshot.
	 *
	 * The shared {@link Argus.Shared.OSQuery.Package} applies it.
	 * This type does not declare {@link Argus.Shared.OSQuery.DebPackages},
	 * {@link Argus.Shared.OSQuery.RpmPackages}, or
	 * {@link Argus.Shared.OSQuery.Programs}.
	 */
	public interface Package : Argus.Shared.OSQuery.Package
	{
		/**
		 * Query this table and post the snapshot.
		 *
		 * {@link Execute.select} fills the list.
		 * {@link Execute.init} sets {@link Execute.osqueryi}
		 * when it is still empty. An empty path posts nothing.
		 * An empty query after ''application.packages_sent''
		 * posts nothing.
		 *
		 * @param application agent that holds the connection and
		 *   {@link Application.packages_sent}
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public virtual int send(Application application)
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return 0;
			}
			var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			application.osquery.select(
				this.get_type(), "SELECT * FROM " + this.table_name(), fresh);
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
