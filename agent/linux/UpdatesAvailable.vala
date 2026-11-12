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
	 * Read which installed packages have an update waiting, on Linux.
	 *
	 * Not compiled. Nothing calls {@link check}. The host is the
	 * ''os_version'' row kept on {@link Application}.
	 * {@link Argus.Shared.OSQuery.OsVersion.package_manager} chooses
	 * {@link check_apt} or {@link check_rpm}. Each reads its own
	 * output. Unknown, including SUSE, does not run. The read does
	 * not install anything, and it does not send a row.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var waiting = new Argus.Agent.UpdatesAvailable(application).check();
	 * }}}
	 */
	public class UpdatesAvailable : GLib.Object
	{
		/**
		 * Agent that holds the ''os_version'' row.
		 */
		public Application application { get; construct; }

		/**
		 * @param application agent whose ''os_version'' query has run
		 */
		public UpdatesAvailable(Application application)
		{
			Object(application: application);
		}

		/**
		 * Package names that have an update waiting.
		 *
		 * An empty list is up to date. A failed command throws.
		 *
		 * @return package names
		 * @throws GLib.Error when the host has no row or no command
		 */
		public Gee.ArrayList<string> check() throws GLib.Error
		{
			var os = this.application.os_version;
			if (os == null) {
				throw new GLib.IOError.FAILED("os_version has not run");
			}
			switch (os.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return this.check_apt();
				case Argus.Shared.OSQuery.PackageManager.DNF:
					return this.check_rpm();
				default:
					throw new GLib.IOError.FAILED("no package command");
			}
		}

		/**
		 * Read ''apt-get -s upgrade'' and keep each ''Inst'' name.
		 *
		 * ''*Inst'' repeats that name, so it is skipped.
		 *
		 * @return package names, empty when none are waiting
		 * @throws GLib.Error when apt-get fails
		 */
		public Gee.ArrayList<string> check_apt() throws GLib.Error
		{
			var waiting = new Gee.ArrayList<string>();
			var child = new GLib.Subprocess.newv({
				"apt-get", "-o", "Debug::NoLocking=true",
				"-s", "-qq", "upgrade"
			}, GLib.SubprocessFlags.STDOUT_PIPE);
			string? stdout_text = null;
			var queried = child.communicate_utf8(null, null, out stdout_text, null);
			if (!queried || child.get_exit_status() != 0) {
				throw new GLib.IOError.FAILED("apt-get exited %d", child.get_exit_status());
			}
			var output = stdout_text != null ? stdout_text : "";
			var lines = output.split("\n");
			for (var i = 0; i < lines.length; i++) {
				var line = lines[i].strip();
				if (!line.has_prefix("Inst ")) {
					continue;
				}
				var parts = line.split(" ");
				if (parts.length < 2 || parts[1] == "") {
					continue;
				}
				waiting.add(parts[1]);
			}
			return waiting;
		}

		/**
		 * Read ''dnf check-update'' and keep each package name.
		 *
		 * Exit ''100'' means updates are waiting. Exit ''0'' means
		 * none. The name is the token before the architecture dot.
		 *
		 * @return package names, empty when none are waiting
		 * @throws GLib.Error when dnf fails
		 */
		public Gee.ArrayList<string> check_rpm() throws GLib.Error
		{
			var waiting = new Gee.ArrayList<string>();
			var child = new GLib.Subprocess.newv(
				{ "dnf", "check-update" },
				GLib.SubprocessFlags.STDOUT_PIPE);
			string? stdout_text = null;
			var queried = child.communicate_utf8(null, null, out stdout_text, null);
			var status = child.get_exit_status();
			if (!queried || (status != 0 && status != 100)) {
				throw new GLib.IOError.FAILED("dnf exited %d", status);
			}
			var output = stdout_text != null ? stdout_text : "";
			var lines = output.split("\n");
			for (var i = 0; i < lines.length; i++) {
				var line = lines[i].strip();
				if (line == "" || line.has_prefix("Last metadata")) {
					continue;
				}
				var fields = line.split(" ");
				var token = "";
				for (var f = 0; f < fields.length; f++) {
					if (fields[f] != "") {
						token = fields[f];
						break;
					}
				}
				var dot = token.last_index_of_char('.');
				if (dot <= 0) {
					continue;
				}
				waiting.add(token.slice(0, dot));
			}
			return waiting;
		}
	}
}
