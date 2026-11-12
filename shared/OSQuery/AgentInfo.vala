/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Shared.OSQuery
{
	/**
	 * Data associated with one registered agent.
	 */
	public interface AgentInfo : GLib.Object
	{
		public abstract int64 agent_id { get; set; }

		/**
		 * Replace this agent's rows with one snapshot.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows complete table snapshot
		 * @return true when every row has the expected type
		 */
		public abstract bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows);

		/**
		 * Compare persisted data properties, excluding database identity.
		 *
		 * @param newer row received from the agent
		 * @param exclude additional property names to ignore
		 * @return true when the rows contain identical data
		 */
		public virtual bool compare(AgentInfo newer, string[] exclude = {})
		{
			if (this.get_type() != newer.get_type()) {
				return false;
			}
			var object_class = (GLib.ObjectClass) this.get_type().class_ref();
			foreach (var prop in object_class.list_properties()) {
				if (prop.name == "id" || prop.name == "agent-id" || GLib.strv_contains(exclude, prop.name)) {
					continue;
				}
				var older_value = GLib.Value(prop.value_type);
				var newer_value = GLib.Value(prop.value_type);
				((GLib.Object) this).get_property(prop.name, ref older_value);
				((GLib.Object) newer).get_property(prop.name, ref newer_value);
				var value_type = prop.value_type.is_enum() ? GLib.Type.ENUM : prop.value_type;
				switch (value_type) {
					case GLib.Type.BOOLEAN:
						if (older_value.get_boolean() != newer_value.get_boolean()) {
							return false;
						}
						break;
					case GLib.Type.INT:
						if (older_value.get_int() != newer_value.get_int()) {
							return false;
						}
						break;
					case GLib.Type.INT64:
						if (older_value.get_int64() != newer_value.get_int64()) {
							return false;
						}
						break;
					case GLib.Type.STRING:
						if (older_value.get_string() != newer_value.get_string()) {
							return false;
						}
						break;
					case GLib.Type.ENUM:
						if (older_value.get_enum() != newer_value.get_enum()) {
							return false;
						}
						break;
					default:
						return false;
				}
			}
			return true;
		}
	}
}
