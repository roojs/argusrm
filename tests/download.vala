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

namespace Argus
{
	public string AGENT_DATA_DIR;
	public string SERVER_DATA_DIR;
}

/**
 * Stub {@link Application} for ''argus-download'' so the live
 * {@link Net.Download} compiles without the rest of the server tree.
 */
namespace Argus.Server
{
	public class Application : GLib.Object
	{
		public static string opt_data_dir = "";

		public string download { get; set; default = ""; }

		public OLLMrpc.Transport.Cert tls {
			get; set; default = new OLLMrpc.Transport.Cert();
		}
	}
}

int main(string[] args)
{
	var root = "";
	try {
		root = GLib.DirUtils.make_tmp("argus-download-XXXXXX");
	} catch (GLib.FileError e) {
		GLib.printerr("make_tmp failed: %s\n", e.message);
		return 1;
	}
	var server_dir = GLib.Path.build_filename(root, "server");
	var tls_dir = GLib.Path.build_filename(server_dir, "tls");
	var pkg_dir = GLib.Path.build_filename(server_dir, "packages", "osquery");
	var client_dir = GLib.Path.build_filename(root, "client");
	var untrusted_dir = GLib.Path.build_filename(root, "untrusted");
	GLib.DirUtils.create_with_parents(tls_dir, 0700);
	GLib.DirUtils.create_with_parents(pkg_dir, 0700);
	GLib.DirUtils.create_with_parents(client_dir, 0700);
	GLib.DirUtils.create_with_parents(untrusted_dir, 0700);

	var ca_pem = GLib.Path.build_filename(tls_dir, "server-ca.pem");
	var ca_key = GLib.Path.build_filename(tls_dir, "server-ca-key.pem");
	var ca = new OLLMrpc.Transport.Cert() {
		dir = tls_dir,
		cert_pem = "server-ca.pem",
		key_pem = "server-ca-key.pem",
		trust_pem = "server-ca.pem",
		cn = "Argus RM Test CA",
		certificate_authority = true,
	};
	ca.ensure();

	var app = new Argus.Server.Application();
	app.tls.dir = tls_dir;
	app.tls.ca_pem_path = ca_pem;
	app.tls.ca_key_path = ca_key;
	app.tls.server_san = true;
	app.tls.cn = "argus";
	app.tls.ensure();
	if (app.tls.trust == null || app.tls.certificate == null) {
		GLib.printerr("server TLS setup failed\n");
		return 1;
	}

	var client_cert = new OLLMrpc.Transport.Cert() {
		dir = client_dir,
		cert_pem = "client.pem",
		key_pem = "client-key.pem",
		ca_pem_path = ca_pem,
		ca_key_path = ca_key,
		cn = "argus-agent",
	};
	client_cert.ensure();

	var untrusted_cert = new OLLMrpc.Transport.Cert() {
		dir = untrusted_dir,
		cert_pem = "client.pem",
		key_pem = "client-key.pem",
		cn = "argus-untrusted",
	};
	untrusted_cert.ensure();

	// Pick an unused loopback port.
	uint16 port = 0;
	try {
		var probe = new GLib.Socket(
			GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
		probe.bind(new GLib.InetSocketAddress.from_string("127.0.0.1", 0), true);
		var bound = probe.get_local_address() as GLib.InetSocketAddress;
		port = bound.get_port();
		probe.close();
	} catch (GLib.Error e) {
		GLib.printerr("port probe failed: %s\n", e.message);
		return 1;
	}

	// Build a 512 KiB binary payload containing \0, \r, \n, and \r\n.
	var payload = new uint8[524288];
	payload[0] = '\n';
	payload[1] = '\r';
	payload[2] = '\n';
	payload[3] = 0;
	for (var i = 4; i < payload.length; i++) {
		payload[i] = (uint8) (i & 0xff);
	}
	var expected_sha = GLib.Checksum.compute_for_data(GLib.ChecksumType.SHA256, payload);
	var pkg_file = GLib.Path.build_filename(pkg_dir, "osquery.deb");
	try {
		GLib.FileUtils.set_data(pkg_file, payload);
		GLib.FileUtils.set_contents(
			GLib.Path.build_filename(client_dir, "download"),
			"127.0.0.1:" + port.to_string() + "\n");
		GLib.FileUtils.set_contents(
			GLib.Path.build_filename(untrusted_dir, "download"),
			"127.0.0.1:" + port.to_string() + "\n");
	} catch (GLib.FileError e) {
		GLib.printerr("fixture write failed: %s\n", e.message);
		return 1;
	}

	Argus.SERVER_DATA_DIR = server_dir;
	app.download = "127.0.0.1:" + port.to_string();
	var listener = new Argus.Server.Net.Download(app);
	if (!listener.listen()) {
		GLib.printerr("download listener failed to bind on %s\n", app.download);
		return 1;
	}

	var loop = new GLib.MainLoop();
	var exit_code = 0;
	var fetched_path = "";

	new GLib.Thread<int>("download-test-worker", () => {
		Argus.AGENT_DATA_DIR = client_dir;
		var ok = new Argus.Agent.Download();
		var code = ok.fetch("/osquery/osquery.deb");
		if (code != 0) {
			GLib.printerr("valid fetch failed with %d\n", code);
			exit_code = 1;
		}
		if (exit_code == 0) {
			fetched_path = ok.path;
			var got = new uint8[0];
			try {
				GLib.FileUtils.get_data(fetched_path, out got);
			} catch (GLib.FileError e) {
				GLib.printerr("could not read fetched file: %s\n", e.message);
				exit_code = 1;
			}
			var got_sha = GLib.Checksum.compute_for_data(GLib.ChecksumType.SHA256, got);
			if (got.length != payload.length || got_sha != expected_sha) {
				GLib.printerr("payload mismatch: got %d bytes (%s), expected %d (%s)\n",
					got.length, got_sha, payload.length, expected_sha);
				exit_code = 1;
			}
		}

		if (exit_code == 0) {
			var missing = new Argus.Agent.Download();
			var missing_code = missing.fetch("/osquery/missing.deb");
			if (missing_code == 0) {
				GLib.printerr("missing file unexpectedly succeeded\n");
				exit_code = 1;
			}
		}

		if (exit_code == 0) {
			Argus.AGENT_DATA_DIR = untrusted_dir;
			var rejected = new Argus.Agent.Download();
			var rejected_code = rejected.fetch("/osquery/osquery.deb");
			if (rejected_code == 0) {
				GLib.printerr("untrusted client unexpectedly succeeded\n");
				exit_code = 1;
			}
		}

		GLib.Idle.add(() => {
			loop.quit();
			return false;
		});
		return 0;
	});

	loop.run();
	listener.stop();
	if (fetched_path != "") {
		GLib.FileUtils.remove(fetched_path);
	}
	return exit_code;
}
