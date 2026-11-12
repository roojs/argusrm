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
	 * ''rpm_packages'' rows on the open server.
	 *
	 * A {@link GLib.ListModel} of
	 * {@link Argus.Shared.OSQuery.RpmPackages}. {@link items} is the
	 * backing list. {@link load} talks to ''RpmPackages.list''.
	 * That call already adds the rows up by name. The call sets
	 * {@link busy} until its reply. The first reply fills the
	 * list. A later reply keeps a row whose name is unchanged,
	 * inserts a new name, and drops a name that is gone. A newer
	 * {@link load} drops a reply that is still waiting. An empty
	 * list is omitted on the wire, so an unset return is no rows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.RpmPackages(app);
	 * store.load(0);
	 * }}}
	 */
	public class RpmPackages : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.OSQuery.RpmPackages> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.OSQuery.RpmPackages>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.OSQuery.RpmPackages> items {
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
		 * True while the list call is in flight.
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
		 * @param app the controller process
		 */
		public RpmPackages(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.OSQuery.RpmPackages);
		}

		/**
		 * Number of rows in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Row at ''position''.
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
		 * Fetch ''RpmPackages.list'' and apply it to {@link items}.
		 *
		 * Zero asks for every agent, added up by name. An
		 * ''agent_id'' greater than zero asks for that agent's
		 * stored rows. The call passes ''since'' zero, so a
		 * deleted row stays out. The first reply fills the list.
		 * A later reply is applied by name.
		 *
		 * @param agent_id agent id, or zero for every agent
		 */
		public void load(int agent_id)
		{
			this.busy = true;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "RpmPackages.list",
				args = OLLMrpc.args("ii", agent_id, 0)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list RPM packages", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list RPM packages", response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.RpmPackages>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.RpmPackages>) response.retval.get_object();
				}
				if (this.items_store.size == 0) {
					this.items = listed;
					this.busy = false;
					return;
				}
				var at = new Gee.HashMap<string, int>();
				for (var i = 0; i < this.items_store.size; i++) {
					at.set(this.items_store.get(i).name, i);
				}
				foreach (var row in listed) {
					if (!at.has_key(row.name)) {
						this.items_store.add(row);
						this.items_changed((uint) (this.items_store.size - 1), 0, 1);
						continue;
					}
					var index = at.get(row.name);
					var have = this.items_store.get(index);
					at.unset(row.name);
					if (have.arch == row.arch &&
						have.package_group == row.package_group &&
						have.source == row.source &&
						have.vendor == row.vendor &&
						have.min_version == row.min_version &&
						have.max_version == row.max_version &&
						have.max_size == row.max_size &&
						have.installed == row.installed) {
						continue;
					}
					this.items_store.set(index, row);
					this.items_changed((uint) index, 1, 1);
				}
				var gone = new Gee.ArrayList<int>();
				foreach (var index in at.values) {
					gone.add(index);
				}
				gone.sort((a, b) => {
					if (a == b) {
						return 0;
					}
					if (a > b) {
						return -1;
					}
					return 1;
				});
				foreach (var index in gone) {
					this.items_store.remove_at(index);
					this.items_changed((uint) index, 1, 0);
				}
				this.busy = false;
			});
		}
	}
}
