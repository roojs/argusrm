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

namespace Argus.Agent.Win32
{
	/**
	 * Windows service for {@link Argus.Agent.Application}.
	 *
	 * Construct one and call {@link start}. That calls
	 * ''StartServiceCtrlDispatcherW''. The manager then enters
	 * {@link service_main}, which reports running and starts the
	 * application. {@link control} accepts stop. Those two API entry
	 * points are function pointers with no instance, so they call back
	 * into this object. A console launch is not a service, and
	 * {@link start} returns -1 so the caller runs
	 * {@link Argus.Agent.Application} directly. While the service
	 * is running it starts ''argus-tray'' in the signed-in session
	 * when that process is not already running, reads the number
	 * from the local pipe, and calls {@link Argus.Shared.Register}.
	 * The tray tip is ''Connected to management server'' or
	 * ''Disconnected''. A failed reach is tried again two minutes
	 * later.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var service = new Argus.Agent.Win32.Service();
	 * var service_exit = service.start();
	 * if (service_exit >= 0) {
	 *     return service_exit;
	 * }
	 * }}}
	 */
	public class Service : GLib.Object
	{
		/**
		 * The service the control manager calls back into.
		 *
		 * One process runs one service. The dispatcher function pointers
		 * have no context argument, so they use this.
		 */
		private static Service current;

		private static LPSERVICE_MAIN_FUNCTIONW main_proc = (argc, argv) => {
			Service.current.service_main();
		};

		private static LPHANDLER_FUNCTION handler_proc = (code) => {
			Service.current.control(code);
		};

		private string16 service_name;
		private void* handle;
		private uint32 state;
		private Argus.Agent.Application application;
		private void* pipe = (void*) (intptr) (-1);
		private bool pipe_up = false;
		private bool pipe_warned = false;
		private string number = "";
		private string tip = "";
		private string reply_line = "";
		private bool tip_due = false;
		private int ticks = 0;
		private bool probe_open = false;
		private int probe_id = 0;

		/**
		 * Hand this process to the Service Control Manager.
		 *
		 * Blocks until the service stops when the manager started the
		 * process.
		 *
		 * @return -1 when the process was started from a console. 0 when
		 *   the service ran and stopped. 1 when the dispatcher failed
		 *   for another reason.
		 */
		public int start()
		{
			Service.current = this;
			try {
				this.service_name = "argus-agent".to_utf16();
			} catch (GLib.Error e) {
				GLib.warning("service name: %s", e.message);
				return 1;
			}
			var table = new SERVICE_TABLE_ENTRYW[2];
			table[0].lpServiceName = this.service_name;
			table[0].lpServiceProc = Service.main_proc;
			if (StartServiceCtrlDispatcherW(table)) {
				return 0;
			}
			if (GetLastError() == ERROR_FAILED_SERVICE_CONTROLLER_CONNECT) {
				return -1;
			}
			GLib.warning("service dispatcher failed: %u", GetLastError());
			return 1;
		}

		/**
		 * Service entry after {@link start} connects to the manager.
		 *
		 * Reports running, then runs {@link Argus.Agent.Application}
		 * until {@link control} stops it. {@link tick} runs once a
		 * second on that loop.
		 */
		private void service_main()
		{
			this.application = new Argus.Agent.Application();
			this.state = SERVICE_START_PENDING;
			this.handle = RegisterServiceCtrlHandlerW(this.service_name, Service.handler_proc);
			if (this.handle == null) {
				GLib.warning("service handler was not registered: %u", GetLastError());
				return;
			}
			var pending = SERVICE_STATUS();
			pending.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			pending.dwCurrentState = this.state;
			SetServiceStatus(this.handle, ref pending);
			this.state = SERVICE_RUNNING;
			var running = SERVICE_STATUS();
			running.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			running.dwCurrentState = this.state;
			running.dwControlsAccepted = SERVICE_ACCEPT_STOP;
			SetServiceStatus(this.handle, ref running);
			GLib.Timeout.add_seconds(1, this.tick);
			this.application.run({ "argus-agent" });
			this.state = SERVICE_STOPPED;
			var stopped = SERVICE_STATUS();
			stopped.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			stopped.dwCurrentState = this.state;
			SetServiceStatus(this.handle, ref stopped);
		}

		/**
		 * One second of service work.
		 *
		 * Opens the registration pipe, reads a pin, and calls
		 * {@link Argus.Shared.Register}. Starts ''argus-tray''
		 * when that process is not already running. A launch that
		 * is not ready waits for the next second. Reaches the
		 * stored download socket every two minutes.
		 *
		 * @return true so the timeout repeats
		 */
		private bool tick()
		{
			this.ticks++;
			if ((intptr) this.pipe == -1) {
				this.pipe = CreateNamedPipeW(
					g_utf8_to_utf16("\\\\.\\pipe\\Argus.Register"),
					PIPE_ACCESS_DUPLEX,
					PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT,
					1, 4096, 4096, 0, null);
				this.pipe_up = false;
			}
			if (this.pipe == null) {
				this.pipe = (void*) (intptr) (-1);
			}
			if ((intptr) this.pipe == -1 && !this.pipe_warned) {
				GLib.warning("pipe: %u", GetLastError());
				this.pipe_warned = true;
			}
			if ((intptr) this.pipe != -1) {
				this.pipe_warned = false;
			}
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			var became = false;
			if ((intptr) this.pipe != -1 && !this.pipe_up &&
				(ConnectNamedPipe(this.pipe, null) ||
					GetLastError() == ERROR_PIPE_CONNECTED)) {
				became = true;
				this.pipe_up = true;
			}
			if (became && this.tip != "") {
				this.tip_due = true;
			}
			if (became && this.tip == "" &&
				GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.tip = "Disconnected";
				GLib.debug("tip %s", this.tip);
				this.tip_due = true;
			}
			uint32 avail = 0;
			if (this.pipe_up && this.number == "" &&
				!PeekNamedPipe(this.pipe, null, 0, null, out avail, null)) {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
			}
			uint32 got = 0;
			var buf = new uint8[256];
			if (this.pipe_up && this.number == "" && avail > 0 &&
				!ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
			}
			if (this.pipe_up && this.number == "" && got == 6) {
				this.number = (string) buf[0:6];
			}
			var line = "";
			if (this.number != "") {
				line = this.application.browse.poll();
			}
			if (line == "none") {
				this.reply_line = "%d".printf((int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR);
				this.number = "";
			}
			var host = "";
			var port = 0;
			var split = line.index_of("\n");
			var hostport = "";
			if (split >= 1) {
				hostport = line.substring(split + 1);
			}
			var colon = hostport.last_index_of(":");
			if (line != "" && line != "none" && colon >= 1) {
				host = hostport.substring(0, colon);
				port = int.parse(hostport.substring(colon + 1));
			}
			var code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			if (host != "" && port > 0) {
				var registration = new Argus.Shared.Register();
				code = registration.try_connection(host, (uint16) port,
					this.number, GLib.Environment.get_host_name());
				GLib.debug("registration %d", code);
			}
			if (line != "" && line != "none" && code == 0) {
				this.probe_id++;
				this.probe_open = false;
				this.tip = "Connected to management server";
				GLib.debug("tip %s", this.tip);
				this.tip_due = true;
			}
			if (line != "" && line != "none") {
				this.reply_line = "%d".printf(code);
				this.number = "";
			}
			var probing = this.ticks % 120 == 1 && !this.probe_open &&
				GLib.FileUtils.test(cert, GLib.FileTest.EXISTS);
			var text = "";
			if (probing) {
				try {
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "download"), out text);
				} catch (GLib.Error e) {
					text = "";
				}
				text = text.strip();
			}
			var mark = text.last_index_of(":");
			if (probing && (text == "" || mark < 1) && this.tip != "Disconnected") {
				this.tip = "Disconnected";
				GLib.debug("tip %s", this.tip);
				this.tip_due = true;
			}
			var reach_port = 0;
			if (probing && text != "" && mark >= 1) {
				reach_port = int.parse(text.substring(mark + 1));
			}
			if (reach_port > 0) {
				this.probe_open = true;
				this.probe_id++;
				var id = this.probe_id;
				var client = new GLib.SocketClient() {
					timeout = 10
				};
				client.connect_to_host_async.begin(text.substring(0, mark), (uint16) reach_port, null, (obj, res) => {
					if (id != this.probe_id) {
						return;
					}
					this.probe_open = false;
					var next = "Disconnected";
					try {
						var conn = client.connect_to_host_async.end(res);
						next = "Connected to management server";
						conn.close();
					} catch (GLib.Error e) {
						if (next == "Connected to management server") {
							GLib.debug("download socket: %s", e.message);
						}
					}
					if (next == this.tip) {
						return;
					}
					this.tip = next;
					GLib.debug("tip %s", this.tip);
					this.tip_due = true;
				});
			}
			uint32 wrote = 0;
			var reply = this.reply_line.data;
			if (this.reply_line != "" && this.pipe_up && (intptr) this.pipe != -1 &&
				WriteFile(this.pipe, reply, (uint32) reply.length, out wrote, null)) {
				this.reply_line = "";
			}
			if (this.reply_line != "" && this.pipe_up && (intptr) this.pipe != -1) {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
				this.reply_line = "";
			}
			var tip_bytes = ("tip " + this.tip).data;
			if (this.tip_due && this.pipe_up && (intptr) this.pipe != -1 && this.tip != "" &&
				WriteFile(this.pipe, tip_bytes, (uint32) tip_bytes.length, out wrote, null)) {
				this.tip_due = false;
			}
			if (this.tip_due && this.pipe_up && (intptr) this.pipe != -1 && this.tip != "") {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
			}
			if (this.ticks % 5 != 1) {
				return true;
			}
			var found = false;
			var listed = false;
			var ids = new uint32[4096];
			uint32 needed = 0;
			if (!EnumProcesses(ids, (uint32) (ids.length * 4), out needed)) {
				return true;
			}
			listed = true;
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
				if (!name.has_suffix("\\argus-tray.exe")) {
					continue;
				}
				found = true;
				break;
			}
			if (!listed || found) {
				return true;
			}
			var session = WTSGetActiveConsoleSessionId();
			if (session == (uint32) 0xFFFFFFFF) {
				return true;
			}
			void* user;
			if (!WTSQueryUserToken(session, out user)) {
				return true;
			}
			void* dup;
			if (!DuplicateTokenEx(user, MAXIMUM_ALLOWED, null,
				SecurityIdentification, TokenPrimary, out dup)) {
				CloseHandle(user);
				return true;
			}
			var exe = g_utf8_to_utf16(string.nfill(259, ' '));
			if (GetModuleFileNameW(null, exe, 260) == 0) {
				CloseHandle(dup);
				CloseHandle(user);
				return true;
			}
			var path = "";
			try {
				path = exe.to_utf8();
			} catch (GLib.ConvertError e) {
				GLib.warning("tray path: %s", e.message);
			}
			var slash = path.last_index_of("\\");
			if (path == "" || slash < 0) {
				CloseHandle(dup);
				CloseHandle(user);
				return true;
			}
			var si = StartupInfo() {
				cb = (uint32) sizeof(StartupInfo),
				desktop = g_utf8_to_utf16("winsta0\\default"),
			};
			var info = ProcessInfo();
			try {
				var started = CreateProcessAsUserW(dup,
					(path.substring(0, slash + 1) + "argus-tray.exe").to_utf16(),
					null, null, null, false, 0, null,
					path.substring(0, slash).to_utf16(),
					&si, out info);
				if (!started) {
					GLib.warning("tray start failed: %u", GetLastError());
				}
				if (started) {
					CloseHandle(info.thread);
					CloseHandle(info.process);
					GLib.debug("starting tray");
				}
			} catch (GLib.ConvertError e) {
				GLib.warning("tray start: %s", e.message);
			}
			CloseHandle(dup);
			CloseHandle(user);
			return true;
		}

		/**
		 * Control codes from the Service Control Manager.
		 *
		 * Stop asks {@link Argus.Agent.Application} to quit. Interrogate
		 * reports the current state.
		 *
		 * @param code control code from the manager
		 */
		private void control(uint32 code)
		{
			switch (code) {
				case SERVICE_CONTROL_STOP:
					this.state = SERVICE_STOP_PENDING;
					var stopping = SERVICE_STATUS();
					stopping.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
					stopping.dwCurrentState = this.state;
					SetServiceStatus(this.handle, ref stopping);
					this.application.quit();
					return;
				case SERVICE_CONTROL_INTERROGATE:
					var status = SERVICE_STATUS();
					status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
					status.dwCurrentState = this.state;
					status.dwControlsAccepted = SERVICE_ACCEPT_STOP;
					SetServiceStatus(this.handle, ref status);
					return;
				default:
					return;
			}
		}
	}
}
