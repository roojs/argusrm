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
	 * Test copy of ''OLLMrpc.Transport.TlsClient''.
	 * {@link sync-lag} and {@link command} compile this file, not
	 * the library class. Do not edit OLLMchat from this tree.
	 */
	public class TlsClient : GLib.Object
	{
		public string host { get; construct; }
		public uint16 port { get; construct; }
		public bool accept_any = false;
		public uint timeout = 10;
		public GLib.TlsCertificate? tls_certificate { get; set; default = null; }
		public GLib.TlsDatabase? tls_database { get; set; default = null; }
		public signal void notification(OLLMrpc.Notification notif);

		private bool connected = false;
		private int fd = -1;
		private uint watch_id = 0;
		private bool watching = false;
		private GLib.Mutex mutex;
		private GLib.SocketConnection? socket = null;
		private GLib.TlsClientConnection? connection = null;
		private OLLMrpc.Bin.Stream bin {
			get; set; default = new OLLMrpc.Bin.Stream(null, null, false);
		}

		public TlsClient(string host, uint16 port)
		{
			GLib.Object(host: host, port: port);
		}

		public void open() throws GLib.Error
		{
			if (this.connected) {
				return;
			}
			var client = new GLib.SocketClient();
			client.timeout = this.timeout;
			var conn = client.connect_to_host(this.host, this.port);
			conn.socket.blocking = true;
			var tls = GLib.TlsClientConnection.@new(conn, null);
			if (this.tls_certificate != null) {
				tls.set_certificate(this.tls_certificate);
			}
			if (this.accept_any) {
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
			}
			if (!this.accept_any) {
				if (this.tls_database != null) {
					tls.database = this.tls_database;
				}
				tls.accept_certificate.connect((peer_cert, errors) => {
					return peer_cert != null &&
						(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
			}
			tls.handshake();
			this.bin.in_stream = new GLib.DataInputStream(tls.get_input_stream());
			this.bin.in_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			this.bin.out_stream = new GLib.DataOutputStream(tls.get_output_stream());
			this.bin.out_stream.set_byte_order(GLib.DataStreamByteOrder.BIG_ENDIAN);
			this.socket = conn;
			this.connection = tls;
			this.fd = conn.socket.fd;
			this.connected = true;
		}

		public OLLMrpc.Response call(OLLMrpc.Request request) throws GLib.Error
		{
			this.open();
			if (this.watch_id != 0) {
				GLib.Source.remove(this.watch_id);
				this.watch_id = 0;
			}
			this.socket.socket.blocking = true;
			this.mutex.lock();
			this.bin.write(request);
			var reply_wait = GLib.get_monotonic_time() + 10 * 1000000;
			while (true) {
				try {
					var parsed = this.bin.parse();
					var notif = parsed as OLLMrpc.Notification;
					if (notif != null) {
						this.notification(notif);
						continue;
					}
					if (!(parsed is OLLMrpc.Response)) {
						continue;
					}
					this.mutex.unlock();
					if (this.watching) {
						GLib.Idle.add(() => {
							this.watch();
							return false;
						});
					}
					return (OLLMrpc.Response) parsed;
				} catch (GLib.IOError e) {
					if (e.code != GLib.IOError.WOULD_BLOCK ||
						GLib.get_monotonic_time() >= reply_wait) {
						this.mutex.unlock();
						if (this.watching) {
							GLib.Idle.add(() => {
								this.watch();
								return false;
							});
						}
						throw e;
					}
					var reply_poll = GLib.PollFD();
					reply_poll.fd = this.fd;
					reply_poll.events = GLib.IOCondition.IN;
					GLib.poll(new GLib.PollFD[] { reply_poll }, 200);
				}
			}
		}

		public void watch()
		{
			if (this.watch_id != 0) {
				return;
			}
			this.watching = true;
			this.open();
			this.socket.socket.blocking = false;
			this.watch_id = GLib.Timeout.add(50, () => {
				if (this.watch_id == 0) {
					return false;
				}
				this.mutex.lock();
				if (this.watch_id == 0) {
					this.mutex.unlock();
					return false;
				}
				this.socket.socket.blocking = false;
				if (this.bin.in_stream.get_available() < 1) {
					var pollable = this.connection.get_input_stream()
						as GLib.PollableInputStream;
					if (pollable == null || !pollable.is_readable()) {
						this.mutex.unlock();
						return true;
					}
				}
				try {
					var parsed = this.bin.parse();
					var notif = parsed as OLLMrpc.Notification;
					if (notif != null) {
						this.notification(notif);
					}
				} catch (GLib.Error e) {
					if (e.code == GLib.IOError.WOULD_BLOCK ||
						e.code == GLib.IOError.TIMED_OUT) {
						this.mutex.unlock();
						return true;
					}
					GLib.warning("%s", e.message);
					this.watch_id = 0;
					this.mutex.unlock();
					return false;
				}
				this.mutex.unlock();
				return true;
			});
		}
	}
}
