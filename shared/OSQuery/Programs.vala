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
	 * One Windows ''programs'' row.
	 */
	public class Programs : Package
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_packages<Programs>(db, agent_id, rows);
		}

		public override string pkg_name()
		{
			return this.source + "\n" + this.name + "\n" + this.identifying_number;
		}

		/**
		 * Osquery statement for one Windows software snapshot.
		 *
		 * Add/Remove programs, Store packages (''package_family_name''
		 * on ''programs''), Chocolatey, filtered services, and
		 * startup items. Portable file scans are out.
		 * ''system_component'' is ''1'' when that uninstall key
		 * sets SystemComponent.
		 *
		 * @return osquery SQL
		 */
		public static string snapshot_sql()
		{
			return """
				SELECT
					CASE
						WHEN package_family_name != ''
						THEN 'appx'
						ELSE 'programs'
					END AS source,
					name,
					version,
					publisher,
					'' AS architecture,
					CASE
						WHEN identifying_number LIKE '%HKEY_USERS%'
							OR install_location LIKE 'C:\\Users\\%'
						THEN 'user'
						ELSE 'system'
					END AS scope,
					'' AS user_account,
					install_date,
					install_location,
					identifying_number,
					install_source,
					language,
					uninstall_string,
					CASE
						WHEN (SELECT data FROM registry WHERE path = printf('%s%s%s', 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\', identifying_number, '\\SystemComponent')) = '1'
							OR (SELECT data FROM registry WHERE path = printf('%s%s%s', 'HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\', identifying_number, '\\SystemComponent')) = '1'
						THEN '1'
						ELSE '0'
					END AS system_component,
					'source_reg=' || install_source
						|| ';uninstall=' || uninstall_string AS extra
				FROM programs
				WHERE name != ''

				UNION ALL

				SELECT
					'chocolatey' AS source,
					name,
					version,
					'' AS publisher,
					'' AS architecture,
					'system' AS scope,
					'' AS user_account,
					'' AS install_date,
					path AS install_location,
					name || '@' || version AS identifying_number,
					'' AS install_source,
					'' AS language,
					'' AS uninstall_string,
					'0' AS system_component,
					summary AS extra
				FROM chocolatey_packages

				UNION ALL

				SELECT
					'service' AS source,
					display_name AS name,
					'' AS version,
					'' AS publisher,
					'' AS architecture,
					'system' AS scope,
					user_account,
					'' AS install_date,
					path AS install_location,
					name AS identifying_number,
					'' AS install_source,
					'' AS language,
					'' AS uninstall_string,
					'0' AS system_component,
					'status=' || status
						|| ';start_type=' || start_type
						|| ';service_type=' || service_type AS extra
				FROM services
				WHERE path != ''
					AND path NOT LIKE '%\\Windows\\System32\\%'
					AND path NOT LIKE '%\\Windows\\SysWOW64\\%'

				UNION ALL

				SELECT
					'startup' AS source,
					name,
					'' AS version,
					'' AS publisher,
					'' AS architecture,
					CASE
						WHEN path LIKE 'C:\\Users\\%'
							OR source LIKE 'HKEY_USERS%'
						THEN 'user'
						ELSE 'system'
					END AS scope,
					username AS user_account,
					'' AS install_date,
					path AS install_location,
					args AS identifying_number,
					'' AS install_source,
					'' AS language,
					'' AS uninstall_string,
					'0' AS system_component,
					'startup_source=' || source
						|| ';status=' || status AS extra
				FROM startup_items
				""";
		}

		/**
		 * Silent uninstall command built from {@link uninstall_string}.
		 *
		 * Rewrites ''msiexec /I...'' to ''/X...'' and appends
		 * ''/qn /norestart'' when no quiet flag is present.
		 *
		 * @return silent command string, or empty when unset
		 */
		public string silent_command()
		{
			var cmd = this.uninstall_string.strip();
			if (cmd == "") {
				return "";
			}
			if (!GLib.Regex.match_simple("(^|\\s|\\\\)msiexec(\\.exe)?\\b", cmd,
				GLib.RegexCompileFlags.CASELESS)) {
				return cmd;
			}
			cmd = new GLib.Regex("(^|\\s)/i(?=(\\{|\\s|$))",
				GLib.RegexCompileFlags.CASELESS).replace(cmd, -1, 0, "\\1/X");
			if (GLib.Regex.match_simple("(^|\\s)/q", cmd, GLib.RegexCompileFlags.CASELESS)) {
				return cmd;
			}
			return cmd + " /qn /norestart";
		}

		public override string table_name() { return "programs"; }

		public override string rpc_name() { return "Programs"; }

		/**
		 * Create ''programs''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Programs.db = db;
			db.exec("""
				CREATE TABLE IF NOT EXISTS programs (
					id                  INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id            INTEGER NOT NULL,
					source              TEXT NOT NULL DEFAULT '',
					name                TEXT NOT NULL DEFAULT '',
					version             TEXT NOT NULL DEFAULT '',
					install_location    TEXT NOT NULL DEFAULT '',
					install_source      TEXT NOT NULL DEFAULT '',
					language            TEXT NOT NULL DEFAULT '',
					publisher           TEXT NOT NULL DEFAULT '',
					uninstall_string    TEXT NOT NULL DEFAULT '',
					install_date        TEXT NOT NULL DEFAULT '',
					identifying_number  TEXT NOT NULL DEFAULT '',
					system_component    TEXT NOT NULL DEFAULT '',
					architecture        TEXT NOT NULL DEFAULT '',
					scope               TEXT NOT NULL DEFAULT '',
					user_account        TEXT NOT NULL DEFAULT '',
					extra               TEXT NOT NULL DEFAULT '',
					file_sha256         TEXT NOT NULL DEFAULT '',
					signing_result      TEXT NOT NULL DEFAULT '',
					signer_cert_sha256  TEXT NOT NULL DEFAULT '',
					signer_subject_key_id TEXT NOT NULL DEFAULT '',
					signer_publisher    TEXT NOT NULL DEFAULT '',
					signer_issuer       TEXT NOT NULL DEFAULT '',
					signer_serial       TEXT NOT NULL DEFAULT ''
				);
				""");
			Argus.Shared.init_db_audit(db, "programs");
			db.exec("ALTER TABLE programs ADD COLUMN source TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN architecture TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN scope TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN user_account TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN extra TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN file_sha256 TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN signing_result TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN signer_cert_sha256 TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN signer_subject_key_id TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN signer_publisher TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN signer_issuer TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN signer_serial TEXT NOT NULL DEFAULT '';");
			db.exec("ALTER TABLE programs ADD COLUMN system_component TEXT NOT NULL DEFAULT '';");
			db.exec("""
				CREATE INDEX IF NOT EXISTS programs_deleted_name_agent
				ON programs (deleted_dt, name, agent_id);
				""");
			db.exec("""
				CREATE INDEX IF NOT EXISTS programs_agent
				ON programs (agent_id);
				""");
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Programs", typeof(Programs));
			OLLMrpc.Request.add_class(
				"Programs", typeof(Programs),
				"list", "ii",
				"machines", "ss"
			);
		}

		/**
		 * One row per program name, or one agent's stored rows.
		 *
		 * A controller calls this. Zero lists every agent, added
		 * up by name. An ''agent_id'' greater than zero is a
		 * different query: that agent's stored rows, with no
		 * added-up columns. A row whose ''agent_id'' is not in
		 * ''agent'' is absent. A caller that is not a controller
		 * is refused. ''since'' zero leaves out a row whose
		 * ''deleted_dt'' is set. A later ''since'' returns every
		 * row changed after that time, including a deleted row.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id agent id, or zero for every agent
		 * @param since unix time, or zero for the current list
		 */
		public void list(OLLMrpc.Request request, int agent_id, int since)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Programs>();
			var query = new SQ.Query<Programs>(Programs.db, "programs");
			var id_text = agent_id.to_string();
			var since_text = since.to_string();
			// The check is the signing certificate hash. The two parents are
			// recorded by that hash. Both chain to Microsoft Root
			// Certificate Authority 2010. That root is not the check.
			// VirtualBox reaches it through Third Party Component CA 2014,
			// and Edge through Microsoft Code Signing PCA 2024.
			// Microsoft Windows Production PCA 2011
			// e8e95f0733a55e8bad7be0a1413ee23c51fcea64b3c8fa6a786935fddcc71961
			// Windows Production PCA 2023
			// 4f771e28419476af6791f116f65e963812ee85f841a8184e85f592ba3d51a4bf
			// Microsoft Windows, Production PCA 2011.
			// https://www.joesandbox.com/analysis/1772502/1/html
			// 1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de
			// Microsoft Windows Publisher, same issuer
			// 12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50
			// Defender early-launch driver
			// 836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1
			// Microsoft Windows, Production PCA 2011.
			// https://www.virustotal.com/gui/file/8aff1d47aa7c26ebaea9ad9df102c090fe99c9847a8c832ca95e05e5feb1793f
			// e866d202865ed3d83c35dff4cde3a2d0fc1d2b17c084e8b26dd0ca28a8c75cfb
			// Microsoft Windows, Production PCA 2011.
			// https://www.virustotal.com/gui/file/BDB69D9590F69A4883D62153CCA935D4A02CE435CAD31CFE45C9D1B7A119DA3D
			// aec8b67481dfcd2b03398cf9c9439e80ef3e75d407fb0753f9e6c548bc3b5eff
			// Microsoft Windows, Production PCA 2011.
			// https://www.virustotal.com/gui/file/8efadea41916b544e3d93362c28437ab21aae978f1a3f5fa019ff4601f8a1af7
			// 2724aeb0c497bf5fd732958120d1ae3341cfd252ab1680de03d10503abc666c1
			// Microsoft Windows, Production PCA 2011. ntoskrnl.exe.
			// https://www.joesandbox.com/analysis/1325053/0/html
			// 1721693d3e23c7abf800ae7b86654ed86dceab48c530a57c00d24ef23ff7407e
			// Microsoft Windows, Production PCA 2011.
			// https://fixdlls.com/microsoft-windows-sac-events.dll
			// 2d7ffce2c256016291b67285456aa8da779d711bbf8e6b85c212a157ddfbe77e
			if (since > 0 && agent_id > 0) {
				query.select(@"
					WHERE
						agent_id = $(id_text)
					AND
						system_component != '1'
					AND NOT (
						source = 'service'
						AND signing_result = 'Valid'
						AND lower(signer_cert_sha256) IN (
							'1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de',
							'12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50',
							'836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1',
							'e866d202865ed3d83c35dff4cde3a2d0fc1d2b17c084e8b26dd0ca28a8c75cfb',
							'aec8b67481dfcd2b03398cf9c9439e80ef3e75d407fb0753f9e6c548bc3b5eff',
							'2724aeb0c497bf5fd732958120d1ae3341cfd252ab1680de03d10503abc666c1',
							'1721693d3e23c7abf800ae7b86654ed86dceab48c530a57c00d24ef23ff7407e',
							'2d7ffce2c256016291b67285456aa8da779d711bbf8e6b85c212a157ddfbe77e'
						)
					)
					AND NOT (
						source = 'appx'
						AND signing_result = 'NoExecutable'
					)
					AND
						(
							added_dt > $(since_text)
						OR
							updated_dt > $(since_text)
						OR
							deleted_dt > $(since_text)
						)
					", rows);
			}
			if (since > 0 && agent_id <= 0) {
				query.select(@"
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						system_component != '1'
					AND NOT (
						source = 'service'
						AND signing_result = 'Valid'
						AND lower(signer_cert_sha256) IN (
							'1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de',
							'12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50',
							'836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1',
							'e866d202865ed3d83c35dff4cde3a2d0fc1d2b17c084e8b26dd0ca28a8c75cfb',
							'aec8b67481dfcd2b03398cf9c9439e80ef3e75d407fb0753f9e6c548bc3b5eff',
							'2724aeb0c497bf5fd732958120d1ae3341cfd252ab1680de03d10503abc666c1',
							'1721693d3e23c7abf800ae7b86654ed86dceab48c530a57c00d24ef23ff7407e',
							'2d7ffce2c256016291b67285456aa8da779d711bbf8e6b85c212a157ddfbe77e'
						)
					)
					AND NOT (
						source = 'appx'
						AND signing_result = 'NoExecutable'
					)
					AND
						(
							added_dt > $(since_text)
						OR
							updated_dt > $(since_text)
						OR
							deleted_dt > $(since_text)
						)
					", rows);
			}
			if (since <= 0 && agent_id > 0) {
				query.select(@"
					WHERE
						agent_id = $(id_text)
					AND
						deleted_dt = 0
					AND
						system_component != '1'
					AND NOT (
						source = 'service'
						AND signing_result = 'Valid'
						AND lower(signer_cert_sha256) IN (
							'1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de',
							'12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50',
							'836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1',
							'e866d202865ed3d83c35dff4cde3a2d0fc1d2b17c084e8b26dd0ca28a8c75cfb',
							'aec8b67481dfcd2b03398cf9c9439e80ef3e75d407fb0753f9e6c548bc3b5eff',
							'2724aeb0c497bf5fd732958120d1ae3341cfd252ab1680de03d10503abc666c1',
							'1721693d3e23c7abf800ae7b86654ed86dceab48c530a57c00d24ef23ff7407e',
							'2d7ffce2c256016291b67285456aa8da779d711bbf8e6b85c212a157ddfbe77e'
						)
					)
					AND NOT (
						source = 'appx'
						AND signing_result = 'NoExecutable'
					)
					", rows);
				foreach (var row in rows) {
					row.uninstall_count = row.uninstall_string != "" ? 1 : 0;
				}
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery(@"
					SELECT
						source,
						name,
						GROUP_CONCAT(DISTINCT NULLIF(publisher, '')) AS publisher,
						GROUP_CONCAT(DISTINCT NULLIF(language, '')) AS language,
						GROUP_CONCAT(DISTINCT NULLIF(identifying_number, '')) AS identifying_number,
						GROUP_CONCAT(DISTINCT NULLIF(install_date, '')) AS install_date,
						GROUP_CONCAT(DISTINCT NULLIF(install_location, '')) AS install_location,
						GROUP_CONCAT(DISTINCT NULLIF(install_source, '')) AS install_source,
						GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string,
						GROUP_CONCAT(DISTINCT NULLIF(architecture, '')) AS architecture,
						GROUP_CONCAT(DISTINCT NULLIF(scope, '')) AS scope,
						GROUP_CONCAT(DISTINCT NULLIF(user_account, '')) AS user_account,
						GROUP_CONCAT(DISTINCT NULLIF(extra, '')) AS extra,
						MIN(version) AS min_version,
						MAX(version) AS max_version,
						COUNT(DISTINCT agent_id) AS installed,
						COUNT(DISTINCT CASE
							WHEN uninstall_string != '' THEN agent_id
						END) AS uninstall_count
					FROM
						programs
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						deleted_dt = 0
					AND
						system_component != '1'
					AND NOT (
						source = 'service'
						AND signing_result = 'Valid'
						AND lower(signer_cert_sha256) IN (
							'1308aad34660d785a76b7360c31308d8835cf5721c364a6f5aedcba85eb5b3de',
							'12ff747d652cc79a2079377aa26a15c2e22951cc2108a9e9074e971ec5d2ad50',
							'836c0b480b54147739746cf07a5ec97aa98644e5883e8c1c71ee463d369361f1',
							'e866d202865ed3d83c35dff4cde3a2d0fc1d2b17c084e8b26dd0ca28a8c75cfb',
							'aec8b67481dfcd2b03398cf9c9439e80ef3e75d407fb0753f9e6c548bc3b5eff',
							'2724aeb0c497bf5fd732958120d1ae3341cfd252ab1680de03d10503abc666c1',
							'1721693d3e23c7abf800ae7b86654ed86dceab48c530a57c00d24ef23ff7407e',
							'2d7ffce2c256016291b67285456aa8da779d711bbf8e6b85c212a157ddfbe77e'
						)
					)
					AND NOT (
						source = 'appx'
						AND signing_result = 'NoExecutable'
					)
					GROUP BY
						source,
						name
					ORDER BY
						source,
						name
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * List per-machine stored rows for one program ''name''.
		 *
		 * A controller calls this. Rows whose ''agent_id'' is not in
		 * ''agent'' or whose ''deleted_dt'' is set are omitted.
		 *
		 * @param request inbound RPC from a controller
		 * @param name exact ''programs.name''
		 * @param source ''programs.source'', or empty for every source
		 */
		public void machines(OLLMrpc.Request request, string name, string source)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Programs>();
			var query = new SQ.Query<Programs>(Programs.db, "programs");
			var binds = new Gee.HashMap<string, string>();
			binds.set("name", name);
			var where = """
				WHERE
					name = $name
				AND
					deleted_dt = 0
				AND
					agent_id IN (SELECT id FROM agent)
				""";
			if (source != "") {
				binds.set("source", source);
				where += " AND source = $source";
			}
			where += " ORDER BY agent_id";
			query.selectWhere(where, null, binds, rows);
			foreach (var row in rows) {
				row.uninstall_count = row.uninstall_string != "" ? 1 : 0;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Osquery origin: ''programs'', ''appx'', ''chocolatey'',
		 * ''service'', or ''startup''.
		 */
		public string source { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public string version { get; set; default = ""; }
		public string install_location { get; set; default = ""; }
		public string install_source { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public string publisher { get; set; default = ""; }
		public string uninstall_string { get; set; default = ""; }
		public string install_date { get; set; default = ""; }
		public string identifying_number { get; set; default = ""; }
		/**
		 * ''1'' when the uninstall key sets SystemComponent.
		 * ''0'' when it does not. Empty on a row synced
		 * before this column existed.
		 */
		public string system_component { get; set; default = ""; }
		public string architecture { get; set; default = ""; }
		public string scope { get; set; default = ""; }
		public string user_account { get; set; default = ""; }
		/**
		 * Source-specific fields not stored in their own column.
		 */
		public string extra { get; set; default = ""; }
		/** PE file SHA-256 when a path was resolved (Windows enrichment). */
		public string file_sha256 { get; set; default = ""; }
		/** Authenticode status: Valid, NotSigned, missing, … */
		public string signing_result { get; set; default = ""; }
		/** Signing certificate SHA-256 thumbprint (ignore-set key). */
		public string signer_cert_sha256 { get; set; default = ""; }
		public string signer_subject_key_id { get; set; default = ""; }
		/** Certificate subject CN (human signer label). */
		public string signer_publisher { get; set; default = ""; }
		public string signer_issuer { get; set; default = ""; }
		public string signer_serial { get; set; default = ""; }
		/**
		 * Lowest version for this name. Filled by ''list''.
		 * Not stored.
		 */
		public string min_version { get; set; default = ""; }
		/**
		 * Highest version for this name. Filled by ''list''.
		 * Not stored.
		 */
		public string max_version { get; set; default = ""; }
		/**
		 * How many machines have this name. Filled by ''list''.
		 * Not stored.
		 */
		public int installed { get; set; default = 0; }
		/**
		 * How many of those machines have an uninstall string.
		 * Filled by ''list''. Not stored.
		 */
		public int uninstall_count { get; set; default = 0; }
	}
}
