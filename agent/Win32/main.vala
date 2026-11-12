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
