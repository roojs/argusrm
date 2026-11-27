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
	 * Windows service for {@link Argus.Agent.Application}.
	 *
	 * Construct one and call {@link start}. That calls
	 * ''StartServiceCtrlDispatcherW''. The manager then enters
	 * {@link service_main}, which reports running, starts
	 * {@link TrayServer}, and runs the application. {@link control}
	 * accepts stop, and {@link restart} stops and restarts the service
	 * via the Service Control Manager. A console launch is not a service,
	 * and {@link start} returns -1 so the caller runs
	 * {@link Argus.Agent.Application} directly.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var service = new Argus.Agent.Windows.Service();
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
		internal static Service current;

		private static Win32.LPSERVICE_MAIN_FUNCTIONW main_proc = (argc, argv) => {
			Service.current.service_main();
		};

		private static Win32.LPHANDLER_FUNCTION handler_proc = (code) => {
			Service.current.control(code);
		};

		private string16 service_name;
		private void* handle;
		private uint32 state;
		private Argus.Agent.Application application;
		private TrayServer tray = new TrayServer();
		private DesktopShare share = new DesktopShare();
		private bool desktop_on = false;
		private bool start_asked = false;
		internal Argus.Agent.Rdp.Tunnel? tunnel;

		/**
		 * Set Remote Desktop to accept connections and start it.
		 *
		 * The password prompt stays on. The firewall group is left closed.
		 * When the controller has asked for the desktop, a failed start is
		 * tried again, up to three times.
		 *
		 * @param attempt how many starts have already failed
		 */
		internal void desktop(int attempt = 0)
		{
			if (this.desktop_on) {
				return;
			}
			var term_key = (void*) null;
			var term_open = RegOpenKeyExW(argus_hkey_local_machine(),
				g_utf8_to_utf16("SYSTEM\\CurrentControlSet\\Control\\Terminal Server"),
				0, KEY_SET_VALUE, (void*) (&term_key));
			if (term_open != 0) {
				GLib.warning("remote desktop registry open failed %d", term_open);
			}
			if (term_open == 0) {
				var deny = (uint32) 0;
				RegSetValueExW(term_key, g_utf8_to_utf16("fDenyTSConnections"), 0, REG_DWORD, (void*) (&deny), 4);
				RegCloseKey(term_key);
			}
			var nla_key = (void*) null;
			var nla_open = RegOpenKeyExW(argus_hkey_local_machine(),
				g_utf8_to_utf16("SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp"),
				0, KEY_SET_VALUE, (void*) (&nla_key));
			if (nla_open != 0) {
				GLib.warning("remote desktop password prompt open failed %d", nla_open);
			}
			if (nla_open == 0) {
				var nla = (uint32) 1;
				RegSetValueExW(nla_key, g_utf8_to_utf16("UserAuthentication"), 0, REG_DWORD, (void*) (&nla), 4);
				RegCloseKey(nla_key);
			}
			var started = false;
			var scm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
			if (scm == null) {
				GLib.warning("remote desktop service manager %u", GetLastError());
			}
			if (scm != null) {
				var svc = OpenServiceW(scm, g_utf8_to_utf16("TermService"), SERVICE_CHANGE_CONFIG | SERVICE_START);
				if (svc == null) {
					GLib.warning("remote desktop service open %u", GetLastError());
					CloseServiceHandle(scm);
				}
				if (svc != null) {
					if (!ChangeServiceConfigW(svc, SERVICE_NO_CHANGE, SERVICE_AUTO_START, SERVICE_NO_CHANGE,
						null, null, null, null, null, null, null)) {
						GLib.warning("remote desktop service config %u", GetLastError());
					}
					started = StartServiceW(svc, 0, null) || GetLastError() == ERROR_SERVICE_ALREADY_RUNNING;
					if (!started) {
						GLib.warning("remote desktop service start %u", GetLastError());
					}
					CloseServiceHandle(svc);
					CloseServiceHandle(scm);
				}
			}
			if (!started) {
				if (this.start_asked && this.application.connection != null) {
					try {
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.report",
							args = OLLMrpc.args("ii", (int) Argus.Rdp.State.RETRY_REMOTE_DESKTOP_DISABLED, attempt + 1)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				if (this.start_asked && attempt < 2) {
					var next = attempt + 1;
					GLib.Timeout.add_seconds(2, () => {
						this.desktop(next);
						return false;
					});
				}
				return;
			}
			this.desktop_on = true;
			if (!this.start_asked) {
				return;
			}
			if (this.application.connection != null) {
				try {
					this.application.connection.call(new OLLMrpc.Request() {
						method = "Relay.report",
						args = OLLMrpc.args("ii", (int) Argus.Rdp.State.SUCCESS_REMOTE_DESKTOP_ENABLED, 0)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			this.relay_start();
		}

		/**
		 * Stop any active desktop tunnel and sharing helper.
		 *
		 * @param by_user true when the signed-in user clicked Disconnect
		 */
		internal void relay_stop(bool by_user = false)
		{
			this.start_asked = false;
			if (this.tunnel != null) {
				this.tunnel.retire();
				this.tunnel = null;
			}
			this.share.stop();
			if (this.tray.local_listen != null) {
				this.tray.local_listen.broadcast(new OLLMrpc.Notification() {
					method = "agent.desktop_active",
					args = OLLMrpc.args("b", false)
				});
			}
			if (!by_user || this.application.connection == null) {
				return;
			}
			try {
				this.application.connection.call(new OLLMrpc.Request() {
					method = "Relay.report",
					args = OLLMrpc.args("ii", (int) Argus.Rdp.State.FAIL_USER_DISCONNECTED, 0)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}

		/**
		 * Open the desktop stream for a signed-in user or unattended RDP.
		 */
		internal void relay_start()
		{
			if (this.tunnel != null) {
				if (this.tunnel.rpc != null && this.tunnel.rpc.connected) {
					return;
				}
				this.relay_stop(false);
			}
			var session = argus_active_session();
			if (session != (uint32) 0xFFFFFFFF) {
				this.share.start(session, this.application.data_dir);
				return;
			}
			if (this.application.os_version == null || !this.application.os_version.supports_rdp()) {
				if (this.application.connection != null) {
					try {
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.report",
							args = OLLMrpc.args("ii", (int) Argus.Rdp.State.FAIL_SHARE_START, 0)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				return;
			}
			if (!this.desktop_on) {
				if (this.application.connection != null) {
					try {
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.report",
							args = OLLMrpc.args("ii", (int) Argus.Rdp.State.REQUEST_ENABLE_REMOTE_DESKTOP, 0)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				this.start_asked = true;
				this.desktop();
				return;
			}
			this.start_asked = false;
			if (this.application.connection != null) {
				try {
					this.application.connection.call(new OLLMrpc.Request() {
						method = "Relay.ticket",
						args = OLLMrpc.args("ss", "", "")
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			var rpc = this.application.stream_connection();
			if (rpc == null) {
				if (this.application.connection != null) {
					try {
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.report",
							args = OLLMrpc.args("ii", (int) Argus.Rdp.State.REQUEST_MACHINE_JOIN_RELAY, 0)
						});
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.report",
							args = OLLMrpc.args("ii", (int) Argus.Rdp.State.RETRY_SECOND_CONNECTION, 1)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				return;
			}
			if (this.application.connection != null) {
				try {
					this.application.connection.call(new OLLMrpc.Request() {
						method = "Relay.report",
						args = OLLMrpc.args("ii", (int) Argus.Rdp.State.REQUEST_CONNECT_LOCAL_RDP, 0)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			this.tunnel = new Argus.Agent.Rdp.Tunnel();
			this.tunnel.app = this.application;
			this.tunnel.adapter.target_host = "127.0.0.1";
			this.tunnel.adapter.target_port = 3389;
			this.tunnel.adapter.skip_logoff = false;
			var refused = false;
			try {
				this.tunnel.open_windows(rpc);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				refused = true;
			}
			if (!refused) {
				return;
			}
			if (this.application.connection != null) {
				try {
					this.application.connection.call(new OLLMrpc.Request() {
						method = "Relay.report",
						args = OLLMrpc.args("ii", (int) Argus.Rdp.State.RETRY_LOCAL_RDP_REFUSED, 1)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			this.tunnel = null;
		}

		/**
		 * Stop and start the ''argus-agent'' Windows service elevated.
		 *
		 * Called by ''argus-agent --restart'' from the tray menu.
		 *
		 * @return 0 when the service is running again, non-zero Win32 error or 1
		 */
		public static int restart()
		{
			var scm = OpenSCManagerW(null, null, SC_MANAGER_CONNECT);
			if (scm == null) {
				var err = (int) GetLastError();
				return err != 0 ? err : 1;
			}
			var access = SERVICE_STOP | SERVICE_START | SERVICE_QUERY_STATUS;
			var svc = OpenServiceW(scm, g_utf8_to_utf16("argus-agent"), access);
			if (svc == null) {
				var err = (int) GetLastError();
				CloseServiceHandle(scm);
				return err != 0 ? err : 1;
			}
			var ssp = SERVICE_STATUS_PROCESS();
			var needed = (uint32) 0;
			var ssp_size = (uint32) sizeof(SERVICE_STATUS_PROCESS);
			if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (void*) (&ssp), ssp_size, (void*) (&needed))) {
				var err = (int) GetLastError();
				CloseServiceHandle(svc);
				CloseServiceHandle(scm);
				return err != 0 ? err : 1;
			}
			var stop_sent = false;
			for (var i = 0; i < 60; i++) {
				if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (void*) (&ssp), ssp_size, (void*) (&needed))) {
					break;
				}
				if (ssp.dwCurrentState == SERVICE_STOPPED) {
					break;
				}
				if (!stop_sent && ssp.dwCurrentState == SERVICE_RUNNING) {
					var ctrl = SERVICE_STATUS();
					if (ControlService(svc, SERVICE_CONTROL_STOP, ref ctrl)) {
						stop_sent = true;
					}
				}
				Sleep(250);
			}
			if (ssp.dwCurrentState != SERVICE_STOPPED && ssp.dwProcessId != 0) {
				var proc = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, false, ssp.dwProcessId);
				if (proc != null) {
					TerminateProcess(proc, 1);
					WaitForSingleObject(proc, 5000);
					CloseHandle(proc);
				}
				for (var i = 0; i < 20; i++) {
					if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (void*) (&ssp), ssp_size, (void*) (&needed))) {
						break;
					}
					if (ssp.dwCurrentState == SERVICE_STOPPED) {
						break;
					}
					Sleep(250);
				}
			}
			if (ssp.dwCurrentState != SERVICE_STOPPED) {
				CloseServiceHandle(svc);
				CloseServiceHandle(scm);
				return 1;
			}
			if (!StartServiceW(svc, 0, null) && GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) {
				var err = (int) GetLastError();
				CloseServiceHandle(svc);
				CloseServiceHandle(scm);
				return err != 0 ? err : 1;
			}
			for (var i = 0; i < 60; i++) {
				if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO, (void*) (&ssp), ssp_size, (void*) (&needed))) {
					break;
				}
				if (ssp.dwCurrentState == SERVICE_RUNNING) {
					CloseServiceHandle(svc);
					CloseServiceHandle(scm);
					return 0;
				}
				if (ssp.dwCurrentState == SERVICE_STOPPED) {
					break;
				}
				Sleep(250);
			}
			CloseServiceHandle(svc);
			CloseServiceHandle(scm);
			return 1;
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
			var table = new Win32.SERVICE_TABLE_ENTRYW[2];
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
		 * Reports running, starts {@link TrayServer}, wires
		 * {@link DesktopShare}, and runs {@link Argus.Agent.Application}
		 * until {@link control} stops it.
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
			this.tray.start(this.application, this);
			this.share.failed.connect(() => {
				this.relay_stop(false);
				if (this.application.connection == null) {
					return;
				}
				try {
					this.application.connection.call(new OLLMrpc.Request() {
						method = "Relay.report",
						args = OLLMrpc.args("ii", (int) Argus.Rdp.State.FAIL_SHARE_START, 0)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			});
			this.share.ready.connect((invite, password, host, port) => {
				if (this.application.connection != null) {
					try {
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.ticket",
							args = OLLMrpc.args("ss", invite, password)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				var rpc = this.application.stream_connection();
				if (rpc == null) {
					this.relay_stop(false);
					if (this.application.connection != null) {
						try {
							this.application.connection.call(new OLLMrpc.Request() {
								method = "Relay.report",
								args = OLLMrpc.args("ii", (int) Argus.Rdp.State.RETRY_SECOND_CONNECTION, 1)
							});
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
						}
					}
					return;
				}
				if (this.application.connection != null) {
					try {
						this.application.connection.call(new OLLMrpc.Request() {
							method = "Relay.report",
							args = OLLMrpc.args("ii", (int) Argus.Rdp.State.REQUEST_CONNECT_LOCAL_RDP, 0)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				this.tunnel = new Argus.Agent.Rdp.Tunnel();
				this.tunnel.app = this.application;
				this.tunnel.adapter.target_host = host;
				this.tunnel.adapter.target_port = port;
				this.tunnel.adapter.skip_logoff = true;
				try {
					this.tunnel.open_windows(rpc);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					this.relay_stop(false);
					if (this.application.connection != null) {
						try {
							this.application.connection.call(new OLLMrpc.Request() {
								method = "Relay.report",
								args = OLLMrpc.args("ii", (int) Argus.Rdp.State.RETRY_LOCAL_RDP_REFUSED, 1)
							});
						} catch (GLib.Error err) {
							GLib.warning("%s", err.message);
						}
					}
					return;
				}
				this.tray.local_listen.broadcast(new OLLMrpc.Notification() {
					method = "agent.desktop_active",
					args = OLLMrpc.args("b", true)
				});
			});
			this.state = SERVICE_RUNNING;
			var running = SERVICE_STATUS();
			running.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			running.dwCurrentState = this.state;
			running.dwControlsAccepted = SERVICE_ACCEPT_STOP;
			SetServiceStatus(this.handle, ref running);
			this.application.run({ "argus-agent" });
			this.relay_stop(false);
			this.tray.stop();
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
