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
		 * until {@link control} stops it. The tray launch, the
		 * registration pipe, and the two-minute reach run on that
		 * loop.
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
			GLib.Timeout.add_seconds(1, () => {
				this.ticks++;
				if ((intptr) this.pipe == -1) {
					this.pipe = CreateNamedPipeW(
						g_utf8_to_utf16("\\\\.\\pipe\\Argus.Register"),
						PIPE_ACCESS_DUPLEX,
						PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT,
						1, 4096, 4096, 0, null);
					this.pipe_up = false;
					if (this.pipe == null || (intptr) this.pipe == -1) {
						this.pipe = (void*) (intptr) (-1);
						if (!this.pipe_warned) {
							GLib.warning("pipe: %u", GetLastError());
							this.pipe_warned = true;
						}
					}
					if ((intptr) this.pipe != -1) {
						this.pipe_warned = false;
					}
				}
				var became = false;
				if ((intptr) this.pipe != -1 && !this.pipe_up) {
					if (ConnectNamedPipe(this.pipe, null) ||
						GetLastError() == ERROR_PIPE_CONNECTED) {
						became = true;
						this.pipe_up = true;
					}
				}
				if (became && this.tip != "") {
					this.tip_due = true;
				}
				var cert = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argus", "client.pem");
				if (became && this.tip == "" &&
					GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
					this.tip = "Disconnected";
					GLib.debug("tip %s", this.tip);
					this.tip_due = true;
				}
				if (this.pipe_up && this.number == "") {
					uint32 avail = 0;
					if (!PeekNamedPipe(this.pipe, null, 0, null, out avail, null)) {
						DisconnectNamedPipe(this.pipe);
						CloseHandle(this.pipe);
						this.pipe = (void*) (intptr) (-1);
						this.pipe_up = false;
					}
					if (this.pipe_up && avail > 0) {
						uint32 got = 0;
						var buf = new uint8[256];
						if (!ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
							DisconnectNamedPipe(this.pipe);
							CloseHandle(this.pipe);
							this.pipe = (void*) (intptr) (-1);
							this.pipe_up = false;
						}
						if (this.pipe_up && got > 0) {
							var n = int.min((int) got, buf.length);
							var msg = (string) buf[0:n];
							if (msg.length == 6) {
								this.number = msg;
							}
						}
					}
				}
				if (this.number != "") {
					var line = this.application.browse.poll();
					if (line == "none") {
						this.reply_line = "%d".printf((int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR);
						this.number = "";
					}
					if (line != "" && line != "none") {
						var split = line.index_of("\n");
						var hostport = "";
						if (split >= 1) {
							hostport = line.substring(split + 1);
						}
						var colon = hostport.last_index_of(":");
						var host = "";
						var port = 0;
						if (colon >= 1) {
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
						this.reply_line = "%d".printf(code);
						this.number = "";
						if (code == 0) {
							this.probe_id++;
							this.probe_open = false;
							this.tip = "Connected to management server";
							GLib.debug("tip %s", this.tip);
							this.tip_due = true;
						}
					}
				}
				if (this.ticks % 5 == 1) {
					var found = false;
					var listed = false;
					var ids = new uint32[4096];
					uint32 needed = 0;
					if (EnumProcesses(ids, (uint32) (ids.length * 4), out needed)) {
						listed = true;
						var count = int.min((int) (needed / 4), ids.length);
						for (var i = 0; i < count; i++) {
							if (ids[i] == 0) {
								continue;
							}
							var proc = OpenProcess(
								PROCESS_QUERY_LIMITED_INFORMATION, false, ids[i]);
							if (proc == null) {
								continue;
							}
							var image = g_utf8_to_utf16(string.nfill(259, ' '));
							uint32 size = 260;
							if (!QueryFullProcessImageNameW(proc, 0, image, ref size)) {
								CloseHandle(proc);
								continue;
							}
							try {
								if (image.to_utf8().down().has_suffix("\\argus-tray.exe")) {
									found = true;
								}
							} catch (GLib.ConvertError e) {
								CloseHandle(proc);
								continue;
							}
							CloseHandle(proc);
							if (found) {
								break;
							}
						}
					}
					var session = (uint32) 0xFFFFFFFF;
					if (listed && !found) {
						session = WTSGetActiveConsoleSessionId();
					}
					if (listed && !found && session != 0xFFFFFFFF) {
						void* user;
						if (WTSQueryUserToken(session, out user)) {
							void* dup;
							if (DuplicateTokenEx(user, MAXIMUM_ALLOWED, null,
								SecurityIdentification, TokenPrimary, out dup)) {
								var exe = g_utf8_to_utf16(string.nfill(259, ' '));
								if (GetModuleFileNameW(null, exe, 260) != 0) {
									var path = "";
									try {
										path = exe.to_utf8();
									} catch (GLib.ConvertError e) {
										GLib.warning("tray path: %s", e.message);
									}
									var slash = path.last_index_of("\\");
									if (path != "" && slash >= 0) {
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
									}
								}
								CloseHandle(dup);
							}
							CloseHandle(user);
						}
					}
				}
				if (this.ticks % 120 == 1 && !this.probe_open &&
					GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
					var text = "";
					try {
						GLib.FileUtils.get_contents(GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "argus", "download"), out text);
					} catch (GLib.Error e) {
						text = "";
					}
					text = text.strip();
					var mark = text.last_index_of(":");
					if (text == "" || mark < 1) {
						if (this.tip != "Disconnected") {
							this.tip = "Disconnected";
							GLib.debug("tip %s", this.tip);
							this.tip_due = true;
						}
					}
					if (text != "" && mark >= 1) {
						var where = text.substring(0, mark);
						var reach_port = int.parse(text.substring(mark + 1));
						if (reach_port > 0) {
							this.probe_open = true;
							this.probe_id++;
							var id = this.probe_id;
							var client = new GLib.SocketClient() {
								timeout = 10
							};
							client.connect_to_host_async.begin(where, (uint16) reach_port, null, (obj, res) => {
								if (id != this.probe_id) {
									return;
								}
								this.probe_open = false;
								var next = "Disconnected";
								try {
									var conn = client.connect_to_host_async.end(res);
									try {
										conn.close();
									} catch (GLib.Error e) {
										GLib.debug("download socket: %s", e.message);
									}
									next = "Connected to management server";
								} catch (GLib.Error e) {
									next = "Disconnected";
								}
								if (next == this.tip) {
									return;
								}
								this.tip = next;
								GLib.debug("tip %s", this.tip);
								this.tip_due = true;
							});
						}
					}
				}
				if (this.reply_line != "" && this.pipe_up && (intptr) this.pipe != -1) {
					var bytes = this.reply_line.data;
					uint32 wrote = 0;
					if (WriteFile(this.pipe, bytes, (uint32) bytes.length, out wrote, null)) {
						this.reply_line = "";
					}
					if (this.reply_line != "") {
						DisconnectNamedPipe(this.pipe);
						CloseHandle(this.pipe);
						this.pipe = (void*) (intptr) (-1);
						this.pipe_up = false;
						this.reply_line = "";
					}
				}
				if (this.tip_due && this.pipe_up && (intptr) this.pipe != -1 && this.tip != "") {
					var bytes = ("tip " + this.tip).data;
					uint32 wrote = 0;
					if (WriteFile(this.pipe, bytes, (uint32) bytes.length, out wrote, null)) {
						this.tip_due = false;
					}
					if (this.tip_due) {
						DisconnectNamedPipe(this.pipe);
						CloseHandle(this.pipe);
						this.pipe = (void*) (intptr) (-1);
						this.pipe_up = false;
					}
				}
				return true;
			});
			this.application.run({ "argus-agent" });
			this.state = SERVICE_STOPPED;
			var stopped = SERVICE_STATUS();
			stopped.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			stopped.dwCurrentState = this.state;
			SetServiceStatus(this.handle, ref stopped);
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
