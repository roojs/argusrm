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
	/**
	 * Windows entry point for the agent, tray, desktop share, and service restart.
	 *
	 * Sets ''GIO_MODULE_DIR'' beside the executable before any TLS call,
	 * parses Windows options with {@link GLib.OptionContext}, dispatches
	 * ''--restart'', ''--share-invite'', ''argus-tray'', and the Windows
	 * Service Control Manager, and falls back to
	 * {@link Argus.Agent.Application} for console launches.
	 *
	 * Extends {@link GLib.Object} rather than {@link GLib.Application} so
	 * the main thread does not acquire the default {@link GLib.MainContext}
	 * before ''StartServiceCtrlDispatcherW'' invokes
	 * {@link Service.service_main} on the SCM thread.
	 */
	internal class Application : GLib.Object
	{
		private static bool opt_restart;
		private static int opt_share_port;
		private static string opt_share_pass = "";
		private static string opt_share_invite = "";
		private static string opt_share_stop = "";

		/**
		 * Point GIO at the bundled TLS module directory beside the exe.
		 */
		public Application()
		{
			var exe = Win32.g_utf8_to_utf16(string.nfill(259, ' '));
			if (Win32.GetModuleFileNameW(null, exe, 260) != 0) {
				try {
					var path = exe.to_utf8();
					var slash = path.last_index_of("\\");
					if (slash > 0) {
						GLib.Environment.set_variable("GIO_MODULE_DIR", path.substring(0, slash) + "\\gio\\modules", true);
					}
				} catch (GLib.ConvertError e) {
					GLib.warning("%s", e.message);
				}
			}
		}

		/**
		 * Parse Windows options and dispatch before starting {@link Argus.Agent.Application}.
		 *
		 * @param args process arguments
		 * @return process exit code
		 */
		public int run(string[] args)
		{
			opt_restart = false;
			opt_share_port = 0;
			opt_share_pass = "";
			opt_share_invite = "";
			opt_share_stop = "";
			var opt_context = new GLib.OptionContext("org.roojs.ArgusAgent");
			opt_context.set_help_enabled(false);
			opt_context.set_ignore_unknown_options(true);
			GLib.OptionEntry[] win_options = {
				{ "restart", 0, 0, GLib.OptionArg.NONE, ref opt_restart, "Restart the Windows agent service", null },
				{ "share-port", 0, 0, GLib.OptionArg.INT, ref opt_share_port, "TCP port for desktop sharing", "PORT" },
				{ "share-pass", 0, 0, GLib.OptionArg.STRING, ref opt_share_pass, "One-time desktop share password", "PASSWORD" },
				{ "share-invite", 0, 0, GLib.OptionArg.STRING, ref opt_share_invite, "Output path for RACS2 invitation XML", "PATH" },
				{ "share-stop", 0, 0, GLib.OptionArg.STRING, ref opt_share_stop, "Named Win32 stop event", "EVENT" },
				{ null }
			};
			opt_context.add_main_entries(win_options, null);
			string[] parse_args = {};
			foreach (var arg in args) {
				parse_args += arg;
			}
			try {
				unowned string[] unowned_args = parse_args;
				opt_context.parse(ref unowned_args);
			} catch (GLib.OptionError e) {
				GLib.stderr.printf("error: %s\n", e.message);
				return 1;
			}
			if (opt_restart) {
				return Service.restart();
			}
			if (opt_share_invite != "") {
				var share = new DesktopShare();
				return share.run((uint16) opt_share_port, opt_share_pass, opt_share_invite, opt_share_stop);
			}
			var exe_name = args.length > 0 ? GLib.Path.get_basename(args[0]).down() : "";
			if (exe_name == "argus-tray" || exe_name == "argus-tray.exe") {
				var tray = new Tray();
				return tray.run();
			}
			var service = new Service();
			var service_exit = service.start();
			if (service_exit >= 0) {
				return service_exit;
			}
			var app = new Argus.Agent.Application();
			return app.run(args);
		}
	}
}
