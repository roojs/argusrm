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
	 * create this table. The controller opens
	 * ''server.sqlite'' on {@link Argus.Controller.Application}
	 * construction and calls {@link init_db}.
	 *
	 * Non-secret columns are stored in SQLite. Certificate PEM strings
	 * are {@link pem_private_key}, {@link pem_client_certificate}, and
	 * {@link pem_ca_certificate} on the row object only. Subclasses
	 * implement {@link load_certificates} and {@link store_certificates}.
	 * {@link save} and {@link remove} handle SQLite; {@link clear_registration}
	 * clears platform storage.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQT.Server.init_db(db);
	 * var rows = new Gee.ArrayList<Argus.Shared.SQT.Server>();
	 * Argus.Shared.SQT.Server.query(db).select("", rows);
	 * }}}
	 */
	public class Server : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable, Json.Serializable
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
		 * Unix time this row was inserted.
		 */
		public int added_dt { get; set; default = 0; }
		/**
		 * Unix time this row was last updated.
		 */
		public int updated_dt { get; set; default = 0; }
		/**
		 * Unix time this row was soft-deleted, or ''0'' when active.
		 */
		public int deleted_dt { get; set; default = 0; }
		/**
		 * Failure text on local registration JSON / RPC only; not a SQLite column.
		 */
		public string error { get; set; default = ""; }

		/**
		 * Client private key PEM. Not a SQLite column.
		 */
		public string pem_private_key { get; set; default = ""; }
		/**
		 * Signed client certificate PEM. Not a SQLite column.
		 */
		public string pem_client_certificate { get; set; default = ""; }
		/**
		 * Management CA PEM. Not a SQLite column.
		 */
		public string pem_ca_certificate { get; set; default = ""; }

		private Gee.ArrayList<string>? address_list_hosts;

		/**
		 * Hosts from {@link addresses}, parsed once after the row is loaded.
		 */
		public Gee.ArrayList<string> address_list()
		{
			if (this.address_list_hosts == null) {
				this.address_list_hosts = new Gee.ArrayList<string>();
				if (this.addresses != "") {
					foreach (var line in this.addresses.split("\n")) {
						var text = line.strip();
						if (text == "") {
							continue;
						}
						var host = text;
						var mark = text.last_index_of(":");
						if (mark > 0) {
							host = text.substring(0, mark);
						}
						if (!Argus.Shared.Net.Route.can_route_to(host)) {
							continue;
						}
						this.address_list_hosts.add(text);
					}
				}
			}
			return this.address_list_hosts;
		}

		/**
		 * True when all three {@link pem_*} properties are non-empty.
		 */
		public bool has_certificate {
			get {
				return this.pem_private_key != ""
					&& this.pem_client_certificate != ""
					&& this.pem_ca_certificate != "";
			}
		}

		/**
		 * List row title: {@link name}, else the first {@link address_list}
		 * host, else ''Server''.
		 */
		public string title {
			get {
				if (this.name != "") {
					return this.name;
				}
				var hosts = this.address_list();
				if (hosts.size > 0) {
					return @"$(hosts.get(0))";
				}
				return "Server";
			}
		}

		/**
		 * Comma-separated {@link address_list} for a list subtitle, or
		 * empty when there are no hosts.
		 */
		public string addresses_subtitle {
			get {
				var hosts = this.address_list();
				if (hosts.size == 0) {
					return "";
				}
				return @"$(string.joinv(", ", hosts.to_array()))";
			}
		}

		/**
		 * Client identity for {@link OLLMrpc.Transport.TlsClient}.
		 *
		 * @return client certificate and private key for TLS
		 * @throws GLib.Error PEM material is missing or invalid
		 */
		public GLib.TlsCertificate tls_certificate() throws GLib.Error
		{
			if (!this.has_certificate) {
				throw new GLib.IOError.FAILED("no certificate for this server row");
			}
			var pem = this.pem_client_certificate + "\n" + this.pem_private_key;
			return new GLib.TlsCertificate.from_pem(pem, pem.length);
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
					download_path   TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("server create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "server");
		}

		/**
		 * Host and port for connection try ''index''.
		 *
		 * @param index position in {@link address_list}
		 * @return TCP endpoint before TLS
		 * @throws GLib.Error index or port is invalid
		 */
		public GLib.InetSocketAddress socket(int index) throws GLib.Error
		{
			var hosts = this.address_list();
			if (index < 0 || index >= hosts.size) {
				throw new GLib.IOError.FAILED("address index out of range");
			}
			if (this.port < 1 || this.port > 65535) {
				throw new GLib.IOError.FAILED("port is not set");
			}
			var where = new GLib.InetSocketAddress.from_string(
				hosts[index], (uint16) this.port);
			if (where == null) {
				throw new GLib.IOError.FAILED("address is invalid");
			}
			return where;
		}

		/**
		 * Write {@link pem_*} to platform storage, then upsert this row in ''db''.
		 */
		public void save(SQ.Database db) throws GLib.Error
		{
			if (this.name == "") {
				throw new GLib.IOError.FAILED("server name is empty");
			}
			if (!this.has_certificate) {
				throw new GLib.IOError.FAILED("certificate material is incomplete");
			}
			this.store_certificates();
			var now = (int) (GLib.get_real_time() / 1000000);
			var q = Server.query(db);
			if (this.id > 0) {
				this.updated_dt = now;
				q.updateById(this);
				return;
			}
			var existing = new Gee.ArrayList<Server>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("name", this.name);
			q.selectWhere(
				"WHERE name = $name AND deleted_dt = 0", null, text_binds, existing);
			if (existing.size > 0) {
				this.id = existing.get(0).id;
				this.added_dt = existing.get(0).added_dt;
				this.updated_dt = now;
				q.updateById(this);
				return;
			}
			this.added_dt = now;
			this.updated_dt = now;
			this.deleted_dt = 0;
			this.id = q.insert(this);
		}

		/**
		 * Clear platform credentials and soft-delete this row in ''db''.
		 */
		public void remove(SQ.Database db) throws GLib.Error
		{
			this.clear_registration();
			if (this.id < 1) {
				return;
			}
			var now = (int) (GLib.get_real_time() / 1000000);
			this.deleted_dt = now;
			this.updated_dt = now;
			Server.query(db).updateById(this);
		}

		/**
		 * Read platform storage into {@link pem_*}.
		 *
		 * @throws GLib.Error storage could not be read
		 */
		public virtual void load_certificates() throws GLib.Error
		{
		}

		/**
		 * Write {@link pem_*} to platform storage.
		 *
		 * @throws GLib.Error storage could not be written
		 */
		public virtual void store_certificates() throws GLib.Error
		{
			throw new GLib.IOError.FAILED("store_certificates is not implemented");
		}

		/**
		 * Drop stored certificates for this row.
		 *
		 * @throws GLib.Error storage could not be cleared
		 */
		public virtual void clear_registration() throws GLib.Error
		{
			this.pem_private_key = "";
			this.pem_client_certificate = "";
			this.pem_ca_certificate = "";
		}

		/**
		 * Register the saved-server row type with the ''OLLMrpc'' bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Shared.SQT.Server", typeof(Server));
		}
	}
}