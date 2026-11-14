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
	 * Agent ''logged_in_users'' row.
	 *
	 * Extends {@link Argus.Shared.OSQuery.LoggedInUsers} and posts
	 * the session snapshot with a Linux cgroup fallback when
	 * ''utmp'' is absent.
	 */
	public class LoggedInUsers : Argus.Shared.OSQuery.LoggedInUsers
	{
		/**
		 * Query ''logged_in_users'' and post the snapshot.
		 *
		 * Calls {@link Execute.sync_table} directly when
		 * ''logged_in_users'' returns rows. Otherwise falls back to
		 * active systemd session scopes in ''processes'' on Linux.
		 *
		 * @param application agent whose server connection is open
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public int send(Application application)
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return 0;
			}
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(this.rpc_name());
			application.osquery.select(row_type, "SELECT * FROM " + this.table_name(), rows);
			if (rows.size > 0) {
				return application.osquery.sync_table(this.table_name(), this.rpc_name());
			}
			/* Workaround for systemd 256+ removing /run/utmp and
			 * osquery's logged_in_users table still relying on utmp
			 * (causing it to return 0 rows on modern Linux distros).
			 */
			application.osquery.select(row_type,
				"SELECT 'user' AS type, u.username AS user, '' AS tty, '' AS host, " +
				"MIN(p.start_time) AS time, MIN(p.pid) AS pid " +
				"FROM processes p " +
				"JOIN users u ON p.cgroup_path LIKE '/user.slice/user-' || u.uid || '.slice/%' " +
				"WHERE p.cgroup_path LIKE '/user.slice/user-%.slice/session-%.scope' " +
				"GROUP BY p.cgroup_path, u.username",
				rows);
			if (rows.size == 0) {
				return application.osquery.sync_table(this.table_name(), this.rpc_name());
			}
			GLib.debug("SELECT * FROM %s %d rows", this.table_name(), rows.size);
			var connection = application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Response response;
			try {
				response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", this.rpc_name(), rows)
				});
			} catch (GLib.Error e) {
				Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", this.table_name(), response.error.message);
				return response.error.code;
			}
			GLib.debug("%s sent", this.table_name());
			return 0;
		}
	}
}
