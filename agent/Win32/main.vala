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
	int main(string[] args)
	{
		// GIO loads TLS from a module. This executable is installed
		// outside the MSYS2 prefix, so the default search misses
		// libgiognutls.dll and GDummyTlsBackend is used. Certificate
		// load then aborts: "TLS support is not available". The
		// package copies that DLL to gio\modules beside the
		// executable. Point GIO there before any TLS call.
		var exe = Win32.g_utf8_to_utf16(string.nfill(259, ' '));
		if (Win32.GetModuleFileNameW(null, exe, 260) != 0) {
			try {
				var path = exe.to_utf8();
				var slash = path.last_index_of("\\");
				if (slash > 0) {
					GLib.Environment.set_variable("GIO_MODULE_DIR",
						path.substring(0, slash) + "\\gio\\modules", true);
				}
			} catch (GLib.ConvertError e) {
				GLib.warning("%s", e.message);
			}
		}
		foreach (var arg in args) {
			if (arg != "--restart") {
				continue;
			}
			var scm = Win32.OpenSCManagerW(null, null, Win32.SC_MANAGER_CONNECT);
			if (scm == null) {
				var err = (int) Win32.GetLastError();
				return err != 0 ? err : 1;
			}
			var svc = Win32.OpenServiceW(scm, Win32.g_utf8_to_utf16("argus-agent"),
				Win32.SERVICE_STOP | Win32.SERVICE_START | Win32.SERVICE_QUERY_STATUS);
			if (svc == null) {
				var err = (int) Win32.GetLastError();
				Win32.CloseServiceHandle(scm);
				return err != 0 ? err : 1;
			}
			var ssp = Win32.SERVICE_STATUS_PROCESS();
			var needed = (uint32) 0;
			if (!Win32.QueryServiceStatusEx(svc, Win32.SC_STATUS_PROCESS_INFO,
				(void*) (&ssp), (uint32) sizeof(Win32.SERVICE_STATUS_PROCESS), (void*) (&needed))) {
				var err = (int) Win32.GetLastError();
				Win32.CloseServiceHandle(svc);
				Win32.CloseServiceHandle(scm);
				return err != 0 ? err : 1;
			}
			var stop_sent = false;
			for (var i = 0; i < 60; i++) {
				if (!Win32.QueryServiceStatusEx(svc, Win32.SC_STATUS_PROCESS_INFO,
					(void*) (&ssp), (uint32) sizeof(Win32.SERVICE_STATUS_PROCESS), (void*) (&needed))) {
					break;
				}
				if (ssp.dwCurrentState == Win32.SERVICE_STOPPED) {
					break;
				}
				if (!stop_sent && ssp.dwCurrentState == Win32.SERVICE_RUNNING) {
					var ctrl = Win32.SERVICE_STATUS();
					if (Win32.ControlService(svc, Win32.SERVICE_CONTROL_STOP, ref ctrl)) {
						stop_sent = true;
					}
				}
				Win32.Sleep(250);
			}
			if (ssp.dwCurrentState != Win32.SERVICE_STOPPED && ssp.dwProcessId != 0) {
				var proc = Win32.OpenProcess(Win32.PROCESS_TERMINATE | Win32.SYNCHRONIZE,
					false, ssp.dwProcessId);
				if (proc != null) {
					Win32.TerminateProcess(proc, 1);
					Win32.WaitForSingleObject(proc, 5000);
					Win32.CloseHandle(proc);
				}
				for (var i = 0; i < 20; i++) {
					if (!Win32.QueryServiceStatusEx(svc, Win32.SC_STATUS_PROCESS_INFO,
						(void*) (&ssp), (uint32) sizeof(Win32.SERVICE_STATUS_PROCESS), (void*) (&needed))) {
						break;
					}
					if (ssp.dwCurrentState == Win32.SERVICE_STOPPED) {
						break;
					}
					Win32.Sleep(250);
				}
			}
			if (ssp.dwCurrentState != Win32.SERVICE_STOPPED) {
				Win32.CloseServiceHandle(svc);
				Win32.CloseServiceHandle(scm);
				return 1;
			}
			if (!Win32.StartServiceW(svc, 0, null) &&
				Win32.GetLastError() != Win32.ERROR_SERVICE_ALREADY_RUNNING) {
				var err = (int) Win32.GetLastError();
				Win32.CloseServiceHandle(svc);
				Win32.CloseServiceHandle(scm);
				return err != 0 ? err : 1;
			}
			for (var i = 0; i < 60; i++) {
				if (!Win32.QueryServiceStatusEx(svc, Win32.SC_STATUS_PROCESS_INFO,
					(void*) (&ssp), (uint32) sizeof(Win32.SERVICE_STATUS_PROCESS), (void*) (&needed))) {
					break;
				}
				if (ssp.dwCurrentState == Win32.SERVICE_RUNNING) {
					Win32.CloseServiceHandle(svc);
					Win32.CloseServiceHandle(scm);
					return 0;
				}
				if (ssp.dwCurrentState == Win32.SERVICE_STOPPED) {
					break;
				}
				Win32.Sleep(250);
			}
			Win32.CloseServiceHandle(svc);
			Win32.CloseServiceHandle(scm);
			return 1;
		}
		var exe_name = GLib.Path.get_basename(args[0]).down();
		if (exe_name == "argus-tray" || exe_name == "argus-tray.exe") {
			var tray = new Win32.Tray();
			return tray.run();
		}
		var service = new Win32.Service();
		var service_exit = service.start();
		if (service_exit >= 0) {
			return service_exit;
		}
		var app = new Application();
		return app.run(args);
	}
}
