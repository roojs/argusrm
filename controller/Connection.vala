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

namespace Argus.Controller
{
	/**
	 * Non-secret connection data for one Argus Remote Manager server.
	 *
	 * The user's ''connections.json'' file is an array of these records.
	 * Credentials and CA trust remain in password storage.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var connection = new Argus.Controller.Connection() {
	 *     name = "office-server",
	 *     addresses = { "192.0.2.10" },
	 *     port = 817
	 * };
	 * }}}
	 */
	public class Connection : GLib.Object, Json.Serializable
	{
		public string name { get; set; default = ""; }
		public string[] addresses { get; set; default = {}; }
		public int port { get; set; default = 0; }
	}

	/**
	 * Saved servers from ''connections.json''.
	 *
	 * The file is a JSON array of {@link Connection}. Callers wrap
	 * that array as the ''rows'' member before
	 * {@link Json.gobject_from_data}. Each element is one server.
	 * A non-object element is skipped. This program reads the file.
	 * It does not write it back here.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var saved = (Argus.Controller.Connections)
	 *     Json.gobject_from_data(typeof(Argus.Controller.Connections),
	 *         "{\"rows\":" + text + "}");
	 * }}}
	 */
	public class Connections : GLib.Object, Json.Serializable
	{
		/**
		 * Servers in the file, in file order.
		 */
		public Gee.ArrayList<Connection> rows {
			get; set; default = new Gee.ArrayList<Connection>();
		}

		/**
		 * Fill one property from its JSON node.
		 *
		 * ''rows'' is one {@link Connection} per element. Anything
		 * else uses the default.
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
			if (property_name != "rows") {
				return this.default_deserialize_property(
					property_name, out value, pspec, property_node);
			}
			var rows = new Gee.ArrayList<Connection>();
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var list = property_node.get_array();
				var count = list.get_length();
				for (var i = 0; i < (int) count; i++) {
					var element = list.get_element(i);
					if (element.get_node_type() != Json.NodeType.OBJECT) {
						continue;
					}
					var obj = Json.gobject_deserialize(typeof(Connection), element);
					if (obj == null) {
						continue;
					}
					rows.add((Connection) obj);
				}
			}
			value = GLib.Value(typeof(Gee.ArrayList));
			value.set_object(rows);
			return true;
		}
	}
}
