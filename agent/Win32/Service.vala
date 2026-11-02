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
