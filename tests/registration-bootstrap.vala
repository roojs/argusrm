/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * Controller Bootstrap path after pkexec JSON: parse, save, list.
 */
class RegistrationBootstrapTest
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

	static int main()
	{
		var failure_json = Json.gobject_to_data(new Argus.Shared.SQT.Server() {
			error = "root is required"
		}, null);
		Argus.Shared.SQT.Server? failure = null;
		try {
			failure = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), failure_json)
				as Argus.Shared.SQT.Server;
		} catch (GLib.Error e) {
			note(false, "pkexec failure JSON parses");
			return 1;
		}
		note(failure != null && failure.error == "root is required", "pkexec failure JSON");
		note(!bootstrap_ready(failure), "Bootstrap rejects pkexec failure row");

		var root = "";
		try {
			root = GLib.DirUtils.make_tmp("argus-reg-bootstrap-XXXXXX");
		} catch (GLib.Error e) {
			GLib.printerr("fail temp dir: %s\n", e.message);
			return 1;
		}
		var db_path = GLib.Path.build_filename(root, "server.sqlite");
		var store_dir = GLib.Path.build_filename(root, "certs");
		var db = new SQ.Database(db_path, true);
		Argus.Shared.SQT.Server.init_db(db);

		var probe_addrs = string.joinv("\n", OLLMrpc.Transport.TcpListen.ifaces());
		if (probe_addrs == "") {
			probe_addrs = "192.0.2.1";
		}
		var issued = new Argus.Shared.SQT.Server() {
			name = "bootstrap-test",
			port = Argus.SOCKET_PORT,
			addresses = probe_addrs,
			pem_private_key = "-----BEGIN PRIVATE KEY-----\nenroll\n-----END PRIVATE KEY-----\n",
			pem_client_certificate = "-----BEGIN CERTIFICATE-----\nenroll\n-----END CERTIFICATE-----\n",
			pem_ca_certificate = "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----\n"
		};
		var wire = Json.gobject_to_data(issued, null);
		Argus.Shared.SQT.Server? data = null;
		try {
			data = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), wire)
				as Argus.Shared.SQT.Server;
		} catch (GLib.Error e) {
			note(false, "success JSON parses");
			return 1;
		}
		note(data != null && bootstrap_ready(data), "Bootstrap ready with server addresses");
#if LINUX
		var hosts = data.address_list();
		note(hosts.size > 0, "address_list has probe targets");
		note(hosts.size > 0 && hosts.get(0) != "", "first probe host");
#else
		note(data.addresses != "", "addresses set for probe");
#endif

		var reg = new Argus.Shared.Register() {
			client_db = db,
			server_row = data
		};
		var row = new Argus.Test.StoreServer() {
			name = data.name,
			store_dir = store_dir
		};
		note(reg.save(row), "finish_registration save");
		note(row.has_certificate, "saved row keeps PEM");
		var cred_path = GLib.Path.build_filename(store_dir, "certs.json");
		note(GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS), "credential file written");

		var listed = new Gee.ArrayList<Argus.Shared.SQT.Server>();
		var int_binds = new Gee.HashMap<string, int>();
		var text_binds = new Gee.HashMap<string, string>();
		try {
			Argus.Shared.SQT.Server.query(db).selectWhere(
				"WHERE deleted_dt = 0", int_binds, text_binds, listed);
			note(true, "startup store list query");
		} catch (GLib.Error e) {
			note(false, "startup store list query (" + e.message + ")");
		}
		note(listed.size == 1, "one saved server after local login");
		return failures == 0 ? 0 : 1;
	}
}