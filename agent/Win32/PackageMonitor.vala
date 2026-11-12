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

namespace Argus.Agent
{
	[CCode (cheader_filename = "winevt.h", has_target = false)]
	private delegate uint32 EvtSubscribeCallback (int action, void* context, void* evt);

	[CCode (cheader_filename = "winevt.h")]
	private extern void* EvtSubscribe (
		void* session,
		void* signal_event,
		[CCode (array_length = false, array_null_terminated = true)] uint16[] channel,
		[CCode (array_length = false, array_null_terminated = true)] uint16[] query,
		void* bookmark,
		void* context,
		EvtSubscribeCallback callback,
		uint32 flags
	);

	/**
	 * Watch Windows programs and sync after an installer event.
	 *
	 * The constructor subscribes to the Application log. The
	 * source is ''MsiInstaller''. Install is event 1033 and
	 * 11707. Removal is event 1034 and 11724. {@link send}
	 * compares the new ''programs'' query with the startup
	 * fetch and calls ''OSQuery.update'' with the changed
	 * rows. An exe install or a store install does not emit
	 * those events. Nothing constructs this yet. The Linux
	 * class of the same name is
	 * ''agent/linux/PackageMonitor.vala''. Linking this file
	 * needs ''wevtapi''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var monitor = new Argus.Agent.PackageMonitor(
	 *     application, "osqueryi.exe");
	 * }}}
	 */
	public class PackageMonitor : GLib.Object
	{
		/**
		 * Agent process. {@link Application.connection} sends the
		 * sync.
		 */
		public Application application { get; construct; }

		/**
		 * Path to ''osqueryi'', or the name looked up on ''PATH''.
		 */
		public string osqueryi = "";

		private static PackageMonitor running;
		private void* subscription = null;
		private uint16[] channel = new uint16[0];
		private uint16[] query = new uint16[0];

		/**
		 * Subscribe to future ''MsiInstaller'' events.
		 *
		 * @param application agent process with the server connection
		 * @param osqueryi path or name of ''osqueryi''
		 */
		public PackageMonitor(Application application, string osqueryi)
		{
			Object(
				application: application
			);
			this.osqueryi = osqueryi;
			PackageMonitor.running = this;
			this.channel = "Application".to_utf16();
			this.query = ("*[System[Provider[@Name='MsiInstaller'] and " +
				"(EventID=1033 or EventID=11707 or " +
				"EventID=1034 or EventID=11724)]]").to_utf16();
			this.subscription = EvtSubscribe(null, null,
				this.channel, this.query, null, null, PackageMonitor.delivered, 1);
			if (this.subscription == null) {
				GLib.warning("application log subscribe failed");
			}
		}

		/*
		 * EvtSubscribe calls this on a thread-pool thread. The
		 * query already selected the four event ids, so the
		 * callback only schedules the program sync.
		 */
		private static uint32 delivered(int action, void* context, void* evt)
		{
			if (action != 1) {
				GLib.warning("application log subscribe error");
				return 0;
			}
			GLib.Idle.add(() => {
				PackageMonitor.running.send(
					"programs", "Programs", { "name", "identifying-number" });
				return false;
			});
			return 0;
		}

		/**
		 * Query ''programs'' and send the rows that changed.
		 *
		 * The startup fetch is
		 * {@link Application.package_rows}. A new row and a
		 * changed row are sent as they are. A stored row the
		 * query left out is sent with ''deleted_dt'' set.
		 * ''OSQuery.update'' applies that list.
		 *
		 * @param table osquery table name
		 * @param class_name bin alias of the row class
		 * @param keys properties that identify a row
		 */
		private void send(string table, string class_name, string[] keys)
		{
			var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			new OSQuery.Query(this.osqueryi, row_type).select(
				"SELECT * FROM " + table, fresh);
			GLib.debug("SELECT * FROM %s %d rows", table, fresh.size);
			if (!this.application.package_rows.has_key(table)) {
				GLib.warning("%s has no stored fetch", table);
			}
			var stored = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			if (this.application.package_rows.has_key(table)) {
				foreach (var row in this.application.package_rows.get(table)) {
					stored.add(row);
				}
			}
			string[] exclude = {};
			var object_class = (GLib.ObjectClass) row_type.class_ref();
			foreach (var prop in object_class.list_properties()) {
				if (!GLib.strv_contains(keys, prop.name)) {
					exclude += prop.name;
				}
			}
			var diff = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			foreach (var row in fresh) {
				Argus.Shared.OSQuery.AgentInfo? found = null;
				foreach (var old in stored) {
					if (!old.compare(row, exclude)) {
						continue;
					}
					found = old;
					break;
				}
				if (found == null) {
					diff.add(row);
					continue;
				}
				stored.remove(found);
				if (found.compare(row)) {
					continue;
				}
				diff.add(row);
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var old in stored) {
				((Argus.Shared.OSQuery.Row) old).deleted_dt = now;
				diff.add(old);
			}
			if (diff.size == 0) {
				this.application.package_rows.set(table, fresh);
				return;
			}
			if (this.application.connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			OLLMrpc.Response response;
			try {
				response = this.application.connection.call(new OLLMrpc.Request() {
					method = "OSQuery.update",
					args = OLLMrpc.args("so", class_name, diff)
				});
			} catch (GLib.Error e) {
				Application.connection_down = true;
				GLib.warning("%s", e.message);
				return;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", table, response.error.message);
				return;
			}
			this.application.package_rows.set(table, fresh);
			GLib.debug("%s sent %d", table, diff.size);
		}
	}
}
