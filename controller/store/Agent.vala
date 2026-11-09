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
	 * Registered machines on the open server.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.Agent}.
	 * {@link items} is the backing list. Rows are not copied into
	 * a {@link GLib.ListStore}. {@link load} talks to ''Agent.list''.
	 * A newer {@link load} drops a reply that is still waiting.
	 * The call sets {@link busy} until its reply. The page that
	 * made the call masks while {@link busy} is true, so the wait
	 * is visible.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Agent(app);
	 * store.load();
	 * }}}
	 */
	public class Agent : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.Agent> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.Agent>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.Agent> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * True after a list reply with no rows. False while a load
		 * is waiting, and false when rows are shown.
		 */
		public bool empty { get; private set; default = false; }

		/**
		 * True while the list call is in flight.
		 *
		 * The page that started the call masks until this is false.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * The list call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * ''Agent.remove'' succeeded.
		 */
		public signal void removed();

		/**
		 * @param app the controller process
		 */
		public Agent(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.Agent);
		}

		/**
		 * Number of machines in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Machine at ''position''.
		 *
		 * @param position zero-based index
		 * @return the row, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''Agent.list'' and apply it to {@link items}.
		 *
		 * The first reply fills the list. A later reply copies
		 * status, last connected, and connected onto the object
		 * already in the grid, appends a new id, and drops an id
		 * that is gone. The grid is not cleared. A newer call
		 * drops a reply that is still waiting.
		 * An empty list is omitted on the wire, so an unset return
		 * is no rows.
		 */
		public void load()
		{
			this.busy = true;
			this.empty = false;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.list"
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list machines", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list machines", response.error.message);
					return;
				}
				Gee.ArrayList<Argus.Shared.Agent> listed;
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.Agent>) response.retval.get_object();
				} else if (response.retval.type() == GLib.Type.INVALID) {
					listed = new Gee.ArrayList<Argus.Shared.Agent>();
				} else {
					this.busy = false;
					this.failed("Could not list machines", "invalid reply");
					return;
				}
				if (listed == null) {
					listed = new Gee.ArrayList<Argus.Shared.Agent>();
				}
				this.empty = listed.size == 0;
				if (this.items_store.size == 0) {
					this.items = listed;
					this.busy = false;
					return;
				}
				var by_id = new Gee.HashMap<string, Argus.Shared.Agent>();
				foreach (var row in this.items_store) {
					by_id.set(row.id.to_string(), row);
				}
				var seen = new Gee.HashMap<string, bool>();
				foreach (var row in listed) {
					var key = row.id.to_string();
					seen.set(key, true);
					if (!by_id.has_key(key)) {
						this.items_store.add(row);
						this.items_changed((uint) (this.items_store.size - 1), 0, 1);
						continue;
					}
					var current = by_id.get(key);
					current.status = row.status;
					current.last_connected = row.last_connected;
					current.connected = row.connected;
				}
				for (var i = this.items_store.size - 1; i >= 0; i--) {
					if (seen.has_key(this.items_store.get(i).id.to_string())) {
						continue;
					}
					this.items_store.remove_at(i);
					this.items_changed((uint) i, 1, 0);
				}
				this.busy = false;
			});
		}

		/**
		 * Delete one machine.
		 *
		 * The caller reloads {@link items} when it has finished
		 * the machines it is removing.
		 *
		 * @param id ''agent.id''
		 */
		public void remove(int id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.remove",
				args = OLLMrpc.args("i", id)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not remove", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not remove", response.error.message);
					return;
				}
				this.busy = false;
				this.removed();
			});
		}
	}
}
