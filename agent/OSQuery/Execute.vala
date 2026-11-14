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
	 * Run one osquery statement and fill objects from the JSON rows.
	 *
	 * ''osqueryi --json'' prints the rows.
	 * {@link Json.gobject_deserialize} fills one
	 * {@link Argus.Shared.OSQuery.Row} per JSON object. A column
	 * with no property is skipped.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
	 * new Argus.Agent.OSQuery.Execute(application).select(
	 *     typeof(Argus.Shared.OSQuery.SystemInfo),
	 *     "SELECT * FROM system_info", rows);
	 * }}}
	 */
	public class Execute : GLib.Object
	{
		/**
		 * Path to ''osqueryi''. Empty until {@link init}.
		 */
		public static string osqueryi = "";

		/**
		 * Find ''osqueryi'' when {@link osqueryi} is still empty.
		 *
		 * The first call searches ''PATH''. On Windows it then
		 * checks ''Program Files\osquery\osqueryi.exe''. A hit
		 * is kept. A miss leaves the string empty, so the next
		 * call searches again.
		 */
		public static void init()
		{
			if (Execute.osqueryi != "") {
				return;
			}
			var found = GLib.Environment.find_program_in_path("osqueryi");
			if (found != null && found != "") {
				Execute.osqueryi = found;
				return;
			}
#if WINDOWS
			var program_files = GLib.Environment.get_variable("ProgramFiles");
			if (program_files == null || program_files == "") {
				program_files = "C:\\Program Files";
			}
			var installed = GLib.Path.build_filename(
				program_files, "osquery", "osqueryi.exe");
			if (GLib.FileUtils.test(installed, GLib.FileTest.EXISTS)) {
				Execute.osqueryi = installed;
			}
#endif
		}

		private Application application;

		/**
		 * @param application agent whose server connection is open
		 */
		public Execute(Application application)
		{
			this.application = application;
		}

		/**
		 * Run ''sql'' and append one row object per JSON row.
		 *
		 * ''row_type'' is an {@link Argus.Shared.OSQuery.Row}. A failed
		 * launch, a non-zero exit, or a body that is not a JSON
		 * list leaves ''rows'' as the caller passed it.
		 *
		 * @param row_type shared osquery row class
		 * @param sql osquery statement, column names unchanged
		 * @param rows list to append to
		 */
		public void select(GLib.Type row_type, string sql, Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> rows)
		{
			GLib.Subprocess child;
			try {
				Execute.init();
				if (Execute.osqueryi == "") {
					return;
				}
				child = new GLib.Subprocess.newv({
					Execute.osqueryi, "--json", sql
				}, GLib.SubprocessFlags.STDOUT_PIPE);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			string? stdout_text = null;
			var queried = false;
			try {
				queried = child.communicate_utf8(null, null, out stdout_text, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			if (!queried || child.get_exit_status() != 0) {
				GLib.warning("osqueryi exited %d", child.get_exit_status());
				return;
			}
			var output = stdout_text != null ? stdout_text : "";
			var parser = new Json.Parser();
			try {
				parser.load_from_data(output);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				GLib.warning("osquery json was not a list");
				return;
			}
			var list = root.get_array();
			var count = list.get_length();
			for (var i = 0; i < (int) count; i++) {
				var element = list.get_element(i);
				if (element.get_node_type() != Json.NodeType.OBJECT) {
					continue;
				}
				var obj = Json.gobject_deserialize(row_type, element);
				if (obj == null) {
					continue;
				}
				rows.add((Argus.Shared.OSQuery.AgentInfo) obj);
			}
		}

		/**
		 * Post the startup tables, then the one package class.
		 */
		public void send_startup()
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return;
			}
			var code = 0;
			code += this.sync_table("system_info", "SystemInfo");
			code += this.sync_table("cpu_info", "CpuInfo");
#if LINUX
			// deal with buggy logged in users in osquery
			code += new LoggedInUsers().send(this.application);
#else
			code += this.sync_table("logged_in_users", "LoggedInUsers");
#endif
			code += this.sync_table("users", "Users");
			code += this.sync_table("groups", "Groups");
			code += this.sync_table("user_groups", "UserGroups");
			code += this.sync_table("interface_addresses", "InterfaceAddresses");
			code += this.sync_table("os_version", "OsVersion");
			code += this.send_packages();
			GLib.debug("osquery %d", code);
		}

		/**
		 * Query one table and post it.
		 *
		 * @param table osquery table name
		 * @param class_name registered row name
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		internal int sync_table(string table, string class_name)
		{
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			this.select(row_type, "SELECT * FROM " + table, rows);
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
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", table, response.error.message);
				return response.error.code;
			}
			if (table == "os_version" && rows.size > 0) {
				this.application.os_version = (Argus.Shared.OSQuery.OsVersion) rows.get(0);
			}
			GLib.debug("%s sent", table);
			return 0;
		}

		/**
		 * Forward the one package class for this host.
		 *
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		internal int send_packages()
		{
			switch (this.application.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return new DebPackages().send(this.application);

				case Argus.Shared.OSQuery.PackageManager.DNF:
					return new RpmPackages().send(this.application);

				case Argus.Shared.OSQuery.PackageManager.WIN:
					return new Programs().send(this.application);

				default:
					return 0;
			}
		}
	}
}
