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
	 * Cloned script repositories on the open server.
	 *
	 * A {@link GLib.ListModel} of
	 * {@link Argus.Shared.SQT.ScriptRepository}. {@link items} is the
	 * backing list. Rows are not copied into a
	 * {@link GLib.ListStore}. {@link load} and {@link save} talk to
	 * ''ScriptRepository''. A newer {@link load} drops a reply that
	 * is still waiting. Passwords and keys are cleared when a list
	 * reply is applied. Every call sets {@link busy} until its
	 * reply. The page or dialog that made the call masks while
	 * {@link busy} is true, so the wait is visible.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Repository(app);
	 * store.load();
	 * }}}
	 */
	public class Repository : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQT.ScriptRepository> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQT.ScriptRepository> items {
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
		 * True while a repository call is in flight.
		 *
		 * The page or dialog that started the call masks until
		 * this is false.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * A repository call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * ''ScriptRepository.clone'' succeeded.
		 */
		public signal void saved();

		/**
		 * ''ScriptRepository.pull'' succeeded.
		 *
		 * @param count script rows in the reply
		 */
		public signal void pulled(int count);

		/**
		 * ''ScriptRepository.remove'' succeeded.
		 */
		public signal void removed();

		/**
		 * @param app the controller process
		 */
		public Repository(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQT.ScriptRepository);
		}

		/**
		 * Number of repositories in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Repository at ''position''.
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
		 * Fetch ''ScriptRepository.list'' and replace {@link items}.
		 *
		 * A newer call drops the previous reply.
		 */
		public void load()
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
			this.empty = false;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "ScriptRepository.list"
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list repositories", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list repositories", response.error.message);
					return;
				}
				var listed = response.retval as Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>;
				if (listed == null) {
					this.busy = false;
					this.failed("Could not list repositories", "invalid reply");
					return;
				}
				foreach (var row in listed) {
					row.password = "";
					row.key = "";
				}
				this.empty = listed.size == 0;
				this.items = listed;
				this.busy = false;
			});
		}

		/**
		 * Clone ''row'' with ''ScriptRepository.clone'', then
		 * {@link load}.
		 *
		 * @param row url, name, and credentials
		 */
		public void save(Argus.Shared.SQT.ScriptRepository row)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "ScriptRepository.clone",
				args = OLLMrpc.args("o", row)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not clone", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not clone", response.error.message);
					return;
				}
				this.busy = false;
				this.saved();
				this.load();
			});
		}

		/**
		 * Fetch one clone and refresh its scripts.
		 *
		 * @param id ''script_repository.id''
		 */
		public void pull(int id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "ScriptRepository.pull",
				args = OLLMrpc.args("i", id)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not pull", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not pull", response.error.message);
					return;
				}
				var scripts = response.retval as Gee.ArrayList<Argus.Shared.SQT.Script>;
				var count = 0;
				if (scripts != null) {
					count = scripts.size;
				}
				this.busy = false;
				this.pulled(count);
			});
		}

		/**
		 * Delete one clone.
		 *
		 * @param id ''script_repository.id''
		 */
		public void remove(int id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "ScriptRepository.remove",
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
				this.load();
			});
		}
	}
}
