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

namespace Argus.Agent.OSQuery
{
	/**
	 * Install osquery, query it, and sync the rows.
	 *
	 * {@link start} runs {@link run} on the caller. Windows and
	 * Linux use {@link Download} for the registration URL path
	 * when ''osqueryi'' is missing, then install that file.
	 * ''OSQuery.sync'' sends one table on
	 * {@link Application.connection}: the registered row name and
	 * the array of row objects.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new Argus.Agent.OSQuery.Initialize(application).start();
	 * }}}
	 */
	public class Initialize : GLib.Object
	{
		/**
		 * Agent that owns the server connection.
		 *
		 * {@link sync_table} sends on {@link Application.connection}
		 * at that moment.
		 */
		private Application application;

		/**
		 * @param application agent whose server connection is open
		 */
		public Initialize(Application application)
		{
			this.application = application;
		}

		/**
		 * True while {@link run} is in progress.
		 *
		 * {@link start} returns without a second run when this
		 * is set.
		 */
		private static bool running = false;

		/**
		 * Install osquery when needed, query, and sync.
		 *
		 * Returns immediately when a run is already in progress.
		 * The result is logged from this call.
		 */
		public void start()
		{
			if (Initialize.running) {
				return;
			}
			Initialize.running = true;
			var code = this.run();
			Initialize.running = false;
			GLib.debug("osquery %d", code);
		}

		/**
		 * Query osquery and sync each table.
		 *
		 * Windows and Linux fetch the registration URL path and
		 * install that file when ''osqueryi'' is not already on
		 * the machine. Each sync goes to the server connection,
		 * including an empty array.
		 *
		 * @return zero when every sync succeeds, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int run()
		{
			var osqueryi = "";
			var pass = 0;
			while (osqueryi == "" && pass < 2) {
				pass++;
				var found = GLib.Environment.find_program_in_path("osqueryi");
				if (found != null && found != "") {
					osqueryi = found;
				}
#if WINDOWS
				if (osqueryi == "") {
					var program_files = GLib.Environment.get_variable("ProgramFiles");
					if (program_files == null || program_files == "") {
						program_files = "C:\\Program Files";
					}
					var installed = GLib.Path.build_filename(program_files, "osquery", "osqueryi.exe");
					if (GLib.FileUtils.test(installed, GLib.FileTest.EXISTS)) {
						osqueryi = installed;
					}
				}
#endif
				if (osqueryi != "") {
					break;
				}
				if (pass > 1) {
					break;
				}
				var url_path = "";
				try {
#if LINUX
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						Argus.AGENT_DATA_DIR, "download-path"),
						out url_path);
#else
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "download-path"),
						out url_path);
#endif
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				var download = new Download();
				var fetched = download.fetch(url_path.strip());
				if (fetched != 0) {
					return fetched;
				}
				string[] argv = {};
#if WINDOWS
				argv = new string[] { download.path, "/S" };
				if (download.path.has_suffix(".msi")) {
					argv = new string[] { "msiexec.exe", "/i", download.path, "/qn" };
				}
#elif LINUX
				if (download.path.has_suffix(".deb")) {
					argv = new string[] { "dpkg", "-i", download.path };
				} else if (download.path.has_suffix(".rpm")) {
					argv = new string[] { "rpm", "-U", download.path };
				}
#endif
				if (argv.length == 0) {
					GLib.warning("osquery installer %s", download.path);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				GLib.Subprocess installer;
				try {
					installer = new GLib.Subprocess.newv(argv, GLib.SubprocessFlags.NONE);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					installer.wait(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (installer.get_exit_status() != 0) {
					GLib.warning("osquery installer exited %d", installer.get_exit_status());
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				continue;
			}
			if (osqueryi == "") {
				GLib.warning("osqueryi is not installed");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.debug("syncing osquery rows");
			var code = 0;
			code += this.sync_table(osqueryi, "system_info", "SystemInfo");
			code += this.sync_table(osqueryi, "cpu_info", "CpuInfo");
			code += this.sync_table(osqueryi, "logged_in_users", "LoggedInUsers");
			code += this.sync_table(osqueryi, "interface_addresses", "InterfaceAddresses");
			return code;
		}

		private int sync_table(string osqueryi, string table, string class_name)
		{
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			new Query(osqueryi, row_type).select("SELECT * FROM " + table, rows);
			GLib.debug("SELECT * FROM %s %d rows", table, rows.size);
			var connection = this.application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Response response;
			try {
				response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", class_name, rows)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", table, response.error.message);
				return response.error.code;
			}
			GLib.debug("%s sent", table);
			return 0;
		}
	}
}
