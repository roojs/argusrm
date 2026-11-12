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
	 * queries osquery. {@link send}
	 * posts ''OSQuery.update''. Startup does not construct this.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var monitor = new Argus.Agent.PackageMonitor(application);
	 * monitor.apt();
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
		 * @param application agent whose startup fetch is kept
		 */
		public PackageMonitor(Application application)
		{
			this.application = application;
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
					return;
				}
				this.later = GLib.Timeout.add_seconds(1, () => {
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
					return;
				}
				this.later = GLib.Timeout.add_seconds(1, () => {
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
