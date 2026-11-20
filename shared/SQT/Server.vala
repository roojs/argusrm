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

namespace Argus.Shared.SQT
{
	/**
	 * One saved management-server row on a client.
	 *
	 * The table is ''server''. It lives in the **controller** (or
	 * agent) **local** SQLite file, not in the Argus Remote Manager
	 * server database. {@link Argus.Shared.SQT.init_db} does **not**
	 * create this table. {@link Argus.Controller.Store.Servers}
	 * opens the client database and calls {@link init_db}.
	 *
	 * Non-secret columns only; client certificates stay in libsecret
	 * or Android credential files keyed by {@link name}. How the
	 * management link reads row fields and secrets is **not** defined
	 * on this class yet — see the registration-store bug log (R1).
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.Server.init_db(db);
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.Server>();
	 * Argus.Shared.SQT.Server.query(db).select("", rows);
	 * }}}
	 */
	public class Server : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		/**
		 * Row id in ''server''.
		 */
		public int64 id { get; set; default = 0; }
		/**
		 * Display name and secret lookup key.
		 */
		public string name { get; set; default = ""; }
		/**
		 * TLS port for the management app socket.
		 */
		public int port { get; set; default = 0; }
		/**
		 * Listen addresses to try, one host per line.
		 */
		public string addresses { get; set; default = ""; }
		/**
		 * Host that last answered a probe, or empty.
		 */
		public string last_host { get; set; default = ""; }
		/**
		 * Agent download socket as ''host:port''.
		 */
		public string download { get; set; default = ""; }
		/**
		 * Download URL path from registration.
		 */
		public string download_path { get; set; default = ""; }
		/**
		 * True when this row is the active server for the controller.
		 */
		public bool is_active { get; set; default = false; }

		/**
		 * {@link addresses} split into lines; empty entries skipped.
		 */
		public string[] address_list {
			owned get {
				if (this.addresses == "") {
					return {};
				}
				var hosts = new Gee.ArrayList<string>();
				foreach (var line in this.addresses.split("\n")) {
					var text = line.strip();
					if (text != "") {
						hosts.add(text);
					}
				}
				return (string[]) hosts.to_array();
			}
		}

		/**
		 * Rows in ''server''.
		 *
		 * @param db client-local database
		 * @return the query
		 */
		public static SQ.Query<Server> query(SQ.Database db)
		{
			return new SQ.Query<Server>(db, "server");
		}

		/**
		 * Create ''server'' on a client-local database.
		 *
		 * Do not call this on the management server Argus database.
		 *
		 * @param db client-local database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS server (
					id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					name            TEXT NOT NULL DEFAULT '',
					port            INTEGER NOT NULL DEFAULT 0,
					addresses       TEXT NOT NULL DEFAULT '',
					last_host       TEXT NOT NULL DEFAULT '',
					download        TEXT NOT NULL DEFAULT '',
					download_path   TEXT NOT NULL DEFAULT '',
					is_active       INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("server create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "server");
		}
	}
}