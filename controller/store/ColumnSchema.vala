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
	 * One column or vertical field definition parsed from
	 * ''/argusrm/columns/*.csv''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var col = new Argus.Controller.Store.ColumnSchema() {
	 *     title = "Hostname",
	 *     name = "hostname",
	 *     visible = true,
	 *     width = 160,
	 *     format = "text",
	 *     sort = true,
	 *     indent = 1,
	 *     source = "system_info"
	 * };
	 * }}}
	 */
	public class ColumnSchema : GLib.Object
	{
		/**
		 * Column header or field label.
		 */
		public string title { get; set; default = ""; }

		/**
		 * Database / JSON property name (hyphens stand in for
		 * underscores).
		 */
		public string name { get; set; default = ""; }

		/**
		 * True when the column starts visible (''ON'' in the CSV).
		 */
		public bool visible { get; set; default = false; }

		/**
		 * Fixed width in pixels, or ''-1'' to expand.
		 */
		public int width { get; set; default = -1; }

		/**
		 * Display format (''text'', ''number'', ''bytes'', ''mhz'',
		 * ''date'', ''status'', ''expander'', etc.).
		 */
		public string format { get; set; default = "text"; }

		/**
		 * True when sorting is enabled (''ON'' in the CSV).
		 */
		public bool sort { get; set; default = false; }

		/**
		 * Indentation level when the CSV includes an indent column.
		 */
		public int indent { get; set; default = 0; }

		/**
		 * Source query key when multiple tables fill one vertical view.
		 */
		public string source { get; set; default = ""; }

		/**
		 * Format ''row'' for this schema entry into a {@link KeyValue}.
		 *
		 * @param row source row object
		 * @return formatted key-value entry
		 */
		public KeyValue display_value(GLib.Object row)
		{
			var ret = new KeyValue() {
				key = this.title,
				indent = this.indent,
				expander = this.format == "expander",
				expanded = true
			};
			ret.set_data("row", row);
			if (this.format == "expander") {
				return ret;
			}
			var prop = row.get_class().find_property(this.name);
			if (prop == null) {
				return ret;
			}
			var value = GLib.Value(prop.value_type);
			row.get_property(this.name, ref value);
			switch (this.format) {
				case "bytes":
					var count = prop.value_type == GLib.Type.INT64 ?
						(uint64) value.get_int64() :
						(uint64) value.get_int();
					ret.val = GLib.format_size(count, GLib.FormatSizeFlags.IEC_UNITS)
						.replace("\xc2\xa0", " ")
						.replace("TiB", "TB")
						.replace("GiB", "GB")
						.replace("MiB", "MB")
						.replace("KiB", "KB")
						.replace(".0 ", " ");
					return ret;

				case "date":
					var stamp = prop.value_type == GLib.Type.INT64 ?
						value.get_int64() :
						(int64) value.get_int();
					if (stamp < 1) {
						return ret;
					}
					var when = new GLib.DateTime.from_unix_local(stamp);
					if (when == null) {
						return ret;
					}
					var formatted = when.format("%Y-%m-%d");
					if (formatted != null) {
						ret.val = formatted;
					}
					var full = when.format("%Y-%m-%d %H:%M:%S");
					if (full != null) {
						ret.tooltip = full;
					}
					return ret;

				case "mhz":
					var mhz = (int64) 0;
					if (prop.value_type == GLib.Type.INT64) {
						mhz = value.get_int64();
					}
					if (prop.value_type == GLib.Type.INT) {
						mhz = (int64) value.get_int();
					}
					if (mhz > 0) {
						ret.val = mhz.to_string("%'" + int64.FORMAT) + " MHz";
					}
					return ret;

				case "status":
					switch (value.get_int()) {
						case 1:
							ret.css_class = "status-ok";
							break;

						case 2:
							ret.css_class = "status-warn";
							break;

						case 0:
							ret.css_class = "status-bad";
							break;

						default:
							break;
					}
					var tip_prop = row.get_class().find_property("tooltip-" + this.name);
					if (tip_prop == null || tip_prop.value_type != GLib.Type.STRING) {
						return ret;
					}
					var tip_val = GLib.Value(GLib.Type.STRING);
					row.get_property("tooltip-" + this.name, ref tip_val);
					var tip = tip_val.get_string();
					if (tip != null) {
						ret.val = tip;
						ret.tooltip = tip;
					}
					return ret;

				default:
					break;
			}
			switch (prop.value_type) {
				case GLib.Type.INT:
					ret.val = value.get_int().to_string();
					return ret;

				case GLib.Type.INT64:
					ret.val = value.get_int64().to_string();
					return ret;

				default:
					var str = value.get_string();
					if (str != null) {
						ret.val = str;
					}
					return ret;
			}
		}
	}
}
