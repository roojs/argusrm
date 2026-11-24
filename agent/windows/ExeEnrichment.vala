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

namespace Argus.Agent.Windows
{
	/**
	 * Map program rows to PE paths, then fill {@link by_path}.
	 *
	 * {@link locate} maps each snapshot row to one ''.exe'' or ''.dll''.
	 * {@link enrich} stats that path, reads {@link Argus.Agent.SQT.WinFileIdentity},
	 * hashes on cache miss, and reads Authenticode via {@link Win32.WinPeAuthenticode}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var enrich = new Argus.Agent.Windows.ExeEnrichment();
	 * enrich.locate(rows);
	 * enrich.enrich(rows, app.client_db);
	 * var cached = enrich.by_path.get("C:\\\\Windows\\\\System32\\\\foo.exe");
	 * }}}
	 */
	public class ExeEnrichment : GLib.Object
	{
		private Gee.HashMap<Argus.Shared.OSQuery.Programs, string> row_path {
			get; set; default = new Gee.HashMap<Argus.Shared.OSQuery.Programs, string>();
		}
		private Gee.HashMap<string, Gee.ArrayList<Argus.Shared.OSQuery.Programs>> path_rows {
			get; set; default = new Gee.HashMap<string, Gee.ArrayList<Argus.Shared.OSQuery.Programs>>();
		}

		/**
		 * Enrichment after {@link enrich}, keyed by PE path.
		 */
		public Gee.HashMap<string, Argus.Agent.SQT.WinFileIdentity> by_path {
			get; private set; default =
				new Gee.HashMap<string, Argus.Agent.SQT.WinFileIdentity>();
		}

		/**
		 * Index each row's PE path.
		 *
		 * @param rows osquery programs snapshot
		 */
		public void locate(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
		{
			this.row_path.clear();
			this.path_rows.clear();
			var pe_path = new GLib.Regex("([A-Za-z]:\\\\.*?\\.(?:exe|dll))",
				GLib.RegexCompileFlags.CASELESS);
			foreach (var row in rows) {
				switch (row.source) {
					case "programs":
					case "appx":
					case "chocolatey":
					case "service":
					case "startup":
						var path = row.install_location.strip();
						var lower = path.down();
						if (!lower.has_suffix(".exe") && !lower.has_suffix(".dll")) {
							var haystack = row.install_location;
							switch (row.source) {
								case "programs":
									haystack = row.uninstall_string;
									break;

								default:
									break;
							}
							GLib.MatchInfo match;
							if (!pe_path.match(haystack, 0, out match)) {
								continue;
							}
							var start = 0;
							var end = 0;
							if (!match.fetch_pos(1, out start, out end)) {
								continue;
							}
							path = match.fetch(1);
							if (path == "") {
								continue;
							}
						}
						this.row_path.set(row, path);
						if (!this.path_rows.has_key(path)) {
							this.path_rows.set(path, new Gee.ArrayList<Argus.Shared.OSQuery.Programs>());
						}
						this.path_rows.get(path).add(row);
						break;

					default:
						continue;
				}
			}
		}

		/**
		 * Stat each located path and fill {@link by_path}.
		 *
		 * @param rows same snapshot passed to {@link locate}
		 * @param db agent client database with ''win_file_identity''
		 */
		public void enrich(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows, SQ.Database db)
		{
			this.by_path.clear();
			foreach (var path in this.path_rows.keys) {
				var file = GLib.File.new_for_path(path);
				var size = (int64) 0;
				var mtime = 0;
				try {
					var info = file.query_info(
						GLib.FileAttribute.STANDARD_SIZE + "," + GLib.FileAttribute.TIME_MODIFIED,
						GLib.FileQueryInfoFlags.NONE);
					size = info.get_size();
					var dt = info.get_modification_date_time();
					if (dt != null) {
						mtime = (int) dt.to_unix();
					}
				} catch (GLib.Error e) {
					var miss = new Argus.Agent.SQT.WinFileIdentity() {
						path = path,
						signing_result = "missing",
						scan_source = "win32",
						scanned_dt = (int) new GLib.DateTime.now_utc().to_unix(),
					};
					this.by_path.set(path, miss);
					Argus.Agent.SQT.WinFileIdentity.replace_row(db, miss);
					continue;
				}
				var stored = new Gee.ArrayList<Argus.Agent.SQT.WinFileIdentity>();
				var int_binds = new Gee.HashMap<string, int>();
				var binds = new Gee.HashMap<string, string>();
				binds.set("path", path);
				Argus.Agent.SQT.WinFileIdentity.query(db).selectWhere(
					"WHERE path = $path", int_binds, binds, stored);
				if (stored.size > 0 && stored.get(0).size_bytes == size &&
					stored.get(0).mtime_unix == mtime && stored.get(0).file_sha256 != "" &&
					stored.get(0).signing_result != "") {
					this.by_path.set(path, stored.get(0));
					continue;
				}
				var file_sha256 = "";
				var signing_result = "";
				try {
					var checksum = new GLib.Checksum(GLib.ChecksumType.SHA256);
					var stream = file.read();
					var buf = new uint8[65536];
					while (true) {
						var n = stream.read(buf);
						if (n <= 0) {
							break;
						}
						checksum.update(buf, (size_t) n);
					}
					file_sha256 = checksum.get_string();
				} catch (GLib.Error e) {
					signing_result = "unreadable";
				}
				var signer_cert_sha256 = "";
				var signer_subject_key_id = "";
				var signer_publisher = "";
				var signer_issuer = "";
				var signer_serial = "";
				if (signing_result == "") {
					var auth = Win32.WinPeAuthenticode();
					if (Win32.win_pe_read_authenticode(path.to_utf16(), ref auth)) {
						signing_result = (string) auth.signing_result;
						signer_cert_sha256 = (string) auth.signer_cert_sha256;
						signer_subject_key_id = (string) auth.signer_subject_key_id;
						signer_publisher = (string) auth.signer_publisher;
						signer_issuer = (string) auth.signer_issuer;
						signer_serial = (string) auth.signer_serial;
					} else {
						signing_result = "error";
					}
				}
				var now = (int) new GLib.DateTime.now_utc().to_unix();
				var fresh = new Argus.Agent.SQT.WinFileIdentity() {
					path = path,
					size_bytes = size,
					mtime_unix = mtime,
					file_sha256 = file_sha256,
					signing_result = signing_result,
					signer_cert_sha256 = signer_cert_sha256,
					signer_subject_key_id = signer_subject_key_id,
					signer_publisher = signer_publisher,
					signer_issuer = signer_issuer,
					signer_serial = signer_serial,
					scan_source = "win32",
					scanned_dt = now,
				};
				this.by_path.set(path, fresh);
				Argus.Agent.SQT.WinFileIdentity.replace_row(db, fresh);
			}
		}

		/**
		 * Copy {@link by_path} enrichment onto each program row located in
		 * {@link locate}.
		 *
		 * @param rows same snapshot passed to {@link enrich}
		 */
		public void attach(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
		{
			foreach (var row in rows) {
				if (!this.row_path.has_key(row)) {
					continue;
				}
				var path = this.row_path.get(row);
				if (!this.by_path.has_key(path)) {
					continue;
				}
				var identity = this.by_path.get(path);
				row.file_sha256 = identity.file_sha256;
				row.signing_result = identity.signing_result;
				row.signer_cert_sha256 = identity.signer_cert_sha256;
				row.signer_subject_key_id = identity.signer_subject_key_id;
				row.signer_publisher = identity.signer_publisher;
				row.signer_issuer = identity.signer_issuer;
				row.signer_serial = identity.signer_serial;
			}
		}
	}
}