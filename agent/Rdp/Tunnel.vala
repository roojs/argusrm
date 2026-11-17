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
	}
}
