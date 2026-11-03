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

namespace Argus.Server.GitHub
{
	/**
	 * One GitHub release.
	 *
	 * {@link Json.gobject_from_data} fills the properties from
	 * ''GET /repos/{owner}/{repo}/releases/latest''. The property
	 * name is the JSON member. A nested user, such as ''author'',
	 * is not a property and is skipped. A null string stays "".
	 * This program reads the record. It does not write it back.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var release = (Argus.Server.GitHub.Release) Json.gobject_from_data(
	 *     typeof(Argus.Server.GitHub.Release), body);
	 * }}}
	 */
	public class Release : GLib.Object, Json.Serializable
	{
		public string url { get; set; default = ""; }
		public string assets_url { get; set; default = ""; }
		public string upload_url { get; set; default = ""; }
		public string html_url { get; set; default = ""; }
		/**
		 * GitHub id. ''int64'' because it does not fit in ''int''.
		 */
		public int64 id { get; set; default = 0; }
		public string node_id { get; set; default = ""; }
		public string tag_name { get; set; default = ""; }
		public string target_commitish { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public bool draft { get; set; default = false; }
		public bool prerelease { get; set; default = false; }
		public string created_at { get; set; default = ""; }
		public string published_at { get; set; default = ""; }
		public string tarball_url { get; set; default = ""; }
		public string zipball_url { get; set; default = ""; }
		public string body { get; set; default = ""; }
		/**
		 * Files attached to this release.
		 */
		public Gee.ArrayList<Asset> assets { get; set; default = new Gee.ArrayList<Asset>(); }

		/**
		 * Property for a JSON member name.
		 *
		 * Underscores in the member use the GObject spelling.
		 *
		 * @param name JSON member name
		 * @return the property, or null when this release has none
		 */
		public unowned GLib.ParamSpec? find_property(string name)
		{
			unowned GLib.ParamSpec? pspec = this.get_class().find_property(name);
			if (pspec != null) {
				return pspec;
			}
			return this.get_class().find_property(name.replace("_", "-"));
		}

		/**
		 * Fill one property from its JSON node.
		 *
		 * A null string becomes "". ''assets'' is one
		 * {@link Asset} per element. Anything else uses the default.
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
			if (property_node.get_node_type() == Json.NodeType.NULL &&
				pspec.value_type == GLib.Type.STRING) {
				value = GLib.Value(GLib.Type.STRING);
				value.set_string("");
				return true;
			}
			if (property_name != "assets") {
				return this.default_deserialize_property(
					property_name, out value, pspec, property_node);
			}
			var assets = new Gee.ArrayList<Asset>();
			if (property_node.get_node_type() == Json.NodeType.ARRAY) {
				var list = property_node.get_array();
				var count = list.get_length();
				for (var i = 0; i < (int) count; i++) {
					var element = list.get_element(i);
					if (element.get_node_type() != Json.NodeType.OBJECT) {
						continue;
					}
					var obj = Json.gobject_deserialize(typeof(Asset), element);
					if (obj == null) {
						continue;
					}
					assets.add((Asset) obj);
				}
			}
			value = GLib.Value(typeof(Gee.ArrayList));
			value.set_object(assets);
			return true;
		}
	}

	/**
	 * One file attached to a {@link Release}.
	 *
	 * {@link Json.gobject_deserialize} fills the properties from
	 * one element of ''assets''. The property name is the JSON
	 * member. ''uploader'' is not a property and is skipped.
	 * A null string stays "". This program reads the record.
	 * It does not write it back.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var asset = release.assets.get(0);
	 * }}}
	 */
	public class Asset : GLib.Object, Json.Serializable
	{
		public string url { get; set; default = ""; }
		/**
		 * GitHub id. ''int64'' because it does not fit in ''int''.
		 */
		public int64 id { get; set; default = 0; }
		public string node_id { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public string label { get; set; default = ""; }
		public string content_type { get; set; default = ""; }
		public string state { get; set; default = ""; }
		/**
		 * Byte count. ''int64'' because it does not fit in ''int''.
		 */
		public int64 size { get; set; default = 0; }
		public int64 download_count { get; set; default = 0; }
		public string created_at { get; set; default = ""; }
		public string updated_at { get; set; default = ""; }
		public string browser_download_url { get; set; default = ""; }

		/**
		 * Property for a JSON member name.
		 *
		 * Underscores in the member use the GObject spelling.
		 *
		 * @param name JSON member name
		 * @return the property, or null when this asset has none
		 */
		public unowned GLib.ParamSpec? find_property(string name)
		{
			unowned GLib.ParamSpec? pspec = this.get_class().find_property(name);
			if (pspec != null) {
				return pspec;
			}
			return this.get_class().find_property(name.replace("_", "-"));
		}

		/**
		 * Fill one property from its JSON node.
		 *
		 * A null string becomes "". Anything else uses the default.
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
			if (property_node.get_node_type() == Json.NodeType.NULL &&
				pspec.value_type == GLib.Type.STRING) {
				value = GLib.Value(GLib.Type.STRING);
				value.set_string("");
				return true;
			}
			return this.default_deserialize_property(
				property_name, out value, pspec, property_node);
		}
	}
}
