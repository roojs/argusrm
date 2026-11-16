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
	 * Task target runs on the open server.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.SQT.TaskTarget}.
	 * {@link items} is the backing list. {@link load} calls
	 * ''Task.all_targets''. {@link run_script} resolves a library script
	 * via ''Script.search'' and submits a task via ''Task.submit''.
	 * {@link fetch_logs} and {@link watch} load saved output and enable
	 * live streaming for one target.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.TaskTarget(app);
	 * store.load();
	 * }}}
	 */
	public class TaskTarget : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQT.TaskTarget> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQT.TaskTarget> items {
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
		 * True while ''Task.all_targets'' is in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * An RPC call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * ''Task.submit'' queued targets on the server.
		 *
		 * @param count number of target rows created
		 */
		public signal void submitted(int count);

		/**
		 * ''Task.logs'' returned saved output streams.
		 *
		 * @param target_id ''task_target.id''
		 * @param stdout_text saved stdout
		 * @param stderr_text saved stderr
		 * @param stdin_text saved stdin
		 */
		public signal void logs_loaded(
			int target_id,
			string stdout_text,
			string stderr_text,
			string stdin_text
		);

		/**
		 * @param app the controller process
		 */
		public TaskTarget(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQT.TaskTarget);
		}

		/**
		 * Number of target rows in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Target row at ''position''.
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
		 * Fetch ''Task.all_targets'' and apply it to {@link items}.
		 */
		public void load()
		{
			this.busy = true;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.all_targets"
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list tasks", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list tasks", response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID ||
					!response.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.items = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
					this.busy = false;
					return;
				}
				this.items = (Gee.ArrayList<Argus.Shared.SQT.TaskTarget>) response.retval.get_object();
				this.busy = false;
			});
		}

		/**
		 * Search a script by ''platform'', ''app'', and ''action'', then
		 * submit a task for ''agent_ids''.
		 *
		 * @param platform target OS family
		 * @param app target tool
		 * @param action target action
		 * @param agent_ids selected ''agent.id'' values
		 */
		public void run_script(
			string platform,
			string app,
			string action,
			Gee.ArrayList<int32> agent_ids
		) {
			if (agent_ids.size < 1) {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Script.search",
				args = OLLMrpc.args("sss", platform, app, action)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not find script", e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not find script", response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID ||
					!response.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.failed("Could not find script",
						"No script found for " + platform + " " + app + " " + action);
					return;
				}
				var scripts = (Gee.ArrayList<Argus.Shared.SQT.Script>) response.retval.get_object();
				if (scripts.size == 0) {
					this.failed("Could not find script",
						"No script found for " + platform + " " + app + " " + action);
					return;
				}
				var script = scripts.get(0);
				var now = new GLib.DateTime.now_utc().to_unix();
				var builder = new GLib.VariantBuilder(new GLib.VariantType("ai"));
				string[] id_text = {};
				foreach (var id in agent_ids) {
					builder.add_value(new GLib.Variant.int32(id));
					id_text += id.to_string();
				}
				var canonical = script.id.to_string() + "|1||" +
					now.to_string() + "|" + string.joinv(",", id_text);
				var task = new Argus.Shared.SQT.Task() {
					name = app + " " + action,
					is_script = true,
					script_id = script.id,
					scheduled = now,
					payload_hash = GLib.Checksum.compute_for_string(
						GLib.ChecksumType.SHA256, canonical)
				};
				this.app.rpc.call.begin(new OLLMrpc.Request() {
					method = "Task.submit",
					args = OLLMrpc.args("ovb", task, builder.end(), false)
				}, (submit_obj, submit_res) => {
					OLLMrpc.Response submit_reply;
					try {
						submit_reply = this.app.rpc.call.end(submit_res);
					} catch (GLib.Error e) {
						this.failed("Could not queue task", e.message);
						return;
					}
					if (submit_reply.error != null) {
						this.failed("Could not queue task", submit_reply.error.message);
						return;
					}
					if (submit_reply.retval.type() == GLib.Type.INVALID ||
						!submit_reply.retval.type().is_a(typeof(Gee.ArrayList))) {
						this.submitted(agent_ids.size);
						return;
					}
					var targets = (Gee.ArrayList<Argus.Shared.SQT.TaskTarget>)
						submit_reply.retval.get_object();
					this.submitted(targets.size);
				});
			});
		}

		/**
		 * Fetch saved stdout, stderr, and stdin logs for one target.
		 *
		 * @param target_id ''task_target.id''
		 */
		public void fetch_logs(int target_id)
		{
			if (target_id < 1) {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.logs",
				args = OLLMrpc.args("i", target_id)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not load logs", e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not load logs", response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID) {
					this.logs_loaded(target_id, "", "", "");
					return;
				}
				var parts = (string[]) response.retval;
				var stdout_text = parts.length > 0 ? parts[0] : "";
				var stderr_text = parts.length > 1 ? parts[1] : "";
				var stdin_text = parts.length > 2 ? parts[2] : "";
				this.logs_loaded(target_id, stdout_text, stderr_text, stdin_text);
			});
		}

		/**
		 * Subscribe this connection to live output for an active target.
		 *
		 * @param target_id ''task_target.id''
		 */
		public void watch(int target_id)
		{
			if (target_id < 1) {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.watch",
				args = OLLMrpc.args("i", target_id)
			}, (obj, res) => {
				try {
					this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.debug("%s", e.message);
				}
			});
		}
	}
}
