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
 * Code the agent and the controller both use.
 *
 * {@link Register} sends the certificate registration call over
 * {@link OLLMrpc}. {@link Browse} finds the ''_rpc._tcp'' broadcast.
 * On Android that call goes through ''PairBrowse''.
 * {@link RegisterWindow} is the six-digit dialog for the agent and
 * the controller. The sixth digit calls {@link Register}.
 * {@link OSQuery.Row} is one osquery row. The agent and the
 * server both use those objects. {@link SQT.Task} and the other
 * SQT rows are the task and script tables.
 *
 * == Example ==
 *
 * {{{
 * var registration = new Argus.Shared.Register();
 * registration.try_connection(host, port, pin, "desktop");
 * }}}
 */
namespace Argus.Shared
{
	internal class NamespaceDoc {}

	/**
	 * Add ''added_dt'', ''updated_dt'', and ''deleted_dt''.
	 *
	 * Call this after CREATE TABLE. A table that already has
	 * the columns is left as it is.
	 *
	 * @param db Argus database
	 * @param table stored table name
	 */
	public void init_db_audit(SQ.Database db, string table)
	{
		var errmsg = "";
		db.db.exec("ALTER TABLE " + table + " ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
		db.db.exec("ALTER TABLE " + table + " ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
		db.db.exec("ALTER TABLE " + table + " ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
	}
}
