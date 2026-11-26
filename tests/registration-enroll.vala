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
	static int main()
	{
		var root = "";
		try {
			root = GLib.DirUtils.make_tmp("argus-reg-enroll-XXXXXX");
		} catch (GLib.Error e) {
			GLib.printerr("temp dir: %s\n", e.message);
			return 1;
		}
		var db_path = GLib.Path.build_filename(root, "server.sqlite");
		var store_dir = GLib.Path.build_filename(root, "certs");
		var db = new SQ.Database(db_path, true);
		Argus.Shared.SQT.Server.init_db(db);
		db.backupDB();
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
		if (!reg.save(row)) {
			GLib.printerr("Register.save failed\n");
			return 1;
		}
		var reload = new SQ.Database(db_path, true);
		Argus.Shared.SQT.Server.init_db(reload);
		var on_disk = new Gee.ArrayList<Argus.Shared.SQT.Server>();
		var disk_int = new Gee.HashMap<string, int>();
		var disk_text = new Gee.HashMap<string, string>();
		Argus.Shared.SQT.Server.query(reload).selectWhere(
			"WHERE deleted_dt = 0", disk_int, disk_text, on_disk);
		if (on_disk.size != 1) {
			GLib.printerr(
				"expected one server row on disk after backupDB, got %u\n",
				on_disk.size);
			return 1;
		}
		if (on_disk.get(0).port != reply.port ||
				on_disk.get(0).addresses != reply.addresses) {
			GLib.printerr("reloaded row does not match registration reply\n");
			return 1;
		}
		var cred_path = GLib.Path.build_filename(store_dir, "certs.json");
		if (!GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS)) {
			GLib.printerr("credential file was not written\n");
			return 1;
		}
		if (row.pem_private_key != reply.pem_private_key) {
			GLib.printerr("PEM not kept on row after save\n");
			return 1;
		}
		return 0;
	}
}