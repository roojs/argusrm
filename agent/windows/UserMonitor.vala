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
	/**
	 * Watch Security log logon and account events on Windows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var monitor = new Argus.Agent.UserMonitor(application);
	 * monitor.start();
	 * }}}
	 */
	public class UserMonitor : GLib.Object
	{
		private static UserMonitor current;

		private static Win32.EVT_SUBSCRIBE_CALLBACK session_logged = (action, context, event) => {
			if (action != 1) {
				return 0;
			}
			GLib.Idle.add(() => {
				UserMonitor.current.arm_session();
				return false;
			});
			return 0;
		};

		private static Win32.EVT_SUBSCRIBE_CALLBACK account_logged = (action, context, event) => {
			if (action != 1) {
				return 0;
			}
			GLib.Idle.add(() => {
				UserMonitor.current.arm_accounts();
				return false;
			});
			return 0;
		};

		private Application application;
		private uint session_later = 0;
		private uint account_later = 0;
		private void* session_subscription;
		private void* account_subscription;

		/**
		 * @param application agent whose startup fetch is kept
		 */
		public UserMonitor(Application application)
		{
			this.application = application;
			UserMonitor.current = this;
		}

		/**
		 * Subscribe to Security log logon and account-management events.
		 */
		public void start()
		{
			var session_query = ("*[System[(EventID=4624 or EventID=4634 or EventID=4647)]]")
				.to_utf16();
			this.session_subscription = Win32.EvtSubscribe(null, null,
				"Security".to_utf16(), session_query, null, null,
				UserMonitor.session_logged, Win32.EvtSubscribeToFutureEvents);
			if (this.session_subscription == null) {
				GLib.warning("security session log %u", Win32.GetLastError());
			}
			var account_query = ("*[System[(EventID=4720 or EventID=4726 or EventID=4738)]]")
				.to_utf16();
			this.account_subscription = Win32.EvtSubscribe(null, null,
				"Security".to_utf16(), account_query, null, null,
				UserMonitor.account_logged, Win32.EvtSubscribeToFutureEvents);
			if (this.account_subscription == null) {
				GLib.warning("security account log %u", Win32.GetLastError());
			}
		}

		private void arm_session()
		{
			if (this.session_later != 0) {
				GLib.Source.remove(this.session_later);
			}
			this.session_later = GLib.Timeout.add_seconds(60, () => {
				this.send_sessions();
				this.session_later = 0;
				return false;
			});
		}

		private void arm_accounts()
		{
			if (this.account_later != 0) {
				GLib.Source.remove(this.account_later);
			}
			this.account_later = GLib.Timeout.add_seconds(60, () => {
				this.send_accounts();
				this.account_later = 0;
				return false;
			});
		}

		private void send_sessions()
		{
			if (this.application.connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			this.application.osquery.sync_table("logged_in_users", "LoggedInUsers");
		}

		private void send_accounts()
		{
			if (this.application.connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			var osquery = this.application.osquery;
			osquery.sync_table("users", "Users");
			osquery.sync_table("groups", "Groups");
			osquery.sync_table("user_groups", "UserGroups");
		}
	}
}