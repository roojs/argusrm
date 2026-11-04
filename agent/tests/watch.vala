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

namespace Argus.Agent
{
	/**
	 * Wire ''Argus.Command'' for the loopback. {@link run} records
	 * the line. No process is spawned.
	 */
	public class Command : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Command", typeof(Command));
		}

		public int identifier { get; set; default = 0; }
		public string command { get; set; default = ""; }
		public string[] environment { get; set; default = {}; }
		public string cwd { get; set; default = ""; }
		internal static GLib.Mutex send_lock;
		internal static Gee.HashMap<int, Command> running;
		internal static string during = "";
		internal static string after = "";
		internal static GLib.MainLoop loop;

		public void run(OLLMrpc.Transport.TlsClient link)
		{
			GLib.debug("command %d", this.identifier);
			if (Command.during == "") {
				Command.during = this.command;
			} else {
				Command.after = this.command;
			}
			if (Command.during != "" && Command.after != "") {
				Command.loop.quit();
			}
		}

		public void send(string text)
		{
		}
	}
}

/**
 * Loopback for the live command path.
 *
 * Four worker ''OSQuery.sync'' calls, like osquery. The first
 * reply is preceded by ''agent.run'' with an ''Argus.Command'',
 * the same order as a controller hit during a sync. After the
 * last reply, a second ''agent.run'' goes out on the idle
 * watch. Both must reach {@link Argus.Agent.Command.run}.
 *
 * == Example ==
 *
 * {{{
 * ninja -C build agent/argus-agent-watch
 * ./build/agent/argus-agent-watch
 * }}}
 */
int main(string[] args)
{
	OLLMrpc.rpc_register();
	Argus.Agent.Command.rpc_register();
	var dir = "";
	try {
		dir = GLib.DirUtils.make_tmp("argus-watch-XXXXXX");
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var tls_files = new OLLMrpc.Transport.Cert() {
		dir = dir,
		server_san = true,
		cn = "argus-watch"
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
			if (syncs == 1) {
				try {
					bin.write(new OLLMrpc.Notification() {
						method = "agent.run",
						args = OLLMrpc.args("o", new Argus.Agent.Command() {
							identifier = 1,
							command = "ls -l /home/alan"
						})
					});
					bin.out_stream.flush();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return 1;
				}
			}
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
		try {
			bin.write(new OLLMrpc.Notification() {
				method = "agent.run",
				args = OLLMrpc.args("o", new Argus.Agent.Command() {
					identifier = 2,
					command = "true"
				})
			});
			bin.out_stream.flush();
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
			return 1;
		}
		GLib.Thread.usleep(2 * 1000000);
		return 0;
	});
	var link = new OLLMrpc.Transport.TlsClient("127.0.0.1", (uint16) inet.port) {
		accept_any = true
	};
	try {
		link.open();
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	Argus.Agent.Command.loop = new GLib.MainLoop();
	link.notification.connect((notif) => {
		if (notif.method != "agent.run" || notif.args.size == 0) {
			return;
		}
		var command = notif.args.get(0).get_object() as Argus.Agent.Command;
		command.run(link);
	});
	link.watch();
	new GLib.Thread<int>("call", () => {
		var n = 0;
		while (n < 4) {
			n++;
			try {
				link.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					id = n
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				Argus.Agent.Command.loop.quit();
				return 1;
			}
		}
		return 0;
	});
	GLib.Timeout.add_seconds(5, () => {
		Argus.Agent.Command.loop.quit();
		return false;
	});
	Argus.Agent.Command.loop.run();
	tls_files.remove();
	if (Argus.Agent.Command.during != "ls -l /home/alan") {
		GLib.printerr("during call: %s\n", Argus.Agent.Command.during);
		return 1;
	}
	if (Argus.Agent.Command.after != "true") {
		GLib.printerr("after osquery: %s\n", Argus.Agent.Command.after);
		return 1;
	}
	GLib.print("ok during %s after %s\n",
		Argus.Agent.Command.during, Argus.Agent.Command.after);
	return 0;
}
