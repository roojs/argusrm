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
				var buf = new uint8[65536];
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

		private uint8[] buf { get; set; }
		public GLib.SocketConnection? plain;
		public OLLMrpc.Transport.TlsClient? rpc;
		public Argus.Agent.Application? app;
		public bool again;
		private bool dropped;
		private bool streaming;
		private bool reading;
		private GLib.Mutex read_lock;
		private int stream_tries;

		/**
		 * Desktop dial for this platform.
		 *
		 * Windows dials either the active sharing session or TermService.
		 * Linux has the same methods so this file compiles without a
		 * platform ifdef.
		 */
		internal Adapter adapter = new Adapter();

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
		 * Dial Windows and join the server as ''agent''.
		 *
		 * The app connection is not this socket. ''Relay.write''
		 * carries bytes read from the desktop. ''relay.data'' is
		 * written back. On Windows {@link Adapter.connect} dials
		 * TermService directly on 127.0.0.1:3389. An existing Remote
		 * Desktop session is logged off first.
		 *
		 * @param rpc the agent's second connection
		 */
		public void open_windows(OLLMrpc.Transport.TlsClient rpc) throws GLib.Error
		{
			this.adapter.logoff();
			this.plain = this.adapter.connect();
			this.plain.socket.timeout = 0;
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
			this.read_desktop(false);
		}

		/**
		 * Read the desktop on the desktop thread.
		 *
		 * ''cut'' dials Windows again and calls ''Relay.fresh''
		 * before the first read. When the read has already
		 * returned, {@link reopen} starts this again.
		 *
		 * @param cut true when this run replaces the Windows socket
		 */
		private void read_desktop(bool cut)
		{
			this.read_lock.lock();
			this.reading = true;
			this.read_lock.unlock();
			new GLib.Thread<int>("desktop", () => {
				this.desktop_loop(cut);
				return 0;
			});
		}

		/**
		 * Read until the Windows socket ends.
		 *
		 * A cut that arrives as the read returns dials again on
		 * this same thread.
		 *
		 * @param cut true when the first step is a fresh dial
		 */
		private void desktop_loop(bool cut)
		{
			if (this.buf == null) {
				this.buf = new uint8[65536];
			}
			if (cut && !this.fresh_dial()) {
				this.read_lock.lock();
				this.reading = false;
				this.read_lock.unlock();
				return;
			}
			while (true) {
				while (this.handle_stream()) {
				}
				this.read_lock.lock();
				var pending = this.again;
				if (pending) {
					this.again = false;
				} else {
					this.reading = false;
				}
				this.read_lock.unlock();
				if (!pending) {
					return;
				}
				if (!this.fresh_dial()) {
					this.read_lock.lock();
					this.reading = false;
					this.read_lock.unlock();
					return;
				}
			}
		}

		/**
		 * Open the Windows connection again after the read stopped.
		 *
		 * Three tries, then the desktop thread stops.
		 *
		 * @return true when the desktop thread should read again
		 */
		private bool redial()
		{
			this.stream_tries++;
			this.report(Argus.Rdp.State.RETRY_MACHINE_STREAM, this.stream_tries);
			if (this.stream_tries >= 3) {
				return false;
			}
			try {
				this.adapter.logoff();
				this.plain = this.adapter.connect();
				this.plain.socket.timeout = 0;
			} catch (GLib.Error e) {
				GLib.warning("desktop: %s", e.message);
				return false;
			}
			try {
				this.plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				GLib.warning("nodelay: %s", e.message);
			}
			this.streaming = false;
			return true;
		}

		/**
		 * Dial Windows again and mark that socket as the start.
		 *
		 * @return false when the dial or ''Relay.fresh'' failed
		 */
		private bool fresh_dial()
		{
			try {
				this.plain = this.adapter.connect();
				this.plain.socket.timeout = 0;
			} catch (GLib.Error e) {
				GLib.warning("desktop: %s", e.message);
				this.report(Argus.Rdp.State.RETRY_STREAM_FRESH_CUT, 1);
				return false;
			}
			try {
				this.plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				GLib.warning("nodelay: %s", e.message);
			}
			this.stream_tries = 0;
			this.streaming = false;
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
			if (this.dropped) {
				return false;
			}
			ssize_t n = 0;
			try {
				n = this.plain.input_stream.read(this.buf);
			} catch (GLib.Error e) {
				if (!this.again) {
					GLib.warning("desktop read: %s", e.message);
					return this.redial();
				}
			}
			if (this.again && !this.dropped) {
				this.again = false;
				return this.fresh_dial();
			}
			if (n <= 0) {
				GLib.warning("desktop read ended");
				return this.redial();
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
		 * Stop this desktop. The server connection is already gone.
		 *
		 * The read returns and does not dial again.
		 */
		public void retire()
		{
			this.read_lock.lock();
			this.again = false;
			this.dropped = true;
			this.read_lock.unlock();
			if (this.plain != null) {
				try {
					this.plain.close();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			var until = GLib.get_monotonic_time() + 1000000;
			while (GLib.get_monotonic_time() < until) {
				this.read_lock.lock();
				var live = this.reading;
				this.read_lock.unlock();
				if (!live) {
					return;
				}
				GLib.Thread.usleep(20000);
			}
		}

		/**
		 * Dial Windows again and call ''Relay.fresh''.
		 *
		 * A live read is closed so it notices. A read that has
		 * already returned starts a new desktop thread.
		 */
		public void reopen()
		{
			this.read_lock.lock();
			var live = this.reading;
			if (live) {
				this.again = true;
			}
			this.read_lock.unlock();
			if (live) {
				if (this.plain == null) {
					return;
				}
				try {
					this.plain.close();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				return;
			}
			this.read_desktop(true);
		}
	}
}
