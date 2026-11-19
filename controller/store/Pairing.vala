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
	 * Machines waiting for registration approval.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.AgentPending}.
	 * {@link items} is the backing list. {@link picked} is the ticked
	 * rows, keyed by {@link Argus.Shared.AgentPending.id}. A tick
	 * puts the row in that map. Clearing the tick takes it out.
	 * {@link append} adds one pending request. {@link drop} takes
	 * one row off the list. {@link clear} drops the list and the map.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Pairing();
	 * store.append(4, "192.168.88.14", "web-03");
	 * }}}
	 */
	public class Pairing : GLib.Object, GLib.ListModel
	{
		private Gee.ArrayList<Argus.Shared.AgentPending> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.AgentPending>();
		}

		/**
		 * Ticked rows, keyed by {@link Argus.Shared.AgentPending.id}.
		 */
		public Gee.HashMap<int64?, Argus.Shared.AgentPending> picked {
			get; private set; default = new Gee.HashMap<int64?, Argus.Shared.AgentPending>();
		}

		/**
		 * Rows in arrival order.
		 */
		public Gee.ArrayList<Argus.Shared.AgentPending> items {
			get {
				return this.items_store;
			}
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.AgentPending);
		}

		/**
		 * Number of machines in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items_store.size;
		}

		/**
		 * Machine at ''position''.
		 *
		 * @param position zero-based index
		 * @return the row, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items_store.size) {
				return null;
			}
			return this.items_store.get((int) position);
		}

		/**
		 * Drop every waiting machine.
		 */
		public void clear()
		{
			var removed = (uint) this.items_store.size;
			this.picked.clear();
			this.items_store.clear();
			this.items_changed(0, removed, 0);
		}

		/**
		 * Take one machine off the list.
		 *
		 * The row leaves {@link items} and {@link picked}.
		 * An unknown id does nothing.
		 *
		 * @param id ''agent_pending.id''
		 */
		public void drop(int64 id)
		{
			this.picked.unset(id);
			for (var i = 0; i < this.items_store.size; i++) {
				if (this.items_store.get(i).id != id) {
					continue;
				}
				this.items_store.remove_at(i);
				this.items_changed((uint) i, 1, 0);
				return;
			}
		}

		/**
		 * Add one machine from a pending registration.
		 *
		 * @param id ''agent_pending.id''
		 * @param ip peer address
		 * @param name machine name, or empty
		 */
		public void append(int64 id, string ip, string name)
		{
			var row = new Argus.Shared.AgentPending() {
				id = id,
				ip = ip,
				hostname = name
			};
			row.notify["picked"].connect(() => {
				var was = this.picked.has_key(row.id);
				if (row.picked && !was) {
					this.picked.set(row.id, row);
				}
				if (!row.picked && was) {
					this.picked.unset(row.id);
				}
				if (was == this.picked.has_key(row.id)) {
					return;
				}
				this.changed(row);
			});
			this.items_store.add(row);
			this.items_changed((uint) (this.items_store.size - 1), 0, 1);
		}

		/**
		 * A tick on a row changed.
		 *
		 * @param row the machine whose tick changed
		 */
		public signal void changed(Argus.Shared.AgentPending row);
	}
}
