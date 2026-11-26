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

namespace Argus.Controller.Rdp
{
	/**
	 * Carries a local FreeRDP client to the relay.
	 *
	 * The viewer binds a loopback port. sdl-freerdp3 connects there.
	 * This class then opens a {@link OLLMrpc.Transport.TlsClient}
	 * and joins as ''view''. Bytes from the client are
	 * ''Relay.write'' chunks. ''relay.data'' notifications are
	 * written back to the client. {@link Argus.Agent.Rdp.Tunnel}
	 * is the other end. {@link Argus.Server.Rdp.Relay} pairs them.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var viewer = new Argus.Controller.Rdp.Viewer();
	 * viewer.run(dir, relay_port, view_port);
	 * }}}
	 */
	public class Viewer : GLib.Object
	{
		public uint16 view_port { get; private set; }
		/**
		 * The second connection could not be opened.
		 *
		 * A refused ''Relay.view'' is reported by the server. This
		 * signal is the case the server never saw.
		 *
		 * @param message the transport error
		 */
		public signal void failed(string message);
		private OLLMrpc.Transport.TlsClient rpc;
		private GLib.SocketConnection? plain;
		/**
		 * Accept one FreeRDP client and copy until that socket closes.
		 *
		 * @param dir directory of the view certificate and ca.crt
		 * @param relay_port relay listen port
		 * @param view_port loopback port sdl-freerdp3 connects to
		 */
		public void run(string dir, uint16 relay_port, uint16 view_port) throws GLib.Error
		{
			var listener = new GLib.SocketListener();
			var where = new GLib.InetSocketAddress(
				new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), view_port);
			listener.add_address(where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, null);
			stderr.printf("view listening %u\n", view_port);
			var plain = listener.accept(null);
			try {
				plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				stderr.printf("nodelay: %s\n", e.message);
			}
			stderr.printf("view accepted %u\n", view_port);
			this.carry(dir, relay_port, plain);
		}

		void carry(string dir, uint16 relay_port, GLib.SocketConnection plain) throws GLib.Error
		{
			var rpc = new OLLMrpc.Transport.TlsClient("127.0.0.1", relay_port) {
				tls_certificate = new GLib.TlsCertificate.from_files(
					GLib.Path.build_filename(dir, "view.crt"),
					GLib.Path.build_filename(dir, "view.key")),
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
						stderr.printf("view tcp write: %s\n", e.message);
						return;
					}
				}
			});
			rpc.open();
			stderr.printf("view opened\n");
			var joined = rpc.call(new OLLMrpc.Request() {
				method = "Relay.join",
				args = OLLMrpc.args("s", "view")
			});
			if (joined.error != null) {
				stderr.printf("join: %s\n", joined.error.message);
				return;
			}
			stderr.printf("view joined\n");
			rpc.watch();
			new GLib.Thread<int>("view", () => {
				var buf = new uint8[16384];
				while (true) {
					ssize_t n = 0;
					try {
						n = plain.input_stream.read(buf);
					} catch (GLib.Error e) {
						stderr.printf("view tcp read: %s\n", e.message);
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
							stderr.printf("view write: %s\n", response.error.message);
							break;
						}
					} catch (GLib.Error e) {
						stderr.printf("view call: %s\n", e.message);
						break;
					}
				}
				GLib.Process.exit(0);
			});
			new GLib.MainLoop().run();
		}

		/**
		 * Listen on loopback and carry that socket to one agent.
		 *
		 * {@link view_port} is set before this returns. FreeRDP
		 * connects there. ''Relay.view'' is the join. A second
		 * open waits until the machine starts the desktop again,
		 * so this socket has no read timeout. ''run'' is the
		 * test and is not this method.
		 *
		 * @param host server that answered
		 * @param port server port
		 * @param certificate this controller's certificate
		 * @param database the server CA
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void serve(
			string host,
			uint16 port,
			GLib.TlsCertificate certificate,
			GLib.TlsDatabase database,
			int agent_id
		) throws GLib.Error
		{
			var listener = new GLib.SocketListener();
			var where = new GLib.InetSocketAddress(
				new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0);
			GLib.SocketAddress? bound = null;
			listener.add_address(
				where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out bound);
			this.view_port = ((GLib.InetSocketAddress) bound).get_port();
			this.rpc = new OLLMrpc.Transport.TlsClient(host, port) {
				tls_certificate = certificate,
				tls_database = database,
				timeout = 0
			};
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
						GLib.warning("%s", e.message);
						return;
					}
				}
			});
			this.rpc.watch();
			new GLib.Thread<int>("view", () => {
				this.view(listener, agent_id);
				return 0;
			});
		}

		/**
		 * Join one agent and copy until that socket closes.
		 *
		 * This is the view thread. A closed socket is accepted
		 * again, up to three times. ''Relay.view'', the accept,
		 * the read, and ''Relay.write'' each have their own try.
		 *
		 * @param listener the loopback listen
		 * @param agent_id ''agent.id'' of the machine
		 */
		private void view(GLib.SocketListener listener, int agent_id)
		{
			OLLMrpc.Response joined;
			try {
				joined = this.rpc.call(new OLLMrpc.Request() {
					method = "Relay.view",
					args = OLLMrpc.args("i", agent_id)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				var message = e.message;
				GLib.Idle.add(() => {
					this.failed(message);
					return false;
				});
				return;
			}
			if (joined.error != null) {
				GLib.warning("%s", joined.error.message);
				return;
			}
			for (var round = 0; round < 3; round++) {
				try {
					this.plain = listener.accept(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				try {
					this.plain.socket.set_option(6, 1, 1);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				var buf = new uint8[16384];
				var open = true;
				while (open) {
					ssize_t n = 0;
					try {
						n = this.plain.input_stream.read(buf);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						open = false;
						continue;
					}
					if (n <= 0) {
						open = false;
						continue;
					}
					var chunk = new uint8[n];
					GLib.Memory.copy((uint8[]) chunk, buf, n);
					var held = GLib.Value(typeof(GLib.Bytes));
					held.set_boxed(new GLib.Bytes(chunk));
					var request = new OLLMrpc.Request() {
						method = "Relay.write"
					};
					request.args.add(held);
					OLLMrpc.Response response;
					try {
						response = this.rpc.call(request);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						return;
					}
					if (response.error != null) {
						GLib.warning("%s", response.error.message);
						return;
					}
				}
			}
		}
	}
}
