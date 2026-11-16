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

namespace Argus.Shared.OSQuery
{
	/**
	 * One osquery ''apt_sources'' row (configured APT repository).
	 */
	public class AptSources : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<AptSources>(
				db,
				agent_id,
				rows,
				"apt_sources",
				{ "base_uri", "release", "components", "source" });
		}

		public override string table_name() { return "apt_sources"; }

		public override string rpc_name() { return "AptSources"; }

		public string name { get; set; default = ""; }
		public string source { get; set; default = ""; }
		public string base_uri { get; set; default = ""; }
		public string release { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string maintainer { get; set; default = ""; }
		public string components { get; set; default = ""; }
		public string architectures { get; set; default = ""; }

		/**
		 * Create ''apt_sources'' and the ''apt_sources_catalog'' view.
		 *
		 * Call after {@link Argus.Shared.SQT.init_db} so ''apt_url'' exists
		 * for the view. The view is SQL-only (reconcile helper), not inventory.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			AptSources.db = db;
			db.exec("""
				CREATE TABLE IF NOT EXISTS apt_sources (
					id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id        INTEGER NOT NULL,
					name            TEXT NOT NULL DEFAULT '',
					source          TEXT NOT NULL DEFAULT '',
					base_uri        TEXT NOT NULL DEFAULT '',
					release         TEXT NOT NULL DEFAULT '',
					version         TEXT NOT NULL DEFAULT '',
					maintainer      TEXT NOT NULL DEFAULT '',
					components      TEXT NOT NULL DEFAULT '',
					architectures   TEXT NOT NULL DEFAULT ''
				);
				""");
			Argus.Shared.init_db_audit(db, "apt_sources");
			db.exec("""
				CREATE INDEX IF NOT EXISTS apt_sources_agent
				ON apt_sources (agent_id);
				""");
			db.exec("""
				CREATE VIEW IF NOT EXISTS apt_sources_catalog AS
				SELECT
					agent_id,
					id,
					base_uri,
					release,
					components,
					catalog_arch,
					base_uri
						|| '|' || release
						|| '|' || components
						|| '|' || catalog_arch AS url_key
				FROM (
					SELECT
						agent_id,
						id,
						base_uri,
						release,
						components,
						CASE
							WHEN (
								' ' || TRIM(COALESCE(architectures, '')) || ' '
							) LIKE '% amd64 %'
								THEN 'amd64'
							WHEN TRIM(COALESCE(architectures, '')) != ''
								THEN TRIM(SUBSTR(
									TRIM(architectures) || ' ',
									1,
									INSTR(TRIM(architectures) || ' ', ' ') - 1))
							ELSE 'amd64'
						END AS catalog_arch
					FROM
						apt_sources
					WHERE
						deleted_dt = 0
						AND TRIM(base_uri) != ''
						AND TRIM(release) != ''
						AND TRIM(components) != ''
				);
				""");
		}

		/**
		 * Insert missing fleet ''apt_url'' rows from ''apt_sources_catalog''.
		 *
		 * Called from {@link Argus.Server.Apt.CatalogImport.run_update}
		 * before ''Packages'' import, not from {@link sync}.
		 * Does not update rows that already exist (catalog import metadata
		 * stays on the row).
		 *
		 * @param db Argus database
		 */
		public static void reconcile_apt_url(SQ.Database db)
		{
			db.exec("""
				INSERT OR IGNORE INTO apt_url (
					url_key,
					base_uri,
					suite,
					components,
					arch
				)
				SELECT DISTINCT
					url_key,
					base_uri,
					release,
					components,
					catalog_arch
				FROM
					apt_sources_catalog;
				""");
		}

		/**
		 * Register this row for {@link OSQuery.sync}.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("AptSources", typeof(AptSources));
		}
	}
}