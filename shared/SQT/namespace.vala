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

/**
 * SQL tables for tasks and the script library.
 *
 * {@link Task} is the activity. {@link TaskTarget} is one machine it
 * runs on. {@link Script} is a file under ''scripts/'' or a clone.
 * {@link ScriptPerm} permits a script on a machine.
 * {@link ScriptRepository} is a git clone under ''git/''.
 * {@link Distributable} is a product we can install.
 * {@link DistributableVersion} is one uploaded file for that product.
 * {@link AptUrl}, {@link AptPkg}, and {@link AptPkgDepends} are the
 * Debian repository dependency catalog.
 * {@link Server} is a client-local saved management-server row;
 * it is not created by {@link init_db} on the management server.
 *
 * == Example ==
 *
 * {{{
 * Argus.Shared.SQT.rpc_register();
 * Argus.Shared.SQT.init_db(db);
 * var rows = new Gee.ArrayList<Argus.Shared.SQT.Task>();
 * Argus.Shared.SQT.Task.query(db).select("", rows);
 * }}}
 */
namespace Argus.Shared.SQT
{
	/**
	 * Register task and script row types with the ''OLLMrpc'' bin codec.
	 */
	public static void rpc_register()
	{
		Task.rpc_register();
		TaskTarget.rpc_register();
		Script.rpc_register();
		ScriptPerm.rpc_register();
		ScriptRepository.rpc_register();
		Distributable.rpc_register();
		DistributableVersion.rpc_register();
	}

	/**
	 * Create the task and script tables.
	 *
	 * @param db Argus database
	 */
	public static void init_db(SQ.Database db)
	{
		Task.init_db(db);
		TaskTarget.init_db(db);
		Script.init_db(db);
		ScriptPerm.init_db(db);
		ScriptRepository.init_db(db);
		Distributable.init_db(db);
		DistributableVersion.init_db(db);
		AptUrl.init_db(db);
		AptPkg.init_db(db);
		AptPkgDepends.init_db(db);
	}
}
