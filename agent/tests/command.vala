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
	 * Held the same way {@link Application} is. The switch is
	 * {@link Application.notification}.
	 */
	class App : GLib.Object
	{
		public OLLMrpc.Transport.TlsClient connection;
		public static string got_out;
		public static int got_end;
		public static int ran_in_handler;
		public static GLib.MainLoop loop;

		public void notification(OLLMrpc.Notification notification)
		{
			GLib.printerr("notif %s\n", notification.method);
			switch (notification.method) {
				case "agent.send":
					if (notification.args.size < 2) {
						return;
					}
					var id_value = notification.args.get(0);
					var text_value = notification.args.get(1);
					if (id_value == null || text_value == null) {
						return;
					}
					if (!id_value.holds(typeof(int)) ||
						!text_value.holds(typeof(string))) {
						return;
					}
					var identifier = id_value.get_int();
					Command.send_lock.lock();
					Command order = null;
					if (Command.running != null &&
						Command.running.has_key(identifier)) {
						order = Command.running.get(identifier);
					}
					Command.send_lock.unlock();
					if (order == null) {
						GLib.warning("command %d is not running", identifier);
						return;
					}
					order.send(text_value.get_string());
					return;
				case "agent.run":
					if (notification.args.size == 0) {
						GLib.warning("no argument");
						return;
					}
					var value = notification.args.get(0);
					var obj = value.get_object();
					if (!(obj is Command)) {
						GLib.warning("%s", value.type().name());
						return;
					}
					var command = (Command) obj;
					command.run(this.connection);
					App.ran_in_handler++;
					GLib.printerr("ran %d\n", App.ran_in_handler);
					return;
				default:
					return;
			}
		}
	}
}

/**
 * Loopback for the live command path.
 *
 * Four worker ''OSQuery.sync'' calls, then an idle watch, then
 * ''agent.run'' with ''printf listing''. That is the 11:58 live
 * order. The handler must call {@link Argus.Agent.Command.run}
 * before it returns. The peer answers ''Command.stdout'' and
 * ''Command.ended''.
 *
 * == Example ==
 *
 * {{{
 * ninja -C build agent/argus-agent-command
 * meson test -C build agent-command --print-errorlogs
 * }}}
 */
int main(string[] args)
{
	OLLMrpc.rpc_register();
	Argus.Agent.Command.rpc_register();
	Argus.Agent.App.got_out = "";
	Argus.Agent.App.got_end = 0;
	Argus.Agent.App.ran_in_handler = 0;
	var dir = "";
	try {
		dir = GLib.DirUtils.make_tmp("argus-command-XXXXXX");
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var tls_files = new OLLMrpc.Transport.Cert() {
		dir = dir,
		server_san = true,
		cn = "argus-command"
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
		while (Argus.Agent.App.got_end == 0) {
			OLLMrpc.Request req;
			try {
				req = (OLLMrpc.Request) bin.parse();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
			switch (req.method) {
			case "OSQuery.sync":
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
				if (syncs != 4) {
					break;
				}
				GLib.Thread.usleep(200 * 1000);
				try {
					bin.write(new OLLMrpc.Notification() {
						method = "agent.run",
						args = OLLMrpc.args("o", new Argus.Agent.Command() {
							identifier = 1,
							command = "printf listing"
						})
					});
					bin.out_stream.flush();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return 1;
				}
				break;
			case "Command.stdout":
				if (req.args.size < 2) {
					break;
				}
				Argus.Agent.App.got_out += req.args.get(1).get_string();
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
				break;
			case "Command.stderr":
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
				break;
			case "Command.ended":
				if (req.args.size > 0 && req.args.get(0).get_int() == 1) {
					Argus.Agent.App.got_end = 1;
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
				if (Argus.Agent.App.got_end != 0) {
					GLib.Idle.add(() => {
						Argus.Agent.App.loop.quit();
						return false;
					});
				}
				break;
			default:
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
				break;
			}
		}
		return 0;
	});
	var connection = new OLLMrpc.Transport.TlsClient("127.0.0.1", (uint16) inet.port) {
		accept_any = true
	};
	try {
		connection.open();
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var app = new Argus.Agent.App();
	app.connection = connection;
	Argus.Agent.App.loop = new GLib.MainLoop();
	connection.notification.connect(app.notification);
	new GLib.Thread<int>("call", () => {
		var n = 0;
		while (n < 4) {
			n++;
			try {
				connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					id = n
				});
				GLib.printerr("sync %d\n", n);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				GLib.Idle.add(() => {
					Argus.Agent.App.loop.quit();
					return false;
				});
				return 1;
			}
		}
		GLib.Idle.add(() => {
			connection.watch();
			return false;
		});
		return 0;
	});
	new GLib.Thread<int>("gate", () => {
		GLib.Thread.usleep(5 * 1000 * 1000);
		if (Argus.Agent.App.got_end != 0) {
			return 0;
		}
		GLib.printerr("Command.stdout still blocked after agent.run\n");
		Posix._exit(1);
		return 1;
	});
	GLib.Timeout.add_seconds(12, () => {
		Argus.Agent.App.loop.quit();
		return false;
	});
	Argus.Agent.App.loop.run();
	tls_files.remove();
	if (Argus.Agent.App.ran_in_handler < 1) {
		GLib.printerr("command did not run in the handler\n");
		return 1;
	}
	if (Argus.Agent.App.got_out.index_of("listing") < 0) {
		GLib.printerr("stdout: %s\n", Argus.Agent.App.got_out);
		return 1;
	}
	if (Argus.Agent.App.got_end == 0) {
		GLib.printerr("ended missing\n");
		return 1;
	}
	GLib.print("ok %s\n", Argus.Agent.App.got_out.strip());
	return 0;
}
