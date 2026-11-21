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
	 * Machines that have one package name.
	 *
	 * Extends {@link Argus.Shared.SQV.PackageMachine}. {@link machines}
	 * reads ''deb_packages'', ''rpm_packages'', or ''programs''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQV.PackageMachine.rpc_register();
	 * OLLMrpc.Request.register("PackageMachine",
	 *     new Argus.Server.SQV.PackageMachine.for_rpc(app));
	 * }}}
	 */
	public class PackageMachine : Argus.Shared.SQV.PackageMachine
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public PackageMachine()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public PackageMachine.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register the row type and {@link machines}.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQV.PackageMachine.rpc_register();
			OLLMrpc.Request.add_class(
				"PackageMachine", typeof(PackageMachine),
				"machines", "ss"
			);
		}

		/**
		 * Machines that have this exact package name.
		 *
		 * ''kind'' is ''deb'', ''rpm'', or ''programs''. One row per
		 * agent still in ''agent''. The machine name is
		 * ''system_info.computer_name'', or the agent hostname,
		 * requester, or id. {@link logged_in_users} is the distinct
		 * live sessions on that agent, the same join the Machines
		 * list uses. Version matches the Software grid: Debian is
		 * version and revision, RPM is epoch, version, and release,
		 * and Windows is ''programs.version''.
		 * {@link update_since} is the earliest ''package_updates.since''
		 * for this name on that agent, or zero. {@link uninstall_string}
		 * is the Windows uninstall command, or empty.
		 *
		 * @param request inbound RPC from a controller
		 * @param name exact package or program name
		 * @param kind ''deb'', ''rpm'', or ''programs''
		 */
		public void machines(OLLMrpc.Request request, string name, string kind)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var table = "";
			var version = "";
			var command = "''";
			switch (kind) {
			case "deb":
				table = "deb_packages";
				version = "deb_packages.version || '-' || deb_packages.revision";
				break;

			case "rpm":
				table = "rpm_packages";
				version = "rpm_packages.epoch || ':' || " +
					"rpm_packages.version || '-' || rpm_packages.release";
				break;

			case "programs":
				table = "programs";
				version = "programs.version";
				command = "programs.uninstall_string";
				break;

			default:
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown package list")
				});
				return;
			}
			var source_filter = "";
			var live_source = "";
			if (kind == "programs") {
				source_filter = @"AND $(table).source = 'programs'";
				live_source = "AND source = 'programs'";
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQV.PackageMachine>();
			var query = new SQ.Query<Argus.Shared.SQV.PackageMachine>(this.app.db, table);
			var stmt = query.selectPrepare(@"
				SELECT
					agent.id AS agent_id,
					CASE
						WHEN system_info.computer_name != '' THEN system_info.computer_name
						WHEN agent.hostname != '' THEN agent.hostname
						WHEN agent.requester != '' THEN agent.requester
						ELSE CAST(agent.id AS TEXT)
					END AS machine,
					$(version) AS version,
					COALESCE((
						SELECT
							MIN(package_updates.since)
						FROM
							package_updates
						WHERE
							package_updates.agent_id = agent.id
						AND
							package_updates.name = $$name
					), 0) AS update_since,
					$(command) AS uninstall_string,
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
					$(table)
				JOIN
					agent
				ON
					agent.id = $(table).agent_id
				LEFT JOIN
					system_info
				ON
					system_info.agent_id = agent.id
				AND
					system_info.id = (
						SELECT
							MAX(id)
						FROM
							system_info
						WHERE
							agent_id = agent.id
					)
				WHERE
					$(table).name = $$name
				AND
					$(table).deleted_dt = 0
				$(source_filter)
				AND
					$(table).id = (
						SELECT
							MAX(id)
						FROM
							$(table)
						WHERE
							agent_id = agent.id
						AND
							name = $$name
						$(live_source)
						AND
							deleted_dt = 0
					)
				ORDER BY
					machine COLLATE NOCASE
				");
			stmt.bind_text(stmt.bind_parameter_index("$name"), name);
			query.selectExecute(stmt, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
	}
}
