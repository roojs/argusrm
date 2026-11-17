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

namespace Argus.Server
{
	/**
	 * Proves a FreeRDP session can cross {@link OLLMrpc.Transport.TlsClient}
	 * and {@link OLLMrpc.Transport.Connection}.
	 *
	 * {@link Argus.Agent.Rdp.Desk} is the desktop.
	 * {@link Argus.Agent.Rdp.Tunnel} dials it.
	 * {@link Rdp.Relay} pairs that tunnel with
	 * {@link Argus.Controller.Rdp.Viewer}. sdl-freerdp3 talks to the
	 * viewer port. The test passes when the desk prints ACTIVATED.
	 */
	class RdpRelayTest
	{
		static Gee.ArrayList<GLib.Subprocess> children = new Gee.ArrayList<GLib.Subprocess>();

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
				"-subj", "/CN=argus-rdp-test-ca"
			})) {
				return false;
			}
			string[] names = { "server", "agent", "view" };
			foreach (var name in names) {
				var key = Path.build_filename(dir, name + ".key");
				var csr = Path.build_filename(dir, name + ".csr");
				var crt = Path.build_filename(dir, name + ".crt");
				string[] req = {
					"openssl", "req", "-newkey", "rsa:2048",
					"-keyout", key, "-out", csr, "-nodes",
					"-subj", "/CN=" + (name == "server" ? "127.0.0.1" : name)
				};
				if (name == "server") {
					req += "-addext";
					req += "subjectAltName=IP:127.0.0.1";
				}
				if (!openssl(req)) {
					return false;
				}
				string[] sign = {
					"openssl", "x509", "-req", "-in", csr,
					"-CA", ca_crt, "-CAkey", ca_key, "-CAcreateserial",
					"-out", crt, "-days", "2"
				};
				if (name == "server") {
					sign += "-copy_extensions";
					sign += "copy";
				}
				if (!openssl(sign)) {
					return false;
				}
			}
			return true;
		}

		static ChildLog spawn(string[] argv) throws GLib.Error
		{
			var launch = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_PIPE);
			var proc = launch.spawnv(argv);
			children.add(proc);
			return new ChildLog(proc);
		}

		static void stop_children()
		{
			foreach (var child in children) {
				child.force_exit();
			}
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

		public static int prove(string desk_bin, string sdl_bin)
		{
			try {
				var dir = GLib.DirUtils.make_tmp("argus-rdp-XXXXXX");
				if (!certificates(dir)) {
					return 1;
				}
				var desk_port = free_port();
				var relay_port = free_port();
				var view_port = free_port();
				var self = self_path();
				var desk = spawn({
					desk_bin, desk_port.to_string(),
					Path.build_filename(dir, "server.crt"),
					Path.build_filename(dir, "server.key")
				});
				if (!desk.wait_for("desk listening", 5)) {
					stop_children();
					return 1;
				}
				var relay = spawn({
					self, "relay", dir, relay_port.to_string()
				});
				if (!relay.wait_for("relay listening", 5)) {
					stop_children();
					return 1;
				}
				spawn({
					self, "agent", dir, relay_port.to_string(), desk_port.to_string()
				});
				var view = spawn({
					self, "view", dir, relay_port.to_string(), view_port.to_string()
				});
				if (!view.wait_for("view listening", 5)) {
					stop_children();
					return 1;
				}
				spawn({
					sdl_bin,
					"/v:127.0.0.1:%u".printf(view_port),
					"/u:probe", "/p:probe",
					"/sec:tls:on", "/sec:nla:off",
					"/cert:ignore", "+auth-only",
					"/log-level:INFO"
				});
				var activated = desk.wait_for("ACTIVATED", 20);
				stop_children();
				if (!activated) {
					stderr.printf("desktop did not activate\n");
					return 1;
				}
				stdout.printf("ok rdp relay activated\n");
				return 0;
			} catch (GLib.Error e) {
				stderr.printf("%s\n", e.message);
				stop_children();
				return 1;
			}
		}
	}
}

int main(string[] args)
{
	OLLMrpc.rpc_register();
	try {
		if (args.length == 3) {
			return Argus.Server.RdpRelayTest.prove(args[1], args[2]);
		}
		if (args.length == 4 && args[1] == "relay") {
			return new Argus.Server.Rdp.Relay().listen(args[2], (uint16) int.parse(args[3]));
		}
		if (args.length == 5 && args[1] == "agent") {
			new Argus.Agent.Rdp.Tunnel().run(
				args[2], (uint16) int.parse(args[3]), (uint16) int.parse(args[4]));
			return 0;
		}
		if (args.length == 5 && args[1] == "view") {
			new Argus.Controller.Rdp.Viewer().run(
				args[2], (uint16) int.parse(args[3]), (uint16) int.parse(args[4]));
			return 0;
		}
	} catch (GLib.Error e) {
		stderr.printf("%s\n", e.message);
		return 1;
	}
	stderr.printf("usage: argus-rdp-relay-test desk sdl-freerdp3\n");
	return 2;
}
