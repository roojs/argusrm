/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
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
 * Calls {@link Argus.Server.Rdp.Relay.start} on two TLS sockets.
 *
 * The controller connects first, then the agent. The agent is
 * not in {@link Argus.Server.Net.SslListen.by_id}, so the first
 * start replies ''unknown agent''. The agent is then stored and
 * the second start writes ''relay.start''. {@link Argus.Server.Rdp.Relay.join}
 * writes ''relay.ready'' back to the controller.
 */
namespace Argus.Server
{
	/**
	 * Stand-in for the process. {@link Rdp.Relay.start} only
	 * reads {@link ssl_listen}.
	 */
	public class Application : GLib.Object
	{
		public Net.SslListen ssl_listen { get; private set; }

		public Application()
		{
			this.ssl_listen = new Net.SslListen();
		}
	}
}

namespace Argus.Server.Net
{
	/**
	 * The agent map {@link Argus.Server.Rdp.Relay.start} looks in.
	 */
	public class SslListen : GLib.Object
	{
		internal Gee.HashMap<int, SslConnection> by_id {
			get; set; default = new Gee.HashMap<int, SslConnection>();
		}
	}

	/**
	 * App-socket connection. Records every reply and notification
	 * before the bytes go out.
	 */
	public class SslConnection : OLLMrpc.Transport.Connection
	{
		public Application app { get; construct; }
		public Argus.Shared.Agent user {
			get; set; default = new Argus.Shared.Agent();
		}

		public SslConnection(GLib.SocketConnection stream, Application app)
		{
			GLib.Object(stream: stream, app: app);
		}

		public override void write(
			GLib.Object gobject,
			OLLMrpc.Live.Buffer? buffer = null
		)
		{
			if (gobject is OLLMrpc.Response) {
				var response = (OLLMrpc.Response) gobject;
				if (response.error != null) {
					stderr.printf("reply %s\n", response.error.message);
				} else {
					stderr.printf("reply ok\n");
				}
			}
			if (gobject is OLLMrpc.Notification) {
				stderr.printf("sent %s\n", ((OLLMrpc.Notification) gobject).method);
			}
			base.write(gobject, buffer);
		}
	}
}

class RdpStartTest
{
	static Gee.ArrayList<GLib.Subprocess> children = new Gee.ArrayList<GLib.Subprocess>();
	static Argus.Server.Application app;
	static Argus.Server.Rdp.Relay relay;
	static Argus.Server.Net.SslConnection? controller_conn;
	static Argus.Server.Net.SslConnection? agent_conn;
	static bool scenario_armed = false;

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
			"-subj", "/CN=argus-rdp-start-ca"
		})) {
			return false;
		}
		string[] names = { "server", "controller", "agent" };
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
			var dir = GLib.DirUtils.make_tmp("argus-rdp-start-XXXXXX");
			if (!certificates(dir)) {
				return 1;
			}
			var port = free_port();
			var self = self_path();
			var server = spawn({
				self, "listen", dir, port.to_string()
			});
			if (!server.wait_for("start listening", 5)) {
				stop_children();
				return 1;
			}
			var controller = spawn({
				self, "client", dir, port.to_string(), "controller"
			});
			if (!server.wait_for("controller ready", 5)) {
				stop_children();
				return 1;
			}
			var agent = spawn({
				self, "client", dir, port.to_string(), "agent"
			});
			if (!server.wait_for("reply The machine is not connected.", 10)) {
				stop_children();
				stderr.printf("missing agent was not rejected\n");
				return 1;
			}
			if (!agent.wait_for("agent relay.start", 10)) {
				stop_children();
				stderr.printf("agent did not get relay.start\n");
				return 1;
			}
			var down = Argus.Rdp.State.RETRY_MACHINE_DOWN.to_string();
			var asked = Argus.Rdp.State.SUCCESS_ASKED_MACHINE.to_string();
			var hold = Argus.Rdp.State.SUCCESS_SERVER_AWAITING_VIEW.to_string();
			var local = Argus.Rdp.State.SUCCESS_LOCAL_RDP_CONNECTED.to_string();
			if (!controller.wait_for("controller relay.status 42 " + hold + " 0", 10)) {
				stop_children();
				stderr.printf("controller did not get %s\n", hold);
				return 1;
			}
			if (!controller.wait_for("controller relay.status 42 " + down + " 1", 1)) {
				stop_children();
				stderr.printf("controller did not get %s\n", down);
				return 1;
			}
			if (!controller.wait_for("controller relay.status 42 " + asked + " 0", 1)) {
				stop_children();
				stderr.printf("controller did not get %s\n", asked);
				return 1;
			}
			if (!controller.wait_for("controller relay.status 42 " + local + " 0", 1)) {
				stop_children();
				stderr.printf("controller did not get %s\n", local);
				return 1;
			}
			if (!controller.wait_for("controller relay.ready 42", 10)) {
				stop_children();
				stderr.printf("controller did not get relay.ready\n");
				return 1;
			}
			stop_children();
			stdout.printf("ok rdp start\n");
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

	static void scenario()
	{
		var request = new OLLMrpc.Request() {
			method = "Relay.start",
			connection = controller_conn
		};
		relay.start(request, 42);
		agent_conn.user = new Argus.Shared.Agent() {
			id = 42,
			status = 1,
			is_controller = false
		};
		app.ssl_listen.by_id.set(42, agent_conn);
		relay.start(request, 42);
		var join = new OLLMrpc.Request() {
			method = "Relay.join",
			connection = agent_conn
		};
		relay.join(join, "agent");
		var report = new OLLMrpc.Request() {
			method = "Relay.report",
			connection = agent_conn
		};
		relay.report(
			report,
			(int) Argus.Rdp.State.SUCCESS_LOCAL_RDP_CONNECTED,
			0);
	}

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
		app = new Argus.Server.Application();
		relay = new Argus.Server.Rdp.Relay();
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
				var rpc = new Argus.Server.Net.SslConnection(conn, app) {
					io = tls
				};
				rpc.start();
				if (controller_conn == null) {
					controller_conn = rpc;
					stderr.printf("controller ready\n");
					return;
				}
				if (agent_conn == null) {
					agent_conn = rpc;
					stderr.printf("agent ready\n");
				}
				if (scenario_armed || controller_conn == null || agent_conn == null) {
					return;
				}
				scenario_armed = true;
				GLib.Idle.add(() => {
					scenario();
					return false;
				});
			});
			return true;
		});
		service.start();
		stderr.printf("start listening\n");
		new GLib.MainLoop().run();
		return 0;
	}

	public static int client_side(
		string dir, uint16 port, string role
	) throws GLib.Error {
		var rpc = new OLLMrpc.Transport.TlsClient("127.0.0.1", port) {
			accept_any = true,
			tls_certificate = new GLib.TlsCertificate.from_files(
				Path.build_filename(dir, role + ".crt"),
				Path.build_filename(dir, role + ".key")),
			tls_database = GLib.TlsFileDatabase.new(
				Path.build_filename(dir, "ca.crt"))
		};
		rpc.open();
		rpc.notification.connect((notif) => {
			if (notif.method == "relay.status" && notif.args.size >= 3) {
				var state = (Argus.Rdp.State) notif.args.get(1).get_int();
				stderr.printf(
					"%s relay.status %d %s %d\n",
					role,
					notif.args.get(0).get_int(),
					state.to_string(),
					notif.args.get(2).get_int());
				return;
			}
			if (notif.method == "relay.ready" && notif.args.size > 0) {
				stderr.printf("%s relay.ready %d\n", role, notif.args.get(0).get_int());
				return;
			}
			stderr.printf("%s %s\n", role, notif.method);
		});
		rpc.watch();
		stderr.printf("%s watching\n", role);
		new GLib.MainLoop().run();
		return 0;
	}
}

int main(string[] args)
{
	OLLMrpc.rpc_register();
	try {
		if (args.length == 2 && args[1] == "prove") {
			return RdpStartTest.prove();
		}
		if (args.length == 4 && args[1] == "listen") {
			return RdpStartTest.listen_side(args[2], (uint16) int.parse(args[3]));
		}
		if (args.length == 5 && args[1] == "client") {
			return RdpStartTest.client_side(
				args[2], (uint16) int.parse(args[3]), args[4]);
		}
	} catch (GLib.Error e) {
		stderr.printf("%s\n", e.message);
		return 1;
	}
	stderr.printf("usage: argus-rdp-start-test prove | listen dir port | client dir port role\n");
	return 1;
}
