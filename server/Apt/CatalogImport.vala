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

namespace Argus.Server.Apt
{
	/**
	 * One Depends edge in {@code apt_pkg_depends_staging} (names only).
	 */
	public class PkgDependsStaging : GLib.Object, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
		public string pkg_name { get; set; default = ""; }
		public string depends_pkg_name { get; set; default = ""; }
		public string constraint_text { get; set; default = ""; }

		public static SQ.Query<PkgDependsStaging> query(SQ.Database db)
		{
			return new SQ.Query<PkgDependsStaging>(db, "apt_pkg_depends_staging");
		}
	}

	/**
	 * Refresh catalog edges for one {@link AptUrl} row.
	 *
	 * Call {@link import} on one row, or {@link run_update} for every {@link AptUrl}.
	 */
	public class CatalogImport : GLib.Object
	{
		public SQ.Database db { get; construct; }
		public Argus.Shared.SQT.AptUrl url { get; construct; }

		public CatalogImport(SQ.Database db, Argus.Shared.SQT.AptUrl url)
		{
			Object(db: db, url: url);
		}

		/**
		 * {@link import} every row in ''apt_url''.
		 *
		 * @param db Argus database
		 */
		public static void run_update(SQ.Database db)
		{
			var rows = new Gee.ArrayList<Argus.Shared.SQT.AptUrl>();
			Argus.Shared.SQT.AptUrl.query(db).select("", rows);
			foreach (var row in rows) {
				new CatalogImport(db, row).import();
			}
		}

		/**
		 * @return false when the row is invalid or any step fails
		 */
		public bool import()
		{
			if (this.url.id < 1) {
				this.mark_error("missing apt_url");
				return false;
			}
			try {
				if (this.url.head()) {
					return true;
				}
			} catch (GLib.Error e) {
				this.mark_error(e.message);
				return false;
			}
			GLib.InputStream packages_stream;
			try {
				packages_stream = this.url.fetch();
			} catch (GLib.Error e) {
				this.mark_error(e.message);
				return false;
			}
			if (!this.read_staging(packages_stream)) {
				return false;
			}
			if (!this.merge()) {
				return false;
			}
			this.mark_synced();
			return true;
		}

		private bool read_staging(GLib.InputStream packages_stream)
		{
			this.db.exec("""
				CREATE TEMP TABLE apt_pkg_depends_staging (
					id                 INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					pkg_name           TEXT NOT NULL,
					depends_pkg_name   TEXT NOT NULL,
					constraint_text    TEXT NOT NULL DEFAULT ''
				);
				BEGIN TRANSACTION;
				""");

			var staging_q = PkgDependsStaging.query(this.db);
			var dis = new GLib.DataInputStream(packages_stream);
			string current_pkg = "";
			string current_field = "";
			string deps_text = "";
			string? line;
			while (true) {
				try {
					line = dis.read_line(null);
				} catch (GLib.Error e) {
					this.mark_error(e.message);
					this.db.exec(
						"ROLLBACK; DROP TABLE IF EXISTS apt_pkg_depends_staging;");
					return false;
				}
				if (line == null) {
					break;
				}
				if (line == "") {
					if (current_pkg != "" && deps_text != "") {
						this.stage_depends(staging_q, current_pkg, deps_text);
						deps_text = "";
					}
					current_pkg = "";
					current_field = "";
					continue;
				}
				if (line.has_prefix(" ") || line.has_prefix("\t")) {
					if (current_field == "Depends" || current_field == "Pre-Depends") {
						deps_text += " " + line.strip();
					}
					continue;
				}
				var header = line.split(": ", 2);
				if (header.length != 2) {
					continue;
				}
				current_field = header[0];
				var val = header[1].strip();
				if (current_field == "Package") {
					current_pkg = val;
				} else if (current_field == "Depends" || current_field == "Pre-Depends") {
					deps_text = val;
				}
			}
			if (current_pkg != "" && deps_text != "") {
				this.stage_depends(staging_q, current_pkg, deps_text);
			}
			return true;
		}

		private void stage_depends(
			SQ.Query<PkgDependsStaging> staging_q,
			string pkg_name,
			string dep_str)
		{
			foreach (var clause in dep_str.split(",")) {
				var trimmed = clause.strip();
				if (trimmed == "" || trimmed.index_of("|") >= 0) {
					continue;
				}
				var paren = trimmed.index_of("(");
				string dep_name;
				string constraint = "";
				if (paren < 0) {
					dep_name = trimmed;
				} else {
					dep_name = trimmed.substring(0, paren).strip();
					constraint = trimmed.substring(paren).strip();
				}
				if (dep_name == "") {
					continue;
				}
				staging_q.insert(new PkgDependsStaging() {
					pkg_name = pkg_name,
					depends_pkg_name = dep_name,
					constraint_text = constraint,
				});
			}
		}

		private bool merge()
		{
			var apt_url_id = this.url.id;
			var depends_q = Argus.Shared.SQT.AptPkgDepends.query(this.db);

			this.db.exec("""
				INSERT OR IGNORE INTO apt_pkg (
					name
				)
				SELECT
					pkg_name
				FROM
					apt_pkg_depends_staging
				UNION
				SELECT
					depends_pkg_name
				FROM
					apt_pkg_depends_staging
				WHERE
					depends_pkg_name NOT IN (
						SELECT
							name
						FROM
							apt_pkg
					);
				""");

			var delete_sql = """
				DELETE
				FROM
					apt_pkg_depends
				WHERE
					apt_url_id = $apt_url_id
					AND (
						pkg_id,
						depends_pkg_id
					) NOT IN (
						SELECT
							apt_pkg.id,
							apt_pkg_depends.id
						FROM
							apt_pkg_depends_staging
						INNER JOIN apt_pkg
							ON apt_pkg.name = apt_pkg_depends_staging.pkg_name
						INNER JOIN apt_pkg AS apt_pkg_depends
							ON apt_pkg_depends.name = apt_pkg_depends_staging.depends_pkg_name
					);
				""";
			var delete_stmt = depends_q.selectPrepare(delete_sql);
			delete_stmt.bind_int64(
				delete_stmt.bind_parameter_index("$apt_url_id"), apt_url_id);
			this.db.db_mutex.lock();
			if (Sqlite.DONE != delete_stmt.step()) {
				this.db.db_mutex.unlock();
				this.mark_error(this.db.db.errmsg());
				this.db.exec(
					"ROLLBACK; DROP TABLE IF EXISTS apt_pkg_depends_staging;");
				return false;
			}
			this.db.db_mutex.unlock();

			var insert_sql = """
				INSERT OR IGNORE INTO apt_pkg_depends (
					apt_url_id,
					pkg_id,
					depends_pkg_id,
					constraint_text
				)
				SELECT
					$apt_url_id,
					apt_pkg.id,
					apt_pkg_depends.id,
					apt_pkg_depends_staging.constraint_text
				FROM
					apt_pkg_depends_staging
				INNER JOIN apt_pkg
					ON apt_pkg.name = apt_pkg_depends_staging.pkg_name
				INNER JOIN apt_pkg AS apt_pkg_depends
					ON apt_pkg_depends.name = apt_pkg_depends_staging.depends_pkg_name;
				""";
			var insert_stmt = depends_q.selectPrepare(insert_sql);
			insert_stmt.bind_int64(
				insert_stmt.bind_parameter_index("$apt_url_id"), apt_url_id);
			this.db.db_mutex.lock();
			if (Sqlite.DONE != insert_stmt.step()) {
				this.db.db_mutex.unlock();
				this.mark_error(this.db.db.errmsg());
				this.db.exec(
					"ROLLBACK; DROP TABLE IF EXISTS apt_pkg_depends_staging;");
				return false;
			}
			this.db.db_mutex.unlock();

			this.db.exec(
				"DROP TABLE apt_pkg_depends_staging; COMMIT;");
			return true;
		}

		private void mark_error(string message)
		{
			this.url.last_error = message;
			Argus.Shared.SQT.AptUrl.query(this.db).updateById(this.url);
		}

		private void mark_synced()
		{
			this.url.last_synced_dt = new GLib.DateTime.now_utc().to_unix();
			this.url.last_error = "";
			Argus.Shared.SQT.AptUrl.query(this.db).updateById(this.url);
		}
	}
}