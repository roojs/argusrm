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

namespace Argus.Controller.SQT
{
	/**
	 * Controller management-server row with libsecret or credential-file PEMs.
	 */
	public class Server : Argus.Shared.SQT.Server
	{
#if LINUX
		private static Secret.Schema? credential_schema;
#endif

		/**
		 * Rows in ''server'' on the controller client database.
		 */
		public static SQ.Query<Server> query(SQ.Database db)
		{
			return new SQ.Query<Server>(db, "server");
		}

		/**
		 * Load PEMs for {@link name} from platform storage.
		 */
		public override void load_certificates() throws GLib.Error
		{
			this.pem_private_key = "";
			this.pem_client_certificate = "";
			this.pem_ca_certificate = "";
			if (this.name == "") {
				throw new GLib.IOError.FAILED("server name is empty");
			}
#if LINUX
			if (Server.credential_schema == null) {
				var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(
					GLib.str_hash, GLib.str_equal);
				types.insert("service", Secret.SchemaAttributeType.STRING);
				types.insert("server", Secret.SchemaAttributeType.STRING);
				types.insert("name", Secret.SchemaAttributeType.STRING);
				Server.credential_schema = new Secret.Schema.newv(
					"org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
			}
			var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
			attrs.insert("service", "argusrm");
			attrs.insert("name", this.name);
			var secret = "";
			var found = Secret.password_lookupv_sync(
				Server.credential_schema, attrs, null);
			if (found != null) {
				secret = found;
			}
			if (secret == "") {
				return;
			}
#elif ANDROID
			var cred_path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(), 
				"argusrm", "credentials", this.name + ".json");
				
			if (!GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS)) {
				return;
			}
			var secret = "";
			GLib.FileUtils.get_contents(cred_path, out secret);
#else
			throw new GLib.IOError.FAILED("controller certificates are not supported on this platform");
#endif
#if LINUX || ANDROID
			var stored = Json.gobject_from_data(
				typeof(Argus.Shared.SQT.Server), secret) as Argus.Shared.SQT.Server;
			if (stored == null) {
				throw new GLib.IOError.FAILED("credential JSON could not be read");
			}
			if (!stored.has_certificate) {
				throw new GLib.IOError.FAILED("certificate material is incomplete");
			}
			this.pem_private_key = stored.pem_private_key;
			this.pem_client_certificate = stored.pem_client_certificate;
			this.pem_ca_certificate = stored.pem_ca_certificate;
#endif
		}

		/**
		 * Remove stored PEMs for {@link name}.
		 */
		public override void clear_registration() throws GLib.Error
		{
#if LINUX
			if (this.name != "") {
				if (Server.credential_schema == null) {
					var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(
						GLib.str_hash, GLib.str_equal);
					types.insert("service", Secret.SchemaAttributeType.STRING);
					types.insert("server", Secret.SchemaAttributeType.STRING);
					types.insert("name", Secret.SchemaAttributeType.STRING);
					Server.credential_schema = new Secret.Schema.newv(
						"org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
				}
				var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
				attrs.insert("service", "argusrm");
				attrs.insert("name", this.name);
				Secret.password_clearv_sync(Server.credential_schema, attrs, null);
			}
#elif ANDROID
			if (this.name != "") {
				var cred_path = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(), "argusrm", "credentials",
					this.name + ".json");
				if (GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS)) {
					GLib.FileUtils.remove(cred_path);
				}
			}
#endif
			this.pem_private_key = "";
			this.pem_client_certificate = "";
			this.pem_ca_certificate = "";
		}

		/**
		 * Write {@link pem_*} to libsecret or the credential file.
		 */
		public override void store_certificates() throws GLib.Error
		{
			var json = Json.gobject_to_data(this, null);
#if LINUX
			if (Server.credential_schema == null) {
				var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(
					GLib.str_hash, GLib.str_equal);
				types.insert("service", Secret.SchemaAttributeType.STRING);
				types.insert("server", Secret.SchemaAttributeType.STRING);
				types.insert("name", Secret.SchemaAttributeType.STRING);
				Server.credential_schema = new Secret.Schema.newv(
					"org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
			}
			var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
			attrs.insert("service", "argusrm");
			attrs.insert("name", this.name);
			Secret.password_storev_sync(
				Server.credential_schema,
				attrs,
				Secret.COLLECTION_DEFAULT,
				"certificate for %s".printf(this.name),
				json,
				null);
#elif ANDROID
			var cred_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "credentials");
			if (GLib.DirUtils.create_with_parents(cred_dir, 0700) != 0) {
				throw new GLib.FileError.FAILED("Could not create the credentials directory");
			}
			var cred_path = GLib.Path.build_filename(cred_dir, this.name + ".json");
			GLib.FileUtils.set_contents(cred_path, json);
			GLib.FileUtils.chmod(cred_path, 0600);
#else
			throw new GLib.IOError.FAILED("controller certificates are not supported on this platform");
#endif
		}

		/**
		 * SHA-256 fingerprint of the client certificate (deregister RPC argument).
		 */
		public string fingerprint() throws GLib.Error
		{
			if (this.pem_client_certificate == "") {
				throw new GLib.IOError.FAILED("The saved server has no certificate.");
			}
			GLib.TlsCertificate cert = new GLib.TlsCertificate.from_pem(
				this.pem_client_certificate, this.pem_client_certificate.length);
			return GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, cert.certificate.data);
		}
	}
}