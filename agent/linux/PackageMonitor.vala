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
	 * Watch Debian or RPM packages and sync after a change.
	 *
	 * Startup ''osqueryi'' has already read ''os_version''. The
	 * caller then uses {@link debian} or {@link rpm}. This class
	 * does not decide which one. Inotify arms a rescan. The
	 * rescan runs when a write lock can be taken. {@link send}
	 * compares the new query with the startup fetch and calls
	 * ''OSQuery.update'' with the changed rows. Nothing
	 * constructs this yet. The Windows class of the same name is
	 * ''agent/Win32/PackageMonitor.vala''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var monitor = new Argus.Agent.PackageMonitor(
	 *     application, "/usr/bin/osqueryi");
	 * monitor.debian();
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

		private Gee.ArrayList<GLib.FileMonitor> monitors {
			get; set; default = new Gee.ArrayList<GLib.FileMonitor>();
		}
		private uint dpkg_wait = 0;
		private uint rpm_wait = 0;
		private bool lock_error = false;

		/**
		 * Store the agent and ''osqueryi'' for the later rescan.
		 *
		 * @param application agent process with the server connection
		 * @param osqueryi path or name of ''osqueryi''
		 */
		public PackageMonitor(Application application, string osqueryi)
		{
			Object(application: application);
			this.osqueryi = osqueryi;
		}

		/**
		 * Watch ''/var/lib/dpkg'' and rescan ''deb_packages''.
		 *
		 * The rescan waits until a write lock can be taken on
		 * ''/var/lib/dpkg/lock'' and
		 * ''/var/lib/dpkg/lock-frontend''.
		 */
		public void debian()
		{
			var dpkg = GLib.File.new_for_path("/var/lib/dpkg");
			GLib.FileMonitor dpkg_monitor;
			try {
				dpkg_monitor = dpkg.monitor_directory(GLib.FileMonitorFlags.NONE);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			dpkg_monitor.changed.connect((file, other, event_type) => {
				if (this.dpkg_wait != 0) {
					return;
				}
				this.dpkg_wait = GLib.Timeout.add(1000, () => {
					string[] paths = {
						"/var/lib/dpkg/lock",
						"/var/lib/dpkg/lock-frontend"
					};
					this.lock_error = false;
					var busy = false;
					foreach (var path in paths) {
						var fd = Posix.open(path, Posix.O_RDWR | Posix.O_CLOEXEC);
						if (fd < 0 && Posix.errno == Posix.ENOENT) {
							continue;
						}
						if (fd < 0) {
							GLib.warning("lock %s %d", path, Posix.errno);
							this.lock_error = true;
							break;
						}
						var flock = Posix.Flock() {
							l_type = Posix.F_WRLCK,
							l_whence = Posix.SEEK_SET,
							l_start = 0,
							l_len = 0,
							l_pid = 0
						};
						if (Posix.fcntl(fd, Posix.F_SETLK, ref flock) != 0) {
							Posix.close(fd);
							busy = true;
							break;
						}
						flock.l_type = Posix.F_UNLCK;
						Posix.fcntl(fd, Posix.F_SETLK, ref flock);
						Posix.close(fd);
					}
					if (busy) {
						return true;
					}
					this.dpkg_wait = 0;
					if (!this.lock_error) {
						this.send("deb_packages", "DebPackages", { "name", "arch" });
					}
					return false;
				});
			});
			this.monitors.add(dpkg_monitor);
		}

		/**
		 * Watch ''/var/lib/rpm'' and rescan ''rpm_packages''.
		 *
		 * The rescan waits until a write lock can be taken on
		 * ''/var/lib/rpm/.rpm.lock''.
		 */
		public void rpm()
		{
			var rpm = GLib.File.new_for_path("/var/lib/rpm");
			GLib.FileMonitor rpm_monitor;
			try {
				rpm_monitor = rpm.monitor_directory(GLib.FileMonitorFlags.NONE);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			rpm_monitor.changed.connect((file, other, event_type) => {
				if (this.rpm_wait != 0) {
					return;
				}
				this.rpm_wait = GLib.Timeout.add(1000, () => {
					string[] paths = { "/var/lib/rpm/.rpm.lock" };
					this.lock_error = false;
					var busy = false;
					foreach (var path in paths) {
						var fd = Posix.open(path, Posix.O_RDWR | Posix.O_CLOEXEC);
						if (fd < 0 && Posix.errno == Posix.ENOENT) {
							continue;
						}
						if (fd < 0) {
							GLib.warning("lock %s %d", path, Posix.errno);
							this.lock_error = true;
							break;
						}
						var flock = Posix.Flock() {
							l_type = Posix.F_WRLCK,
							l_whence = Posix.SEEK_SET,
							l_start = 0,
							l_len = 0,
							l_pid = 0
						};
						if (Posix.fcntl(fd, Posix.F_SETLK, ref flock) != 0) {
							Posix.close(fd);
							busy = true;
							break;
						}
						flock.l_type = Posix.F_UNLCK;
						Posix.fcntl(fd, Posix.F_SETLK, ref flock);
						Posix.close(fd);
					}
					if (busy) {
						return true;
					}
					this.rpm_wait = 0;
					if (!this.lock_error) {
						this.send("rpm_packages", "RpmPackages", { "name", "arch" });
					}
					return false;
				});
			});
			this.monitors.add(rpm_monitor);
		}

		/**
		 * Query one package table and send the rows that changed.
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
