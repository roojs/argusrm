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

namespace Argus.Shared.OSQuery
{
	/**
	 * One osquery row.
	 *
	 * {@link Json.Serializable} fills the properties from
	 * ''osqueryi --json''. The property name is the column name.
	 * Numeric columns are ''int''. A value that does not fit in
	 * ''int'' is ''int64''. The column ''type'' is the property
	 * ''ctype''.
	 */
	public abstract class Row : GLib.Object, Json.Serializable, OLLMrpc.Bin.Serializable
	{
		/**
		 * Property for a JSON member name.
		 *
		 * ''type'' is ''ctype''. Other names use the GObject
		 * spelling of the column.
		 *
		 * @param name JSON member name
		 * @return the property, or null when this row has none
		 */
		public unowned GLib.ParamSpec? find_property(string name)
		{
			var prop = name == "type" ? "ctype" : name;
			unowned GLib.ParamSpec? pspec = this.get_class().find_property(prop);
			if (pspec != null) {
				return pspec;
			}
			return this.get_class().find_property(prop.replace("_", "-"));
		}

		/**
		 * Store one deserialized property.
		 *
		 * @param pspec property to set
		 * @param value value from JSON
		 */
		public new void Json.Serializable.set_property(GLib.ParamSpec pspec, GLib.Value value)
		{
			base.set_property(pspec.get_name(), value);
		}

		/**
		 * Read one property for JSON.
		 *
		 * @param pspec property to read
		 * @return the current value
		 */
		public new GLib.Value Json.Serializable.get_property(GLib.ParamSpec pspec)
		{
			var val = GLib.Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}

		/**
		 * Fill one property from its JSON node.
		 *
		 * Osquery prints numbers as strings. An ''int'' or
		 * ''int64'' property parses that string. Anything else
		 * uses the default.
		 *
		 * @param property_name JSON member name
		 * @param value filled value
		 * @param pspec property being filled
		 * @param property_node JSON for this member
		 * @return true when the property was filled
		 */
		public override bool deserialize_property(
			string property_name,
			out GLib.Value value,
			GLib.ParamSpec pspec,
			Json.Node property_node
		) {
			if (property_node.get_node_type() == Json.NodeType.VALUE &&
				property_node.get_value_type() == GLib.Type.STRING &&
				pspec.value_type == GLib.Type.INT) {
				value = GLib.Value(GLib.Type.INT);
				var text = property_node.get_string();
				value.set_int(int.parse(text != null ? text : ""));
				return true;
			}
			if (property_node.get_node_type() == Json.NodeType.VALUE &&
				property_node.get_value_type() == GLib.Type.STRING &&
				pspec.value_type == GLib.Type.INT64) {
				value = GLib.Value(GLib.Type.INT64);
				var text = property_node.get_string();
				value.set_int64(int64.parse(text != null ? text : ""));
				return true;
			}
			return this.default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
	}
}
