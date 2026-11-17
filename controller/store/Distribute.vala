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
	 * Machines that can take one distributable.
	 *
	 * A {@link GLib.ListModel} of
	 * {@link Argus.Shared.SQV.DistributeMachine}.
	 * {@link load} is ''DistributeMachine.machines''. {@link selected} is the
	 * ticked rows. The dialog asks {@link Distributable} to create the
	 * task.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Distribute(app);
	 * store.load("Argus RM Agent", "windows", "1.2.3");
	 * }}}
	 */
	public class Distribute : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQV.DistributeMachine> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last machines reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQV.DistributeMachine> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				foreach (var row in this.items_store) {
					row.notify["picked"].connect(() => {
						this.tally();
					});
				}
				this.tally();
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * How many machines are ticked.
		 *
		 * Changes when the list is replaced and when a row's
		 * {@link Argus.Shared.SQV.DistributeMachine.picked} changes.
		 */
		public int picked { get; private set; default = 0; }

		/**
		 * True after a load with no rows. False while a load is waiting.
		 */
		public bool empty { get; private set; default = false; }

		/**
		 * True while {@link load} is in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * A call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * @param app the controller process
		 */
		public Distribute(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Count ticked machines into {@link picked}.
		 */
		private void tally()
		{
			var count = 0;
			foreach (var row in this.items_store) {
				if (!row.picked) {
					continue;
				}
				count++;
			}
			this.picked = count;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQV.DistributeMachine);
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
		 * Ticked machines, including one hidden by the current search.
		 *
		 * @return the rows whose {@link Argus.Shared.SQV.DistributeMachine.picked}
		 * is true
		 */
		public Gee.ArrayList<Argus.Shared.SQV.DistributeMachine> selected()
		{
			var rows = new Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>();
			foreach (var row in this.items) {
				if (!row.picked || row.agent_id < 1) {
					continue;
				}
				rows.add(row);
			}
			return rows;
		}

		/**
		 * Load machines for one product.
		 *
		 * Clears the grid, then calls ''DistributeMachine.machines''.
		 * A newer call drops a reply that is still waiting. Each row's
		 * {@link Argus.Shared.SQV.DistributeMachine.version} is ''version''.
		 * A row with an installed copy starts ticked.
		 *
		 * @param name ''distributable.name'', matched to ''programs.name''
		 * @param platform ''distributable.platform''
		 * @param version latest version the grid will send
		 */
		public void load(string name, string platform, string version)
		{
			this.busy = true;
			this.empty = false;
			this.items = new Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>();
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "DistributeMachine.machines",
				args = OLLMrpc.args("ss", name, platform)
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
				Gee.ArrayList<Argus.Shared.SQV.DistributeMachine> listed;
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>)
						response.retval.get_object();
				} else if (response.retval.type() == GLib.Type.INVALID) {
					listed = new Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>();
				} else {
					this.busy = false;
					this.failed("Could not list machines", "invalid reply");
					return;
				}
				if (listed == null) {
					listed = new Gee.ArrayList<Argus.Shared.SQV.DistributeMachine>();
				}
				foreach (var row in listed) {
					row.version = version;
					row.picked = row.existing != "";
				}
				this.items = listed;
				this.empty = listed.size == 0;
				this.busy = false;
			});
		}
	}
}
