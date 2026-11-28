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
	 * Packages removed with one Debian package.
	 *
	 * Extends {@link Argus.Shared.SQV.AptDepends}. {@link removed}
	 * reads every dependent from ''apt_pkg_depends''. The catalog
	 * stores Depends and Pre-Depends only.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQV.AptDepends.rpc_register();
	 * OLLMrpc.Request.register("AptDepends",
	 *     new Argus.Server.SQV.AptDepends.for_rpc(app));
	 * }}}
	 */
	public class AptDepends : Argus.Shared.SQV.AptDepends
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public AptDepends()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public AptDepends.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register the row type and {@link removed}.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQV.AptDepends.rpc_register();
			OLLMrpc.Request.add_class(
				"AptDepends", typeof(AptDepends),
				"removed", "s"
			);
		}

		/**
		 * Every package that depends on ''name''.
		 *
		 * One query. The first step is the packages that depend on
		 * ''name''. Each later step is the packages that depend on
		 * those. Depends and Pre-Depends are the only edges. ''name''
		 * is not a row. An unknown name is an empty list. The column
		 * view sorts the names.
		 *
		 * @param db Argus database
		 * @param name exact ''apt_pkg.name''
		 * @return all dependents, without ''name''
		 */
		public static Gee.ArrayList<Argus.Shared.SQV.AptDepends> dependents(
			SQ.Database db,
			string name
		) {
			var rows = new Gee.ArrayList<Argus.Shared.SQV.AptDepends>();
			var query = new SQ.Query<Argus.Shared.SQV.AptDepends>(db, "apt_pkg");
			var stmt = query.selectPrepare(@"
				WITH RECURSIVE
					dependents (id) AS (
						SELECT
							apt_pkg.id
						FROM
							apt_pkg
						JOIN
							apt_pkg_depends
						ON
							apt_pkg.id = apt_pkg_depends.pkg_id
						WHERE
							apt_pkg_depends.depends_pkg_id = (
								SELECT
									apt_pkg.id
								FROM
									apt_pkg
								WHERE
									apt_pkg.name = $$name
							)
						UNION
						SELECT
							apt_pkg.id
						FROM
							apt_pkg
						JOIN
							apt_pkg_depends
						ON
							apt_pkg.id = apt_pkg_depends.pkg_id
						JOIN
							dependents
						ON
							apt_pkg_depends.depends_pkg_id = dependents.id
					)
				SELECT
					apt_pkg.name AS name
				FROM
					apt_pkg
				JOIN
					dependents
				ON
					apt_pkg.id = dependents.id
				WHERE
					apt_pkg.name != $$name
				");
			stmt.bind_text(stmt.bind_parameter_index("$name"), name);
			query.selectExecute(stmt, rows);
			return rows;
		}

		/**
		 * Reply with the packages removed with ''name''.
		 *
		 * @param request inbound RPC from a controller
		 * @param name exact package name
		 */
		public void removed(OLLMrpc.Request request, string name)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var dependents = AptDepends.dependents(this.app.db, name);
			var response = new OLLMrpc.Response() {
				msg = "ok"
			};
			if (dependents.size > 0) {
				response.retval = OLLMrpc.val("o", dependents);
			}
			request.reply(response);
		}
	}
}
