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
		 * and ''host:port'' from the local pipe, and calls
		 * {@link Argus.Shared.Register}.
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
		private OLLMrpc.Transport.TcpListen local_listen;
		private int ticks = 0;

		/**
		 * Register ''AgentService'' RPC methods on {@link OLLMrpc.Request}.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"AgentService", typeof(Service),
				"hello", "is",
				"status", "",
				"register", "ss"
			);
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
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var registered =
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
					GLib.FileTest.EXISTS) &&
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"),
					GLib.FileTest.EXISTS);
			var connected = registered &&
				this.application.connection != null &&
				!Argus.Agent.Application.connection_down;
			var tip = "Not registered";
			if (!registered && this.application.status_notice != "") {
				tip = this.application.status_notice;
			}
			if (registered && connected) {
				tip = "Connected to management server";
			}
			if (registered && !connected) {
				tip = "Disconnected";
			}
			string[] reply = {
				registered ? "1" : "0",
				connected ? "1" : "0",
				tip
			};
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", reply),
				msg = "ok"
			});
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
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var registered =
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
					GLib.FileTest.EXISTS) &&
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"),
					GLib.FileTest.EXISTS);
			if (registered) {
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
			var code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			if (host != "" && port > 0) {
				var registration = new Argus.Shared.Register();
				code = registration.try_connection(host, (uint16) port,
					pin.strip(), GLib.Environment.get_host_name());
				GLib.debug("registration %d", code);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("i", code),
				msg = "ok"
			});
			if (code != 0) {
				return;
			}
			this.application.status_notice = "";
			GLib.Idle.add(() => {
				this.application.attach_connection();
				if (this.application.connection == null) {
					return false;
				}
				new GLib.Thread<int>("osquery-init", () => {
					var init_code = new Argus.Agent.OSQuery.Initialize(this.application).run();
					GLib.Idle.add(() => {
						if (init_code != 0) {
							return false;
						}
						if (this.application.connection == null) {
							return false;
						}
						this.application.osquery.send_startup();
						this.application.monitor =
							new Argus.Agent.PackageMonitor(this.application);
						this.application.monitor.start();
						this.application.user_monitor =
							new Argus.Agent.UserMonitor(this.application);
						this.application.user_monitor.start();
						return false;
					});
					return 0;
				});
				return false;
			});
		}

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
			OLLMrpc.rpc_register();
			Service.rpc_register();
			OLLMrpc.Request.register("AgentService", this);
			this.local_listen = new OLLMrpc.Transport.TcpListen("127.0.0.1", 4142);
			if (!this.local_listen.start()) {
				GLib.warning("local RPC listener did not bind");
			}
			this.application.state_changed.connect(() => {
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argus");
				var registered =
					GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
						GLib.FileTest.EXISTS) &&
					GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"),
						GLib.FileTest.EXISTS);
				var connected = registered &&
					this.application.connection != null &&
					!Argus.Agent.Application.connection_down;
				var tip = "Not registered";
				if (!registered && this.application.status_notice != "") {
					tip = this.application.status_notice;
				}
				if (registered && connected) {
					tip = "Connected to management server";
				}
				if (registered && !connected) {
					tip = "Disconnected";
				}
				this.local_listen.broadcast(new OLLMrpc.Notification() {
					method = "agent.status",
					args = OLLMrpc.args("bbs", registered, connected, tip)
				});
			});
			this.state = SERVICE_RUNNING;
			var running = SERVICE_STATUS();
			running.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			running.dwCurrentState = this.state;
			running.dwControlsAccepted = SERVICE_ACCEPT_STOP;
			SetServiceStatus(this.handle, ref running);
			GLib.Timeout.add_seconds(1, this.tick);
			this.application.run({ "argus-agent" });
			this.local_listen.stop();
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
			if (this.ticks % 5 != 1) {
				return true;
			}
			var found = false;
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
				if (!name.has_suffix("\\argus-tray.exe")) {
					continue;
				}
				found = true;
				break;
			}
			if (found) {
				return true;
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
