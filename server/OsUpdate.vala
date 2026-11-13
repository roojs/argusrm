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
	 * Sync OS release data from ''osinfo-query'' into ''os_releases''.
	 *
	 * {@link check} checks whether ''osinfo-query'' is installed,
	 * inspects active ''os_version'' rows, maps each platform via
	 * {@link distro_for}, and passes due distributions to
	 * {@link check_distro} to update ''os_releases'' rows in place.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var os_update = new Argus.Server.OsUpdate(app);
	 * os_update.start();
	 * }}}
	 */
	public class OsUpdate : GLib.Object
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		private uint source_id = 0;
		private bool checking = false;
		private Gee.HashMap<string, int> checked_at = new Gee.HashMap<string, int>();

		/**
		 * Create the checker for one server.
		 *
		 * @param app the running server
		 */
		public OsUpdate(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Run the first check and repeat hourly for due platforms.
		 */
		public void start()
		{
			if (this.source_id != 0) {
				return;
			}
			this.check.begin();
			this.source_id = GLib.Timeout.add_seconds(60 * 60, () => {
				this.check.begin();
				return true;
			});
		}

		/**
		 * Cancel the repeating timer.
		 */
		public void stop()
		{
			if (this.source_id != 0) {
				GLib.Source.remove(this.source_id);
				this.source_id = 0;
			}
		}

		/**
		 * Map an ''os_version.platform'' value to its ''osinfo-query'' ''distro''.
		 *
		 * @param platform ''os_version.platform'' string
		 * @return ''osinfo-query'' distro key, or empty when unsupported
		 */
		public string distro_for(string platform)
		{
			switch (platform.strip().down()) {
				case "":
				case "android":
					return "";

				case "windows":
					return "win";

				case "opensuse-leap":
				case "opensuse-tumbleweed":
					return "opensuse";

				case "darwin":
					return "osx";

				case "alpine":
					return "alpinelinux";

				case "arch":
					return "archlinux";

				case "oracle":
					return "ol";

				default:
					return platform.strip().down();
			}
		}

		/**
		 * Resolve the cleaned ''platform'' for one ''osinfo-query'' row.
		 *
		 * Splits product variants into distinct ''platform'' values so
		 * ''os_releases'' does not mix separate release tracks.
		 *
		 * @param distro ''osinfo-query'' distribution key
		 * @param short_id unique ''osinfo-query'' short identifier
		 * @param name full OS release name
		 * @param fallback default ''os_version.platform''
		 * @return cleaned platform name
		 */
		public string platform_for(string distro, string short_id, string name, string fallback)
		{
			switch (distro) {
				case "opensuse":
					return short_id == "opensusetumbleweed" ? "opensuse-tumbleweed" : "opensuse-leap";

				case "win":
					return name.contains("Server") ? "windows-server" : "windows";

				case "fedora":
					if (short_id.has_prefix("silverblue")) {
						return "fedora-silverblue";
					}
					if (short_id.has_prefix("fedora-coreos")) {
						return "fedora-coreos";
					}
					return fallback;

				case "centos":
					return short_id.has_prefix("centos-stream") ? "centos-stream" : fallback;

				case "rhel":
					return short_id.has_prefix("rhel-atomic") ? "rhel-atomic" : fallback;

				case "almalinux":
					return short_id.has_prefix("almalinux-kitten") ? "almalinux-kitten" : fallback;

				default:
					return fallback;
			}
		}

		/**
		 * Query ''osinfo-query'' for due active platforms.
		 */
		public async void check()
		{
			if (this.checking) {
				return;
			}
			this.checking = true;
			var bin = GLib.Environment.find_program_in_path("osinfo-query");
			if (bin == null || bin == "") {
				GLib.debug("osinfo-query not found; skipping os_releases update");
				this.checking = false;
				return;
			}
			var stored = new Gee.ArrayList<Argus.Shared.OSQuery.OsVersion>();
			new SQ.Query<Argus.Shared.OSQuery.OsVersion>(this.app.db, "os_version").select(
				"WHERE deleted_dt = 0 AND agent_id IN (SELECT id FROM agent)",
				stored);
			var releases = new Gee.ArrayList<Argus.Shared.OsReleases>();
			Argus.Shared.OsReleases.query(this.app.db).select("", releases);
			var updated_by_platform = new Gee.HashMap<string, int>();
			foreach (var rel in releases) {
				if (!updated_by_platform.has_key(rel.platform) ||
					rel.updated > updated_by_platform.get(rel.platform)) {
					updated_by_platform.set(rel.platform, rel.updated);
				}
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			var cutoff = now - (24 * 60 * 60);
			var due = new Gee.HashMap<string, string>();
			foreach (var row in stored) {
				var plat = row.platform.strip().down();
				var distro = this.distro_for(plat);
				if (distro == "") {
					continue;
				}
				if (updated_by_platform.has_key(plat) &&
					updated_by_platform.get(plat) > cutoff) {
					continue;
				}
				if (this.checked_at.has_key(distro) &&
					this.checked_at.get(distro) > cutoff) {
					continue;
				}
				due.set(distro, plat);
			}
			var changed = false;
			foreach (var entry in due.entries) {
				this.checked_at.set(entry.key, now);
				if (yield this.check_distro(bin, entry.value, entry.key)) {
					changed = true;
				}
			}
			if (changed) {
				this.app.db.backupDB();
			}
			this.checking = false;
		}

		/**
		 * Query ''osinfo-query'' for one distribution and sync ''os_releases''.
		 *
		 * Existing rows for ''distro'' are updated in place by ''short_id''
		 * via {@link SQ.Query.updateOld}, new releases are inserted, and
		 * placeholder or removed rows are deleted.
		 *
		 * @param osinfo_bin resolved path to ''osinfo-query''
		 * @param platform default ''os_version.platform'' for this distro
		 * @param distro ''osinfo-query'' distribution key
		 * @return true when ''os_releases'' was updated for ''distro''
		 */
		public async bool check_distro(string osinfo_bin, string platform, string distro)
		{
			GLib.Subprocess child;
			try {
				child = new GLib.Subprocess.newv({
					osinfo_bin,
					"--fields=short-id,name,version,family,distro,release-date,eol-date,codename",
					"os",
					"distro=" + distro
				}, GLib.SubprocessFlags.STDOUT_PIPE);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return false;
			}
			string? stdout_text = null;
			var read = false;
			try {
				read = yield child.communicate_utf8_async(null, null, out stdout_text, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return false;
			}
			if (!read || !child.get_if_exited()) {
				GLib.warning("osinfo-query did not exit for %s", distro);
				return false;
			}
			if (child.get_exit_status() != 0) {
				GLib.debug("osinfo-query returned %d for %s",
					child.get_exit_status(), distro);
				return false;
			}
			var output = stdout_text != null ? stdout_text : "";
			var header_done = false;
			var rel_query = Argus.Shared.OsReleases.query(this.app.db);
			var existing = new Gee.ArrayList<Argus.Shared.OsReleases>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("distro", distro);
			rel_query.selectWhere(
				"WHERE distro = $distro ORDER BY id ASC",
				int_binds, text_binds, existing);
			var index = new Gee.HashMap<string, Argus.Shared.OsReleases>();
			foreach (var old in existing) {
				if (old.short_id != "" && !index.has_key(old.short_id)) {
					index.set(old.short_id, old);
					continue;
				}
				rel_query.deleteId(old.id);
			}
			var fetched = (int) new GLib.DateTime.now_utc().to_unix();
			var seen = new Gee.HashMap<string, bool>();
			foreach (var raw in output.split("\n")) {
				if (raw.strip() == "") {
					continue;
				}
				if (!header_done) {
					header_done = true;
					continue;
				}
				if (raw.contains("---+")) {
					continue;
				}
				var fields = raw.split("|");
				if (fields.length < 8) {
					continue;
				}
				var short_id = fields[0].strip();
				var rel_ver = fields[2].strip();
				var rel_date = fields[5].strip();
				if (short_id == "" || short_id.has_suffix("-unknown") ||
					rel_ver == "unknown" || rel_date == "" || seen.has_key(short_id)) {
					continue;
				}
				seen.set(short_id, true);
				var rel_name = fields[1].strip();
				var rel_distro = fields[4].strip();
				var ver_parts = rel_ver.split(".");
				var newer = new Argus.Shared.OsReleases() {
					short_id = short_id,
					distro = rel_distro != "" ? rel_distro : distro,
					platform = this.platform_for(distro, short_id, rel_name, platform),
					family = fields[3].strip(),
					name = rel_name,
					version = rel_ver,
					major = ver_parts.length > 0 ? int.parse(ver_parts[0]) : 0,
					minor = ver_parts.length > 1 ? int.parse(ver_parts[1]) : 0,
					codename = fields[7].strip(),
					released = rel_date,
					eol = fields[6].strip(),
					is_lts = rel_name.contains("LTS") ? 1 : 0,
					updated = fetched
				};
				if (index.has_key(short_id)) {
					var old = index.get(short_id);
					newer.id = old.id;
					rel_query.updateOld(old, newer);
					index.unset(short_id);
					continue;
				}
				rel_query.insert(newer);
			}
			foreach (var old in index.values) {
				rel_query.deleteId(old.id);
			}
			return seen.size > 0;
		}
	}
}
