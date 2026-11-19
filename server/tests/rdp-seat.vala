/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License published by the Free Software Foundation; either
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
 * Tests the Seat notification flow without the full server.
 *
 * A TLS listener accepts two connections. The first is the
 * controller, the second is the agent. A {@link Seat} is
 * created, ''asked'' is set to the controller, then
 * {@link Seat.joined} is called with the agent. That sends
 * ''relay.ready'' to the controller. A third connection is
 * the view. {@link Seat.attach} stores it, then
 * {@link Seat.forward} sends ''relay.data'' to the view.
 *
 * This is the flow that ''Relay.start'' → ''relay.ready''
 * uses in the product, without ''SslConnection'' or the
 * database.
 */
class RdpSeatTest
{
	static Gee.ArrayList<GLib.Subprocess> children = new Gee.ArrayList<GLib.Subprocess>();

	static uint16 free_port() throws GLib.Error
	{
		var listener = new GLib.SocketListener();
		var where = new GLib.InetSocketAddress(
			new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0);
		GLib.SocketAddress? bound = null;
		listener.add_address(
			where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out bound);
		var port = ((GLib.InetSocketAddress) bound).get_port();
		listener.close();
		return port;
	}

	static bool openssl(string[] argv) throws GLib.Error
	{
		var launch = new GLib.SubprocessLauncher(
			GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_PIPE);
		var proc = launch.spawnv(argv);
		string? err = null;
		proc.communicate_utf8(null, null, null, out err);
		if (proc.get_successful()) {
			return true;
		}
		stderr.printf("%s\n", err ?? "openssl failed");
		return false;
	}

	static bool certificates(string dir) throws GLib.Error
	{
		var ca_key = Path.build_filename(dir, "ca.key");
		var ca_crt = Path.build_filename(dir, "ca.crt");
		if (!openssl({
			"openssl", "req", "-x509", "-newkey", "rsa:2048",
			"-keyout", ca_key, "-out", ca_crt, "-days", "2", "-nodes",
			"-subj", "/CN=argus-rdp-seat-ca"
		})) {
			return false;
		}
		string[] names = { "server", "controller", "agent", "view" };
		foreach (var name in names) {
			var key = Path.build_filename(dir, name + ".key");
			var csr = Path.build_filename(dir, name + ".csr");
			var crt = Path.build_filename(dir, name + ".crt");
			if (!openssl({
				"openssl", "req", "-newkey", "rsa:2048",
				"-keyout", key, "-out", csr, "-nodes",
				"-subj", "/CN=" + name
			})) {
				return false;
			}
			if (!openssl({
				"openssl", "x509", "-req", "-in", csr,
				"-CA", ca_crt, "-CAkey", ca_key, "-CAcreateserial",
				"-out", crt, "-days", "2"
			})) {
				return false;
			}
		}
		return true;
	}

	static string self_path()
	{
		char[] buf = new char[4096];
		var n = Posix.readlink("/proc/self/exe", buf);
		if (n < 1) {
			return "";
		}
		return (string) buf[0:n];
	}

	static void stop_children()
	{
		foreach (var child in children) {
			child.force_exit();
		}
	}

	public static int prove()
	{
		try {
			var dir = GLib.DirUtils.make_tmp("argus-rdp-seat-XXXXXX");
			if (!certificates(dir)) {
				return 1;
			}
			var port = free_port();
			var self = self_path();
			var server = spawn({
				self, "listen", dir, port.to_string()
			});
			if (!server.wait_for("seat listening", 5)) {
				stop_children();
				return 1;
			}
			var controller = spawn({
				self, "client", dir, port.to_string(), "controller"
			});
			if (!controller.wait_for("controller ready", 5)) {
				stop_children();
				return 1;
			}
			var agent = spawn({
				self, "client", dir, port.to_string(), "agent"
			});
			if (!agent.wait_for("agent ready", 5)) {
				stop_children();
				return 1;
			}
			if (!controller.wait_for("relay.ready 42", 10)) {
				stop_children();
				stderr.printf("controller did not get relay.ready\n");
				return 1;
			}
			var view = spawn({
				self, "client", dir, port.to_string(), "view"
			});
			if (!view.wait_for("relay.data 5", 10)) {
				stop_children();
				stderr.printf("view did not get relay.data\n");
				return 1;
			}
			stop_children();
			stdout.printf("ok rdp seat notification\n");
			return 0;
		} catch (GLib.Error e) {
			stderr.printf("%s\n", e.message);
			stop_children();
			return 1;
		}
	}

	class ChildLog
	{
		public string text = "";
		GLib.Mutex mutex;

		public ChildLog(GLib.Subprocess proc)
		{
			var input = new GLib.DataInputStream(proc.get_stderr_pipe());
			new GLib.Thread<int>("child", () => {
				try {
					while (true) {
						var line = input.read_line(null);
						if (line == null) {
							break;
						}
						stderr.printf("%s\n", line);
						this.mutex.lock();
						this.text += line + "\n";
						this.mutex.unlock();
					}
				} catch (GLib.Error e) {
					stderr.printf("%s\n", e.message);
				}
				return 0;
			});
		}

		public bool wait_for(string needle, int seconds)
		{
			var deadline = GLib.get_monotonic_time() + (int64) seconds * 1000000;
			while (GLib.get_monotonic_time() < deadline) {
				this.mutex.lock();
				var hit = needle in this.text;
				this.mutex.unlock();
				if (hit) {
					return true;
				}
				GLib.Thread.usleep(50 * 1000);
			}
			this.mutex.lock();
			var late = needle in this.text;
			this.mutex.unlock();
			return late;
		}
	}

	static ChildLog spawn(string[] argv) throws GLib.Error
	{
		var launch = new GLib.SubprocessLauncher(
			GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_PIPE);
		var proc = launch.spawnv(argv);
		children.add(proc);
		return new ChildLog(proc);
	}

	/**
	 * The server side: accept TLS connections and drive a Seat.
	 */
	public static int listen_side(string dir, uint16 port) throws GLib.Error
	{
		var server_cert = new GLib.TlsCertificate.from_files(
			Path.build_filename(dir, "server.crt"),
			Path.build_filename(dir, "server.key"));
		GLib.TlsDatabase trust = GLib.TlsFileDatabase.new(
			Path.build_filename(dir, "ca.crt"));
		var service = new GLib.SocketService();
		var where = new GLib.InetSocketAddress(
			new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), port);
		service.add_address(where, GLib.SocketType.STREAM,
			GLib.SocketProtocol.TCP, null, null);
		var seat = new Argus.Server.Rdp.Seat();
		OLLMrpc.Transport.Connection? controller_conn = null;
		OLLMrpc.Transport.Connection? agent_conn = null;
		OLLMrpc.Transport.Connection? view_conn = null;
		var got_agent = false;
		var got_view = false;
		service.incoming.connect((conn) => {
			try {
				conn.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				stderr.printf("nodelay: %s\n", e.message);
			}
			GLib.TlsServerConnection tls;
			try {
				tls = GLib.TlsServerConnection.@new(conn, server_cert);
			} catch (GLib.Error e) {
				stderr.printf("tls: %s\n", e.message);
				return true;
			}
			tls.database = trust;
			tls.authentication_mode = GLib.TlsAuthenticationMode.REQUIRED;
			tls.accept_certificate.connect((peer, errors) => {
				return peer != null;
			});
			tls.handshake_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
				try {
					tls.handshake_async.end(res);
				} catch (GLib.Error e) {
					stderr.printf("handshake: %s\n", e.message);
					return;
				}
				var rpc = new OLLMrpc.Transport.Connection(conn) {
					io = tls
				};
				rpc.start();
				if (controller_conn == null) {
					controller_conn = rpc;
					seat.asked = controller_conn;
					stderr.printf("controller ready\n");
					return;
				}
				if (agent_conn == null && !got_agent) {
					got_agent = true;
					agent_conn = rpc;
					var request = new OLLMrpc.Request() {
						method = "Relay.join",
						connection = rpc
					};
					seat.joined(request, 42);
					stderr.printf("agent ready\n");
					return;
				}
				if (view_conn == null && !got_view) {
					got_view = true;
					view_conn = rpc;
					var request = new OLLMrpc.Request() {
						method = "Relay.view",
						connection = rpc
					};
					seat.attach(request);
					var chunk = new uint8[5];
					chunk[0] = 'h';
					chunk[1] = 'e';
					chunk[2] = 'l';
					chunk[3] = 'l';
					chunk[4] = 'o';
					seat.forward(agent_conn, new GLib.Bytes(chunk));
					stderr.printf("view ready\n");
					return;
				}
			});
			return true;
		});
		service.start();
		stderr.printf("seat listening\n");
		var loop = new GLib.MainLoop();
		loop.run();
		return 0;
	}

	/**
	 * The client side: connect, watch, and print notifications.
	 */
	public static int client_side(
		string dir, uint16 port, string role
	) throws GLib.Error {
		var cert_file = Path.build_filename(dir, role + ".crt");
		var key_file = Path.build_filename(dir, role + ".key");
		var rpc = new OLLMrpc.Transport.TlsClient("127.0.0.1", port) {
			accept_any = true,
			tls_certificate = new GLib.TlsCertificate.from_files(
				cert_file, key_file)
		};
		rpc.open();
		rpc.notification.connect((notif) => {
			if (notif.method == "relay.ready" && notif.args.size > 0) {
				var id = notif.args.get(0).get_int();
				stderr.printf("relay.ready %d\n", id);
			}
			if (notif.method == "relay.data" && notif.args.size > 0) {
				var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
				stderr.printf("relay.data %zu\n", blob.get_size());
			}
		});
		rpc.watch();
		stderr.printf("%s ready\n", role);
		var loop = new GLib.MainLoop();
		loop.run();
		return 0;
	}
}

int main(string[] args)
{
	OLLMrpc.rpc_register();
	try {
		if (args.length == 2 && args[1] == "prove") {
			return RdpSeatTest.prove();
		}
		if (args.length == 4 && args[1] == "listen") {
			return RdpSeatTest.listen_side(args[2], (uint16) int.parse(args[3]));
		}
		if (args.length == 5 && args[1] == "client") {
			return RdpSeatTest.client_side(
				args[2], (uint16) int.parse(args[3]), args[4]);
		}
	} catch (GLib.Error e) {
		stderr.printf("%s\n", e.message);
		return 1;
	}
	stderr.printf("usage: argus-rdp-seat-test prove | listen dir port | client dir port role\n");
	return 2;
}
