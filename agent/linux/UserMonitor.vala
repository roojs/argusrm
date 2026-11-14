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
	 * Watch logins and local account files on Linux.
	 *
	 * Session path: first existing utmp file, else
	 * ''/run/systemd/sessions/''. Account paths: ''/etc/passwd'',
	 * ''/etc/group''. Each change is debounced 60s like
	 * {@link PackageMonitor}.
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
		private Application application;
		private uint session_later = 0;
		private uint account_later = 0;
		private GLib.FileMonitor? session_watch;
		private GLib.FileMonitor? passwd_watch;
		private GLib.FileMonitor? group_watch;

		/**
		 * @param application agent whose startup fetch is kept
		 */
		public UserMonitor(Application application)
		{
			this.application = application;
		}

		/**
		 * Arm utmp or systemd session watches and passwd/group files.
		 */
		public void start()
		{
			this.watch_sessions();
			this.watch_accounts();
		}

		private void watch_sessions()
		{
			string[] utmp_paths = {
				"/var/run/utmp",
				"/run/utmp",
				"/var/adm/utmp"
			};
			foreach (var path in utmp_paths) {
				if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
					continue;
				}
				try {
					this.session_watch = GLib.File.new_for_path(path).monitor_file(
						GLib.FileMonitorFlags.NONE, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				break;
			}
			if (this.session_watch == null &&
				GLib.FileUtils.test("/run/systemd/sessions", GLib.FileTest.IS_DIR)) {
				try {
					this.session_watch = GLib.File.new_for_path("/run/systemd/sessions")
						.monitor_directory(GLib.FileMonitorFlags.WATCH_MOVES, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			if (this.session_watch == null) {
				GLib.warning("no session watch for logged_in_users");
				return;
			}
			this.session_watch.changed.connect(() => {
				this.arm_session();
			});
		}

		private void watch_accounts()
		{
			this.passwd_watch = this.monitor_file("/etc/passwd");
			if (this.passwd_watch != null) {
				this.passwd_watch.changed.connect(() => {
					this.arm_accounts();
				});
			}
			this.group_watch = this.monitor_file("/etc/group");
			if (this.group_watch != null) {
				this.group_watch.changed.connect(() => {
					this.arm_accounts();
				});
			}
		}

		private GLib.FileMonitor? monitor_file(string path)
		{
			if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				GLib.warning("missing %s", path);
				return null;
			}
			try {
				return GLib.File.new_for_path(path).monitor_file(
					GLib.FileMonitorFlags.NONE, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
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
			new OSQuery.LoggedInUsers().send(this.application);
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