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

namespace Argus.Controller
{
	/**
	 * Fields {@link Command} reads. Not the process.
	 */
	public class Application : GLib.Object
	{
		public static string agent;
		public static string command;
		public OLLMrpc.Client rpc { get; set; }
		public GLib.MainLoop loop { get; set; }
		public int code { get; set; default = 1; }
	}

	class State : GLib.Object
	{
		public static string got_stdout;
		public static int got_ended;
		public static OLLMrpc.Bin.Stream bin;
	}
}

/**
 * Unix loopback for the controller command path.
 *
 * {@link Argus.Controller.Command.run} sends ''Task.create'',
 * ''Task.target'', ''Task.watch'', then ''Task.approve''. After approve, the peer
 * writes ''controller.stdout'' then ''controller.ended''. A
 * {@link GLib.Object.ref} keeps the command until the process exits.
 * The CLI exits 0 only after ended.
 *
 * == Example ==
 *
 * {{{
 * ninja -C build controller/argus-controller-command
 * meson test -C build controller-command --print-errorlogs
 * }}}
 */
int main(string[] args)
{
	OLLMrpc.rpc_register();
	Argus.Shared.SQT.Task.rpc_register();
	Argus.Shared.SQT.TaskTarget.rpc_register();
	Argus.Controller.Command.rpc_register();
	Argus.Controller.State.got_stdout = "";
	Argus.Controller.State.got_ended = 0;
	Argus.Controller.Application.agent = "1";
	Argus.Controller.Application.command = "echo hello";
	var dir = "";
	try {
		dir = GLib.DirUtils.make_tmp("argus-controller-XXXXXX");
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	var sock = GLib.Path.build_filename(dir, "argus.sock");
	var listener = new GLib.SocketListener();
	GLib.SocketAddress effective;
	try {
		listener.add_address(
			new GLib.UnixSocketAddress(sock),
			GLib.SocketType.STREAM,
			GLib.SocketProtocol.DEFAULT,
			null,
			out effective);
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		return 1;
	}
	new GLib.Thread<int>("accept", () => {
		GLib.SocketConnection conn;
		try {
			conn = listener.accept(null);
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
			return 1;
		}
		Argus.Controller.State.bin = new OLLMrpc.Bin.Stream(
			new GLib.DataInputStream(conn.get_input_stream()),
			new GLib.DataOutputStream(conn.get_output_stream()),
			true);
		while (Argus.Controller.State.got_ended == 0) {
			OLLMrpc.Request req;
			try {
				req = (OLLMrpc.Request) Argus.Controller.State.bin.parse();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
			try {
				if (req.method == "Task.create") {
					Argus.Controller.State.bin.write(new OLLMrpc.Response() {
						id = req.id,
						retval = OLLMrpc.val("o", new Argus.Shared.SQT.Task() {
							id = 1,
							command = "echo hello"
						}),
						msg = "ok"
					});
				} else if (req.method == "Task.target") {
					var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
					rows.add(new Argus.Shared.SQT.TaskTarget() {
						id = 1,
						task_id = 1,
						agent_id = 1
					});
					Argus.Controller.State.bin.write(new OLLMrpc.Response() {
						id = req.id,
						retval = OLLMrpc.val("o", rows),
						msg = "ok"
					});
				} else {
					Argus.Controller.State.bin.write(new OLLMrpc.Response() {
						id = req.id,
						msg = "ok"
					});
				}
				Argus.Controller.State.bin.out_stream.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
			if (req.method != "Task.approve") {
				continue;
			}
			GLib.Thread.usleep(200 * 1000);
			try {
				Argus.Controller.State.bin.write(new OLLMrpc.Notification() {
					method = "controller.stdout",
					args = OLLMrpc.args("is", 1, "hello\n")
				});
				Argus.Controller.State.bin.out_stream.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
			try {
				Argus.Controller.State.bin.write(new OLLMrpc.Notification() {
					method = "controller.ended",
					args = OLLMrpc.args("i", 1)
				});
				Argus.Controller.State.bin.out_stream.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return 1;
			}
		}
		return 0;
	});
	var app = new Argus.Controller.Application();
	app.rpc = new OLLMrpc.Client("", "", sock) {
		live_handles = false
	};
	app.loop = new GLib.MainLoop();
	app.code = 1;
	app.rpc.connect.begin(new OLLMrpc.Request() {
		method = "RPC-Daemon.hello",
		args = OLLMrpc.args("is", 1, "argus-controller")
	}, null, (obj, res) => {
		var opened = app.rpc.connect.end(res);
		if (!opened) {
			GLib.printerr("%s\n", app.rpc.connect_error);
			app.loop.quit();
			return;
		}
		var command = new Argus.Controller.Command(app);
		command.ref();
		command.stdout.connect((text) => {
			Argus.Controller.State.got_stdout += text;
		});
		command.ended.connect(() => {
			Argus.Controller.State.got_ended = 1;
			app.code = 0;
			app.loop.quit();
		});
		command.run();
	});
	GLib.Timeout.add_seconds(8, () => {
		app.loop.quit();
		return false;
	});
	app.loop.run();
	if (Argus.Controller.State.got_stdout != "hello\n") {
		GLib.printerr("stdout: %s\n", Argus.Controller.State.got_stdout);
		return 1;
	}
	if (Argus.Controller.State.got_ended == 0) {
		GLib.printerr("ended missing\n");
		return 1;
	}
	if (app.code != 0) {
		GLib.printerr("code %d\n", app.code);
		return 1;
	}
	GLib.print("ok %s", Argus.Controller.State.got_stdout);
	return 0;
}
