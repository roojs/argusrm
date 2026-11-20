/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * {@link Argus.Shared.Register.save} after a local registration reply.
 */
class RegistrationEnrollTest
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

	static int main()
	{
		var root = "";
		try {
			root = GLib.DirUtils.make_tmp("argus-reg-enroll-XXXXXX");
		} catch (GLib.Error e) {
			GLib.printerr("fail temp dir: %s\n", e.message);
			return 1;
		}
		var db_path = GLib.Path.build_filename(root, "server.sqlite");
		var store_dir = GLib.Path.build_filename(root, "certs");
		var db = new SQ.Database(db_path, true);
		Argus.Shared.SQT.Server.init_db(db);
		var reply = new Argus.Shared.SQT.Server() {
			name = "enroll-test",
			port = 817,
			addresses = "127.0.0.1",
			pem_private_key = "-----BEGIN PRIVATE KEY-----\nenroll\n-----END PRIVATE KEY-----\n",
			pem_client_certificate = "-----BEGIN CERTIFICATE-----\nenroll\n-----END CERTIFICATE-----\n",
			pem_ca_certificate = "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----\n"
		};
		var reg = new Argus.Shared.Register() {
			client_db = db,
			server_row = reply
		};
		var row = new Argus.Test.StoreServer() {
			name = reply.name,
			store_dir = store_dir
		};
		note(reg.save(row), "Register.save succeeds");
		var loaded = new Gee.ArrayList<Argus.Shared.SQT.Server>();
		var int_binds = new Gee.HashMap<string, int>();
		int_binds.set("deleted_dt", 0);
		var text_binds = new Gee.HashMap<string, string>();
		Argus.Shared.SQT.Server.query(db).selectWhere(
			"WHERE deleted_dt = $deleted_dt", int_binds, text_binds, loaded);
		note(loaded.size == 1, "one server row in SQLite");
		note(loaded.size > 0 && loaded.get(0).port == reply.port, "SQLite port");
		note(loaded.size > 0 && loaded.get(0).addresses == reply.addresses, "SQLite addresses");
		var cred_path = GLib.Path.build_filename(store_dir, "certs.json");
		note(GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS), "credential file written");
		note(row.pem_private_key == reply.pem_private_key, "PEM kept on row after save");
		var active = new Gee.ArrayList<Argus.Shared.SQT.Server>();
		var empty_int = new Gee.HashMap<string, int>();
		var empty_text = new Gee.HashMap<string, string>();
		try {
			Argus.Shared.SQT.Server.query(db).selectWhere(
				"WHERE deleted_dt = 0", empty_int, empty_text, active);
			note(true, "selectWhere with empty bind maps");
		} catch (GLib.Error e) {
			note(false, "selectWhere with empty bind maps (" + e.message + ")");
		}
		note(active.size == 1, "list active rows without bind placeholders");
		return failures == 0 ? 0 : 1;
	}
}