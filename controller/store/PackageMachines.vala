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
	 * Machines that have one package name.
	 *
	 * A {@link GLib.ListModel} of
	 * {@link Argus.Shared.SQV.PackageMachine}.
	 * {@link load} is ''PackageMachine.machines''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.PackageMachines(app);
	 * store.load("bash", "deb");
	 * }}}
	 */
	public class PackageMachines : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQV.PackageMachine> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQV.PackageMachine>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last machines reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQV.PackageMachine> items {
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
		public PackageMachines(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQV.PackageMachine);
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
		 * Load machines that have one package name.
		 *
		 * Clears the grid, then calls ''PackageMachine.machines''.
		 * A newer call drops a reply that is still waiting.
		 *
		 * @param name exact package or program name
		 * @param kind ''deb'', ''rpm'', or ''programs''
		 */
		public void load(string name, string kind)
		{
			this.busy = true;
			this.empty = false;
			this.items = new Gee.ArrayList<Argus.Shared.SQV.PackageMachine>();
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "PackageMachine.machines",
				args = OLLMrpc.args("ss", name, kind)
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
				if (!response.retval.type().is_a(typeof(Gee.ArrayList)) &&
					response.retval.type() != GLib.Type.INVALID) {
					this.busy = false;
					this.failed("Could not list machines", "invalid reply");
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.SQV.PackageMachine>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.SQV.PackageMachine>)
						response.retval.get_object();
				}
				if (listed == null) {
					listed = new Gee.ArrayList<Argus.Shared.SQV.PackageMachine>();
				}
				this.items = listed;
				this.empty = listed.size == 0;
				this.busy = false;
			});
		}
	}
}
