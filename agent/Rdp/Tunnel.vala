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

namespace Argus.Agent.Rdp
{
	/**
	 * Carries the machine desktop to the relay.
	 *
	 * The agent dials {@link Desk} on loopback, then opens a second
	 * {@link OLLMrpc.Transport.TlsClient} and joins as ''agent''.
	 * Bytes read from the desktop are ''Relay.write'' chunks.
	 * ''relay.data'' notifications are written back to the desktop.
	 * {@link Argus.Controller.Rdp.Viewer} is the other end.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tunnel = new Argus.Agent.Rdp.Tunnel();
	 * tunnel.run(dir, relay_port, desk_port);
	 * }}}
	 */
	public class Tunnel : GLib.Object
	{
		/**
		 * Dial the desktop and the relay, then copy until the desktop closes.
		 *
		 * @param dir directory of the agent certificate and ca.crt
		 * @param relay_port relay listen port
		 * @param desk_port desktop listen port
		 */
		public void run(string dir, uint16 relay_port, uint16 desk_port) throws GLib.Error
		{
			var client = new GLib.SocketClient();
			client.timeout = 10;
			var plain = client.connect_to_host("127.0.0.1", desk_port);
			try {
				plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				stderr.printf("nodelay: %s\n", e.message);
			}
			stderr.printf("tcp %u\n", desk_port);
			this.carry(dir, relay_port, plain);
		}

		void carry(string dir, uint16 relay_port, GLib.SocketConnection plain) throws GLib.Error
		{
			var rpc = new OLLMrpc.Transport.TlsClient("127.0.0.1", relay_port) {
				tls_certificate = new GLib.TlsCertificate.from_files(
					GLib.Path.build_filename(dir, "agent.crt"),
					GLib.Path.build_filename(dir, "agent.key")),
				tls_database = GLib.TlsFileDatabase.new(GLib.Path.build_filename(dir, "ca.crt"))
			};
			rpc.notification.connect((notif) => {
				if (notif.method != "relay.data" || notif.args.size < 1) {
					return;
				}
				var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
				unowned uint8[] data = blob.get_data();
				if (data == null) {
					return;
				}
				size_t off = 0;
				while (off < data.length) {
					try {
						off += plain.output_stream.write(data[off:data.length]);
					} catch (GLib.Error e) {
						stderr.printf("agent tcp write: %s\n", e.message);
						return;
					}
				}
			});
			rpc.open();
			stderr.printf("agent opened\n");
			var joined = rpc.call(new OLLMrpc.Request() {
				method = "Relay.join",
				args = OLLMrpc.args("s", "agent")
			});
			if (joined.error != null) {
				stderr.printf("join: %s\n", joined.error.message);
				return;
			}
			stderr.printf("agent joined\n");
			rpc.watch();
			new GLib.Thread<int>("agent", () => {
				var buf = new uint8[16384];
				while (true) {
					ssize_t n = 0;
					try {
						n = plain.input_stream.read(buf);
					} catch (GLib.Error e) {
						stderr.printf("agent tcp read: %s\n", e.message);
						break;
					}
					if (n <= 0) {
						break;
					}
					var chunk = new uint8[n];
					GLib.Memory.copy((uint8[]) chunk, buf, n);
					var held = GLib.Value(typeof(GLib.Bytes));
					held.set_boxed(new GLib.Bytes(chunk));
					var request = new OLLMrpc.Request() {
						method = "Relay.write"
					};
					request.args.add(held);
					try {
						var response = rpc.call(request);
						if (response.error != null) {
							stderr.printf("agent write: %s\n", response.error.message);
							break;
						}
					} catch (GLib.Error e) {
						stderr.printf("agent call: %s\n", e.message);
						break;
					}
				}
				GLib.Process.exit(0);
			});
			new GLib.MainLoop().run();
		}

		private GLib.SocketClient dial;
		private uint8[] buf { get; set; }
		public GLib.SocketConnection? plain;
		public OLLMrpc.Transport.TlsClient? rpc;
		public Argus.Agent.Application? app;
		public bool again;
		private bool streaming;

		/**
		 * Send one step on the main loop.
		 *
		 * The desktop thread cannot call the app connection.
		 * ''Relay.report'' runs from idle.
		 *
		 * @param state the step
		 * @param attempt zero the first time, then the retry count
		 */
		private void report(Argus.Rdp.State state, int attempt)
		{
			GLib.Idle.add(() => {
				try {
					this.app.connection.call(new OLLMrpc.Request() {
						method = "Relay.report",
						args = OLLMrpc.args("ii", (int) state, attempt)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				return false;
			});
		}

		/**
		 * Dial Windows on loopback and join the server as ''agent''.
		 *
		 * The app connection is not this socket. ''Relay.write''
		 * carries bytes read from port 3389. ''relay.data'' is
		 * written back to that port.
		 *
		 * @param rpc the agent's second connection
		 */
		public void open_windows(OLLMrpc.Transport.TlsClient rpc) throws GLib.Error
		{
			this.dial = new GLib.SocketClient();
			this.dial.timeout = 10;
			this.plain = this.dial.connect_to_host("127.0.0.1", 3389);
			try {
				this.app.connection.call(new OLLMrpc.Request() {
					method = "Relay.report",
					args = OLLMrpc.args("ii", (int) Argus.Rdp.State.SUCCESS_LOCAL_RDP_CONNECTED, 0)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				this.plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				GLib.warning("nodelay: %s", e.message);
			}
			this.rpc = rpc;
			this.rpc.notification.connect((notif) => {
				if (notif.method != "relay.data" || notif.args.size < 1 || this.plain == null) {
					return;
				}
				var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
				unowned uint8[] data = blob.get_data();
				if (data == null) {
					return;
				}
				size_t off = 0;
				while (off < data.length) {
					try {
						off += this.plain.output_stream.write(data[off:data.length]);
					} catch (GLib.Error e) {
						GLib.warning("desktop write: %s", e.message);
						return;
					}
				}
			});
			try {
				this.app.connection.call(new OLLMrpc.Request() {
					method = "Relay.report",
					args = OLLMrpc.args("ii", (int) Argus.Rdp.State.REQUEST_MACHINE_JOIN_RELAY, 0)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			var joined = this.rpc.call(new OLLMrpc.Request() {
				method = "Relay.join",
				args = OLLMrpc.args("s", "agent")
			});
			if (joined.error != null) {
				GLib.warning("join: %s", joined.error.message);
				try {
					this.app.connection.call(new OLLMrpc.Request() {
						method = "Relay.report",
						args = OLLMrpc.args("ii", (int) Argus.Rdp.State.RETRY_MACHINE_JOIN_REFUSED, 1)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				return;
			}
			try {
				this.app.connection.call(new OLLMrpc.Request() {
					method = "Relay.report",
					args = OLLMrpc.args("ii", (int) Argus.Rdp.State.REQUEST_MACHINE_STREAM_DATA, 0)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			this.rpc.watch();
			new GLib.Thread<int>("desktop", () => {
				this.buf = new uint8[16384];
				while (this.handle_stream()) {
				}
				return 0;
			});
		}

		/**
		 * Read one chunk from Windows and write it to the server.
		 *
		 * A cut dials port 3389 again and calls ''Relay.fresh''.
		 * That chunk is not copied.
		 *
		 * @return true when the desktop thread should read again
		 */
		private bool handle_stream()
		{
			ssize_t n = 0;
			try {
				n = this.plain.input_stream.read(this.buf);
			} catch (GLib.Error e) {
				if (!this.again) {
					GLib.warning("desktop read: %s", e.message);
					this.report(Argus.Rdp.State.RETRY_MACHINE_STREAM, 1);
					return false;
				}
			}
			if (this.again) {
				this.again = false;
				try {
					this.plain = this.dial.connect_to_host("127.0.0.1", 3389);
				} catch (GLib.Error e) {
					GLib.warning("desktop: %s", e.message);
					this.report(Argus.Rdp.State.RETRY_STREAM_FRESH_CUT, 1);
					return false;
				}
				try {
					var mark = this.rpc.call(new OLLMrpc.Request() {
						method = "Relay.fresh"
					});
					if (mark.error != null) {
						GLib.warning("fresh: %s", mark.error.message);
						this.report(Argus.Rdp.State.RETRY_STREAM_FRESH_CUT, 1);
						return false;
					}
				} catch (GLib.Error e) {
					GLib.warning("fresh: %s", e.message);
					this.report(Argus.Rdp.State.RETRY_STREAM_FRESH_CUT, 1);
					return false;
				}
				return true;
			}
			if (n <= 0) {
				this.report(Argus.Rdp.State.RETRY_MACHINE_STREAM, 1);
				return false;
			}
			var chunk = new uint8[n];
			GLib.Memory.copy((uint8[]) chunk, this.buf, n);
			var held = GLib.Value(typeof(GLib.Bytes));
			held.set_boxed(new GLib.Bytes(chunk));
			var request = new OLLMrpc.Request() {
				method = "Relay.write"
			};
			request.args.add(held);
			try {
				var response = this.rpc.call(request);
				if (response.error != null) {
					GLib.warning("desktop write: %s", response.error.message);
					this.report(Argus.Rdp.State.RETRY_MACHINE_STREAM, 1);
					return false;
				}
			} catch (GLib.Error e) {
				GLib.warning("desktop call: %s", e.message);
				this.report(Argus.Rdp.State.RETRY_MACHINE_STREAM, 1);
				return false;
			}
			if (!this.streaming) {
				this.streaming = true;
				this.report(Argus.Rdp.State.SUCCESS_MACHINE_STREAMING, 0);
			}
			return true;
		}

		/**
		 * Close the Windows socket so the read dials a new one.
		 */
		public void reopen()
		{
			this.again = true;
			if (this.plain == null) {
				return;
			}
			try {
				this.plain.close();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}
	}
}
