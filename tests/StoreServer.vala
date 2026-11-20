/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Test
{
	/**
	 * File-backed {@link Argus.Shared.SQT.Server} for enrollment tests.
	 */
	public class StoreServer : Argus.Shared.SQT.Server
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
			var path = GLib.Path.build_filename(this.store_dir, "certs.json");
			GLib.FileUtils.set_contents(path, secret);
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
}