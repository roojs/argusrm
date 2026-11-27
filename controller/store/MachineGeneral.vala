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
	 * Key-value rows for the per-machine General detail tab.
	 *
	 * A {@link GLib.ListModel} of {@link KeyValue}. {@link load} fetches
	 * ''SystemInfo.list'', ''OsVersion.list'', ''OsReleases.list'',
	 * ''CpuInfo.list'', ''Uptime.list'', and ''Agent.list'' for one ''agent_id'' and replaces {@link items} from
	 * ''machine_general.csv''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.MachineGeneral(app);
	 * store.load.begin(1);
	 * }}}
	 */
	public class MachineGeneral : GLib.Object, GLib.ListModel, Base
	{
		public Application app;
		private Gee.ArrayList<KeyValue> items_store {
			get; set; default = new Gee.ArrayList<KeyValue>();
		}
		private Gee.ArrayList<ColumnSchema> cols {
			get; set; default = new Gee.ArrayList<ColumnSchema>();
		}
		private Gee.ArrayList<KeyValue> built {
			get; set; default = new Gee.ArrayList<KeyValue>();
		}
		private int epoch = 0;
		public int loaded_agent { get; private set; default = -1; }
		public bool desktop { get; private set; default = false; }
		public string hostname { get; private set; default = ""; }

		/**
		 * Rows from the last load. This list is the model.
		 */
		public Gee.ArrayList<KeyValue> items {
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
		 * True while subquery RPC calls are in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * One of the subquery calls failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * @param app the controller process
		 */
		public MachineGeneral(Application app)
		{
			Object();
			this.app = app;
			this.cols = this.read_columns("machine_general", true);
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(KeyValue);
		}

		/**
		 * Number of entries in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Entry at ''position''.
		 *
		 * @param position zero-based index
		 * @return the entry, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''SystemInfo.list'', ''OsVersion.list'',
		 * ''OsReleases.list'', ''CpuInfo.list'', ''Uptime.list'', and
		 * ''Agent.list'' for ''agent_id'' and replace {@link items} using
		 * ''machine_general.csv''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public async void load(int agent_id)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent) {
				this.desktop = false;
				this.hostname = "";
				if (this.items_store.size > 0) {
					this.items = new Gee.ArrayList<KeyValue>();
				}
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			this.built = new Gee.ArrayList<KeyValue>();
			if (!yield this.load_section(
				"system_info", "SystemInfo.list", OLLMrpc.args("ib", agent_id, false))) {
				return;
			}
			if (!yield this.load_section(
				"agent", "Agent.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_section(
				"os_version", "OsVersion.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_section(
				"os_releases", "OsReleases.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_section(
				"uptime", "Uptime.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_cpu_section(agent_id)) {
				return;
			}
			this.items = this.built;
			this.busy = false;
		}

		/**
		 * Call ''CpuInfo.list'' and append one expander block per
		 * processor onto {@link built}.
		 *
		 * @param agent_id selected machine agent id
		 * @return false when superseded or failed
		 */
		private async bool load_cpu_section(int agent_id)
		{
			var epoch = this.epoch;
			OLLMrpc.Response response;
			try {
				response = yield this.app.rpc.call(new OLLMrpc.Request() {
					method = "CpuInfo.list",
					args = OLLMrpc.args("i", agent_id)
				});
			} catch (GLib.Error e) {
				if (epoch == this.epoch) {
					this.busy = false;
					this.failed("Could not load CpuInfo.list", e.message);
				}
				return false;
			}
			if (epoch != this.epoch) {
				return false;
			}
			if (response.error != null) {
				this.busy = false;
				this.failed("Could not load CpuInfo.list", response.error.message);
				return false;
			}
			if (!response.retval.type().is_a(typeof(Gee.ArrayList))) {
				return true;
			}
			var rows = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			if (rows.size == 0) {
				return true;
			}
			for (var i = 0; i < rows.size; i++) {
				var row = rows.get(i);
				var title = "CPU";
				if (rows.size > 1) {
					title = @"CPU $(i + 1)";
				}
				this.built.add(new KeyValue() {
					key = title,
					expander = true,
					expanded = true
				});
				foreach (var col in this.cols) {
					if (!col.visible || col.source != "cpu_info") {
						continue;
					}
					this.built.add(col.display_value(row));
				}
			}
			return true;
		}

		/**
		 * Call one RPC list method and append matching {@link KeyValue}
		 * rows from {@link cols} onto {@link built}.
		 *
		 * @param source section key matching {@link ColumnSchema.source}
		 * @param method RPC method name
		 * @param args serialized RPC arguments
		 * @return false when superseded or failed
		 */
		private async bool load_section(
			string source,
			string method,
			Gee.ArrayList<GLib.Value?> args
		) {
			var epoch = this.epoch;
			OLLMrpc.Response response;
			try {
				response = yield this.app.rpc.call(new OLLMrpc.Request() {
					method = method,
					args = args
				});
			} catch (GLib.Error e) {
				if (epoch == this.epoch) {
					this.busy = false;
					this.failed("Could not load " + method, e.message);
				}
				return false;
			}
			if (epoch != this.epoch) {
				return false;
			}
			if (response.error != null) {
				this.busy = false;
				this.failed("Could not load " + method, response.error.message);
				return false;
			}
			if (!response.retval.type().is_a(typeof(Gee.ArrayList))) {
				return true;
			}
			var rows = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			if (rows.size == 0) {
				return true;
			}
			if (source == "os_version") {
				var version = (Argus.Shared.OSQuery.OsVersion) rows.get(0);
				this.desktop = version.platform == "windows";
			}
			if (source == "system_info") {
				var info = (Argus.Shared.OSQuery.SystemInfo) rows.get(0);
				this.hostname = info.hostname;
				if (this.hostname == "") {
					this.hostname = info.computer_name;
				}
			}
			foreach (var col in this.cols) {
				if (!col.visible || col.source != source) {
					continue;
				}
				this.built.add(col.display_value(rows.get(0)));
			}
			return true;
		}

		/**
		 * Ask the server to start this machine's desktop stream.
		 *
		 * Phase 5's screen button calls this on touch and hold.
		 * The caller opens the desktop page only when this returns
		 * true. ''relay.ready'' is the later notice that the stream
		 * is up.
		 *
		 * @return false when the server rejects the start
		 */
		public async bool start_desktop()
		{
			if (this.loaded_agent < 1) {
				this.failed("Desktop", Argus.Rdp.State.FAIL_NO_MACHINE.to_string());
				return false;
			}
			var agent_id = this.loaded_agent;
			var heading = this.hostname;
			if (heading == "") {
				heading = "Desktop";
			}
			OLLMrpc.Response response;
			try {
				response = yield this.app.rpc.call(new OLLMrpc.Request() {
					method = "Relay.start",
					args = OLLMrpc.args("i", agent_id)
				});
			} catch (GLib.Error e) {
				GLib.debug("%s", e.message);
				this.failed(
					heading,
					Argus.Rdp.State.RETRY_SERVER_UNREACHABLE.line(1));
				return false;
			}
			if (response.error != null) {
				var state = Argus.Rdp.State.FAIL_SERVER_REFUSED;
				var attempt = 0;
				var message = response.error.message;
				if (message == Argus.Rdp.State.RETRY_MACHINE_DOWN.to_string()) {
					state = Argus.Rdp.State.RETRY_MACHINE_DOWN;
					attempt = 1;
				} else if (message == Argus.Rdp.State.FAIL_BAD_SOCKET.to_string()) {
					state = Argus.Rdp.State.FAIL_BAD_SOCKET;
				}
				GLib.debug("%s", message);
				this.failed(heading, state.line(attempt));
				return false;
			}
			return true;
		}
	}
}
