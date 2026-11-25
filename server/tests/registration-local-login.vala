/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * End-to-end local login: temp server, real ''argusrm-server
 * --give-me-a-certificate controller'', JSON like Bootstrap, TLS hello.
 *
 * Run as root: ''sudo meson test -C build registration-local-login --print-errorlogs''
 */
namespace Argus.Server
{
	class RegistrationLocalLoginTest
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

		static bool bootstrap_ready(Argus.Shared.SQT.Server data)
		{
			if (data.error != "") {
				return false;
			}
			if (data.name == "" || data.port < 1 || data.addresses == "") {
				return false;
			}
			return data.has_certificate;
		}

		static async int run(string server_exe) throws GLib.Error
		{
			if (Posix.geteuid() != 0) {
				GLib.printerr("fail registration-local-login requires root\n");
				return 1;
			}
			var username = GLib.Environment.get_user_name();
			if (server_exe == "" ||
				!GLib.FileUtils.test(server_exe, GLib.FileTest.IS_EXECUTABLE)) {
				GLib.printerr("fail missing argusrm-server at %s\n", server_exe);
				return 1;
			}
			var data_dir = "";
			try {
				data_dir = GLib.DirUtils.make_tmp("argus-local-login-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temp data dir: %s\n", e.message);
				return 1;
			}
			Application.opt_data_dir = data_dir;
			Application.opt_test_minimal = true;
			GLib.print("step: server init\n");
			OLLMrpc.rpc_register();
			Argus.Shared.Agent.rpc_register();
			Argus.Shared.SQT.Server.rpc_register();
			Daemon.rpc_register();
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
			GLib.print("step: unix socket listening\n");
			var sock = GLib.Path.build_filename(data_dir, "argus.sock");
			var text_binds = new Gee.HashMap<string, string>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("is_controller", 1);
			text_binds.set("username", username);
			Argus.Shared.Agent.query(app.db).deleteWhere(
				"WHERE is_controller = $is_controller AND username = $username",
				int_binds, text_binds);

			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
			launcher.unsetenv("DISPLAY");
			launcher.unsetenv("WAYLAND_DISPLAY");
			GLib.print("step: server --give-me-a-certificate controller\n");
			GLib.Subprocess proc;
			try {
				proc = launcher.spawnv({
					server_exe,
					"--data-dir", data_dir,
					"--give-me-a-certificate", "controller"
				});
			} catch (GLib.Error e) {
				GLib.printerr("fail spawn server client: %s\n", e.message);
				return 1;
			}
			string? stdout_text = null;
			string? stderr_text = null;
			try {
				yield proc.communicate_utf8_async(null, null,
					out stdout_text, out stderr_text);
			} catch (GLib.Error e) {
				GLib.printerr("fail controller communicate: %s\n", e.message);
				return 1;
			}
			var output = stdout_text != null ? stdout_text.strip() : "";
			var err_out = stderr_text != null ? stderr_text.strip() : "";
			note(proc.get_if_exited(), "client exits cleanly");
			note(proc.get_successful(), "client exit 0");
			note(output != "", "client stdout JSON");
			if (err_out != "") {
				GLib.printerr("client stderr: %s\n", err_out);
			}
			if (!proc.get_successful() || output == "") {
				GLib.printerr("fail client before TLS (see stderr above)\n");
				return 1;
			}
			GLib.print("step: TLS listen and probe\n");
			Argus.Shared.SQT.Server? data = null;
			try {
				data = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), output)
					as Argus.Shared.SQT.Server;
			} catch (GLib.Error e) {
				GLib.printerr("fail JSON parse: %s\n", e.message);
				return 1;
			}
			note(data != null, "JSON deserializes");
			if (data == null) {
				return 1;
			}
			note(data.error == "", "no error field on success");
			note(data.addresses != "", "certificate lists management addresses");
			note(bootstrap_ready(data) && data.addresses != "",
				"Bootstrap would accept row");
			note(data.pem_client_certificate.contains("BEGIN CERTIFICATE"),
				"real client certificate PEM");
			note(data.pem_private_key.contains("BEGIN"), "real private key PEM");
			var hosts = data.address_list();
			note(hosts.size > 0, "probe address list");

			var port = (uint16) data.port;
			note(app.ssl_listen.listen(), "management TLS port");
			var probe = new GLib.SocketClient();
			probe.set_timeout(5);
			try {
				var tcp = probe.connect_to_host(hosts.get(0), port, null);
				tcp.close();
				note(true, "Bootstrap TCP probe");
			} catch (GLib.Error e) {
				note(false, "Bootstrap TCP probe (" + e.message + ")");
			}

			GLib.TlsCertificate identity;
			try {
				identity = data.tls_certificate();
			} catch (GLib.Error e) {
				note(false, "client TLS identity (" + e.message + ")");
				return failures == 0 ? 0 : 1;
			}
			var ca_path = GLib.Path.build_filename(data_dir, "probe-ca.pem");
			GLib.FileUtils.set_contents(ca_path, data.pem_ca_certificate);
			var trust = GLib.TlsFileDatabase.@new(ca_path);
			var dial_host = hosts.get(0);
			var colon = dial_host.last_index_of(":");
			if (colon > 0) {
				dial_host = dial_host.substring(0, colon);
			}
			var endpoint = "tcp://" + dial_host + ":" + data.port.to_string();
			var mgr = new OLLMrpc.Client("", "", endpoint) {
				live_handles = true,
				call_timeout_seconds = 5,
				force_localhost_tls = true
			};
			mgr.configure_tls.connect((tls) => {
				tls.certificate = identity;
				tls.database = trust;
			});
			var tls_loop = new GLib.MainLoop();
			var tls_ok = false;
			mgr.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "argus-controller", Argus.VERSION)
			}, null, (obj, res) => {
				tls_ok = mgr.connect.end(res);
				if (!tls_ok && mgr.connect_error != "") {
					GLib.printerr("TLS connect: %s\n", mgr.connect_error);
				}
				tls_loop.quit();
			});
			tls_loop.run();
			note(tls_ok, "management TLS hello (Bootstrap.use path)");
			mgr.disconnect();

			GLib.print("step: deregister cleanup\n");
			var client = new OLLMrpc.Client("", "", sock) {
				live_handles = true,
				call_timeout_seconds = 5
			};
			var loop = new GLib.MainLoop();
			var connected = false;
			client.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "reg-cleanup", Argus.VERSION)
			}, null, (obj, res) => {
				connected = client.connect.end(res);
				loop.quit();
			});
			loop.run();
			if (connected) {
				var cleared = yield client.call(new OLLMrpc.Request() {
					method = "Registration.deregister",
					args = OLLMrpc.args("s", username)
				});
				note(cleared.error == null, "deregister cleanup");
			}
			return failures == 0 ? 0 : 1;
		}

		static int main(string[] args)
		{
			var server_exe = args.length > 1 ? args[1] : "";
			int code = 0;
			var loop = new GLib.MainLoop();
			run.begin(server_exe, (obj, res) => {
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