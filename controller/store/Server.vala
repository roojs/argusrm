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

namespace Argus.Controller.Store
{
	/**
	 * Saved management servers on the controller client database.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Server(app);
	 * var rows = store.list();
	 * }}}
	 */
	public class Server : GLib.Object
	{
		public Application app;

		/**
		 * @param app controller process
		 */
		public Server(Application app)
		{
			this.app = app;
		}

		/**
		 * All non-deleted management-server rows, certificates loaded.
		 */
		public Gee.ArrayList<Argus.Controller.SQT.Server> list() throws GLib.Error
		{
			var rows = new Gee.ArrayList<Argus.Controller.SQT.Server>();
			Argus.Controller.SQT.Server.query(this.app.client_db).selectWhere(
				"WHERE deleted_dt = 0", null, null, rows);
			foreach (var row in rows) {
				row.load_certificates();
			}
			return rows;
		}
	}
}