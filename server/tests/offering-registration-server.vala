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
 * Boots the test {@link Application} stub for ''offering-registration''.
 */
namespace Argus.Server
{
	public class OfferingRegistrationTestServer : GLib.Object
	{
		public Application app { get; private set; }

		public string data_dir { get; private set; default = ""; }

		public string unix_socket_path {
			get {
				return this.app != null ? this.app.listen.socket_path : "";
			}
		}

		public bool start(
			string data_dir,
			string app_endpoint,
			string register_endpoint
		)
		{
			this.data_dir = data_dir;
			Application.opt_data_dir = data_dir;
			OLLMrpc.rpc_register();
			Argus.Shared.Agent.rpc_register();
			Daemon.rpc_register();
			Offering.rpc_register();
			this.app = new Application();
			this.app.socket = app_endpoint;
			this.app.registration = register_endpoint;
			this.app.init_data_dir(data_dir);
			if (!this.ensure_tls()) {
				return false;
			}
			Argus.Shared.Agent.init_db(this.app.db);
			Argus.Shared.AgentPending.init_db(this.app.db);
			this.app.offering = new Offering.Network(this.app);
			this.app.offering.endpoint = register_endpoint;
			Offering.register(this.app);
			OLLMrpc.Request.register("RPC-Daemon", new Daemon());
			if (!this.app.ssl_listen.listen()) {
				return false;
			}
			return this.app.listen.start();
		}

		public void stop()
		{
			if (this.app == null) {
				return;
			}
			if (this.app.offering != null) {
				this.app.offering.pair_publish.stop();
				this.app.offering.listen.stop();
			}
			this.app.listen.stop();
			this.app.ssl_listen.stop();
			this.app.download_listen.stop();
			this.app = null;
		}

		private bool ensure_tls()
		{
			var tls_dir = GLib.Path.build_filename(this.data_dir, "tls");
			if (!GLib.FileUtils.test(tls_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(tls_dir, 0700);
			}
			var ca_pem = GLib.Path.build_filename(tls_dir, "server-ca.pem");
			var ca_key = GLib.Path.build_filename(tls_dir, "server-ca-key.pem");
			var ca = new OLLMrpc.Transport.Cert() {
				dir = tls_dir,
				cert_pem = "server-ca.pem",
				key_pem = "server-ca-key.pem",
				trust_pem = "server-ca.pem",
				cn = "Argus RM Server CA",
				certificate_authority = true
			};
			ca.ensure();
			GLib.FileUtils.chmod(ca_key, 0600);
			this.app.tls.dir = tls_dir;
			this.app.tls.ca_pem_path = ca_pem;
			this.app.tls.ca_key_path = ca_key;
			this.app.tls.server_san = true;
			this.app.tls.cn = "argus";
			this.app.tls.ensure();
			return this.app.tls.trust != null && this.app.tls.certificate != null;
		}
	}
}