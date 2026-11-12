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
	 * Read which installed packages have an update waiting.
	 *
	 * {@link check} uses
	 * {@link Argus.Shared.OSQuery.OsVersion.package_manager}.
	 * APT runs {@link check_apt}. DNF runs {@link check_rpm}.
	 * An empty list is up to date. A failure throws. The
	 * commands read the lists already on the host.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pending = new Argus.Agent.UpdatesAvailable();
	 * var names = pending.check(application.os_version);
	 * }}}
	 */
	public class UpdatesAvailable : GLib.Object
	{
		/**
		 * Pending package names for this operating system.
		 *
		 * APT calls {@link check_apt}. DNF calls {@link check_rpm}.
		 * Any other value throws.
		 *
		 * @param os_version startup ''os_version'' row
		 * @return package names, empty when none are waiting
		 */
		public Gee.ArrayList<string> check(
			Argus.Shared.OSQuery.OsVersion os_version
		) throws GLib.Error
		{
			switch (os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return this.check_apt();
				case Argus.Shared.OSQuery.PackageManager.DNF:
					return this.check_rpm();
				default:
					throw new GLib.IOError.FAILED("no package check for this operating system");
			}
		}

		/**
		 * Packages apt would upgrade from the local lists.
		 *
		 * The command is ''apt-get -s -qq upgrade'' with locking
		 * disabled. Each ''Inst'' line is one package. The name
		 * is the second field. A non-zero exit throws.
		 *
		 * @return package names, empty when none are waiting
		 */
		public Gee.ArrayList<string> check_apt() throws GLib.Error
		{
			var child = new GLib.Subprocess.newv({
				"apt-get", "-o", "Debug::NoLocking=true",
				"-s", "-qq", "upgrade"
			}, GLib.SubprocessFlags.STDOUT_PIPE);
			string? stdout_text = null;
			var read = child.communicate_utf8(null, null, out stdout_text, null);
			if (!read || !child.get_if_exited()) {
				throw new GLib.IOError.FAILED("apt-get did not exit");
			}
			if (child.get_exit_status() != 0) {
				throw new GLib.IOError.FAILED("apt-get exited %d".printf(child.get_exit_status()));
			}
			var names = new Gee.ArrayList<string>();
			var output = stdout_text != null ? stdout_text : "";
			foreach (var line in output.split("\n")) {
				if (!line.has_prefix("Inst ")) {
					continue;
				}
				var fields = line.split(" ");
				if (fields.length < 2 || fields[1] == "") {
					continue;
				}
				names.add(fields[1]);
			}
			return names;
		}

		/**
		 * Packages dnf would upgrade from the local cache.
		 *
		 * The command is ''dnf check-update --cacheonly''.
		 * Exit ''100'' means updates are waiting. Exit ''0''
		 * is an empty list. Any other exit throws. The name
		 * is the first field, without the arch after the
		 * last dot.
		 *
		 * @return package names, empty when none are waiting
		 */
		public Gee.ArrayList<string> check_rpm() throws GLib.Error
		{
			var child = new GLib.Subprocess.newv({
				"dnf", "check-update", "--cacheonly"
			}, GLib.SubprocessFlags.STDOUT_PIPE);
			string? stdout_text = null;
			var read = child.communicate_utf8(null, null, out stdout_text, null);
			if (!read || !child.get_if_exited()) {
				throw new GLib.IOError.FAILED("dnf did not exit");
			}
			var code = child.get_exit_status();
			if (code != 0 && code != 100) {
				throw new GLib.IOError.FAILED("dnf exited %d".printf(code));
			}
			var names = new Gee.ArrayList<string>();
			var output = stdout_text != null ? stdout_text : "";
			foreach (var line in output.split("\n")) {
				var fields = line.split(" ");
				if (fields.length < 2 || fields[0] == "") {
					continue;
				}
				var token = fields[0];
				var dot = token.last_index_of(".");
				if (dot < 1) {
					continue;
				}
				names.add(token.substring(0, dot));
			}
			return names;
		}
	}
}
