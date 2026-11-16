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

namespace Argus.Controller.Store
{
	/**
	 * Shared column CSV reader for controller tabs and stores.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var columns = this.read_columns("system_info");
	 * var fields = this.read_columns("machine_general", true);
	 * }}}
	 */
	public interface Base : GLib.Object
	{
		/**
		 * Read column definitions from ''/argusrm/columns/<table>.csv''.
		 *
		 * When ''has_indent'' is true, column 0 holds the indent level
		 * and the standard columns shift by one, with optional trailing
		 * source table key.
		 *
		 * @param table file name under columns without ''.csv''
		 * @param has_indent true when the first CSV column is indent
		 * @return ordered list of {@link ColumnSchema} rows
		 */
		public Gee.ArrayList<ColumnSchema> read_columns(string table, bool has_indent = false)
		{
			var rows = new Gee.ArrayList<ColumnSchema>();
			var text = (string) GLib.resources_lookup_data(
				"/argusrm/columns/" + table + ".csv",
				GLib.ResourceLookupFlags.NONE).get_data();
			var headings = true;
			var offset = has_indent ? 1 : 0;
			foreach (var line in text.split("\n")) {
				if (line.strip() == "") {
					continue;
				}
				if (headings) {
					headings = false;
					continue;
				}
				var parts = line.strip().split(",");
				if (parts.length < offset + 4) {
					continue;
				}
				if (parts[offset].strip() == "" || parts[offset + 1].strip() == "") {
					continue;
				}
				var indent = 0;
				if (has_indent) {
					int.try_parse(parts[0].strip(), out indent);
				}
				var width = -1;
				if (!int.try_parse(parts[offset + 3].strip(), out width) || width < 1) {
					width = -1;
				}
				var format = "text";
				if (parts.length > offset + 4 && parts[offset + 4].strip() != "") {
					format = parts[offset + 4].strip();
				}
				var source = "";
				if (parts.length > offset + 6) {
					source = parts[offset + 6].strip();
				}
				rows.add(new ColumnSchema() {
					indent = indent > 0 ? indent : 0,
					title = parts[offset].strip(),
					name = parts[offset + 1].strip(),
					visible = parts[offset + 2].strip() == "ON",
					width = width,
					format = format,
					sort = parts.length > offset + 5 && parts[offset + 5].strip() == "ON",
					source = source
				});
			}
			return rows;
		}
	}
}
