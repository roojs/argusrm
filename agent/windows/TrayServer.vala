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
	 * Local TCP RPC server and process supervisor for ''argus-tray.exe''.
	 *
	 * Listens on ''127.0.0.1:4142'' to serve the ''AgentService'' RPC
	 * methods, broadcasts ''agent.status'' when the server link changes,
	 * and checks every five seconds that ''argus-tray.exe'' is running in
	 * the active interactive user session.
	 */
	public class TrayServer : GLib.Object
	{
		internal bool connected = false;
		internal OLLMrpc.Transport.TcpListen local_listen;
		private Argus.Agent.Application application;
		private unowned Service service;
		private uint tick_id = 0;
		private int ticks = 0;

		/**
		 * Start listening for tray clients and supervising ''argus-tray.exe''.
		 *
		 * @param application owning agent application
		 * @param service owning Windows service
		 */
		internal void start(Argus.Agent.Application application, Service service)
		{
			this.application = application;
			this.service = service;
			OLLMrpc.Request.add_class(
				"AgentService", typeof(TrayServer),
				"hello", "is",
				"status", "",
				"retry", "",
				"register", "ss",
				"disconnect", ""
			);
			OLLMrpc.Request.register("AgentService", this);
			this.local_listen = new OLLMrpc.Transport.TcpListen("127.0.0.1", 4142);
			if (!this.local_listen.start()) {
				GLib.warning("local RPC listener did not bind");
			}
			this.application.state_changed.connect(() => {
				var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
				var registered =
					GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS) &&
					GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"), GLib.FileTest.EXISTS);
				var linked = registered &&
					this.application.connection != null &&
					!Argus.Agent.Application.connection_down;
				var tip = "Not registered";
				if (!registered && this.application.status_notice != "") {
					tip = this.application.status_notice;
				}
				if (registered && linked) {
					tip = "Connected to management server";
				}
				if (registered && !linked) {
					tip = this.application.status_notice != "" ? this.application.status_notice : "Disconnected";
				}
				this.local_listen.broadcast(new OLLMrpc.Notification() {
					method = "agent.status",
					args = OLLMrpc.args("bbs", registered, linked, tip)
				});
			});
			this.tick_id = GLib.Timeout.add_seconds(1, this.tick);
		}

		/**
		 * Stop the tray supervisor timer and local TCP listener.
		 */
		internal void stop()
		{
			if (this.tick_id != 0) {
				GLib.Source.remove(this.tick_id);
				this.tick_id = 0;
			}
			if (this.local_listen != null) {
				this.local_listen.stop();
			}
		}

		/**
		 * Answer the tray client's initial handshake.
		 *
		 * @param request inbound RPC from the tray
		 * @param protocol client protocol version
		 * @param client client name
		 */
		public void hello(OLLMrpc.Request request, int protocol, string client)
		{
			GLib.debug("local hello %s %d", client, protocol);
			this.connected = true;
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Return registered flag, server connection flag, and tray tip.
		 *
		 * @param request inbound RPC from the tray
		 */
		public void status(OLLMrpc.Request request)
		{
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
			var registered =
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS) &&
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"), GLib.FileTest.EXISTS);
			var linked = registered &&
				this.application.connection != null &&
				!Argus.Agent.Application.connection_down;
			var tip = "Not registered";
			if (!registered && this.application.status_notice != "") {
				tip = this.application.status_notice;
			}
			if (registered && linked) {
				tip = "Connected to management server";
			}
			if (registered && !linked) {
				tip = this.application.status_notice != "" ? this.application.status_notice : "Disconnected";
			}
			string[] reply = {
				registered ? "1" : "0",
				linked ? "1" : "0",
				tip
			};
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", reply),
				msg = "ok"
			});
		}

		/**
		 * Try the management server again.
		 *
		 * @param request inbound RPC from the tray
		 */
		public void retry(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			if (!Argus.Agent.Application.connection_down) {
				return;
			}
			this.application.status_notice = "";
			this.application.server.schedule_retry(true);
		}

		/**
		 * Register this machine using a PIN and optional ''host:port''.
		 *
		 * @param request inbound RPC from the tray
		 * @param pin six-digit registration PIN
		 * @param hostport management server address, or empty to browse
		 */
		public void register(OLLMrpc.Request request, string pin, string hostport)
		{
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
			var registered =
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS) &&
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"), GLib.FileTest.EXISTS);
			if (registered && this.application.connection != null && !Argus.Agent.Application.connection_down) {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("i", (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR),
					msg = "ok"
				});
				return;
			}
			var target = hostport.strip();
			if (target == "") {
				var line = this.application.browse.poll();
				var split = line.index_of("\n");
				if (split >= 1) {
					target = line.substring(split + 1);
				}
			}
			var colon = target.last_index_of(":");
			var host = colon >= 1 ? target.substring(0, colon) : "";
			var port = colon >= 1 ? int.parse(target.substring(colon + 1)) : 0;
			if (host == "" || port <= 0) {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("i", (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR),
					msg = "ok"
				});
				return;
			}
			var registration = new Argus.Shared.Register() {
				data_dir = this.application.data_dir,
				client_db = this.application.client_db,
				host_name = GLib.Environment.get_host_name(),
			};
			var code = registration.try_connection(host, (uint16) port, pin.strip());
			GLib.debug("registration %d", code);
			if (code != 0) {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("i", code),
					msg = "ok"
				});
				return;
			}
			var row = new Argus.Agent.SQT.Server() {
				data_dir = registration.data_dir != "" ? registration.data_dir : this.application.data_dir,
			};
			if (!registration.save(row)) {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("i", (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR),
					msg = "ok"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("i", code),
				msg = "ok"
			});
			this.application.status_notice = "";
			GLib.Idle.add(() => {
				this.application.attach_connection();
				if (this.application.connection == null) {
					return false;
				}
				new GLib.Thread<int>("osquery-init", () => {
					var init_code = new Argus.Agent.OSQuery.Initialize(this.application).run();
					GLib.Idle.add(() => {
						if (init_code != 0 || this.application.connection == null) {
							return false;
						}
						this.application.osquery.send_startup();
						this.application.monitor = new Argus.Agent.PackageMonitor(this.application);
						this.application.monitor.start();
						this.application.user_monitor = new Argus.Agent.UserMonitor(this.application);
						this.application.user_monitor.start();
						return false;
					});
					return 0;
				});
				return false;
			});
		}

		/**
		 * End an active remote control session at the signed-in user's request.
		 *
		 * @param request inbound RPC from the tray
		 */
		public new void disconnect(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			this.service.relay_stop(true);
		}

		/**
		 * Check every five seconds that ''argus-tray.exe'' is running in the active session.
		 *
		 * @return true so the timeout repeats
		 */
		private bool tick()
		{
			this.ticks++;
			if (this.ticks % 5 != 1) {
				return true;
			}
			var ids = new uint32[4096];
			uint32 needed = 0;
			if (!EnumProcesses(ids, (uint32) (ids.length * 4), out needed)) {
				return true;
			}
			var count = int.min((int) (needed / 4), ids.length);
			for (var i = 0; i < count; i++) {
				if (ids[i] == 0) {
					continue;
				}
				var proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, ids[i]);
				if (proc == null) {
					continue;
				}
				var image = g_utf8_to_utf16(string.nfill(259, ' '));
				uint32 size = 260;
				if (!QueryFullProcessImageNameW(proc, 0, image, ref size)) {
					CloseHandle(proc);
					continue;
				}
				var name = "";
				try {
					name = image.to_utf8().down();
				} catch (GLib.ConvertError e) {
					CloseHandle(proc);
					continue;
				}
				CloseHandle(proc);
				if (name.has_suffix("\\argus-tray.exe")) {
					return true;
				}
			}
			var session = argus_active_session();
			if (session == (uint32) 0xFFFFFFFF) {
				return true;
			}
			void* user;
			if (!WTSQueryUserToken(session, out user)) {
				return true;
			}
			void* dup;
			if (!DuplicateTokenEx(user, MAXIMUM_ALLOWED, null, SecurityIdentification, TokenPrimary, out dup)) {
				CloseHandle(user);
				return true;
			}
			CloseHandle(user);
			var exe = g_utf8_to_utf16(string.nfill(259, ' '));
			if (GetModuleFileNameW(null, exe, 260) == 0) {
				CloseHandle(dup);
				return true;
			}
			var path = "";
			try {
				path = exe.to_utf8();
			} catch (GLib.ConvertError e) {
				GLib.warning("tray path: %s", e.message);
				CloseHandle(dup);
				return true;
			}
			var slash = path.last_index_of("\\");
			if (slash < 0) {
				CloseHandle(dup);
				return true;
			}
			string16 tray_exe;
			string16 work_dir;
			try {
				tray_exe = (path.substring(0, slash + 1) + "argus-tray.exe").to_utf16();
				work_dir = path.substring(0, slash).to_utf16();
			} catch (GLib.ConvertError e) {
				GLib.warning("tray start: %s", e.message);
				CloseHandle(dup);
				return true;
			}
			var si = Win32.StartupInfo() {
				cb = (uint32) sizeof(Win32.StartupInfo),
				desktop = g_utf8_to_utf16("winsta0\\default"),
			};
			var info = ProcessInfo();
			var started = CreateProcessAsUserW(dup, tray_exe, null, null, null, false, 0, null, work_dir, &si, out info);
			CloseHandle(dup);
			if (!started) {
				GLib.warning("tray start failed: %u", GetLastError());
				return true;
			}
			CloseHandle(info.thread);
			CloseHandle(info.process);
			GLib.debug("starting tray");
			return true;
		}
	}
}
