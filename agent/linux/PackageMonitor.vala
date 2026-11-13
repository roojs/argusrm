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
	 * Watch installed packages on Linux and send the difference.
	 *
	 * {@link apt} watches ''/var/lib/dpkg'' and waits for the
	 * dpkg locks. {@link rpm} watches the directory that holds
	 * ''.rpm.lock'' and waits for that lock. The rescan then
	 * queries osquery. {@link start} reads the startup
	 * ''os_version'' row and calls {@link apt} or {@link rpm}.
	 * {@link send_pending} posts the names that need updating
	 * through ''OSQuery.sync'' as ''PackageUpdates'' every
	 * twelve hours.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var monitor = new Argus.Agent.PackageMonitor(application);
	 * monitor.start();
	 * }}}
	 */
	public class PackageMonitor : GLib.Object
	{
		/**
		 * Agent that owns the server connection and the kept fetch.
		 */
		private Application application;

		/**
		 * Directory watch. Held so the signal stays connected.
		 */
		private GLib.FileMonitor? watch;

		/**
		 * Deferred rescan. Zero when none is waiting.
		 */
		private uint later = 0;

		/**
		 * Source id of the twelve-hour update check.
		 *
		 * Zero when {@link start} did not arm it.
		 */
		private uint pending_id = 0;

		/**
		 * @param application agent whose startup fetch is kept
		 */
		public PackageMonitor(Application application)
		{
			this.application = application;
		}

		/**
		 * Start the watch this host uses, then the update check.
		 *
		 * {@link Application.os_version} is the startup osquery
		 * row. {@link Argus.Shared.OSQuery.OsVersion.package_manager}
		 * chooses the watch. APT calls {@link apt}. DNF calls
		 * {@link rpm}. Either one then calls {@link send_pending}
		 * and repeats that every twelve hours. Any other value
		 * returns.
		 */
		public void start()
		{
			switch (this.application.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					this.apt();
					break;

				case Argus.Shared.OSQuery.PackageManager.DNF:
					this.rpm();
					break;

				default:
					return;
			}
			this.send_pending();
			this.pending_id = GLib.Timeout.add_seconds(12 * 60 * 60, () => {
				this.send_pending();
				return true;
			});
		}

		/**
		 * Post the names that need updating through ''OSQuery.sync''.
		 *
		 * {@link UpdatesAvailable.check} reads the host. A failure
		 * is not sent. An empty list clears stored pending updates.
		 */
		public void send_pending()
		{
			var names = new Gee.ArrayList<string>();
			try {
				names = new UpdatesAvailable().check(this.application.os_version);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			if (this.application.connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			foreach (var name in names) {
				if (name == "") {
					continue;
				}
				rows.add(new Argus.Shared.OSQuery.PackageUpdates() {
					name = name
				});
			}
			try {
				var response = this.application.connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", "PackageUpdates", rows)
				});
				if (response.error != null) {
					GLib.debug("PackageUpdates sync failed %s", response.error.message);
				}
			} catch (GLib.Error e) {
				Application.connection_down = true;
				GLib.warning("%s", e.message);
			}
		}

		/**
		 * Watch ''/var/lib/dpkg'' and rescan ''deb_packages''.
		 *
		 * A change waits until a non-blocking fcntl write lock
		 * succeeds on ''/var/lib/dpkg/lock'' and
		 * ''/var/lib/dpkg/lock-frontend''. A missing lock file is
		 * not held. The rescan then queries ''deb_packages''.
		 */
		public void apt()
		{
			try {
				this.watch = GLib.File.new_for_path("/var/lib/dpkg").monitor_directory(
					GLib.FileMonitorFlags.WATCH_MOVES, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			var monitor = this.watch;
			if (monitor == null) {
				return;
			}
			monitor.changed.connect((file, other, event_type) => {
				if (this.later != 0) {
					GLib.Source.remove(this.later);
				}
				this.later = GLib.Timeout.add_seconds(60, () => {
					var fds = new Gee.ArrayList<int>();
					var blocked = false;
					string[] locks = {
						"/var/lib/dpkg/lock",
						"/var/lib/dpkg/lock-frontend"
					};
					foreach (var path in locks) {
						var fd = Posix.open(path, Posix.O_RDWR);
						if (fd < 0) {
							if (Posix.errno != Posix.ENOENT) {
								blocked = true;
								break;
							}
							continue;
						}
						Posix.fcntl(fd, Posix.F_SETFD, Posix.FD_CLOEXEC);
						var flock = Posix.Flock();
						flock.l_type = Posix.F_WRLCK;
						flock.l_whence = Posix.SEEK_SET;
						flock.l_start = 0;
						flock.l_len = 0;
						if (Posix.fcntl(fd, Posix.F_SETLK, flock) != 0) {
							Posix.close(fd);
							blocked = true;
							break;
						}
						fds.add(fd);
					}
					if (blocked) {
						foreach (var fd in fds) {
							Posix.close(fd);
						}
						return true;
					}
					this.application.osquery.send_packages();
					foreach (var fd in fds) {
						Posix.close(fd);
					}
					this.later = 0;
					return false;
				});
			});
		}

		/**
		 * Watch the directory that holds ''.rpm.lock''.
		 *
		 * ''/var/lib/rpm'' may be a link to the database directory.
		 * A change waits until a non-blocking fcntl write lock
		 * succeeds on ''.rpm.lock'', then queries ''rpm_packages''.
		 */
		public void rpm()
		{
			var path = "/var/lib/rpm";
			var dir = GLib.File.new_for_path(path);
			try {
				var info = dir.query_info(
					GLib.FileAttribute.STANDARD_TYPE + "," +
					GLib.FileAttribute.STANDARD_SYMLINK_TARGET,
					GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
				if (info.get_file_type() == GLib.FileType.SYMBOLIC_LINK) {
					var target = info.get_symlink_target();
					if (GLib.Path.is_absolute(target)) {
						path = target;
					}
					if (!GLib.Path.is_absolute(target)) {
						var resolved = dir.get_parent().resolve_relative_path(target).get_path();
						if (resolved != null) {
							path = resolved;
						}
					}
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			var lock_path = GLib.Path.build_filename(path, ".rpm.lock");
			try {
				this.watch = GLib.File.new_for_path(path).monitor_directory(
					GLib.FileMonitorFlags.WATCH_MOVES, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			var monitor = this.watch;
			if (monitor == null) {
				return;
			}
			monitor.changed.connect((file, other, event_type) => {
				if (this.later != 0) {
					GLib.Source.remove(this.later);
				}
				this.later = GLib.Timeout.add_seconds(60, () => {
					var fds = new Gee.ArrayList<int>();
					var blocked = false;
					string[] locks = { lock_path };
					foreach (var lock in locks) {
						var fd = Posix.open(lock, Posix.O_RDWR);
						if (fd < 0) {
							if (Posix.errno != Posix.ENOENT) {
								blocked = true;
								break;
							}
							continue;
						}
						Posix.fcntl(fd, Posix.F_SETFD, Posix.FD_CLOEXEC);
						var flock = Posix.Flock();
						flock.l_type = Posix.F_WRLCK;
						flock.l_whence = Posix.SEEK_SET;
						flock.l_start = 0;
						flock.l_len = 0;
						if (Posix.fcntl(fd, Posix.F_SETLK, flock) != 0) {
							Posix.close(fd);
							blocked = true;
							break;
						}
						fds.add(fd);
					}
					if (blocked) {
						foreach (var held in fds) {
							Posix.close(held);
						}
						return true;
					}
					this.application.osquery.send_packages();
					foreach (var held in fds) {
						Posix.close(held);
					}
					this.later = 0;
					return false;
				});
			});
		}

	}
}
