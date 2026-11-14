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
	 * ''system_info'' rows on the open server.
	 *
	 * A {@link GLib.ListModel} of
	 * {@link Argus.Shared.OSQuery.SystemInfo}. {@link items} is the
	 * backing list. Rows are not copied into a
	 * {@link GLib.ListStore}. {@link load} talks to ''SystemInfo.list''.
	 * A newer {@link load} drops a reply that is still waiting.
	 * An empty list is omitted on the wire, so an unset return
	 * is no rows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.SystemInfo(app);
	 * store.load();
	 * }}}
	 */
	public class SystemInfo : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.OSQuery.SystemInfo> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.OSQuery.SystemInfo>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.OSQuery.SystemInfo> items {
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
		 * The list call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * @param app the controller process
		 */
		public SystemInfo(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.OSQuery.SystemInfo);
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
		 * Fetch ''SystemInfo.list'' and apply it to {@link items}.
		 *
		 * The call asks for the joined ''os_version'' columns
		 * and the distinct logged-in users.
		 * The reply replaces the list. A newer call drops a reply
		 * that is still waiting. An empty list is omitted on the
		 * wire, so an unset return is no rows.
		 */
		public void load()
		{
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "SystemInfo.list",
				args = OLLMrpc.args("ib", 0, true)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not list machines", e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not list machines", response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.SystemInfo>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.SystemInfo>) response.retval.get_object();
				}
				this.items = listed;
			});
		}
	}
}
