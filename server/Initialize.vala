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

namespace Argus.Server
{
	/**
	 * Work done before the sockets bind.
	 *
	 * {@link fetch_osquery} creates the osquery directory under
	 * {@link LOCALSTATEDIR} and fetches the latest stable
	 * installers. Other startup work belongs in this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * if (!(new Argus.Server.Initialize()).fetch_osquery()) {
	 *     return 1;
	 * }
	 * }}}
	 */
	public class Initialize : GLib.Object
	{
		/**
		 * Fetch the osquery installers into {@link LOCALSTATEDIR}.
		 *
		 * Debian, RPM, and Windows files from the latest stable
		 * release are saved as ''osquery/osquery.deb'',
		 * ''osquery/osquery.rpm'', and ''osquery/osquery.msi''.
		 * A file already in the store is left in place. A failed
		 * fetch is logged. The sockets still open.
		 *
		 * @return false when the store directory cannot be created
		 */
		public bool fetch_osquery()
		{
			var osquery_dir = GLib.Path.build_filename(LOCALSTATEDIR, "osquery");
			if (!GLib.FileUtils.test(osquery_dir, GLib.FileTest.IS_DIR)) {
				if (GLib.DirUtils.create_with_parents(osquery_dir, 0755) != 0) {
					GLib.warning("download store %s", osquery_dir);
					return false;
				}
			}
			var session = new Soup.Session();
			var message = new Soup.Message("GET", "https://api.github.com/repos/osquery/osquery/releases/latest");
			message.request_headers.append("User-Agent", "argusrm");
			message.request_headers.append("Accept", "application/vnd.github+json");
			var body = new GLib.Bytes(new uint8[0]);
			try {
				body = session.send_and_read(message, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return true;
			}
			if (message.status_code != 200) {
				GLib.warning("osquery release %u", message.status_code);
				return true;
			}
			GitHub.Release release;
			try {
				var parsed = Json.gobject_from_data(
					typeof(GitHub.Release),
					(string) body.get_data(),
					(ssize_t) body.get_size());
				if (parsed == null) {
					GLib.warning("osquery release was not read");
					return true;
				}
				release = (GitHub.Release) parsed;
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return true;
			}
			if (release.assets.size == 0) {
				GLib.warning("osquery release has no assets");
				return true;
			}
			for (var i = 0; i < release.assets.size; i++) {
				var asset = release.assets.get(i);
				var name = asset.name;
				var saved = "";
				if (name.has_prefix("osquery_") && name.has_suffix(".linux_amd64.deb")) {
					saved = "osquery.deb";
				}
				if (name.has_prefix("osquery-") && name.has_suffix(".linux.x86_64.rpm") && !name.contains("debuginfo")) {
					saved = "osquery.rpm";
				}
				if (name.has_suffix(".msi")) {
					saved = "osquery.msi";
				}
				if (saved == "") {
					continue;
				}
				var dest = GLib.Path.build_filename(osquery_dir, saved);
				if (GLib.FileUtils.test(dest, GLib.FileTest.IS_REGULAR)) {
					try {
						var info = GLib.File.new_for_path(dest).query_info(
							GLib.FileAttribute.STANDARD_SIZE,
							GLib.FileQueryInfoFlags.NONE, null);
						if (info.get_size() > 0) {
							continue;
						}
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						continue;
					}
				}
				var url = asset.browser_download_url;
				GLib.debug("fetching %s", saved);
				var file_message = new Soup.Message("GET", url);
				file_message.request_headers.append("User-Agent", "argusrm");
				var blob = new GLib.Bytes(new uint8[0]);
				try {
					blob = session.send_and_read(file_message, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				if (file_message.status_code != 200 || blob.get_size() == 0) {
					GLib.warning("osquery %s %u", saved, file_message.status_code);
					continue;
				}
				var part = dest + ".part";
				try {
					GLib.FileUtils.set_data(part, blob.get_data());
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					continue;
				}
				try {
					GLib.File.new_for_path(part).move(GLib.File.new_for_path(dest),
						GLib.FileCopyFlags.OVERWRITE, null, null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			return true;
		}
	}
}
