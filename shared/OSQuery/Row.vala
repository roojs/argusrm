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
	 * ''ctype''. ''added_dt'', ''updated_dt'', and ''deleted_dt''
	 * are unix times written by {@link sync_rows}. ''0'' means
	 * that has not happened.
	 */
	public abstract class Row : GLib.Object, Json.Serializable, OLLMrpc.Bin.Serializable, AgentInfo
		, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }
		/**
		 * Unix time {@link sync_rows} inserted this row.
		 * ''0'' means that has not happened.
		 */
		public int added_dt { get; set; default = 0; }
		/**
		 * Unix time a stored column last changed.
		 * ''0'' means that has not happened.
		 */
		public int updated_dt { get; set; default = 0; }
		/**
		 * Unix time a snapshot left this row out.
		 * ''0'' means the row is still present. The row stays
		 * stored.
		 */
		public int deleted_dt { get; set; default = 0; }

		public abstract bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows);

		/**
		 * Osquery table this row is read from.
		 *
		 * @return the table name
		 */
		public abstract string table_name();

		/**
		 * RPC name for this row.
		 *
		 * @return the wire alias
		 */
		public abstract string rpc_name();

		/**
		 * Apply one agent's snapshot to ''table''.
		 *
		 * An insert sets ''added_dt''. A changed row sets
		 * ''updated_dt''. A stored row the snapshot left out
		 * stays, and ''deleted_dt'' is set. A row that comes
		 * back clears ''deleted_dt'' and sets ''updated_dt''.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows complete table snapshot
		 * @param table stored table name
		 * @param key_columns properties that identify a row
		 * @return true when every row has the expected type
		 */
		protected bool sync_rows<T>(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows, string table, string[] key_columns)
		{
			foreach (var row in rows) {
				if (row.get_type() != typeof(T)) {
					return false;
				}
			}
			string[] key_exclude = {};
			var object_class = (GLib.ObjectClass) typeof(T).class_ref();
			foreach (var prop in object_class.list_properties()) {
				if (!GLib.strv_contains(key_columns, prop.name)) {
					key_exclude += prop.name;
				}
			}
			var query = new SQ.Query<T>(db, table);
			var stored = new Gee.ArrayList<T>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in rows) {
				AgentInfo? old = null;
				foreach (var candidate in stored) {
					if (((AgentInfo) candidate).compare(row, key_exclude)) {
						old = (AgentInfo) candidate;
						break;
					}
				}
				var newer = (Row) row;
				newer.agent_id = agent_id;
				if (old == null) {
					newer.id = 0;
					newer.added_dt = now;
					newer.updated_dt = 0;
					newer.deleted_dt = 0;
					query.insert((T) row);
					continue;
				}
				newer.id = ((Row) old).id;
				newer.added_dt = ((Row) old).added_dt;
				if (((Row) old).deleted_dt != 0) {
					newer.deleted_dt = 0;
					newer.updated_dt = now;
					query.updateOld((T) old, (T) row);
					stored.remove((T) old);
					continue;
				}
				newer.deleted_dt = 0;
				if (!old.compare(row)) {
					newer.updated_dt = now;
					query.updateOld((T) old, (T) row);
				}
				stored.remove((T) old);
			}
			foreach (var old in stored) {
				if (((Row) old).deleted_dt != 0) {
					continue;
				}
				((Row) old).deleted_dt = now;
				query.updateById((T) old);
			}
			return true;
		}

		/**
		 * Database identity is assigned by the server, not sent by the agent.
		 */
		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop) throws GLib.Error
		{
			if (prop.name == "id" || prop.name == "agent-id") {
				return;
			}
			this.bin_default_write_prop(ctx, prop);
		}

		/**
		 * Ignore database identity supplied over the wire.
		 */
		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx, GLib.ParamSpec prop, uint8 type_byte) throws GLib.Error
		{
			this.bin_default_read_prop(ctx, prop, type_byte);
			if (prop.name == "id") {
				this.id = 0;
				return;
			}
			if (prop.name == "agent-id") {
				this.agent_id = 0;
			}
		}

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
