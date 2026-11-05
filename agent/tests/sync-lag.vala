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
 * Times four worker ''OSQuery.sync'' calls after {@link
 * Argus.Agent.TlsClient.watch}. The peer replies at once.
 * Each call waits 200 ms first, the same gap as an osquery
 * SELECT. A call that takes 2000 ms or more, or a 12 s hang
 * with no line, is the watch lock. Not osquery. Not the
 * snapshot.
 *
 * == Example ==
 *
 * {{{
 * ninja -C build agent/argus-agent-sync-lag
 * ./build/agent/argus-agent-sync-lag
 * }}}
 */
int main(string[] args)
{
	OLLMrpc.rpc_register();
	var dir = "";
	try {
		dir = GLib.DirUtils.make_tmp("argus-sync-lag-XXXXXX");
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var tls_files = new OLLMrpc.Transport.Cert() {
		dir = dir,
		server_san = true,
		cn = "argus-sync-lag"
	};
	tls_files.ensure();
	var listener = new GLib.SocketListener();
	var bind_addr = new GLib.InetSocketAddress.from_string("127.0.0.1", 0);
	GLib.SocketAddress effective;
	try {
		listener.add_address(
			bind_addr,
			GLib.SocketType.STREAM,
			GLib.SocketProtocol.TCP,
			null,
			out effective);
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var inet = (GLib.InetSocketAddress) effective;
	new GLib.Thread<int>("accept", () => {
		GLib.SocketConnection conn;
		try {
			conn = listener.accept(null);
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
			return 1;
		}
		GLib.TlsServerConnection tls;
		try {
			tls = GLib.TlsServerConnection.@new(conn, tls_files.certificate);
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
			return 1;
		}
		tls.authentication_mode = GLib.TlsAuthenticationMode.NONE;
		tls.accept_certificate.connect((peer_cert, errors) => {
			return true;
		});
		try {
			tls.handshake();
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
			return 1;
		}
		var bin = new OLLMrpc.Bin.Stream(
			new GLib.DataInputStream(tls.get_input_stream()),
			new GLib.DataOutputStream(tls.get_output_stream()),
			true);
		var syncs = 0;
		while (syncs < 4) {
			OLLMrpc.Request req;
			try {
				req = (OLLMrpc.Request) bin.parse();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
			syncs++;
			try {
				bin.write(new OLLMrpc.Response() {
					id = req.id,
					msg = "ok"
				});
				bin.out_stream.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
		}
		return 0;
	});
	var link = new Argus.Agent.TlsClient("127.0.0.1", (uint16) inet.port) {
		accept_any = true
	};
	try {
		link.open();
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var loop = new GLib.MainLoop();
	var code = 0;
	link.watch();
	new GLib.Thread<int>("call", () => {
		var n = 0;
		while (n < 4) {
			n++;
			GLib.Thread.usleep(200 * 1000);
			var started = GLib.get_monotonic_time();
			try {
				link.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					id = n
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				code = 1;
				loop.quit();
				return 1;
			}
			var ms = (GLib.get_monotonic_time() - started) / 1000;
			GLib.print("call %d %d ms\n", n, (int) ms);
			if (ms >= 2000) {
				GLib.printerr("slow\n");
				code = 1;
				loop.quit();
				return 1;
			}
		}
		GLib.print("ok\n");
		loop.quit();
		return 0;
	});
	new GLib.Thread<int>("watchdog", () => {
		GLib.Thread.usleep(12 * 1000 * 1000);
		GLib.printerr("locked\n");
		GLib.Process.exit(1);
	});
	loop.run();
	tls_files.remove();
	return code;
}
