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
	 */
	internal class Application : Argus.Agent.Application
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
		 * Parse Windows options and dispatch before the base agent command line.
		 *
		 * @param command_line arguments for this launch
		 * @return process exit code
		 */
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			opt_restart = false;
			opt_share_port = 0;
			opt_share_pass = "";
			opt_share_invite = "";
			opt_share_stop = "";
			var args = command_line.get_arguments();
			var opt_context = new GLib.OptionContext(this.application_id);
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);
			GLib.OptionEntry[] win_options = {
				{ "restart", 0, 0, GLib.OptionArg.NONE, ref opt_restart, "Restart the Windows agent service", null },
				{ "share-port", 0, 0, GLib.OptionArg.INT, ref opt_share_port, "TCP port for desktop sharing", "PORT" },
				{ "share-pass", 0, 0, GLib.OptionArg.STRING, ref opt_share_pass, "One-time desktop share password", "PASSWORD" },
				{ "share-invite", 0, 0, GLib.OptionArg.STRING, ref opt_share_invite, "Output path for RACS2 invitation XML", "PATH" },
				{ "share-stop", 0, 0, GLib.OptionArg.STRING, ref opt_share_stop, "Named Win32 stop event", "EVENT" },
				{ null }
			};
			opt_context.add_main_entries(win_options, null);
			try {
				unowned string[] unowned_args = args;
				opt_context.parse(ref unowned_args);
			} catch (GLib.OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				return 1;
			}
			if (opt_restart) {
				this.server.stand_down();
				return Service.restart();
			}
			if (opt_share_invite != "") {
				this.server.stand_down();
				var share = new DesktopShare();
				return share.run((uint16) opt_share_port, opt_share_pass, opt_share_invite, opt_share_stop);
			}
			var exe_name = args.length > 0 ? GLib.Path.get_basename(args[0]).down() : "";
			if (exe_name == "argus-tray" || exe_name == "argus-tray.exe") {
				this.server.stand_down();
				var tray = new Tray();
				return tray.run();
			}
			this.server.stand_down();
			var service = new Service();
			var service_exit = service.start();
			if (service_exit >= 0) {
				return service_exit;
			}
			this.attach_connection();
			return base.command_line(command_line);
		}
	}
}
