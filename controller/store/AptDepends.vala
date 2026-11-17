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
	 * Packages removed with one Debian package.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.SQV.AptDepends}.
	 * {@link load} is ''AptDepends.removed''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.AptDepends(app);
	 * store.load("libc6");
	 * }}}
	 */
	public class AptDepends : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQV.AptDepends> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQV.AptDepends>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last removed reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQV.AptDepends> items {
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
		public AptDepends(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQV.AptDepends);
		}

		/**
		 * Number of packages in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Package at ''position''.
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
		 * Load packages removed with one name.
		 *
		 * Clears the grid, then calls ''AptDepends.removed''.
		 * A newer call drops a reply that is still waiting.
		 *
		 * @param name exact package name
		 */
		public void load(string name)
		{
			this.busy = true;
			this.empty = false;
			this.items = new Gee.ArrayList<Argus.Shared.SQV.AptDepends>();
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "AptDepends.removed",
				args = OLLMrpc.args("s", name)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				try {
					var response = this.app.rpc.call.end(res);
					if (response.error != null) {
						this.busy = false;
						this.failed("Could not list packages", response.error.message);
						return;
					}
					if (!response.retval.type().is_a(typeof(Gee.ArrayList)) &&
						response.retval.type() != GLib.Type.INVALID) {
						this.busy = false;
						this.failed("Could not list packages", "invalid reply");
						return;
					}
					var listed = new Gee.ArrayList<Argus.Shared.SQV.AptDepends>();
					if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
						listed = (Gee.ArrayList<Argus.Shared.SQV.AptDepends>)
							response.retval.get_object();
					}
					if (listed == null) {
						listed = new Gee.ArrayList<Argus.Shared.SQV.AptDepends>();
					}
					this.items = listed;
					this.empty = listed.size == 0;
					this.busy = false;
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list packages", e.message);
				}
			});
		}
	}
}
