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

namespace Argus.Shared.SQT
{
	/**
	 * One ''apt_url'' row.
	 *
	 * Repository identity, sync metadata, and HEAD/GET for the ''Packages'' index.
	 */
	public class AptUrl : GLib.Object, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
		public string url_key { get; set; default = ""; }
		public string base_uri { get; set; default = ""; }
		public string suite { get; set; default = ""; }
		public string components { get; set; default = ""; }
		public string arch { get; set; default = "amd64"; }
		public int64 last_synced_dt { get; set; default = 0; }
		public string last_error { get; set; default = ""; }
		/**
		 * ''ETag'' from the last successful ''Packages'' GET.
		 */
		public string packages_etag { get; set; default = ""; }
		/**
		 * ''Last-Modified'' from the last successful ''Packages'' GET.
		 */
		public string packages_last_modified { get; set; default = ""; }

		/**
		 * Rows in ''apt_url''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<AptUrl> query(SQ.Database db)
		{
			return new SQ.Query<AptUrl>(db, "apt_url");
		}

		/**
		 * HEAD the index and compare to stored validators.
		 *
		 * @return true when the index is unchanged and GET can be skipped
		 * @throws GLib.Error when HEAD cannot validate a prior sync
		 */
		public bool head() throws GLib.Error
		{
			var component = this.components.split(" ")[0];
			var packages_url = this.base_uri + "/dists/" + this.suite + "/" + component
				+ "/binary-" + this.arch + "/Packages.gz";
			var session = new Soup.Session();
			var message = new Soup.Message("HEAD", packages_url);
			message.request_headers.append("User-Agent", "argusrm");
			try {
				session.send_and_read(message, null);
			} catch (GLib.Error e) {
				if (this.last_synced_dt < 1) {
					return false;
				}
				throw new IOError.FAILED(
					"apt_url HEAD %s: %s".printf(packages_url, e.message));
			}
			if (message.status_code != Soup.Status.OK) {
				if (this.last_synced_dt < 1) {
					return false;
				}
				throw new IOError.FAILED(
					"apt_url HEAD %s: HTTP %u".printf(packages_url, message.status_code));
			}
			if (this.last_synced_dt < 1) {
				return false;
			}
			var etag_hdr = message.response_headers.get_one("ETag");
			var remote_etag = etag_hdr != null ? etag_hdr : "";
			var modified_hdr = message.response_headers.get_one("Last-Modified");
			var remote_modified = modified_hdr != null ? modified_hdr : "";
			if (remote_etag != ""
				&& this.packages_etag != ""
				&& remote_etag == this.packages_etag) {
				return true;
			}
			if (remote_modified != ""
				&& this.packages_last_modified != ""
				&& remote_modified == this.packages_last_modified) {
				return true;
			}
			return false;
		}

		/**
		 * GET the index after {@link head} returned false.
		 *
		 * @return uncompressed ''Packages'' body
		 * @throws GLib.Error when GET or gunzip fails
		 */
		public GLib.InputStream fetch() throws GLib.Error
		{
			var component = this.components.split(" ")[0];
			var packages_url = this.base_uri + "/dists/" + this.suite + "/" + component
				+ "/binary-" + this.arch + "/Packages.gz";
			var session = new Soup.Session();
			var get = new Soup.Message("GET", packages_url);
			get.request_headers.append("User-Agent", "argusrm");
			GLib.Bytes body = session.send_and_read(get, null);
			if (get.status_code != Soup.Status.OK || body.get_size() == 0) {
				throw new IOError.FAILED(
					"apt_url GET %s: HTTP %u".printf(packages_url, get.status_code));
			}
			var etag_hdr = get.response_headers.get_one("ETag");
			var etag = etag_hdr != null ? etag_hdr : "";
			var modified_hdr = get.response_headers.get_one("Last-Modified");
			var modified = modified_hdr != null ? modified_hdr : "";
			if (etag != "") {
				this.packages_etag = etag;
			}
			if (modified != "") {
				this.packages_last_modified = modified;
			}
			if (!packages_url.has_suffix(".gz")) {
				return new GLib.MemoryInputStream.from_bytes(body);
			}
			var converter = new GLib.ZlibDecompressor(GLib.ZlibCompressorFormat.GZIP);
			var input = new GLib.MemoryInputStream.from_bytes(body);
			var filter = new GLib.ConverterInputStream(input, converter);
			var chunk = new uint8[65536];
			var out_buf = new GLib.ByteArray();
			while (true) {
				var n = filter.read(chunk);
				if (n == 0) {
					break;
				}
				if (n < 0) {
					throw new IOError.FAILED(
						"apt_url gunzip %s".printf(packages_url));
				}
				out_buf.append(chunk[0:n]);
			}
			return new GLib.MemoryInputStream.from_bytes(new GLib.Bytes(out_buf.data));
		}

		/**
		 * Create ''apt_url''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS apt_url (
					id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					url_key         TEXT NOT NULL UNIQUE,
					base_uri        TEXT NOT NULL DEFAULT '',
					suite           TEXT NOT NULL DEFAULT '',
					components      TEXT NOT NULL DEFAULT '',
					arch            TEXT NOT NULL DEFAULT 'amd64',
					last_synced_dt          INTEGER NOT NULL DEFAULT 0,
					last_error              TEXT NOT NULL DEFAULT '',
					packages_etag           TEXT NOT NULL DEFAULT '',
					packages_last_modified  TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("apt_url create failed: %s", db.db.errmsg());
			}
		}
	}
}