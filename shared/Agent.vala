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

namespace Argus.Shared
{
	/**
	 * One registered machine.
	 *
	 * The table is ''agent''. The wire alias is ''Argus.Agent''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.Agent.rpc_register();
	 * var rows = new Gee.ArrayList<Argus.Shared.Agent>();
	 * Argus.Shared.Agent.query(db).select("LIMIT 20", rows);
	 * }}}
	 */
	public class Agent : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		private static SQ.Database db;

		public int64 id { get; set; default = 0; }
		public string fingerprint { get; set; default = ""; }
		public int status { get; set; default = 0; }
		public string ip { get; set; default = ""; }
		public int64 created { get; set; default = 0; }
		/**
		 * Unix time of the latest app-socket session.
		 *
		 * Set when the session opens and again when it closes.
		 * Zero when this machine has never connected.
		 */
		public int64 last_connected { get; set; default = 0; }
		/**
		 * True while an app-socket connection for this row is open.
		 *
		 * ''Agent.list'' sets this from the live connections.
		 * It is not a column.
		 */
		public bool connected { get; set; default = false; }
		public string requester { get; set; default = ""; }
		public string username { get; set; default = ""; }
		public string hostname { get; set; default = ""; }
		public bool is_controller { get; set; default = false; }

		/**
		 * The grid reads the display text. These three sources
		 * change after the row is on screen.
		 */
		construct {
			this.notify["status"].connect(() => {
				this.notify_property("display-registered");
			});
			this.notify["last-connected"].connect(() => {
				this.notify_property("display-last");
			});
			this.notify["connected"].connect(() => {
				this.notify_property("display-connected");
			});
		}

		/**
		 * Name shown for this machine.
		 *
		 * Hostname when it is set, otherwise the requester,
		 * otherwise the row id.
		 */
		public string display_name {
			owned get {
				if (this.hostname != "") {
					return this.hostname;
				}
				if (this.requester != "") {
					return this.requester;
				}
				return this.id.to_string();
			}
		}

		/**
		 * ''Controller'' or ''Agent''.
		 */
		public string display_kind {
			owned get {
				if (this.is_controller) {
					return "Controller";
				}
				return "Agent";
			}
		}

		/**
		 * ''✔️'' when {@link status} is 1. Empty while the row
		 * is still pending.
		 */
		public string display_registered {
			owned get {
				if (this.status == 1) {
					return "✔️";
				}
				return "";
			}
		}

		/**
		 * Local time of {@link created} when that day is today.
		 * The date otherwise. Empty when unset.
		 */
		public string display_created {
			owned get {
				if (this.created < 1) {
					return "";
				}
				var when = new GLib.DateTime.from_unix_local(this.created);
				if (when == null) {
					return "";
				}
				var now = new GLib.DateTime.now_local();
				var text = when.format("%Y-%m-%d");
				if (when.get_year() == now.get_year() &&
					when.get_day_of_year() == now.get_day_of_year()) {
					text = when.format("%H:%M");
				}
				if (text == null) {
					return "";
				}
				return text;
			}
		}

		/**
		 * ''✔️'' while {@link connected} is true. ''❌'' otherwise.
		 */
		public string display_connected {
			owned get {
				if (this.connected) {
					return "✔️";
				}
				return "❌";
			}
		}

		/**
		 * Local time of {@link last_connected} when that day is today.
		 * The date otherwise. Empty when unset.
		 */
		public string display_last {
			owned get {
				if (this.last_connected < 1) {
					return "";
				}
				var when = new GLib.DateTime.from_unix_local(this.last_connected);
				if (when == null) {
					return "";
				}
				var now = new GLib.DateTime.now_local();
				var text = when.format("%Y-%m-%d");
				if (when.get_year() == now.get_year() &&
					when.get_day_of_year() == now.get_day_of_year()) {
					text = when.format("%H:%M");
				}
				if (text == null) {
					return "";
				}
				return text;
			}
		}

		/**
		 * Grid labels are derived. They are not stored or sent.
		 */
		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop) throws GLib.Error
		{
			if (prop.name.has_prefix("display-")) {
				return;
			}
			this.bin_default_write_prop(ctx, prop);
		}

		/**
		 * Register the wire name ''Argus.Agent''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Agent", typeof(Agent));
		}

		/**
		 * Rows in ''agent''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<Agent> query(SQ.Database db)
		{
			return new SQ.Query<Agent>(db, "agent");
		}

		/**
		 * Validate that an RPC request came from a controller.
		 *
		 * The Unix socket has no certificate and is the local controller.
		 * A TLS caller must have an active controller row for its certificate.
		 * An invalid caller receives the error response here.
		 *
		 * @param request inbound RPC request
		 * @return true when the caller is a controller
		 */
		public static bool is_a_controller(OLLMrpc.Request request)
		{
			if (request.connection.cert_fingerprint == "") {
				return true;
			}
			var rows = new Gee.ArrayList<Agent>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", request.connection.cert_fingerprint);
			Agent.query(Agent.db).selectWhere(
				"WHERE fingerprint = $fingerprint AND status = 1 AND is_controller = 1",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				return true;
			}
			request.reply(new OLLMrpc.Response() {
				error = new OLLMrpc.Error.INVALID_REQUEST("controller only")
			});
			return false;
		}

		/**
		 * Create ''agent'', migrating the old ''client_cert'' table.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Agent.db = db;
			string errmsg;
			db.db.exec("ALTER TABLE client_cert RENAME TO agent;", null, out errmsg);
			var ddl = """
				CREATE TABLE IF NOT EXISTS agent (
					id            INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					fingerprint   TEXT NOT NULL UNIQUE,
					status        INTEGER NOT NULL DEFAULT 0,
					ip            TEXT NOT NULL DEFAULT '',
					created       INT64 NOT NULL DEFAULT 0,
					requester     TEXT NOT NULL DEFAULT '',
					username      TEXT NOT NULL DEFAULT '',
					hostname      TEXT NOT NULL DEFAULT '',
					is_controller INTEGER NOT NULL DEFAULT 0,
					last_connected INT64 NOT NULL DEFAULT 0,
					added_dt       INTEGER NOT NULL DEFAULT 0,
					updated_dt     INTEGER NOT NULL DEFAULT 0,
					deleted_dt     INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("Failed to create agent table: %s", db.db.errmsg());
			}
			db.db.exec(
				"""
				ALTER TABLE agent ADD COLUMN
					is_controller INTEGER NOT NULL DEFAULT 0;
				""",
				null,
				out errmsg
			);
			db.db.exec(
				"""
				ALTER TABLE agent ADD COLUMN
					username TEXT NOT NULL DEFAULT '';
				""",
				null,
				out errmsg
			);
			db.db.exec(
				"""
				ALTER TABLE agent ADD COLUMN
					hostname TEXT NOT NULL DEFAULT '';
				""",
				null,
				out errmsg
			);
			db.db.exec(
				"""
				ALTER TABLE agent ADD COLUMN
					last_connected INT64 NOT NULL DEFAULT 0;
				""",
				null,
				out errmsg
			);
			db.db.exec(
				"ALTER TABLE agent ADD COLUMN added_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE agent ADD COLUMN updated_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE agent ADD COLUMN deleted_dt INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
			var q = Agent.query(db);
			var now = new GLib.DateTime.now_utc().to_unix();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("before", (int) (now - (24 * 60 * 60)));
			int_binds.set("status", 0);
			q.deleteWhere(
				"WHERE status = $status AND created < $before",
				int_binds,
				null
			);
		}
	}
}
