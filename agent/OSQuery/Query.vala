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
	 * var query = new Argus.Agent.OSQuery.Query(
	 *     osqueryi, typeof(Argus.Shared.OSQuery.SystemInfo));
	 * query.select("SELECT * FROM system_info", rows);
	 * }}}
	 */
	public class Query : GLib.Object
	{
		/**
		 * Path to ''osqueryi'', or the name looked up on ''PATH''.
		 */
		public string osqueryi = "";
		public GLib.Type row_type { get; construct; }

		/**
		 * @param osqueryi path or name of ''osqueryi''
		 * @param row_type shared osquery row class
		 */
		public Query(string osqueryi, GLib.Type row_type)
		{
			Object(row_type: row_type);
			this.osqueryi = osqueryi;
		}

		/**
		 * Run ''sql'' and append one row object per JSON row.
		 *
		 * {@link row_type} is an {@link Argus.Shared.OSQuery.Row}. A failed
		 * launch, a non-zero exit, or a body that is not a JSON
		 * list leaves ''rows'' as the caller passed it.
		 *
		 * @param sql osquery statement, column names unchanged
		 * @param rows list to append to
		 */
		public void select(string sql, Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> rows)
		{
			GLib.Subprocess child;
			try {
				child = new GLib.Subprocess.newv({
					this.osqueryi, "--json", sql
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
				var obj = Json.gobject_deserialize(this.row_type, element);
				if (obj == null) {
					continue;
				}
				rows.add((Argus.Shared.OSQuery.AgentInfo) obj);
			}
		}
	}
}
