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

namespace Argus.Server.SQV
{
	/**
	 * Machines that can take one distributable.
	 *
	 * Extends {@link Argus.Shared.SQV.DistributeMachine}. {@link machines}
	 * is the registered hosts on a product's platform, with the installed
	 * version when ''programs'' has that name.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQV.DistributeMachine.rpc_register();
	 * OLLMrpc.Request.register("DistributeMachine",
	 *     new Argus.Server.SQV.DistributeMachine.for_rpc(app));
	 * }}}
	 */
	public class DistributeMachine : Argus.Shared.SQV.DistributeMachine
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public DistributeMachine()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public DistributeMachine.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register the row type and {@link machines}.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQV.DistributeMachine.rpc_register();
			OLLMrpc.Request.add_class(
				"DistributeMachine", typeof(DistributeMachine),
				"machines", "ss"
			);
		}

		/**
		 * Registered hosts on ''platform'', with this product's version.
		 *
		 * One row per agent whose ''status'' is 1 and whose live
		 * ''os_version.platform'' is ''platform''. The machine name is
		 * ''system_info.computer_name'', or the agent hostname,
		 * requester, or id. The existing version is the live
		 * ''programs.version'' for ''name'', or empty.
		 * {@link logged_in_users} is the distinct live sessions on that
		 * agent, the same join the Machines list uses.
		 *
		 * @param request inbound RPC from a controller
		 * @param name ''programs.name''
		 * @param platform ''os_version.platform''
		 */
		public void machines(OLLMrpc.Request request, string name, string platform)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>();
			var query = new SQ.Query<Argus.Shared.SQV.DistributeMachine>(this.app.db, "agent");
			var stmt = query.selectPrepare("""
				SELECT
					agent.id AS agent_id,
					CASE
						WHEN system_info.computer_name != '' THEN system_info.computer_name
						WHEN agent.hostname != '' THEN agent.hostname
						WHEN agent.requester != '' THEN agent.requester
						ELSE CAST(agent.id AS TEXT)
					END AS machine,
					COALESCE((
						SELECT
							programs.version
						FROM
							programs
						WHERE
							programs.agent_id = agent.id
						AND
							programs.name = $name
						AND
							programs.deleted_dt = 0
						ORDER BY
							programs.id DESC
						LIMIT
							1
					), '') AS existing,
					COALESCE((
						SELECT
							GROUP_CONCAT(DISTINCT logged_in_users.user)
						FROM
							logged_in_users
						WHERE
							logged_in_users.agent_id = agent.id
						AND
							logged_in_users.user != ''
						AND
							logged_in_users.deleted_dt = 0
					), '') AS logged_in_users
				FROM
					agent
				JOIN
					system_info
				ON
					system_info.agent_id = agent.id
				AND
					system_info.id = (
						SELECT
							MAX(s.id)
						FROM
							system_info AS s
						WHERE
							s.agent_id = agent.id
					)
				JOIN
					os_version
				ON
					os_version.agent_id = agent.id
				AND
					os_version.deleted_dt = 0
				AND
					os_version.platform = $platform
				AND
					os_version.id = (
						SELECT
							MAX(v.id)
						FROM
							os_version AS v
						WHERE
							v.agent_id = agent.id
						AND
							v.deleted_dt = 0
					)
				WHERE
					agent.status = 1
				ORDER BY
					machine COLLATE NOCASE
				""");
			stmt.bind_text(stmt.bind_parameter_index("$name"), name);
			stmt.bind_text(stmt.bind_parameter_index("$platform"), platform);
			query.selectExecute(stmt, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
	}
}
