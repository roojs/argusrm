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

namespace Argus.Agent.Apt
{
	/**
	 * Outcome of verifying one executable against dpkg metadata.
	 */
	public enum ExeVerifyStatus
	{
		VERIFIED_PACKAGE,
		UNPACKAGED,
		NO_MD5SUMS,
		HASH_MISMATCH,
		PACKAGE_NOT_INSTALLED,
		MISSING_OR_UNREADABLE,
		DELETED_BINARY
	}

	/**
	 * Installed Debian package name and version from ''status''.
	 */
	public class InstalledPkgInfo : GLib.Object
	{
		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public bool is_installed { get; set; default = false; }
	}

	/**
	 * Result of {@link PackageExeValidator.verify_exe}.
	 */
	public class ExeVerifyResult : GLib.Object
	{
		public ExeVerifyStatus status { get; set; default = ExeVerifyStatus.UNPACKAGED; }
		public string input_path { get; set; default = ""; }
		public string resolved_path { get; set; default = ""; }
		public string package_name { get; set; default = ""; }
		public string package_version { get; set; default = ""; }
		public string expected_md5 { get; set; default = ""; }
		public string actual_md5 { get; set; default = ""; }
		public string sha256 { get; set; default = ""; }
		public string detail { get; set; default = ""; }
	}

	/**
	 * Verify running executables against Debian package file lists and
	 * ''md5sums'' metadata.
	 *
	 * Reads ''/var/lib/dpkg/status'', per-package ''.list'' files,
	 * diversions, and ''.md5sums'' on demand. Caches the dpkg index until
	 * ''status'' or ''info'' changes. Per-path results are keyed by resolved
	 * path and file mtime.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var validator = new Argus.Agent.Apt.PackageExeValidator();
	 * var result = validator.verify_exe("/usr/bin/bash");
	 * }}}
	 */
	public class PackageExeValidator : GLib.Object
	{
		private GLib.Regex md5_line_regex { get; set; }
		private GLib.Regex usr_sbindir_regex { get; set; }
		private GLib.Regex deleted_suffix_regex { get; set; }
		private GLib.Regex status_stanza_regex { get; set; }

		private int64 cached_status_mtime_usec = -1;
		private int64 cached_info_mtime_usec = -1;

		private Gee.HashMap<string, string> path_to_pkg {
			get; set; default = new Gee.HashMap<string, string>();
		}
		private Gee.HashMap<string, InstalledPkgInfo> pkg_info {
			get; set; default = new Gee.HashMap<string, InstalledPkgInfo>();
		}
		private Gee.HashMap<string, Gee.HashMap<string, string>> pkg_md5sums {
			get; set; default = new Gee.HashMap<string, Gee.HashMap<string, string>>();
		}
		private Gee.HashMap<string, ExeVerifyResult> result_cache {
			get; set; default = new Gee.HashMap<string, ExeVerifyResult>();
		}

		public PackageExeValidator()
		{
			this.md5_line_regex = new GLib.Regex("^([0-9a-fA-F]{32})\\s+(.+)$", GLib.RegexCompileFlags.OPTIMIZE);
			this.usr_sbindir_regex = new GLib.Regex("^/(?:usr/)?((?:s?bin)/.+)$", GLib.RegexCompileFlags.OPTIMIZE);
			this.deleted_suffix_regex = new GLib.Regex("\\s+\\(deleted\\)$", GLib.RegexCompileFlags.OPTIMIZE);
			this.status_stanza_regex = new GLib.Regex("^(Package|Architecture|Version|Status): (.+)$", GLib.RegexCompileFlags.OPTIMIZE);
		}

		/**
		 * Drop cached verification results. The dpkg index cache is kept.
		 */
		public void clear_result_cache()
		{
			this.result_cache.clear();
		}

		/**
		 * Resolve ''raw_path'', map it to an owning package, and compare MD5
		 * when ''md5sums'' metadata exists.
		 *
		 * @param raw_path path from proc or caller; may end with '' (deleted)''
		 * @return verification outcome and package metadata
		 */
		public ExeVerifyResult verify_exe(string raw_path)
		{
			if (raw_path.strip() == "") {
				return new ExeVerifyResult() {
					input_path = raw_path,
					status = ExeVerifyStatus.MISSING_OR_UNREADABLE,
					detail = "Empty path",
				};
			}

			GLib.MatchInfo del_info;
			if (this.deleted_suffix_regex.match(raw_path, 0, out del_info)) {
				var start_pos = 0;
				var end_pos = 0;
				var resolved_path = raw_path;
				if (del_info.fetch_pos(0, out start_pos, out end_pos) && start_pos > 0) {
					resolved_path = raw_path.substring(0, start_pos);
				}
				return new ExeVerifyResult() {
					input_path = raw_path,
					resolved_path = resolved_path,
					status = ExeVerifyStatus.DELETED_BINARY,
					detail = "Executable unlinked from disk while running",
				};
			}

			var resolved = Posix.realpath(raw_path);
			var real = resolved != null ? resolved : "";
			if (real == "") {
				var status = Posix.errno == Posix.ENOENT ?
					ExeVerifyStatus.DELETED_BINARY : ExeVerifyStatus.MISSING_OR_UNREADABLE;
				return new ExeVerifyResult() {
					input_path = raw_path,
					resolved_path = raw_path,
					status = status,
					detail = "realpath failed: " + Posix.strerror(Posix.errno),
				};
			}

			var file_mtime_usec = this.get_path_mtime_usec(real);
			if (file_mtime_usec < 0) {
				return new ExeVerifyResult() {
					input_path = raw_path,
					resolved_path = real,
					status = ExeVerifyStatus.MISSING_OR_UNREADABLE,
					detail = "Failed stat on " + real,
				};
			}

			var cache_key = real + "|" + file_mtime_usec.to_string();

			if (this.ensure_dpkg_index_current()) {
				this.result_cache.clear();
			}

			if (this.result_cache.has_key(cache_key)) {
				return this.result_cache.get(cache_key);
			}

			var computed = this.compute_verification(real);
			this.result_cache.set(cache_key, computed);
			return computed;
		}

		private bool ensure_dpkg_index_current()
		{
			var status_mtime = this.get_path_mtime_usec("/var/lib/dpkg/status");
			var info_mtime = this.get_path_mtime_usec("/var/lib/dpkg/info");
			var changed = status_mtime != this.cached_status_mtime_usec ||
				info_mtime != this.cached_info_mtime_usec ||
				(this.path_to_pkg.size == 0 && this.pkg_info.size == 0);

			if (!changed) {
				return false;
			}

			this.path_to_pkg.clear();
			this.pkg_info.clear();
			this.pkg_md5sums.clear();

			this.read_status_stanzas();
			this.load_dpkg_list_files();
			this.load_dpkg_diversions();

			this.cached_status_mtime_usec = status_mtime;
			this.cached_info_mtime_usec = info_mtime;
			return true;
		}

		private void read_status_stanzas()
		{
			var file = GLib.File.new_for_path("/var/lib/dpkg/status");
			if (!file.query_exists()) {
				return;
			}

			try {
				var dis = new GLib.DataInputStream(file.read());
				var cur_pkg = "";
				var cur_arch = "";
				var cur_ver = "";
				var cur_status = "";
				var raw_line = dis.read_line();

				while (raw_line != null) {
					var line = raw_line;
					if (line.strip() == "") {
						this.commit_status_stanza(cur_pkg, cur_arch, cur_ver, cur_status);
						cur_pkg = "";
						cur_arch = "";
						cur_ver = "";
						cur_status = "";
						raw_line = dis.read_line();
						continue;
					}

					GLib.MatchInfo info;
					if (this.status_stanza_regex.match(line, 0, out info)) {
						var field = info.fetch(1);
						var value_fetched = info.fetch(2);
						var value = value_fetched != null ? value_fetched.strip() : "";
						if (field != null && field != "") {
							switch (field) {
								case "Package":
									cur_pkg = value;
									break;

								case "Architecture":
									cur_arch = value;
									break;

								case "Version":
									cur_ver = value;
									break;

								case "Status":
									cur_status = value;
									break;

								default:
									break;
							}
						}
					}
					raw_line = dis.read_line();
				}

				this.commit_status_stanza(cur_pkg, cur_arch, cur_ver, cur_status);
			} catch (GLib.Error e) {
				GLib.warning("Error reading /var/lib/dpkg/status: %s", e.message);
			}
		}

		private void commit_status_stanza(string pkg, string arch, string ver, string status)
		{
			if (pkg == "" || ver == "" || status == "") {
				return;
			}

			var entry = new InstalledPkgInfo() {
				name = pkg,
				version = ver,
				is_installed = status == "install ok installed",
			};

			this.pkg_info.set(pkg, entry);
			if (arch != "" && arch != "all") {
				this.pkg_info.set(pkg + ":" + arch, entry);
			}
		}

		private void load_dpkg_list_files()
		{
			try {
				var dir = GLib.Dir.open("/var/lib/dpkg/info", 0);
				var raw_name = dir.read_name();

				while (raw_name != null) {
					var entry_name = raw_name;
					if (entry_name.has_suffix(".list")) {
						var pkg_key = entry_name.substring(0, entry_name.length - ".list".length);
						var list_path = GLib.Path.build_filename("/var/lib/dpkg/info", entry_name);
						this.load_single_list_file(list_path, pkg_key);
					}
					raw_name = dir.read_name();
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed opening /var/lib/dpkg/info: %s", e.message);
			}
		}

		private void load_single_list_file(string list_path, string pkg_key)
		{
			try {
				var dis = new GLib.DataInputStream(GLib.File.new_for_path(list_path).read());
				var raw_line = dis.read_line();

				while (raw_line != null) {
					var p = raw_line.strip();
					if (p != "" && p.has_prefix("/")) {
						this.index_path_variants(p, pkg_key);
					}
					raw_line = dis.read_line();
				}
			} catch (GLib.Error e) {
			}
		}

		private void load_dpkg_diversions()
		{
			var file = GLib.File.new_for_path("/var/lib/dpkg/diversions");
			if (!file.query_exists()) {
				return;
			}

			try {
				var dis = new GLib.DataInputStream(file.read());
				var raw_orig = dis.read_line();

				while (raw_orig != null) {
					var raw_diverted = dis.read_line();
					var raw_owner = dis.read_line();
					if (raw_diverted == null || raw_owner == null) {
						break;
					}

					var o = raw_orig.strip();
					var d = raw_diverted.strip();
					var pkg = raw_owner.strip();

					if (d != "" && pkg != "" && pkg != ":") {
						this.index_path_variants(d, pkg);
					}
					if (o != "" && pkg != "" && pkg != ":" && !this.path_to_pkg.has_key(o)) {
						this.index_path_variants(o, pkg);
					}

					raw_orig = dis.read_line();
				}
			} catch (GLib.Error e) {
				GLib.warning("Failed reading /var/lib/dpkg/diversions: %s", e.message);
			}
		}

		private void index_path_variants(string p, string pkg_key)
		{
			if (!this.path_to_pkg.has_key(p)) {
				this.path_to_pkg.set(p, pkg_key);
			}

			var alt = this.usrmerge_alias(p);
			if (alt != "" && !this.path_to_pkg.has_key(alt)) {
				this.path_to_pkg.set(alt, pkg_key);
			}
		}

		private string usrmerge_alias(string p)
		{
			GLib.MatchInfo info;
			if (!this.usr_sbindir_regex.match(p, 0, out info)) {
				return "";
			}
			var tail = info.fetch(1);
			if (tail == null || tail == "") {
				return "";
			}
			if (p.has_prefix("/usr/")) {
				return "/" + tail;
			}
			return "/usr/" + tail;
		}

		private Gee.HashMap<string, string> get_or_load_md5sums(string pkg_key)
		{
			if (this.pkg_md5sums.has_key(pkg_key)) {
				return this.pkg_md5sums.get(pkg_key);
			}

			var map = new Gee.HashMap<string, string>();
			var sums_path = GLib.Path.build_filename("/var/lib/dpkg/info", pkg_key + ".md5sums");
			var file = GLib.File.new_for_path(sums_path);

			if (file.query_exists()) {
				try {
					var dis = new GLib.DataInputStream(file.read());
					var raw_line = dis.read_line();

					while (raw_line != null) {
						GLib.MatchInfo info;
						if (this.md5_line_regex.match(raw_line.strip(), 0, out info)) {
							var md5_fetched = info.fetch(1);
							var path_fetched = info.fetch(2);
							var md5_hex = md5_fetched != null ? md5_fetched.strip().down() : "";
							var rel_path = path_fetched != null ? path_fetched.strip() : "";
							if (rel_path.has_prefix("/")) {
								rel_path = rel_path.substring(1);
							}
							if (md5_hex != "" && rel_path != "") {
								map.set(rel_path, md5_hex);
							}
						}
						raw_line = dis.read_line();
					}
				} catch (GLib.Error e) {
				}
			}

			this.pkg_md5sums.set(pkg_key, map);
			return map;
		}

		private ExeVerifyResult compute_verification(string real_path)
		{
			var pkg_key = this.lookup_pkg_for_path(real_path);
			if (pkg_key == "") {
				return new ExeVerifyResult() {
					input_path = real_path,
					resolved_path = real_path,
					status = ExeVerifyStatus.UNPACKAGED,
					detail = "No owning Debian package found in dpkg file lists",
				};
			}

			var package_name = pkg_key;
			var package_version = "";
			if (this.pkg_info.has_key(pkg_key)) {
				var info_obj = this.pkg_info.get(pkg_key);
				package_name = info_obj.name;
				package_version = info_obj.version;
				if (!info_obj.is_installed) {
					return new ExeVerifyResult() {
						input_path = real_path,
						resolved_path = real_path,
						package_name = package_name,
						package_version = package_version,
						status = ExeVerifyStatus.PACKAGE_NOT_INSTALLED,
						detail = "Package " + info_obj.name + " (" + info_obj.version + ") is not in 'install ok installed' state",
					};
				}
			}

			var expected_md5 = this.lookup_expected_md5(pkg_key, real_path);

			var actual_md5 = "";
			var actual_sha256 = "";
			try {
				this.compute_file_hashes(real_path, out actual_md5, out actual_sha256);
			} catch (GLib.Error e) {
				return new ExeVerifyResult() {
					input_path = real_path,
					resolved_path = real_path,
					package_name = package_name,
					package_version = package_version,
					status = ExeVerifyStatus.MISSING_OR_UNREADABLE,
					detail = "Failed reading binary " + real_path + ": " + e.message,
				};
			}

			if (expected_md5 == "") {
				return new ExeVerifyResult() {
					input_path = real_path,
					resolved_path = real_path,
					package_name = package_name,
					package_version = package_version,
					actual_md5 = actual_md5,
					sha256 = actual_sha256,
					status = ExeVerifyStatus.NO_MD5SUMS,
					detail = "Owned by " + pkg_key + ", but no .md5sums entry exists for this file",
				};
			}

			if (actual_md5.down() != expected_md5.down()) {
				return new ExeVerifyResult() {
					input_path = real_path,
					resolved_path = real_path,
					package_name = package_name,
					package_version = package_version,
					expected_md5 = expected_md5,
					actual_md5 = actual_md5,
					sha256 = actual_sha256,
					status = ExeVerifyStatus.HASH_MISMATCH,
					detail = "MD5 mismatch for " + pkg_key + " (expected " + expected_md5 + ", got " + actual_md5 + ")",
				};
			}

			var display_name = package_name != "" ? package_name : pkg_key;
			var display_ver = package_version != "" ? package_version : "unknown";
			return new ExeVerifyResult() {
				input_path = real_path,
				resolved_path = real_path,
				package_name = package_name,
				package_version = package_version,
				expected_md5 = expected_md5,
				actual_md5 = actual_md5,
				sha256 = actual_sha256,
				status = ExeVerifyStatus.VERIFIED_PACKAGE,
				detail = "Verified against " + display_name + " (" + display_ver + ")",
			};
		}

		private string lookup_pkg_for_path(string path)
		{
			if (this.path_to_pkg.has_key(path)) {
				return this.path_to_pkg.get(path);
			}
			var alt = this.usrmerge_alias(path);
			if (alt != "" && this.path_to_pkg.has_key(alt)) {
				return this.path_to_pkg.get(alt);
			}
			return "";
		}

		private string lookup_expected_md5(string pkg_key, string real_path)
		{
			var sums_map = this.get_or_load_md5sums(pkg_key);
			var rel_real = real_path.has_prefix("/") ? real_path.substring(1) : real_path;
			if (sums_map.has_key(rel_real)) {
				return sums_map.get(rel_real);
			}
			var alt = this.usrmerge_alias(real_path);
			if (alt != "") {
				var rel_alt = alt.has_prefix("/") ? alt.substring(1) : alt;
				if (sums_map.has_key(rel_alt)) {
					return sums_map.get(rel_alt);
				}
			}
			return "";
		}

		private void compute_file_hashes(string path, out string md5_hex, out string sha256_hex) throws GLib.Error
		{
			var stream = GLib.File.new_for_path(path).read();
			var md5 = new GLib.Checksum(GLib.ChecksumType.MD5);
			var sha256 = new GLib.Checksum(GLib.ChecksumType.SHA256);

			var buf = new uint8[65536];
			var n_read = stream.read(buf);
			while (n_read > 0) {
				md5.update(buf, (size_t) n_read);
				sha256.update(buf, (size_t) n_read);
				n_read = stream.read(buf);
			}

			var md5_string = md5.get_string();
			var sha_string = sha256.get_string();
			md5_hex = md5_string != null ? md5_string : "";
			sha256_hex = sha_string != null ? sha_string : "";
		}

		private int64 get_path_mtime_usec(string path)
		{
			try {
				var attrs = GLib.FileAttribute.TIME_MODIFIED + "," + GLib.FileAttribute.TIME_MODIFIED_USEC;
				var info = GLib.File.new_for_path(path).query_info(attrs, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
				var sec = info.get_attribute_uint64(GLib.FileAttribute.TIME_MODIFIED);
				var usec = info.get_attribute_uint32(GLib.FileAttribute.TIME_MODIFIED_USEC);
				return ((int64) sec * 1000000) + (int64) usec;
			} catch (GLib.Error e) {
				return -1;
			}
		}
	}
}