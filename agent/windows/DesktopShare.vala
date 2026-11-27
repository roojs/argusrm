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

namespace Argus.Agent.Windows
{
	using Win32;

	/**
	 * Shares the active Windows desktop without user credentials.
	 *
	 * On the service side, {@link start} launches ''argus-agent.exe'' with
	 * ''--share-*'' options into the signed-in user's interactive session
	 * with SYSTEM privileges, polls for the RACS2 invitation XML, and emits
	 * {@link ready} or {@link failed}. On the worker side, {@link run}
	 * opens ''IRDPSRAPISharingSession'' via the thin COM wrapper in
	 * ''win32/desktop-share.c'' and pumps Win32 messages until {@link stop}
	 * signals the stop event or the idle timeout expires.
	 */
	public class DesktopShare : GLib.Object
	{
		/**
		 * Emitted when the sharing worker is listening and has written its ticket.
		 *
		 * @param invite RACS2 connection string XML
		 * @param password one-time invitation password
		 * @param host local IP address the sharing session bound
		 * @param port TCP port the sharing session bound
		 */
		public signal void ready(string invite, string password, string host, uint16 port);

		/**
		 * Emitted when the sharing worker could not start or timed out.
		 */
		public signal void failed();

		private int attendees = 0;
		private uint64 last_active = 0;
		private void* stop_event = null;
		private void* worker_proc = null;
		private string invite_file = "";
		private string share_pass = "";
		private uint16 chosen_port = 3399;
		private int64 poll_deadline = 0;
		private uint poll_id = 0;
		private int sequence = 0;

		/**
		 * Spawn the sharing worker in ''session'' and emit {@link ready} or {@link failed}.
		 *
		 * @param session active Windows session id
		 * @param data_dir agent data directory for the temporary invite file
		 */
		public void start(uint32 session, string data_dir)
		{
			this.stop();
			this.chosen_port = 3399;
			try {
				var probe = new GLib.SocketListener();
				GLib.SocketAddress? bound = null;
				var loopback = new GLib.InetSocketAddress(new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0);
				probe.add_address(loopback, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out bound);
				this.chosen_port = ((GLib.InetSocketAddress) bound).get_port();
				probe.close();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			var alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
			var pass_builder = new GLib.StringBuilder();
			for (var idx = 0; idx < 16; idx++) {
				pass_builder.append_c(alphabet[GLib.Random.int_range(0, alphabet.length)]);
			}
			this.share_pass = pass_builder.str;
			this.sequence++;
			var stop_name = "Global\\ArgusShareStop-%u-%d".printf(GetCurrentProcessId(), this.sequence);
			this.stop_event = CreateEventW(null, true, false, g_utf8_to_utf16(stop_name));
			this.invite_file = GLib.Path.build_filename(data_dir, "share-invite-%d.xml".printf(this.sequence));
			GLib.FileUtils.unlink(this.invite_file);
			if (!this.spawn(session, this.chosen_port, this.share_pass, this.invite_file, stop_name)) {
				this.stop();
				this.failed();
				return;
			}
			this.poll_deadline = GLib.get_monotonic_time() + 10 * 1000000;
			this.poll_id = GLib.Timeout.add(100, this.poll_invite);
		}

		/**
		 * Signal the sharing worker to stop and clean up handles and temp files.
		 */
		public void stop()
		{
			if (this.poll_id != 0) {
				GLib.Source.remove(this.poll_id);
				this.poll_id = 0;
			}
			if (this.stop_event != null) {
				SetEvent(this.stop_event);
				CloseHandle(this.stop_event);
				this.stop_event = null;
			}
			if (this.worker_proc != null) {
				WaitForSingleObject(this.worker_proc, 2000);
				TerminateProcess(this.worker_proc, 0);
				CloseHandle(this.worker_proc);
				this.worker_proc = null;
			}
			if (this.invite_file != "") {
				GLib.FileUtils.unlink(this.invite_file);
				this.invite_file = "";
			}
		}

		/**
		 * Poll for the worker's RACS2 invite XML and emit {@link ready} or {@link failed}.
		 *
		 * @return true while still waiting for the invite file, false once finished
		 */
		private bool poll_invite()
		{
			if (!GLib.FileUtils.test(this.invite_file, GLib.FileTest.EXISTS)) {
				var exited = this.worker_proc != null && WaitForSingleObject(this.worker_proc, 0) == WAIT_OBJECT_0;
				if (!exited && GLib.get_monotonic_time() < this.poll_deadline) {
					return true;
				}
				this.poll_id = 0;
				this.stop();
				this.failed();
				return false;
			}
			this.poll_id = 0;
			var invite = "";
			try {
				GLib.FileUtils.get_contents(this.invite_file, out invite);
			} catch (GLib.FileError e) {
				GLib.warning("%s", e.message);
			}
			GLib.FileUtils.unlink(this.invite_file);
			this.invite_file = "";
			if (invite == "") {
				this.stop();
				this.failed();
				return false;
			}
			var share_host = "127.0.0.1";
			var share_port = this.chosen_port;
			var l_pos = invite.index_of("<L ");
			if (l_pos < 0) {
				this.ready(invite, this.share_pass, share_host, share_port);
				return false;
			}
			var l_end = invite.index_of(">", l_pos);
			var tag = l_end > l_pos ? invite.substring(l_pos, l_end - l_pos) : invite.substring(l_pos);
			var p_pos = tag.index_of("P=\"");
			var p_end = p_pos >= 0 ? tag.index_of("\"", p_pos + 3) : -1;
			if (p_end > p_pos + 3) {
				share_port = (uint16) int.parse(tag.substring(p_pos + 3, p_end - p_pos - 3));
			}
			var n_pos = tag.index_of("N=\"");
			var n_end = n_pos >= 0 ? tag.index_of("\"", n_pos + 3) : -1;
			if (n_end > n_pos + 3) {
				share_host = tag.substring(n_pos + 3, n_end - n_pos - 3);
			}
			this.ready(invite, this.share_pass, share_host, share_port);
			return false;
		}

		/**
		 * Launch this executable as SYSTEM inside ''session'' with share flags.
		 *
		 * @param session target interactive session id
		 * @param port requested TCP port
		 * @param password one-time invitation password
		 * @param invite_path file path for the RACS2 XML
		 * @param stop_name named Win32 stop event
		 * @return true when the child process started
		 */
		private bool spawn(uint32 session, uint16 port, string password, string invite_path, string stop_name)
		{
			var exe = g_utf8_to_utf16(string.nfill(259, ' '));
			if (GetModuleFileNameW(null, exe, 260) == 0) {
				return false;
			}
			var exe_path = "";
			try {
				exe_path = exe.to_utf8();
			} catch (GLib.ConvertError e) {
				GLib.warning("%s", e.message);
				return false;
			}
			var slash = exe_path.last_index_of("\\");
			if (slash < 1) {
				return false;
			}
			void* self_tok = null;
			var access = TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_SESSIONID;
			if (!OpenProcessToken(GetCurrentProcess(), access, out self_tok)) {
				return false;
			}
			void* dup_tok = null;
			if (!DuplicateTokenEx(self_tok, MAXIMUM_ALLOWED, null, SecurityImpersonation, TokenPrimary, out dup_tok)) {
				CloseHandle(self_tok);
				return false;
			}
			CloseHandle(self_tok);
			var sid = session;
			if (!SetTokenInformation(dup_tok, TokenSessionId, (void*) (&sid), (uint32) sizeof(uint32))) {
				CloseHandle(dup_tok);
				return false;
			}
			var cmd = "\"%s\" --share-port %u --share-pass %s --share-invite \"%s\" --share-stop %s".printf(
				exe_path, port, password, invite_path, stop_name);
			string16 wide_cmd;
			string16 work_dir;
			try {
				wide_cmd = cmd.to_utf16();
				work_dir = exe_path.substring(0, slash).to_utf16();
			} catch (GLib.ConvertError e) {
				GLib.warning("%s", e.message);
				CloseHandle(dup_tok);
				return false;
			}
			var cmd_buf = new GLib.Array<uint16>();
			var cmd_len = wide_length(wide_cmd);
			for (var idx = (uint64) 0; idx < cmd_len; idx++) {
				var unit = wide_at(wide_cmd, idx);
				cmd_buf.append_val(unit);
			}
			var nul = (uint16) 0;
			cmd_buf.append_val(nul);
			var si = Win32.StartupInfo() {
				cb = (uint32) sizeof(Win32.StartupInfo),
				desktop = g_utf8_to_utf16("winsta0\\default"),
			};
			var info = ProcessInfo();
			var started = CreateProcessAsUserW(dup_tok, null, cmd_buf.data, null, null, false,
				CREATE_NO_WINDOW, null, work_dir, &si, out info);
			CloseHandle(dup_tok);
			if (started) {
				CloseHandle(info.thread);
				this.worker_proc = info.process;
			}
			return started;
		}

		/**
		 * Run the sharing session until stopped or idle for 3 minutes.
		 *
		 * @param port TCP port for the sharing session
		 * @param password one-time invitation password
		 * @param invite_file path where the RACS2 XML is written
		 * @param stop_event named Win32 event signaling shutdown
		 * @return 0 on clean exit, non-zero on failure
		 */
		public int run(uint16 port, string password, string invite_file, string stop_event)
		{
			var stop_handle = OpenEventW(SYNCHRONIZE, false, g_utf8_to_utf16(stop_event));
			this.last_active = GetTickCount64();
			var share = argus_rdp_share_open(port, password, (dispid) => {
				switch (dispid) {
					case 301:
						this.attendees++;
						this.last_active = GetTickCount64();
						break;

					case 302:
						if (this.attendees > 0) {
							this.attendees--;
						}
						this.last_active = GetTickCount64();
						break;

					case 309:
						this.last_active = GetTickCount64();
						break;

					default:
						break;
				}
			});
			if (share == null) {
				if (stop_handle != null) {
					CloseHandle(stop_handle);
				}
				return 1;
			}
			try {
				GLib.FileUtils.set_contents(invite_file, argus_rdp_share_invite(share));
			} catch (GLib.FileError e) {
				GLib.warning("%s", e.message);
				argus_rdp_share_close(share);
				if (stop_handle != null) {
					CloseHandle(stop_handle);
				}
				return 2;
			}
			var handles = new void*[1];
			handles[0] = stop_handle;
			var quit = false;
			while (!quit) {
				var count = stop_handle != null ? (uint32) 1 : (uint32) 0;
				var wr = MsgWaitForMultipleObjects(count, handles, false, 500, QS_ALLINPUT);
				if (stop_handle != null && wr == WAIT_OBJECT_0) {
					break;
				}
				while (true) {
					var msg = Msg();
					if (!PeekMessageW(out msg, null, 0, 0, PM_REMOVE)) {
						break;
					}
					if (msg.message == WM_QUIT) {
						quit = true;
						break;
					}
					TranslateMessage(&msg);
					DispatchMessageW(&msg);
				}
				if (this.attendees == 0 && GetTickCount64() - this.last_active > 180000) {
					break;
				}
			}
			argus_rdp_share_close(share);
			if (stop_handle != null) {
				CloseHandle(stop_handle);
			}
			return 0;
		}
	}
}
