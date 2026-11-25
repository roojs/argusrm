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
	 * Live distributables on the open server.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.SQT.Distributable}.
	 * {@link load} is ''Distributable.list''. {@link archive} sets
	 * ''deleted_dt'' and loads again. {@link submit} queues an installer
	 * task for a list of agent ids. A newer {@link load} drops a reply
	 * that is still waiting.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Distributable(app);
	 * store.load();
	 * }}}
	 */
	public class Distributable : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQT.Distributable> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQT.Distributable> items {
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
		 * True while a distributable call is in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * True while an installer upload is sending chunks.
		 */
		public bool uploading { get; private set; default = false; }

		/**
		 * True while {@link submit} is in flight.
		 */
		public bool submitting { get; private set; default = false; }

		/**
		 * A distributable call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * ''Distributable.archive'' succeeded.
		 */
		public signal void archived();

		/**
		 * A chunk was stored. ''sent'' and ''total'' are bytes.
		 *
		 * @param sent bytes the server has
		 * @param total file size
		 */
		public signal void upload_progress(int64 sent, int64 total);

		/**
		 * ''Distributable.complete'' stored the installer.
		 *
		 * @param row the product, with version and size filled in
		 */
		public signal void uploaded(Argus.Shared.SQT.Distributable row);

		/**
		 * The user cancelled and the server dropped the partial file.
		 */
		public signal void upload_cancelled();

		/**
		 * @param app the controller process
		 */
		public Distributable(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQT.Distributable);
		}

		/**
		 * Number of distributables in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Distributable at ''position''.
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
		 * Fetch ''Distributable.list'' and replace {@link items}.
		 *
		 * A newer call drops the previous reply. An empty list is
		 * omitted on the wire, so an unset return is no rows.
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
				method = "Distributable.list"
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list distributables", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list distributables", response.error.message);
					return;
				}
				Gee.ArrayList<Argus.Shared.SQT.Distributable> listed;
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.SQT.Distributable>) response.retval.get_object();
				} else if (response.retval.type() == GLib.Type.INVALID) {
					listed = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
				} else {
					this.busy = false;
					this.failed("Could not list distributables", "invalid reply");
					return;
				}
				if (listed == null) {
					listed = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
				}
				this.empty = listed.size == 0;
				this.items = listed;
				this.busy = false;
			});
		}

		/**
		 * Soft-delete one product, then {@link load}.
		 *
		 * @param id ''distributable.id''
		 */
		public void archive(int id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Distributable.archive",
				args = OLLMrpc.args("i", id)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not archive", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not archive", response.error.message);
					return;
				}
				this.busy = false;
				this.archived();
				this.load();
			});
		}

		/**
		 * Queue the installer on ''agent_ids''. Windows installers only.
		 *
		 * The command is the file name and ''/S''. ''dist_version_id''
		 * is {@link Argus.Shared.SQT.Distributable.version_id}.
		 *
		 * @param product the distributable whose latest file is sent
		 * @param agent_ids ticked machines, including one hidden by search
		 */
		public void submit(Argus.Shared.SQT.Distributable product, Gee.ArrayList<int> agent_ids)
		{
			if (this.submitting || product.version_id < 1 || product.filename == "") {
				return;
			}
			if (agent_ids.size < 1) {
				return;
			}
			this.submitting = true;
			var now = new GLib.DateTime.now_utc().to_unix();
			var command = "\"" + product.filename + "\" /S";
			int[] ids = new int[agent_ids.size];
			var n = 0;
			foreach (var id in agent_ids) {
				ids[n] = id;
				n++;
			}
			var task = new Argus.Shared.SQT.Task() {
				name = product.name + " " + product.version,
				is_script = false,
				command = command,
				script_id = 0,
				dist_version_id = product.version_id,
				scheduled = now
			};
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.submit",
				args = OLLMrpc.args("oaib", task, ids, ids.length, false)
			}, (obj, res) => {
				this.submitting = false;
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not queue task", e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not queue task", response.error.message);
					return;
				}
			});
		}

		private const int UPLOAD_CHUNK = 256 * 1024;
		private int upload_generation = 0;
		private bool upload_cancel = false;
		private int upload_id = 0;
		private int64 upload_offset = 0;
		private int64 upload_size = 0;
		private GLib.FileInputStream? upload_stream = null;

		/**
		 * Send ''file'' to the server in chunks.
		 *
		 * {@link upload_progress} fires after each stored chunk.
		 * {@link cancel_upload} stops the loop and deletes the partial file.
		 *
		 * @param file installer the user picked
		 */
		public void upload(GLib.File file)
		{
			if (this.uploading || this.busy) {
				return;
			}
			GLib.FileInfo info;
			try {
				info = file.query_info(GLib.FileAttribute.STANDARD_SIZE,
					GLib.FileQueryInfoFlags.NONE);
				this.upload_stream = file.read();
			} catch (GLib.Error e) {
				this.failed("Could not read the file", e.message);
				return;
			}
			var size = info.get_size();
			var filename = file.get_basename();
			if (filename == null || filename == "" || size < 1) {
				this.close_upload_stream();
				this.failed("Could not upload", "Choose a file that is not empty");
				return;
			}
			this.uploading = true;
			this.upload_cancel = false;
			this.upload_id = 0;
			this.upload_offset = 0;
			this.upload_size = size;
			this.upload_generation++;
			var generation = this.upload_generation;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Distributable.begin",
				args = OLLMrpc.args("sx", filename, size)
			}, (obj, res) => {
				if (generation != this.upload_generation) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.stop_upload(false);
					this.failed("Could not upload", e.message);
					return;
				}
				if (response.error != null) {
					this.stop_upload(false);
					this.failed("Could not upload", response.error.message);
					return;
				}
				this.upload_id = response.retval.get_int();
				if (this.upload_cancel) {
					this.send_cancel(generation);
					return;
				}
				this.upload_progress(0, size);
				this.send_chunk(generation);
			});
		}

		/**
		 * Stop the upload in progress and ask the server to delete the partial file.
		 */
		public void cancel_upload()
		{
			if (!this.uploading) {
				return;
			}
			this.upload_cancel = true;
		}

		/**
		 * Read and send the next slice, or finish when the file is done.
		 *
		 * @param generation {@link upload_generation} for this upload
		 */
		private void send_chunk(int generation)
		{
			if (generation != this.upload_generation) {
				return;
			}
			if (this.upload_cancel) {
				this.send_cancel(generation);
				return;
			}
			var buf = new uint8[UPLOAD_CHUNK];
			var n = (ssize_t) 0;
			try {
				n = this.upload_stream.read(buf);
			} catch (GLib.Error e) {
				this.send_cancel(generation);
				this.failed("Could not read the file", e.message);
				return;
			}
			if (n < 1) {
				if (this.upload_offset != this.upload_size) {
					this.send_cancel(generation);
					this.failed("Could not upload", "The file ended early");
					return;
				}
				this.send_complete(generation);
				return;
			}
			var raw = new uint8[n];
			GLib.Memory.copy((uint8*) raw, buf, n);
			var chunk = new GLib.Bytes.take((owned) raw);
			var offset = this.upload_offset;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Distributable.chunk",
				args = OLLMrpc.args("ixay", this.upload_id, offset, chunk)
			}, (obj, res) => {
				if (generation != this.upload_generation) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.stop_upload(false);
					this.failed("Could not upload", e.message);
					return;
				}
				if (response.error != null) {
					this.stop_upload(false);
					this.failed("Could not upload", response.error.message);
					return;
				}
				this.upload_offset = offset + n;
				this.upload_progress(this.upload_offset, this.upload_size);
				this.send_chunk(generation);
			});
		}

		/**
		 * Tell the server every byte is in.
		 *
		 * @param generation {@link upload_generation} for this upload
		 */
		private void send_complete(int generation)
		{
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Distributable.complete",
				args = OLLMrpc.args("i", this.upload_id)
			}, (obj, res) => {
				if (generation != this.upload_generation) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.stop_upload(false);
					this.failed("Could not upload", e.message);
					return;
				}
				if (response.error != null) {
					this.stop_upload(false);
					this.failed("Could not upload", response.error.message);
					return;
				}
				var row = response.retval.get_object() as Argus.Shared.SQT.Distributable;
				if (row == null) {
					this.stop_upload(false);
					this.failed("Could not upload", "The server did not return the installer");
					return;
				}
				this.stop_upload(false);
				this.uploaded(row);
				this.load();
			});
		}

		/**
		 * Ask the server to delete the partial file.
		 *
		 * @param generation {@link upload_generation} for this upload
		 */
		private void send_cancel(int generation)
		{
			var id = this.upload_id;
			this.stop_upload(false);
			if (id < 1) {
				this.upload_cancelled();
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Distributable.cancel",
				args = OLLMrpc.args("i", id)
			}, (obj, res) => {
				if (generation != this.upload_generation) {
					return;
				}
				try {
					this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				this.upload_cancelled();
			});
		}

		/**
		 * Close the local file and clear the upload flags.
		 *
		 * @param bump true to ignore a reply already in flight
		 */
		private void stop_upload(bool bump)
		{
			this.close_upload_stream();
			this.uploading = false;
			this.upload_cancel = false;
			this.upload_id = 0;
			if (bump) {
				this.upload_generation++;
			}
		}

		/**
		 * Close {@link upload_stream} when it is open.
		 */
		private void close_upload_stream()
		{
			if (this.upload_stream == null) {
				return;
			}
			try {
				this.upload_stream.close();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			this.upload_stream = null;
		}
	}
}
