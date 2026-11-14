# Refactor OS updates to separate table `os_releases` via `osinfo-query`

**Status:** ✅ closed 2026-11-13. `os_releases` (`shared/OsReleases.vala`), `OsUpdate` (`osinfo-query`), and `os_version` cleanup are in the tree.

**Pointer:** `docs/bug-fix-process.md`. Replaces rejected [5.11-REJECTED-os-update.md](../../plans/done/5.11-REJECTED-os-update.md) and [5.11.1-REJECTED-os-update-server.md](../../plans/done/5.11.1-REJECTED-os-update-server.md). Reporting in `SystemInfo.list` is split out to [2026-11-13-FIXED-os-update-reporting.md](2026-11-13-FIXED-os-update-reporting.md).

---

## Problem

- 🔷 The previous design for OS release currency ([5.11](../../plans/done/5.11-REJECTED-os-update.md) Phase 1 in the tree, and [5.11.1](../../plans/done/5.11.1-REJECTED-os-update-server.md), proposed and not built) stored `os_updated` and `os_status` directly on `os_version`, forbade any separate release table, and fetched `distro-info-data` CSVs over HTTP (Debian/Ubuntu/eLxr only).
- 🔷 That approach mutates per-agent osquery inventory rows (`os_version`) with server-fetched release metadata, duplicates per-platform check timestamps across every machine row, requires special-case omissions in `Row.bin_write_prop`, `AgentInfo.compare`, and `OsVersion.sync`, and misses Red Hat, Fedora, CentOS, Rocky, AlmaLinux, SUSE, and Windows.
- 🔷 Instead, the server should query the system-installed `osinfo-query` (`libosinfo` / `osinfo-db`, updated via normal OS package upgrades rather than online HTTP fetches) and store release data in a dedicated `os_releases` table (`Argus.Shared.OsReleases`), mapping `os_version.platform` to `osinfo-query` `distro` during data collection and syncing existing rows in place without wiping the table.
- 🔷 `os_version` keeps only osquery columns and `reboot_required` (a host-local flag read on Windows), dropping `os_updated` and `os_status`.
- ℹ️ Computing and returning `os_updated` and `os_status` in `SystemInfo.list` (`docs/rpc-commands.md`) is tracked separately in [2026-11-13-FIXED-os-update-reporting.md](2026-11-13-FIXED-os-update-reporting.md).

## Evidence

- ✔️ `shared/OSQuery/OsVersion.vala` currently declares `os_updated` and `os_status` in `CREATE TABLE`, `ALTER TABLE`, as GObject properties, and preserves `os-updated` / `os-status` conditionally in `OsVersion.sync`.
- ✔️ `shared/OSQuery/Row.vala` skips `os-updated` and `os-status` in `bin_write_prop()`, and `shared/OSQuery/AgentInfo.vala` skips `os-updated` and `os-status` in `compare()`.
- ✔️ `libocsqlite`'s `SQ.Query<T>` maps only columns present on the GObject class for `PRAGMA table_info`, so removing `os_updated` and `os_status` from `OsVersion` leaves any existing database column harmlessly ignored.
- ✔️ Verified `osinfo-query` (`/usr/bin/osinfo-query`, Debian `libosinfo-bin` + `osinfo-db`) on the host:
  - `osinfo-query --fields=short-id,name,version,family,distro,release-date,eol-date,codename os distro=<distro>` outputs pipe-delimited rows in fixed order (`Short ID | Name | Version | Family | Distro | Release date | End of life | Code name`) and exits `1` when a distro has no entries.
  - `short-id` is unique across the entire database.
  - `os_version.platform` vs `osinfo-query` `distro`: `windows` -> `win`, `opensuse-leap` / `opensuse-tumbleweed` -> `opensuse`, `darwin` -> `osx`, `alpine` -> `alpinelinux`, `arch` -> `archlinux`, `oracle` -> `ol`.
  - `osinfo-db` contains placeholder `*-unknown` entries (`rocky8-unknown`, `rhel9-unknown`, etc.) with bogus or empty dates that should be skipped when syncing `os_releases`.
- ℹ️ [5.11-REJECTED-os-update.md](../../plans/done/5.11-REJECTED-os-update.md) and [5.11.1-REJECTED-os-update-server.md](../../plans/done/5.11.1-REJECTED-os-update-server.md) were archived as rejected.

## Root cause

- ✔️ Storing server-fetched OS release state (`os_updated` and `os_status`) on `os_version` coupled global platform release metadata to per-agent osquery inventory rows and relied on distro-specific CSV URLs, instead of reading system-packaged `osinfo-query` data into a separate `os_releases` table with `platform` mapped at collection time.

## Proposed fix

- 🔷 Move OS release catalog data (`short_id`, `distro`, `platform`, `family`, `name`, `version`, `codename`, `released`, `eol`, `is_lts`, `updated`) into a new `os_releases` table (`shared/OsReleases.vala`), initialized in `server/Application.vala`.
- 🔷 Remove `os_updated` and `os_status` from `shared/OSQuery/OsVersion.vala`, `shared/OSQuery/Row.vala`, and `shared/OSQuery/AgentInfo.vala` (keep `reboot_required` and single-row `OsVersion.sync`).
- 🔷 Add `libosinfo-bin, osinfo-db` to `argusrm-server` `Depends:` in `debian/control` and `libosinfo, osinfo-db` to `Requires:` in `packaging/rpm/argusrm.spec`.
- 🔷 Add `server/OsUpdate.vala` (`distro_for`, `check`, `check_distro`): check `find_program_in_path("osinfo-query")` at runtime, map active `os_version.platform` values via `distro_for(platform)`, query due distros (missing or `updated <= now - 24h`, checked at startup + hourly + on `OsVersion` sync in `server/OSQuery.vala`), store normalized `platform` on each `OsReleases` row, update existing rows in place by `short_id` via `updateOld`, insert new releases, and delete `*-unknown` or removed rows.
- 🔷 Update `docs/plans/4.0-data-types.md` to remove `os_updated` / `os_status` from `os_version` and document `os_releases`.
- 🚫 Do not write `os_updated` or `os_status` onto `os_version`.
- 🚫 Do not fetch `distro-info-data` CSVs over HTTP.
- 🚫 Do not query `osinfo-query` for distros not present in active `os_version` rows (`deleted_dt = 0` and `agent_id` in `agent`).
- 🚫 Do not wipe `os_releases` with `deleteWhere`; update existing rows by `short_id` with `updateOld`.
- 🚫 Do not put `SystemInfo.list` or `docs/rpc-commands.md` changes in this bug; those belong to [2026-11-13-FIXED-os-update-reporting.md](2026-11-13-FIXED-os-update-reporting.md).

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### 1. `shared/OsReleases.vala` — new `os_releases` table

**Why:** store `osinfo-query` release rows and check timestamps in their own table instead of mutating `os_version`.

**Where:** new file `shared/OsReleases.vala`, plus entries in `shared/meson.build`, `docs/meson.build`, and `server/Application.vala`.

**Depends on:** none.

#### Add — new file `shared/OsReleases.vala`

```vala
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

namespace Argus.Shared
{
	/**
	 * One ''os_releases'' row.
	 *
	 * Stores one operating-system release loaded by the server from
	 * ''osinfo-query'' for platforms active in ''os_version''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rows = new Gee.ArrayList<Argus.Shared.OsReleases>();
	 * Argus.Shared.OsReleases.query(db).select("ORDER BY id ASC", rows);
	 * }}}
	 */
	public class OsReleases : GLib.Object, SQ.Interface
	{
		public int64 id { get; set; default = 0; }
		/**
		 * Unique ''osinfo-query'' short identifier (e.g. ''debian12'').
		 */
		public string short_id { get; set; default = ""; }
		/**
		 * ''osinfo-query'' distribution key (e.g. ''debian'', ''win'').
		 */
		public string distro { get; set; default = ""; }
		/**
		 * Normalized ''os_version.platform'' (e.g. ''debian'', ''windows'').
		 */
		public string platform { get; set; default = ""; }
		/**
		 * Kernel/OS family from ''osinfo-query'' (e.g. ''linux'', ''winnt'').
		 */
		public string family { get; set; default = ""; }
		/**
		 * Full OS release name (e.g. ''Ubuntu 24.04 LTS'').
		 */
		public string name { get; set; default = ""; }
		/**
		 * Release version string (e.g. ''12'', ''24.04'', ''9.5'').
		 */
		public string version { get; set; default = ""; }
		/**
		 * Release codename from ''osinfo-query'' (e.g. ''bookworm'').
		 */
		public string codename { get; set; default = ""; }
		/**
		 * Release date in ''YYYY-MM-DD'' format, or empty when unreleased.
		 */
		public string released { get; set; default = ""; }
		/**
		 * End-of-life date in ''YYYY-MM-DD'' format, or empty when unset.
		 */
		public string eol { get; set; default = ""; }
		/**
		 * ''1'' when marked LTS in {@link name}, ''0'' otherwise.
		 */
		public int is_lts { get; set; default = 0; }
		/**
		 * Unix time this distribution's rows were last synced.
		 */
		public int updated { get; set; default = 0; }

		/**
		 * Rows in ''os_releases''.
		 *
		 * @param db Argus database
		 * @return the query
		 */
		public static SQ.Query<OsReleases> query(SQ.Database db)
		{
			return new SQ.Query<OsReleases>(db, "os_releases");
		}

		/**
		 * Create ''os_releases''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			var ddl = """
				CREATE TABLE IF NOT EXISTS os_releases (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					short_id TEXT NOT NULL DEFAULT '',
					distro   TEXT NOT NULL DEFAULT '',
					platform TEXT NOT NULL DEFAULT '',
					family   TEXT NOT NULL DEFAULT '',
					name     TEXT NOT NULL DEFAULT '',
					version  TEXT NOT NULL DEFAULT '',
					codename TEXT NOT NULL DEFAULT '',
					released TEXT NOT NULL DEFAULT '',
					eol      TEXT NOT NULL DEFAULT '',
					is_lts   INTEGER NOT NULL DEFAULT 0,
					updated  INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("os_releases create failed: %s", db.db.errmsg());
			}
			var idx = """
				CREATE UNIQUE INDEX IF NOT EXISTS os_releases_short_id
				ON os_releases (short_id);
				""";
			if (Sqlite.OK != db.db.exec(idx, null, out errmsg)) {
				GLib.warning("os_releases index failed: %s", db.db.errmsg());
			}
			var platform_idx = """
				CREATE INDEX IF NOT EXISTS os_releases_platform
				ON os_releases (platform);
				""";
			if (Sqlite.OK != db.db.exec(platform_idx, null, out errmsg)) {
				GLib.warning("os_releases platform index failed: %s", db.db.errmsg());
			}
		}
	}
}
```

#### Add — `shared/meson.build`, in `shared_sources` after `'Agent.vala',`

```meson
	'OsReleases.vala',
```

#### Add — `docs/meson.build`, in `valadoc_sources` after `'../shared/Agent.vala',`

```meson
  '../shared/OsReleases.vala',
```

#### Add — `server/Application.vala`, in `command_line` after `Argus.Shared.Agent.init_db(this.db);`

```vala
			Argus.Shared.OsReleases.init_db(this.db);
```

### 2. `shared/OSQuery/OsVersion.vala`, `shared/OSQuery/Row.vala`, and `shared/OSQuery/AgentInfo.vala` — remove `os_updated` and `os_status`

**Why:** `os_version` is an agent osquery table and no longer stores server-checked `os_updated` or `os_status` columns; `reboot_required` and single-row `OsVersion.sync` stay.

**Where:** `sync()`, `init_db()`, and properties in `shared/OSQuery/OsVersion.vala`, `bin_write_prop()` in `shared/OSQuery/Row.vala`, and `compare()` in `shared/OSQuery/AgentInfo.vala`.

**Depends on:** ### 1.

#### `shared/OSQuery/OsVersion.vala` — Remove

```vala
		/**
		 * Store one agent's ''os_version'' row.
		 *
		 * Each agent has one operating-system row. A snapshot
		 * that does not carry a single {@link OsVersion} is
		 * rejected. Stored package check fields stay, and
		 * stored OS check fields stay while ''platform'',
		 * ''version'', and ''codename'' match.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows single-row ''os_version'' snapshot
		 * @return true when ''rows'' has one ''OsVersion'' row
		 */
```

#### `shared/OSQuery/OsVersion.vala` — Replace with

```vala
		/**
		 * Store one agent's ''os_version'' row.
		 *
		 * Each agent has one operating-system row. A snapshot
		 * that does not carry a single {@link OsVersion} is
		 * rejected. Stored package check fields stay.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows single-row ''os_version'' snapshot
		 * @return true when ''rows'' has one ''OsVersion'' row
		 */
```

#### `shared/OSQuery/OsVersion.vala` — Remove

```vala
			var updated = new OsVersion();
			updated.copy_from(old, {});
			string[] keep = {
				"id", "added-dt", "updated-dt", "deleted-dt",
				"pkgs-updated", "pkgs-status"
			};
			if (old.platform == newer.platform &&
				old.version == newer.version &&
				old.codename == newer.codename) {
				keep += "os-updated";
				keep += "os-status";
			}
			updated.copy_from(newer, keep);
```

#### `shared/OSQuery/OsVersion.vala` — Replace with

```vala
			var updated = new OsVersion();
			updated.copy_from(old, {});
			string[] keep = {
				"id", "added-dt", "updated-dt", "deleted-dt",
				"pkgs-updated", "pkgs-status"
			};
			updated.copy_from(newer, keep);
```

#### `shared/OSQuery/OsVersion.vala` — Remove

```vala
					codename      TEXT NOT NULL DEFAULT '',
					arch              TEXT NOT NULL DEFAULT '',
					os_updated      INTEGER NOT NULL DEFAULT 0,
					os_status       INTEGER NOT NULL DEFAULT 0,
					pkgs_updated    INTEGER NOT NULL DEFAULT 0,
					pkgs_status     INTEGER NOT NULL DEFAULT 0,
					reboot_required INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("os_version create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "os_version");
			db.db.exec("ALTER TABLE os_version ADD COLUMN os_updated INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN os_status INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN pkgs_updated INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN pkgs_status INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN reboot_required INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
```

#### `shared/OSQuery/OsVersion.vala` — Replace with

```vala
					codename        TEXT NOT NULL DEFAULT '',
					arch            TEXT NOT NULL DEFAULT '',
					pkgs_updated    INTEGER NOT NULL DEFAULT 0,
					pkgs_status     INTEGER NOT NULL DEFAULT 0,
					reboot_required INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("os_version create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "os_version");
			db.db.exec("ALTER TABLE os_version ADD COLUMN pkgs_updated INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN pkgs_status INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_version ADD COLUMN reboot_required INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
```

#### `shared/OSQuery/OsVersion.vala` — Remove

```vala
		/**
		 * Unix time the server last checked whether this OS release
		 * is current.
		 *
		 * ''0'' means that check has not happened.
		 */
		public int os_updated { get; set; default = 0; }
		/**
		 * Operating-system release is up to date.
		 *
		 * ''1'' when current. ''0'' when not. ''-1'' when the
		 * release file did not list this release.
		 */
		public int os_status { get; set; default = 0; }
```

#### `shared/OSQuery/Row.vala` — Remove

```vala
			switch (prop.name) {
				// Database identity assigned by the server.
				case "id":
				case "agent-id":
				// Server-checked OS fields on OsVersion.
				case "os-updated":
				case "os-status":
				// Server-assigned timestamp on PackageUpdates.
				case "since":
					return;
```

#### `shared/OSQuery/Row.vala` — Replace with

```vala
			switch (prop.name) {
				// Database identity assigned by the server.
				case "id":
				case "agent-id":
				// Server-assigned timestamp on PackageUpdates.
				case "since":
					return;
```

#### `shared/OSQuery/AgentInfo.vala` — Remove

```vala
					case "added-dt":
					case "updated-dt":
					case "deleted-dt":
					case "os-updated":
					case "os-status":
					case "pkgs-updated":
					case "pkgs-status":
						continue;
```

#### `shared/OSQuery/AgentInfo.vala` — Replace with

```vala
					case "added-dt":
					case "updated-dt":
					case "deleted-dt":
					case "pkgs-updated":
					case "pkgs-status":
						continue;
```

### 3. `server/OsUpdate.vala` and packaging — sync `os_releases` from `osinfo-query`

**Why:** query the locally installed `osinfo-query` (`libosinfo-bin` + `osinfo-db` / `libosinfo` + `osinfo-db`) for active `os_version` platforms, map `platform` to `distro` via `distro_for`, store normalized `platform` on `os_releases`, and update rows in place (`check_distro`) without wiping the table.

**Where:** new file `server/OsUpdate.vala`, plus wiring in `server/Application.vala`, `server/OSQuery.vala`, `server/meson.build`, `docs/meson.build`, `debian/control`, and `packaging/rpm/argusrm.spec`.

**Depends on:** ### 1.

#### Add — new file `server/OsUpdate.vala`

```vala
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
				if (short_id == "" ||
					short_id.has_suffix("-unknown") ||
					rel_ver == "unknown" ||
					seen.has_key(short_id)) {
					continue;
				}
				seen.set(short_id, true);
				var rel_name = fields[1].strip();
				var rel_distro = fields[4].strip();
				var rel_platform = platform;
				if (distro == "opensuse") {
					rel_platform = short_id == "opensusetumbleweed" ?
						"opensuse-tumbleweed" : "opensuse-leap";
				}
				var newer = new Argus.Shared.OsReleases() {
					short_id = short_id,
					distro = rel_distro != "" ? rel_distro : distro,
					platform = rel_platform,
					family = fields[3].strip(),
					name = rel_name,
					version = rel_ver,
					codename = fields[7].strip(),
					released = fields[5].strip(),
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
```

#### `server/Application.vala` — Add after `scheduler` property

```vala
		/**
		 * OS release catalog syncer.
		 */
		public OsUpdate os_update { get; private set; }
```

#### `server/Application.vala` — Remove

```vala
			this.scheduler = new SQT.Scheduler(this);
			this.listen = new OLLMrpc.Transport.SocketListen(
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock")) {
				live_handles = true
			};
			this.publish.failed.connect(() => {
				GLib.warning("Could not publish the pairing service");
			});
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				Application.debug_log(dom, lvl, msg);
			});
			this.shutdown.connect(() => {
				this.publish.stop();
				this.scheduler.stop();
```

#### `server/Application.vala` — Replace with

```vala
			this.scheduler = new SQT.Scheduler(this);
			this.os_update = new OsUpdate(this);
			this.listen = new OLLMrpc.Transport.SocketListen(
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock")) {
				live_handles = true
			};
			this.publish.failed.connect(() => {
				GLib.warning("Could not publish the pairing service");
			});
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				Application.debug_log(dom, lvl, msg);
			});
			this.shutdown.connect(() => {
				this.publish.stop();
				this.scheduler.stop();
				this.os_update.stop();
```

#### `server/Application.vala` — Remove

```vala
			this.scheduler.start();
			GLib.debug("staying up");
```

#### `server/Application.vala` — Replace with

```vala
			this.scheduler.start();
			this.os_update.start();
			GLib.debug("staying up");
```

#### `server/OSQuery.vala` — Remove

```vala
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() { 
```

#### `server/OSQuery.vala` — Replace with

```vala
			this.app.db.backupDB();
			if (name == "OsVersion") {
				this.app.os_update.check.begin();
			}
			request.reply(new OLLMrpc.Response() { 
```

#### Add — `server/meson.build`, after `'OSQuery.vala',`

```meson
	'OsUpdate.vala',
```

#### Add — `docs/meson.build`, after `'../server/OSQuery.vala',`

```meson
  '../server/OsUpdate.vala',
```

#### `debian/control` — Remove

```control
Package: argusrm-server
Architecture: any
Depends: libocrpc1, libocsqlite1, ${shlibs:Depends}, ${misc:Depends}
```

#### `debian/control` — Replace with

```control
Package: argusrm-server
Architecture: any
Depends: libocrpc1, libocsqlite1, libosinfo-bin, osinfo-db, ${shlibs:Depends}, ${misc:Depends}
```

#### `packaging/rpm/argusrm.spec` — Remove

```spec
Requires: libocrpc
Requires: libocsqlite
Recommends: avahi
```

#### `packaging/rpm/argusrm.spec` — Replace with

```spec
Requires: libocrpc
Requires: libocsqlite
Requires: libosinfo
Requires: osinfo-db
Recommends: avahi
```

### 4. `docs/plans/4.0-data-types.md` — schema docs

**Why:** document `os_releases` in `4.0-data-types.md` and remove `os_updated` and `os_status` from `os_version` in `4.0-data-types.md`.

**Where:** Operating system and new OS releases section in `docs/plans/4.0-data-types.md`.

**Depends on:** ### 1 and ### 2.

#### `docs/plans/4.0-data-types.md` — Remove

~~~~markdown
## Operating system

`os_version` is the operating system on the agent. Assets shows the name and version on the machine list.

- 💩 `os_updated`, `os_status`, and `reboot_required` are not osquery columns. [5.11](done/5.11-REJECTED-os-update.md) fills them. `os_status` is whether the OS version is current. The server writes it once a week. `reboot_required` is a Windows restart waiting.
- 🔷 `pkgs_updated` and `pkgs_status` are not osquery columns. [5.10](../plans/done/5.10-DONE-data-enrichment.md) fills them. `pkgs_updated` is the last time that host checked its installed packages. `pkgs_status` is whether those packages have an update waiting.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
version               TEXT
major                 INTEGER
minor                 INTEGER
patch                 INTEGER
build                 TEXT
platform              TEXT
platform_like         TEXT
codename              TEXT
arch                  TEXT
os_updated            INTEGER
os_status             INTEGER
pkgs_updated          INTEGER
pkgs_status           INTEGER
reboot_required       INTEGER
added_dt              INTEGER
updated_dt            INTEGER
deleted_dt            INTEGER
```
~~~~

#### `docs/plans/4.0-data-types.md` — Replace with

~~~~markdown
## Operating system

`os_version` is the operating system on the agent. Assets shows the name and version on the machine list.

- 🔷 `reboot_required` is not an osquery column. [5.11](done/5.11-REJECTED-os-update.md) added the column for a Windows restart waiting.
- 🔷 `pkgs_updated` and `pkgs_status` are not osquery columns. [5.10](../plans/done/5.10-DONE-data-enrichment.md) fills them. `pkgs_updated` is the last time that host checked its installed packages. `pkgs_status` is whether those packages have an update waiting.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
version               TEXT
major                 INTEGER
minor                 INTEGER
patch                 INTEGER
build                 TEXT
platform              TEXT
platform_like         TEXT
codename              TEXT
arch                  TEXT
pkgs_updated          INTEGER
pkgs_status           INTEGER
reboot_required       INTEGER
added_dt              INTEGER
updated_dt            INTEGER
deleted_dt            INTEGER
```

## OS releases

`os_releases` is the server-synced OS release table populated from `osinfo-query` (`osinfo-db`).

```
id                    INTEGER
short_id              TEXT
distro                TEXT
platform              TEXT
family                TEXT
name                  TEXT
version               TEXT
codename              TEXT
released              TEXT
eol                   TEXT
is_lts                INTEGER
updated               INTEGER
```
~~~~

## Attempts / changelog

- ℹ️ 2026-11-13: Rejected [5.11-REJECTED-os-update.md](../../plans/done/5.11-REJECTED-os-update.md) and [5.11.1-REJECTED-os-update-server.md](../../plans/done/5.11.1-REJECTED-os-update-server.md) (`os_updated` / `os_status` on `os_version` with no separate table) and drafted this bug proposal with `os_releases` (`shared/OsReleases.vala`), `server/OsUpdate.vala`, and `os_version` cleanup.
- 🔷 2026-11-13: Broke `OsUpdate.check` out into `check_distro(osinfo_bin, platform, distro)` using `osinfo-query` (`libosinfo-bin` + `osinfo-db` / `libosinfo` + `osinfo-db`), added `distro_for(platform)` helper on `OsUpdate` so `platform` mapping happens during data collection and is stored on `os_releases.platform`, updated rows in place via `updateOld` by `short_id`, and split `SystemInfo.list` / `docs/rpc-commands.md` reporting out to [2026-11-13-FIXED-os-update-reporting.md](2026-11-13-FIXED-os-update-reporting.md).
- ✔️ 2026-11-13: Applied `### 1`–`### 4` (`shared/OsReleases.vala`, `server/OsUpdate.vala`, `server/Application.vala`, `server/OSQuery.vala`, `shared/OSQuery/OsVersion.vala`, `shared/OSQuery/Row.vala`, `shared/OSQuery/AgentInfo.vala`, `shared/meson.build`, `server/meson.build`, `docs/meson.build`, `debian/control`, `packaging/rpm/argusrm.spec`, `docs/plans/4.0-data-types.md`). Fixed `selectWhere` `int_binds` parameter (`new Gee.HashMap<string, int>()` instead of `null`).
- ✔️ 2026-11-13: `ninja -C build`, `ninja -C build docs/valadoc`, and `meson test -C build` (6/6) passed. Verified `OsReleases.init_db`, `osinfo-query` parsing (`distro=ubuntu`, 43 rows), `selectWhere`, and `updateOld` against a temporary SQLite database.
- ✅ 2026-11-13: User closed as fixed.

## Next

- ✅ Closed. `os_releases`, `OsUpdate` (`osinfo-query`), and `os_version` cleanup are in the tree; OS update reporting in `SystemInfo.list` continues in [2026-11-13-FIXED-os-update-reporting.md](2026-11-13-FIXED-os-update-reporting.md).
