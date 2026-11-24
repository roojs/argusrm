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

namespace Argus.Agent.SQT
{
	/**
	 * Cached file identity for one PE path on the Windows agent.
	 *
	 * Table ''win_file_identity'' on {@link Argus.Agent.Application.client_db}.
	 * Invalidates when ''size_bytes'' or ''mtime_unix'' no longer match disk.
	 * Not synced to the server (programs noise reduction plan).
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Agent.SQT.WinFileIdentity.init_db(app.client_db);
	 * var row = new Argus.Agent.SQT.WinFileIdentity() {
	 *     path = "C:\\\\foo.exe"
	 * };
	 * Argus.Agent.SQT.WinFileIdentity.replace_row(app.client_db, row);
	 * }}}
	 */
	public class WinFileIdentity : GLib.Object, SQ.Interface
	{
		public override string autoincrement_column()
		{
			return "";
		}

		public string path { get; set; default = ""; }
		public int64 size_bytes { get; set; default = 0; }
		public int mtime_unix { get; set; default = 0; }
		public string file_sha256 { get; set; default = ""; }
		public string signing_result { get; set; default = ""; }
		public string signer_cert_sha256 { get; set; default = ""; }
		public string signer_subject_key_id { get; set; default = ""; }
		public string signer_publisher { get; set; default = ""; }
		public string signer_issuer { get; set; default = ""; }
		public string signer_serial { get; set; default = ""; }
		public string scan_source { get; set; default = ""; }
		public int scanned_dt { get; set; default = 0; }

		/**
		 * Rows in ''win_file_identity''.
		 *
		 * @param db agent client database
		 * @return the query
		 */
		public static SQ.Query<WinFileIdentity> query(SQ.Database db)
		{
			return new SQ.Query<WinFileIdentity>(db, "win_file_identity");
		}

		/**
		 * Create ''win_file_identity'' and indexes.
		 *
		 * @param db agent client database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS win_file_identity (
					path                  TEXT    NOT NULL PRIMARY KEY,
					size_bytes            INTEGER NOT NULL DEFAULT 0,
					mtime_unix            INTEGER NOT NULL DEFAULT 0,
					file_sha256           TEXT    NOT NULL DEFAULT '',
					signing_result        TEXT    NOT NULL DEFAULT '',
					signer_cert_sha256    TEXT    NOT NULL DEFAULT '',
					signer_subject_key_id TEXT    NOT NULL DEFAULT '',
					signer_publisher      TEXT    NOT NULL DEFAULT '',
					signer_issuer         TEXT    NOT NULL DEFAULT '',
					signer_serial         TEXT    NOT NULL DEFAULT '',
					scan_source           TEXT    NOT NULL DEFAULT '',
					scanned_dt            INTEGER NOT NULL DEFAULT 0
				);
				CREATE INDEX IF NOT EXISTS win_file_identity_sha256
					ON win_file_identity (file_sha256);
				CREATE INDEX IF NOT EXISTS win_file_identity_signer
					ON win_file_identity (signer_cert_sha256);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning(
					"win_file_identity create failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Insert or replace one row keyed by {@link path}.
		 *
		 * @param db agent client database
		 * @param row row to store
		 */
		public static void replace_row(SQ.Database db, WinFileIdentity row)
		{
			db.db_mutex.lock();
			Sqlite.Statement stmt;
			var sql = """
				REPLACE INTO win_file_identity (
					path,
					size_bytes,
					mtime_unix,
					file_sha256,
					signing_result,
					signer_cert_sha256,
					signer_subject_key_id,
					signer_publisher,
					signer_issuer,
					signer_serial,
					scan_source,
					scanned_dt
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
				""";
			if (db.db.prepare_v2(sql, -1, out stmt) != Sqlite.OK) {
				GLib.warning(
					"win_file_identity replace prepare: %s", db.db.errmsg());
				db.db_mutex.unlock();
				return;
			}
			stmt.bind_text(1, row.path);
			stmt.bind_int64(2, row.size_bytes);
			stmt.bind_int(3, row.mtime_unix);
			stmt.bind_text(4, row.file_sha256);
			stmt.bind_text(5, row.signing_result);
			stmt.bind_text(6, row.signer_cert_sha256);
			stmt.bind_text(7, row.signer_subject_key_id);
			stmt.bind_text(8, row.signer_publisher);
			stmt.bind_text(9, row.signer_issuer);
			stmt.bind_text(10, row.signer_serial);
			stmt.bind_text(11, row.scan_source);
			stmt.bind_int(12, row.scanned_dt);
			if (stmt.step() != Sqlite.DONE) {
				GLib.warning(
					"win_file_identity replace step: %s", db.db.errmsg());
			}
			stmt.reset();
			db.db_mutex.unlock();
		}
	}
}