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
	 * Blank header for a segment from 10.200.0.1 to port 3389.
	 *
	 * The first 40 bytes are the IPv4 and TCP header. Bytes
	 * 40-51 are the TCP pseudo-header. Bytes 52-55 are the
	 * MSS option. Length, checksum, port, sequence, and flags
	 * are written over the copy.
	 */
	private const uint8[] header = {
		0x45, 0x00, 0x00, 0x00,
		0x12, 0x34, 0x00, 0x00,
		64, 6, 0x00, 0x00,
		0x0a, 0xc8, 0x00, 0x01,
		0x0a, 0xc8, 0x00, 0x02,
		0x00, 0x00, 0x0d, 0x3d,
		0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00,
		0x50, 0x00, 0xff, 0xff,
		0x00, 0x00, 0x00, 0x00,
		0x0a, 0xc8, 0x00, 0x01,
		0x0a, 0xc8, 0x00, 0x02,
		0x00, 6, 0x00, 0x00,
		2, 4, 0x05, 0xb4
	};

	/**
	 * Virtual adapter that presents the desktop peer as 10.200.0.1.
	 *
	 * {@link Tunnel} keeps a loopback {@link GLib.SocketConnection}.
	 * This class owns the Wintun adapter and the IPv4 TCP that
	 * TermService accepts on 10.200.0.2:3389. One adapter stays up
	 * for the process. Each {@link connect} is one TCP connection.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var adapter = new Argus.Agent.Rdp.Adapter();
	 * var desktop = adapter.connect();
	 * }}}
	 */
	public class Adapter : GLib.Object
	{
		/**
		 * Host address dialed by {@link connect} when Wintun is off.
		 */
		public string target_host = "127.0.0.1";
		/**
		 * TCP port dialed by {@link connect} when Wintun is off.
		 */
		public uint16 target_port = 3389;
		/**
		 * Skip logging off existing RDP sessions when sharing an active desktop.
		 */
		public bool skip_logoff = false;
		private bool use_wintun = false;
		private void* module;
		private void* wintun_adapter;
		private void* session;
		private Win32.WintunCreateAdapter create_adapter;
		private Win32.WintunOpenAdapter open_adapter;
		private Win32.WintunCloseAdapter close_adapter;
		private Win32.WintunGetLuid get_luid;
		private Win32.WintunStartSession start_session;
		private Win32.WintunReceive receive_packet;
		private Win32.WintunRelease release_packet;
		private Win32.WintunAllocSend alloc_send;
		private Win32.WintunSend send_packet;
		private Win32.WintunWait wait_event;
		private uint16 src_port = 51421;
		private uint32 snd_nxt;
		private uint32 rcv_nxt;
		private uint32 snd_una;
		private uint32 hold_seq;
		private uint16 peer_window = 65535;
		private int64 hold_at;
		private bool up;
		private bool rst;
		private bool need_ack;
		private bool peer_fin;
		private bool fin_sent;
		private bool local_eof;
		private bool busy;
		private bool stop;
		private uint8[] hold = new uint8[0];
		private uint8[] inbox = new uint8[0];
		private uint8[] pending = new uint8[0];

		/**
		 * Log off existing Remote Desktop sessions.
		 *
		 * The open and the short-read redial call this. A fresh
		 * cut does not.
		 */
		public void logoff()
		{
			if (this.skip_logoff) {
				return;
			}
			Win32.argus_end_rdp_sessions();
		}

		/**
		 * Open one desktop connection on Windows.
		 *
		 * Connects directly to {@link target_host}:{@link target_port}
		 * while Wintun is disabled. When {@link use_wintun} is enabled,
		 * opens the virtual adapter so TermService sees 10.200.0.1.
		 *
		 * @return the desktop socket
		 * @throws GLib.Error when the connect or adapter setup fails
		 */
		public new GLib.SocketConnection connect() throws GLib.Error
		{
			if (!this.use_wintun) {
				var client = new GLib.SocketClient();
				client.timeout = 10;
				return client.connect_to_host(this.target_host, this.target_port);
			}
			this.ensure();
			this.stop = true;
			while (this.busy) {
				GLib.Thread.usleep(20000);
			}
			this.stop = false;
			var listener = new GLib.SocketListener();
			GLib.SocketAddress bound;
			listener.add_address(
				new GLib.InetSocketAddress(
					new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0),
				GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out bound);
			var accept_thread = new GLib.Thread<GLib.SocketConnection?>("accept", () => {
				try {
					return listener.accept();
				} catch (GLib.Error e) {
					return null;
				}
			});
			GLib.SocketConnection local;
			try {
				local = new GLib.SocketClient().connect_to_host("127.0.0.1",
					((GLib.InetSocketAddress) bound).get_port());
			} catch (GLib.Error e) {
				listener.close();
				accept_thread.join();
				throw e;
			}
			var accepted = accept_thread.join();
			listener.close();
			if (accepted == null) {
				throw new GLib.IOError.FAILED("accept failed");
			}
			this.busy = true;
			new GLib.Thread<int>("adapter", () => {
				this.splice(accepted);
				this.busy = false;
				return 0;
			});
			return local;
		}

		/**
		 * Load the adapter and start its Wintun session once.
		 *
		 * A later call returns when the session is already up.
		 *
		 * @throws GLib.Error when the DLL, the adapter, or a row fails
		 */
		private void ensure() throws GLib.Error
		{
			if (this.session != null) {
				return;
			}
			this.load();
			var leftover = this.open_adapter(Win32.g_utf8_to_utf16("ArgusWintun0"));
			if (leftover != null) {
				this.close_adapter(leftover);
				GLib.Thread.usleep(300000);
			}
			this.wintun_adapter = this.create_adapter(
				Win32.g_utf8_to_utf16("ArgusWintun0"),
				Win32.g_utf8_to_utf16("ArgusTunnel"), null);
			if (this.wintun_adapter == null) {
				throw new GLib.IOError.FAILED("create adapter failed");
			}
			var luid = (uint64) 0;
			this.get_luid(this.wintun_adapter, out luid);
			var status = Win32.argus_adapter_address(luid, "10.200.0.2", 32);
			if (status != 0 && status != Win32.ERROR_OBJECT_ALREADY_EXISTS) {
				throw new GLib.IOError.FAILED("address status " + status.to_string());
			}
			status = Win32.argus_adapter_route(luid, "10.200.0.1");
			if (status != 0 && status != Win32.ERROR_OBJECT_ALREADY_EXISTS) {
				throw new GLib.IOError.FAILED("route status " + status.to_string());
			}
			status = Win32.argus_adapter_neighbor(luid, "10.200.0.1");
			if (status != 0 && status != Win32.ERROR_OBJECT_ALREADY_EXISTS) {
				throw new GLib.IOError.FAILED("neighbor status " + status.to_string());
			}
			this.session = this.start_session(this.wintun_adapter, 0x400000);
			if (this.session == null) {
				throw new GLib.IOError.FAILED("start session failed");
			}
		}

		/**
		 * Load wintun.dll from the exe directory and resolve its exports.
		 *
		 * @throws GLib.Error when the DLL or an export is missing
		 */
		private void load() throws GLib.Error
		{
			if (this.module != null) {
				return;
			}
			var exe = Win32.g_utf8_to_utf16(string.nfill(259, ' '));
			if (Win32.GetModuleFileNameW(null, exe, 260) == 0) {
				throw new GLib.IOError.FAILED("agent path unavailable");
			}
			var path = "";
			try {
				path = exe.to_utf8();
			} catch (GLib.ConvertError e) {
				throw new GLib.IOError.FAILED(e.message);
			}
			var slash = path.last_index_of("\\");
			if (slash < 1) {
				throw new GLib.IOError.FAILED("agent path unavailable");
			}
			this.module = Win32.LoadLibraryW(Win32.g_utf8_to_utf16(
				path.substring(0, slash) + "\\wintun.dll"));
			if (this.module == null) {
				var err = Win32.GetLastError();
				throw new GLib.IOError.FAILED("load wintun.dll failed " + err.to_string());
			}
			var create_raw = Win32.GetProcAddress(this.module, "WintunCreateAdapter");
			if (create_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.create_adapter = (Win32.WintunCreateAdapter) create_raw;
			var open_raw = Win32.GetProcAddress(this.module, "WintunOpenAdapter");
			if (open_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.open_adapter = (Win32.WintunOpenAdapter) open_raw;
			var close_raw = Win32.GetProcAddress(this.module, "WintunCloseAdapter");
			if (close_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.close_adapter = (Win32.WintunCloseAdapter) close_raw;
			var luid_raw = Win32.GetProcAddress(this.module, "WintunGetAdapterLUID");
			if (luid_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.get_luid = (Win32.WintunGetLuid) luid_raw;
			var start_raw = Win32.GetProcAddress(this.module, "WintunStartSession");
			if (start_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.start_session = (Win32.WintunStartSession) start_raw;
			var receive_raw = Win32.GetProcAddress(this.module, "WintunReceivePacket");
			if (receive_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.receive_packet = (Win32.WintunReceive) receive_raw;
			var release_raw = Win32.GetProcAddress(this.module, "WintunReleaseReceivePacket");
			if (release_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.release_packet = (Win32.WintunRelease) release_raw;
			var alloc_raw = Win32.GetProcAddress(this.module, "WintunAllocateSendPacket");
			if (alloc_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.alloc_send = (Win32.WintunAllocSend) alloc_raw;
			var send_raw = Win32.GetProcAddress(this.module, "WintunSendPacket");
			if (send_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.send_packet = (Win32.WintunSend) send_raw;
			var wait_raw = Win32.GetProcAddress(this.module, "WintunGetReadWaitEvent");
			if (wait_raw == null) {
				throw new GLib.IOError.FAILED("missing wintun export");
			}
			this.wait_event = (Win32.WintunWait) wait_raw;
		}

		/**
		 * Copy bytes between the accepted loopback socket and TermService.
		 *
		 * Source address is 10.200.0.1. Destination is 10.200.0.2 port
		 * 3389. The thread stays up until the socket closes.
		 *
		 * @param accepted the listener side of the loopback pair
		 */
		private void splice(GLib.SocketConnection accepted)
		{
			this.src_port++;
			if (this.src_port < 51422) {
				this.src_port = 51422;
			}
			this.snd_nxt = 0x10000001;
			this.rcv_nxt = 0;
			this.snd_una = 0x10000001;
			this.hold_seq = 0x10000001;
			this.peer_window = 65535;
			this.up = false;
			this.rst = false;
			this.need_ack = false;
			this.peer_fin = false;
			this.fin_sent = false;
			this.local_eof = false;
			this.hold = new uint8[0];
			this.inbox = new uint8[0];
			this.pending = new uint8[0];
			accepted.socket.set_blocking(false);
			try {
				accepted.socket.set_option(6, 1, 1);
			} catch (GLib.Error err) {
				GLib.warning("nodelay: %s", err.message);
			}
			this.send_tcp(0x10000000, 0x02, new uint8[0], true);
			var syn_at = GLib.get_monotonic_time();
			var syn_again = false;
			while (!this.stop && !this.rst) {
				while (true) {
					var size = (uint32) 0;
					var pkt = this.receive_packet(this.session, out size);
					if (pkt == null) {
						if (Win32.GetLastError() != Win32.ERROR_NO_MORE_ITEMS) {
							this.rst = true;
						}
						break;
					}
					var raw = new uint8[size];
					Win32.argus_adapter_read(raw, pkt, size);
					this.release_packet(this.session, pkt);
					this.on_packet(raw);
				}
				if (this.rst) {
					break;
				}
				if (this.need_ack && this.up) {
					this.send_tcp(this.snd_nxt, 0x10, new uint8[0], false);
				}
				if (!this.up) {
					if (GLib.get_monotonic_time() - syn_at > 1000000) {
						if (syn_again) {
							this.rst = true;
							break;
						}
						this.send_tcp(0x10000000, 0x02, new uint8[0], true);
						syn_again = true;
						syn_at = GLib.get_monotonic_time();
					}
					var ev = this.wait_event(this.session);
					if (ev == null) {
						GLib.Thread.usleep(20000);
					}
					if (ev != null) {
						Win32.WaitForSingleObject(ev, 20);
					}
					continue;
				}
				if (this.inbox.length > 0) {
					try {
						var wrote = accepted.socket.send(this.inbox);
						if (wrote > 0) {
							this.inbox = this.inbox[(int) wrote:this.inbox.length];
						}
					} catch (GLib.IOError.WOULD_BLOCK err) {
					} catch (GLib.Error err) {
						this.local_eof = true;
						this.inbox = new uint8[0];
					}
				}
				if (!this.local_eof && this.pending.length < 65536) {
					var chunk = new uint8[1460];
					try {
						var n = accepted.socket.receive(chunk);
						if (n == 0) {
							this.local_eof = true;
						}
						if (n > 0) {
							var got = chunk[0:n];
							var merged = new uint8[this.pending.length + got.length];
							if (this.pending.length > 0) {
								Win32.argus_adapter_move(merged, 0, this.pending, this.pending.length);
							}
							Win32.argus_adapter_move(merged, this.pending.length, got, got.length);
							this.pending = merged;
						}
					} catch (GLib.IOError.WOULD_BLOCK err) {
					} catch (GLib.Error err) {
						this.local_eof = true;
					}
				}
				var flight = (int) (this.snd_nxt - this.snd_una);
				var room = (int) this.peer_window - flight;
				if (room > 1460) {
					room = 1460;
				}
				if (room > this.pending.length) {
					room = this.pending.length;
				}
				if (room > 0) {
					if (this.hold.length == 0) {
						this.hold_seq = this.snd_nxt;
					}
					var slice = this.pending[0:room];
					this.send_tcp(this.snd_nxt, 0x18, slice, false);
					var held = new uint8[this.hold.length + slice.length];
					if (this.hold.length > 0) {
						Win32.argus_adapter_move(held, 0, this.hold, this.hold.length);
					}
					Win32.argus_adapter_move(held, this.hold.length, slice, slice.length);
					this.hold = held;
					this.snd_nxt += (uint32) slice.length;
					this.pending = this.pending[room:this.pending.length];
					this.hold_at = GLib.get_monotonic_time();
				}
				if (this.hold.length > 0 && GLib.get_monotonic_time() - this.hold_at > 200000) {
					var n = this.hold.length;
					if (n > 1460) {
						n = 1460;
					}
					this.send_tcp(this.hold_seq, 0x18, this.hold[0:n], false);
					this.hold_at = GLib.get_monotonic_time();
				}
				if (this.local_eof && this.pending.length == 0 &&
					this.hold.length == 0 && !this.fin_sent) {
					this.send_tcp(this.snd_nxt, 0x11, new uint8[0], false);
					this.snd_nxt += 1;
					this.fin_sent = true;
				}
				if (this.peer_fin && this.inbox.length == 0) {
					break;
				}
				var wait_ev = this.wait_event(this.session);
				if (wait_ev == null) {
					GLib.Thread.usleep(20000);
				}
				if (wait_ev != null) {
					Win32.WaitForSingleObject(wait_ev, 20);
				}
			}
			if (this.rst) {
				GLib.warning("desktop tcp reset");
			} else if (this.peer_fin) {
				GLib.warning("desktop tcp closed by windows");
			} else if (this.local_eof) {
				GLib.warning("desktop tcp closed locally");
			}
			if (!this.rst && !this.up) {
				this.send_tcp(this.snd_nxt, 0x04, new uint8[0], false);
			}
			if (!this.rst && this.up && !this.fin_sent) {
				this.send_tcp(this.snd_nxt, 0x11, new uint8[0], false);
				this.fin_sent = true;
			}
			try {
				accepted.close();
			} catch (GLib.Error err) {
				GLib.warning("%s", err.message);
			}
		}

		/**
		 * Inject one TCP segment from 10.200.0.1 to 10.200.0.2:3389.
		 *
		 * @param seq sequence number of the first byte
		 * @param flags TCP flags
		 * @param payload bytes after the TCP header
		 * @param syn true when the segment includes the MSS option
		 */
		private void send_tcp(uint32 seq, uint8 flags, uint8[] payload, bool syn)
		{
			var opt = 0;
			if (syn) {
				opt = 4;
			}
			var tcp_len = 20 + opt + payload.length;
			var total = 20 + tcp_len;
			var pkt = new uint8[total];
			GLib.Memory.copy((uint8[]) pkt, header, 40);
			pkt[2] = (uint8) (total >> 8);
			pkt[3] = (uint8) total;
			pkt[20] = (uint8) (this.src_port >> 8);
			pkt[21] = (uint8) this.src_port;
			pkt[24] = (uint8) (seq >> 24);
			pkt[25] = (uint8) (seq >> 16);
			pkt[26] = (uint8) (seq >> 8);
			pkt[27] = (uint8) seq;
			pkt[28] = (uint8) (this.rcv_nxt >> 24);
			pkt[29] = (uint8) (this.rcv_nxt >> 16);
			pkt[30] = (uint8) (this.rcv_nxt >> 8);
			pkt[31] = (uint8) this.rcv_nxt;
			pkt[32] = (uint8) (((20 + opt) / 4) << 4);
			pkt[33] = flags;
			var sum = (uint32) 0;
			var i = 0;
			while (i + 1 < 20) {
				sum += ((uint32) pkt[i] << 8) | pkt[i + 1];
				i += 2;
			}
			while ((sum >> 16) != 0) {
				sum = (sum & 0xffff) + (sum >> 16);
			}
			sum = (~sum) & 0xffff;
			pkt[10] = (uint8) ((sum >> 8) & 0xff);
			pkt[11] = (uint8) (sum & 0xff);
			if (syn) {
				Win32.argus_adapter_move(pkt, 40, header[52:56], 4);
			}
			if (payload.length > 0) {
				Win32.argus_adapter_move(pkt, (uint32) (40 + opt), payload, (uint32) payload.length);
			}
			var pseudo = header[40:52];
			pseudo[10] = (uint8) (tcp_len >> 8);
			pseudo[11] = (uint8) tcp_len;
			sum = 0;
			i = 0;
			while (i + 1 < 12) {
				sum += ((uint32) pseudo[i] << 8) | pseudo[i + 1];
				i += 2;
			}
			i = 0;
			while (i + 1 < tcp_len) {
				sum += ((uint32) pkt[20 + i] << 8) | pkt[20 + i + 1];
				i += 2;
			}
			if (i < tcp_len) {
				sum += (uint32) pkt[20 + i] << 8;
			}
			while ((sum >> 16) != 0) {
				sum = (sum & 0xffff) + (sum >> 16);
			}
			sum = (~sum) & 0xffff;
			pkt[36] = (uint8) ((sum >> 8) & 0xff);
			pkt[37] = (uint8) (sum & 0xff);
			var dst = this.alloc_send(this.session, (uint32) total);
			if (dst == null) {
				return;
			}
			Win32.argus_adapter_write(dst, pkt, (uint32) total);
			this.send_packet(this.session, dst);
			this.need_ack = false;
		}

		/**
		 * Take one IPv4 packet from the adapter and update this TCP.
		 *
		 * In-order payload is queued for the loopback socket. An ACK
		 * drops bytes the peer has accepted.
		 *
		 * @param pkt the raw IPv4 packet
		 */
		private void on_packet(uint8[] pkt)
		{
			if (pkt.length < 20 || (pkt[0] >> 4) != 4) {
				return;
			}
			var ihl = (int) (pkt[0] & 0x0f) * 4;
			if (ihl < 20 || pkt.length < ihl) {
				return;
			}
			var total = ((int) pkt[2] << 8) | (int) pkt[3];
			if (total < ihl || total > pkt.length) {
				total = (int) pkt.length;
			}
			if (pkt[9] != 6) {
				return;
			}
			var frag = ((int) pkt[6] << 8) | (int) pkt[7];
			if ((frag & 0x1fff) != 0) {
				return;
			}
			if (pkt[12] != 0x0a || pkt[13] != 0xc8 || pkt[14] != 0x00 || pkt[15] != 0x02) {
				return;
			}
			if (pkt[16] != 0x0a || pkt[17] != 0xc8 || pkt[18] != 0x00 || pkt[19] != 0x01) {
				return;
			}
			if (total < ihl + 20) {
				return;
			}
			var sport = ((uint16) pkt[ihl] << 8) | (uint16) pkt[ihl + 1];
			var dport = ((uint16) pkt[ihl + 2] << 8) | (uint16) pkt[ihl + 3];
			if (sport != 3389 || dport != this.src_port) {
				return;
			}
			var seq = ((uint32) pkt[ihl + 4] << 24) | ((uint32) pkt[ihl + 5] << 16) |
				((uint32) pkt[ihl + 6] << 8) | (uint32) pkt[ihl + 7];
			var ack = ((uint32) pkt[ihl + 8] << 24) | ((uint32) pkt[ihl + 9] << 16) |
				((uint32) pkt[ihl + 10] << 8) | (uint32) pkt[ihl + 11];
			var off = (int) (pkt[ihl + 12] >> 4) * 4;
			var flags = pkt[ihl + 13];
			if (off < 20 || ihl + off > total) {
				return;
			}
			if ((flags & 0x04) != 0) {
				this.rst = true;
				return;
			}
			if ((flags & 0x12) == 0x12) {
				if (ack != this.snd_nxt) {
					return;
				}
				this.rcv_nxt = seq + 1;
				this.up = true;
				this.need_ack = true;
			}
			var payload_seq = seq;
			if ((flags & 0x02) != 0) {
				payload_seq = seq + 1;
			}
			var data_len = total - ihl - off;
			var took = false;
			if (data_len > 0 && payload_seq == this.rcv_nxt) {
				var data = pkt[ihl + off:ihl + off + data_len];
				var merged = new uint8[this.inbox.length + data.length];
				if (this.inbox.length > 0) {
					Win32.argus_adapter_move(merged, 0, this.inbox, this.inbox.length);
				}
				Win32.argus_adapter_move(merged, this.inbox.length, data, data.length);
				this.inbox = merged;
				this.rcv_nxt += (uint32) data_len;
				this.need_ack = true;
				took = true;
			}
			if (data_len > 0 && !took) {
				this.need_ack = true;
			}
			var fin_seq = payload_seq;
			if (took) {
				fin_seq = this.rcv_nxt;
			}
			if ((flags & 0x01) != 0 && fin_seq == this.rcv_nxt) {
				this.rcv_nxt += 1;
				this.need_ack = true;
				this.peer_fin = true;
			}
			if ((flags & 0x10) != 0) {
				this.snd_una = ack;
				this.peer_window = ((uint16) pkt[ihl + 14] << 8) | (uint16) pkt[ihl + 15];
				var acked = (int) (ack - this.hold_seq);
				if (this.hold.length > 0 && acked > 0 && acked >= this.hold.length) {
					this.hold = new uint8[0];
					this.hold_seq = ack;
				}
				if (this.hold.length > 0 && acked > 0 && acked < this.hold.length) {
					this.hold = this.hold[acked:this.hold.length];
					this.hold_seq = ack;
				}
			}
		}
	}
}
