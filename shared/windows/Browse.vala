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

namespace Argus.Shared
{
	/**
	 * Windows browse for Argus registration.
	 *
	 * Same result as ''PairBrowse'': service ''_rpc._tcp'', TXT
	 * ''id'', then host and port. {@link poll} is empty while
	 * waiting, ''none'' when browse fails, or the id, a newline,
	 * and ''host:port''. ''DnsServiceBrowse'' watches
	 * ''_rpc._tcp.local''. ''DnsServiceResolve'' reads the address
	 * and the TXT record. Those callbacks are function pointers,
	 * so they call back into this object. The Linux browse is
	 * ''shared/Browse.vala''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var browse = new Argus.Shared.Browse();
	 * browse.start();
	 * var line = browse.poll();
	 * browse.stop();
	 * }}}
	 */
	public class Browse : GLib.Object
	{
		/**
		 * Latest line from {@link poll}. Empty until a service
		 * with TXT ''id'' is found, or ''none'' after a failure.
		 */
		private string found = "";
		private bool client_up = false;
		private bool busy = false;
		private string16 query_name;
		private string16 resolve_name;
		private Windows.DNS_SERVICE_CANCEL cancel;
		private Windows.DNS_SERVICE_CANCEL resolve_cancel;

		private static Windows.DNS_SERVICE_BROWSE_CALLBACK browse_proc = (status, context, record) => {
			((Browse) context).browse(status, record);
		};

		private static Windows.DNS_SERVICE_RESOLVE_COMPLETE resolve_proc = (status, context, instance) => {
			((Browse) context).resolve(status, instance);
		};

		/**
		 * One ''DnsServiceBrowse'' result.
		 *
		 * A PTR record with a name is resolved. Cancel and failure
		 * do not replace a line already stored.
		 *
		 * @param status result status from ''DnsServiceBrowse''
		 * @param record records for one service, freed here
		 */
		private void browse(uint32 status, Windows.DNS_RECORDW* record)
		{
			if (status == Windows.ERROR_CANCELLED) {
				if (record != null) {
					Windows.DnsFree(record, Windows.DNS_FREE_TYPE.DnsFreeRecordList);
				}
				return;
			}
			if (status != Windows.ERROR_SUCCESS) {
				GLib.warning("broadcast browse failed: %u", status);
				if (record != null) {
					Windows.DnsFree(record, Windows.DNS_FREE_TYPE.DnsFreeRecordList);
				}
				GLib.Idle.add(() => {
					this.found = "none";
					return false;
				});
				return;
			}
			if (this.busy || this.found != "" || record == null) {
				if (record != null) {
					Windows.DnsFree(record, Windows.DNS_FREE_TYPE.DnsFreeRecordList);
				}
				return;
			}
			unowned Windows.DNS_RECORDW* walk = record;
			var saw = false;
			while (walk != null) {
				if (walk.wType != Windows.DNS_TYPE_PTR || walk.dwTtl == 0 || walk.DataPTR.pNameHost == null) {
					walk = walk.pNext;
					continue;
				}
				try {
					var instance_name = ((string16) walk.DataPTR.pNameHost).to_utf8();
					this.resolve_name = instance_name.to_utf16();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					walk = walk.pNext;
					continue;
				}
				saw = true;
				break;
			}
			Windows.DnsFree(record, Windows.DNS_FREE_TYPE.DnsFreeRecordList);
			if (!saw) {
				return;
			}
			this.busy = true;
			var request = Windows.DNS_SERVICE_RESOLVE_REQUEST();
			request.Version = Windows.DNS_QUERY_REQUEST_VERSION1;
			request.InterfaceIndex = 0;
			request.QueryName = this.resolve_name;
			request.pResolveCompletionCallback = Browse.resolve_proc;
			request.pQueryContext = this;
			this.resolve_cancel = Windows.DNS_SERVICE_CANCEL();
			var resolve_status = Windows.DnsServiceResolve(ref request, ref this.resolve_cancel);
			if (resolve_status != Windows.DNS_REQUEST_PENDING) {
				GLib.warning("broadcast resolve failed: %d", resolve_status);
				this.busy = false;
			}
		}

		/**
		 * One ''DnsServiceResolve'' result.
		 *
		 * Stores the TXT ''id'' and the IPv4 address when both are
		 * present. The instance is freed here.
		 *
		 * @param status result status from ''DnsServiceResolve''
		 * @param instance resolved service, freed here
		 */
		private void resolve(uint32 status, Windows.DNS_SERVICE_INSTANCE* instance)
		{
			if (status != Windows.ERROR_SUCCESS || instance == null) {
				if (instance != null) {
					Windows.DnsServiceFreeInstance(instance);
				}
				this.busy = false;
				return;
			}
			if (instance.ip4Address == null || instance.keys == null || instance.values == null) {
				Windows.DnsServiceFreeInstance(instance);
				this.busy = false;
				return;
			}
			var id = "";
			var index = 0;
			while (index < (int) instance.dwPropertyCount) {
				try {
					var key = ((string16) instance.keys[index]).to_utf8();
					var value = ((string16) instance.values[index]).to_utf8();
					if (key == "id" && value != "") {
						id = value;
						break;
					}
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				index++;
			}
			if (id == "") {
				Windows.DnsServiceFreeInstance(instance);
				this.busy = false;
				return;
			}
			var raw = instance.ip4Address[0];
			var host = "%u.%u.%u.%u".printf(raw & 0xff, (raw >> 8) & 0xff,
				(raw >> 16) & 0xff, (raw >> 24) & 0xff);
			var line = id + "\n" + host + ":" + instance.wPort.to_string();
			Windows.DnsServiceFreeInstance(instance);
			GLib.Idle.add(() => {
				if (this.found != "") {
					return false;
				}
				this.found = line;
				GLib.debug("broadcast %s", line.replace("\n", " "));
				return false;
			});
		}

		/**
		 * Begin browsing for ''_rpc._tcp''.
		 *
		 * A later {@link poll} returns the first service whose TXT
		 * record has an ''id''. A failure sets that result to
		 * ''none''. Calling this again does nothing.
		 */
		public void start()
		{
			if (this.client_up) {
				return;
			}
			this.found = "";
			this.busy = false;
			try {
				this.query_name = "_rpc._tcp.local".to_utf16();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.found = "none";
				return;
			}
			var request = Windows.DNS_SERVICE_BROWSE_REQUEST();
			request.Version = Windows.DNS_QUERY_REQUEST_VERSION1;
			request.InterfaceIndex = 0;
			request.QueryName = this.query_name;
			request.pBrowseCallback = Browse.browse_proc;
			request.pQueryContext = this;
			this.cancel = Windows.DNS_SERVICE_CANCEL();
			var status = Windows.DnsServiceBrowse(ref request, ref this.cancel);
			if (status != Windows.DNS_REQUEST_PENDING) {
				GLib.warning("broadcast browse failed: %d", status);
				this.found = "none";
				return;
			}
			this.client_up = true;
		}

		/**
		 * Latest browse line.
		 *
		 * Empty while waiting. ''none'' when browse failed.
		 * Otherwise the id, a newline, and ''host:port''.
		 *
		 * @return the line described above
		 */
		public string poll()
		{
			return this.found;
		}

		/**
		 * Stop browsing.
		 *
		 * A result already stored for {@link poll} stays. Calling
		 * this before {@link start} does nothing.
		 */
		public void stop()
		{
			if (!this.client_up) {
				return;
			}
			this.client_up = false;
			var status = Windows.DnsServiceBrowseCancel(ref this.cancel);
			if (status != Windows.ERROR_SUCCESS) {
				GLib.warning("broadcast browse cancel failed: %d", status);
			}
		}
	}
}
