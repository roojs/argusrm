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
	 * ''mounts'' rows for one agent on the open server.
	 */
	public class Mounts : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.OSQuery.Mounts> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.OSQuery.Mounts>();
		}
		private int epoch = 0;
		private int loaded_agent = -1;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.OSQuery.Mounts> items {
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

		public bool busy { get; private set; default = false; }

		public signal void failed(string heading, string message);

		public Mounts(Application app)
		{
			Object();
			this.app = app;
		}

		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.OSQuery.Mounts);
		}

		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''Mounts.list'' for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<Argus.Shared.OSQuery.Mounts>();
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Mounts.list",
				args = OLLMrpc.args("i", agent_id)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not load Mounts.list", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not load Mounts.list", response.error.message);
					return;
				}
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.items = (Gee.ArrayList<Argus.Shared.OSQuery.Mounts>) response.retval.get_object();
				} else {
					this.items = new Gee.ArrayList<Argus.Shared.OSQuery.Mounts>();
				}
				this.busy = false;
			});
		}
	}
}