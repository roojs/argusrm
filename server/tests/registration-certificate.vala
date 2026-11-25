/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Server
{
	class FileStoreServer : Argus.Shared.SQT.Server
	{
		public string store_dir { get; set; default = ""; }

		public override void store_certificates() throws GLib.Error
		{
			if (this.store_dir == "") {
				throw new GLib.IOError.FAILED("store_dir is not set");
			}
			if (GLib.DirUtils.create_with_parents(this.store_dir, 0700) != 0) {
				throw new GLib.IOError.FAILED("Could not create store directory");
			}
			var secret = Json.gobject_to_data(this, null);
			GLib.FileUtils.set_contents(
				GLib.Path.build_filename(this.store_dir, "certs.json"), secret);
		}

		public override void load_certificates() throws GLib.Error
		{
			var path = GLib.Path.build_filename(this.store_dir, "certs.json");
			if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				return;
			}
			var secret = "";
			GLib.FileUtils.get_contents(path, out secret);
			var stored = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), secret)
				as Argus.Shared.SQT.Server;
			if (stored == null || !stored.has_certificate) {
				throw new GLib.IOError.FAILED("credential JSON could not be read");
			}
			this.pem_private_key = stored.pem_private_key;
			this.pem_client_certificate = stored.pem_client_certificate;
			this.pem_ca_certificate = stored.pem_ca_certificate;
		}
	}

	/**
	 * Issue and revoke a local controller certificate over the Unix socket.
	 *
	 * Requires root (same as production) and {@link Application.opt_data_dir}
	 * for an isolated server data tree.
	 */
	class RegistrationCertificateTest
	{
		static int failures = 0;

		static void note(bool ok, string message)
		{
			if (ok) {
				GLib.print("ok %s\n", message);
				return;
			}
			failures++;
			GLib.printerr("fail %s\n", message);
		}

		static bool ensure_tls(Application app, string data_dir)
		{
			var tls_dir = GLib.Path.build_filename(data_dir, "tls");
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
			app.tls.dir = tls_dir;
			app.tls.ca_pem_path = ca_pem;
			app.tls.ca_key_path = ca_key;
			app.tls.server_san = true;
			app.tls.cn = "argus";
			app.tls.ensure();
			return app.tls.trust != null && app.tls.certificate != null;
		}

		static async int run() throws GLib.Error
		{
			if (Posix.geteuid() != 0) {
				GLib.printerr(
					"fail registration-certificate requires root (see registration-local-login)\n");
				return 1;
			}
			var data_dir = "";
			try {
				data_dir = GLib.DirUtils.make_tmp("argus-reg-cert-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temp data dir: %s\n", e.message);
				return 1;
			}
			Application.opt_data_dir = data_dir;
			Application.opt_test_minimal = true;
			OLLMrpc.rpc_register();
			Argus.Shared.Agent.rpc_register();
			Argus.Shared.SQT.Server.rpc_register();
			var app = new Application();
			if (!ensure_tls(app, data_dir)) {
				GLib.printerr("fail TLS material\n");
				return 1;
			}
			var port_probe = new GLib.SocketListener();
			GLib.SocketAddress? port_bind = null;
			try {
				port_probe.add_address(
					new GLib.InetSocketAddress(
						new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0),
					GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out port_bind);
			} catch (GLib.Error e) {
				GLib.printerr("fail ephemeral port: %s\n", e.message);
				return 1;
			}
			var test_port = ((GLib.InetSocketAddress) port_bind).get_port();
			port_probe.close();
			app.socket = "0.0.0.0:" + test_port.to_string();
			Argus.Shared.Agent.init_db(app.db);
			Registration.rpc_register();
			Daemon.rpc_register();
			OLLMrpc.Request.register("Registration", new Registration(app));
			OLLMrpc.Request.register("RPC-Daemon", new Daemon());
			app.firewall = new Net.NFTables(test_port);
			app.firewall.apply(SQT.Agent.allowlist(app.db, app.interfaces));
			app.firewall.enable();
			if (!app.ssl_listen.listen()) {
				GLib.printerr("fail TLS listen on %s\n", app.socket);
				return 1;
			}
			if (!app.listen.start()) {
				GLib.printerr("fail Unix listener\n");
				return 1;
			}
			var sock = GLib.Path.build_filename(data_dir, "argus.sock");
			var client = new OLLMrpc.Client("", "",
				sock) {
				live_handles = true,
				call_timeout_seconds = 5
			};
			client.debug = false;
			var loop = new GLib.MainLoop();
			var hello_ok = false;
			client.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "reg-cert-test", Argus.VERSION)
			}, null, (obj, res) => {
				hello_ok = client.connect.end(res);
				loop.quit();
			});
			loop.run();
			if (!hello_ok) {
				GLib.printerr("fail RPC hello: %s\n", client.connect_error);
				return 1;
			}
			var username = GLib.Environment.get_user_name();
			if (username == "") {
				username = "regtest";
			}
			var response = yield client.call(new OLLMrpc.Request() {
				method = "Registration.certificate",
				args = OLLMrpc.args("s", username)
			});
			if (response == null || response.error != null) {
				var text = response != null && response.error != null ?
					response.error.message : "no response";
				GLib.printerr("fail certificate error: %s\n", text);
				return 1;
			}
			var row = response.retval as Argus.Shared.SQT.Server;
			note(row != null, "retval is SQT.Server");
			note(row != null && row.name != "", "certificate name");
			note(row != null && row.port > 0, "certificate port");
			note(row != null && row.addresses != "", "certificate addresses");
			note(row != null && row.addresses.index_of("127.0.0.1") >= 0,
				"certificate lists loopback for TLS local login");
			note(row != null && row.has_certificate, "certificate PEM material");
			note(row != null && row.error == "", "success has empty error");
			if (row == null) {
				return failures == 0 ? 0 : 1;
			}
			{
				var json = Json.gobject_to_data(row, null);
				note(json.contains("pem_client_certificate"), "wire JSON pem_client_certificate");
				Argus.Shared.SQT.Server? bootstrap = null;
				try {
					bootstrap = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), json)
						as Argus.Shared.SQT.Server;
				} catch (GLib.Error e) {
					note(false, "Bootstrap JSON parse");
				}
				if (bootstrap != null) {
					note(bootstrap.addresses != "", "Bootstrap row has addresses");
					note(bootstrap.has_certificate, "Bootstrap ready row");
					var hosts = bootstrap.address_list();
					note(hosts.size > 0, "Bootstrap address_list");
					var client_dir = GLib.Path.build_filename(data_dir, "client");
					var cred_dir = GLib.Path.build_filename(client_dir, "certs");
					var client_db = new SQ.Database(
						GLib.Path.build_filename(client_dir, "server.sqlite"), true);
					Argus.Shared.SQT.Server.init_db(client_db);
					var reg = new Argus.Shared.Register() {
						client_db = client_db,
						server_row = bootstrap
					};
					var stored = new FileStoreServer() {
						name = bootstrap.name,
						store_dir = cred_dir
					};
					note(reg.save(stored), "Bootstrap finish_registration save");
					stored.load_certificates();
					note(stored.has_certificate, "saved credentials reload");
					var list = new Gee.ArrayList<Argus.Shared.SQT.Server>();
					var empty_int = new Gee.HashMap<string, int>();
					var empty_text = new Gee.HashMap<string, string>();
					Argus.Shared.SQT.Server.query(client_db).selectWhere(
						"WHERE deleted_dt = 0", empty_int, empty_text, list);
					note(list.size == 1, "client store list after save");
				}
			}
			var port = (uint16) row.port;
			note(app.ssl_listen.listen(), "management TLS port");
			var probe_hosts = row.address_list();
			note(probe_hosts.size > 0, "probe host list before TCP");
			var probe_ok = false;
			if (probe_hosts.size > 0) {
				var probe = new GLib.SocketClient();
				probe.set_timeout(5);
				try {
					var conn = probe.connect_to_host(
						probe_hosts.get(0), port, null);
					conn.close();
					probe_ok = true;
				} catch (GLib.Error e) {
					GLib.warning("probe: %s", e.message);
				}
			}
			note(probe_ok, "Bootstrap TCP probe reaches TLS port");
			var pending = new Gee.ArrayList<Argus.Shared.Agent>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds.set("status", 0);
			int_binds.set("is_controller", 1);
			text_binds.set("username", username);
			text_binds.set("hostname", GLib.Environment.get_host_name());
			try {
				Argus.Shared.Agent.query(app.db).selectWhere(
					"WHERE status = $status AND is_controller = $is_controller " +
						"AND username = $username AND hostname = $hostname",
					int_binds, text_binds, pending);
			} catch (GLib.Error e) {
				GLib.printerr("fail pending row query: %s\n", e.message);
				return 1;
			}
			note(pending.size == 1, "pending controller row stored");
			var activated = pending.get(0);
			activated.status = 1;
			activated.ip = "192.168.0.16";
			try {
				Argus.Shared.Agent.query(app.db).updateById(activated);
			} catch (GLib.Error e) {
				note(false, "simulate active controller with routable ip");
				return failures == 0 ? 0 : 1;
			}
			var blocked = yield client.call(new OLLMrpc.Request() {
				method = "Registration.certificate",
				args = OLLMrpc.args("s", username)
			});
			note(blocked.error != null &&
				blocked.error.message == "This machine is already registered.",
				"active row blocks second certificate");
			var cleared = yield client.call(new OLLMrpc.Request() {
				method = "Registration.deregister",
				args = OLLMrpc.args("s", username)
			});
			note(cleared.error == null, "deregister succeeds");
			var reissued = yield client.call(new OLLMrpc.Request() {
				method = "Registration.certificate",
				args = OLLMrpc.args("s", username)
			});
			note(reissued.error == null &&
				(reissued.retval as Argus.Shared.SQT.Server) != null,
				"username deregister clears routable-ip row");
			return failures == 0 ? 0 : 1;
		}

		static int main()
		{
			int code = 0;
			var loop = new GLib.MainLoop();
			run.begin((obj, res) => {
				try {
					code = run.end(res);
				} catch (GLib.Error e) {
					GLib.printerr("fail: %s\n", e.message);
					code = 1;
				}
				loop.quit();
			});
			loop.run();
			return code;
		}
	}
}