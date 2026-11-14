# Refactor package updates to fake osquery table `package_updates`

**Status:** ✅ closed 2026-11-13. `PackageUpdates` (`package_updates` via `OSQuery.sync`), `DebPackages.list` / `RpmPackages.list` `update_since` lookup, and `PackageMonitor.send_pending` are in the tree.

**Pointer:** `docs/bug-fix-process.md`. Replaces rejected [5.10.1-REJECTED-package-updates.md](../../plans/done/5.10.1-REJECTED-package-updates.md).

---

## Problem

- 🔷 The previous design for listing packages that need updating added an `update_available` column directly onto `deb_packages` and `rpm_packages` (in tree from [5.10](../../plans/done/5.10-DONE-data-enrichment.md) Phase 1) and proposed two custom RPCs (`DebPackages.send_pending` and `RpmPackages.send_pending`) doing bulk SQL `UPDATE` statements with `IN` / `NOT IN` lists.
- 🔷 That approach mutates installed-package inventory rows for pending-update state, duplicates handlers across `DebPackages` and `RpmPackages`, and does not record when an update first became pending.
- 🔷 Instead, pending package updates should be stored in a dedicated `package_updates` table modeled as a fake osquery row class (`PackageUpdates`) with `id`, `agent_id`, `name`, and `since`.
- 🔷 The agent sends `PackageUpdates` rows through the existing `OSQuery.sync` RPC.
- 🔷 On the server, `PackageUpdates.sync` syncs by package `name`:
  - Existing package name stays untouched (do **not** update `since`).
  - New package name is inserted with `since` set to the current unix time.
  - Stored package name missing from the incoming set is deleted.
- 🔷 `DebPackages.list` and `RpmPackages.list` look up `package_updates` when listing packages for the user instead of reading `update_available` from `deb_packages` / `rpm_packages`.

## Evidence

- ✔️ `shared/OSQuery/DebPackages.vala` and `shared/OSQuery/RpmPackages.vala` currently declare `update_available` in `CREATE TABLE`, `ALTER TABLE`, and as a GObject property.
- ✔️ `shared/OSQuery/AgentInfo.vala` skips `update-available` in `compare()` so full `OSQuery.sync` package snapshots do not overwrite it.
- ✔️ `server/OSQuery.vala` already dispatches `OSQuery.sync` for any registered `Argus.Shared.OSQuery.Row` subclass via `OLLMrpc.Bin.alias_to_gtype`.
- ✔️ `libocsqlite`'s `SQ.Query<T>` (`insert`, `selectWhere`, `selectQuery`, `deleteId`) maps only columns present in the SQLite table schema (`PRAGMA table_info`), so `PackageUpdates : Row` can store `id`, `agent_id`, `name`, `since` without adding `added_dt`/`updated_dt`/`deleted_dt` columns to `package_updates`, and removing `update_available` from `DebPackages`/`RpmPackages` leaves any existing database column harmlessly ignored.
- ✔️ `agent/linux/UpdatesAvailable.vala` and `agent/Win32/UpdatesAvailable.vala` are already in the tree from [5.10](../../plans/done/5.10-DONE-data-enrichment.md) Phase 2.
- ℹ️ [5.10.1-REJECTED-package-updates.md](../../plans/done/5.10.1-REJECTED-package-updates.md) was archived as rejected.

## Root cause

- ✔️ Treating `update_available` as a column on `deb_packages` and `rpm_packages` coupled transient pending-update state to the installed-package inventory tables, forcing bespoke `send_pending` RPCs and bulk `UPDATE ... IN / NOT IN` SQL instead of reusing `OSQuery.sync` with a dedicated `package_updates` table.

## Proposed fix

- 🔷 Add `shared/OSQuery/PackageUpdates.vala` (`Argus.Shared.OSQuery.PackageUpdates : Row`) backed by `package_updates` (`id`, `agent_id`, `name`, `since`).
- 🔷 `PackageUpdates.sync` indexes existing rows for `agent_id` by `name`, leaves matching names unchanged without updating `since`, inserts new names with `since = now`, and deletes any stored row missing from the incoming list (`query.deleteId`).
- 🔷 Register `PackageUpdates` in `shared/OSQuery/namespace.vala`, `server/OSQuery.vala`, `agent/Application.vala`, `shared/meson.build`, and `docs/meson.build`.
- 🔷 Remove `update_available` from `shared/OSQuery/DebPackages.vala`, `shared/OSQuery/RpmPackages.vala`, and `shared/OSQuery/AgentInfo.vala`.
- 🔷 Add non-stored `update_since` (`int`) to `DebPackages` and `RpmPackages`, populated by `DebPackages.list` and `RpmPackages.list` via `package_updates` lookup (`since <= 0`, both aggregated across all agents and per-agent).
- 🔷 Update `agent/linux/PackageMonitor.vala` to call `UpdatesAvailable.check` on `start()` and every 12 hours, and send the names as `PackageUpdates` rows via `OSQuery.sync`. A failure from `check` does not send (so an error does not clear `package_updates`).
- 💩 Also compare `update_since` in `controller/store/DebPackages.vala` and `controller/store/RpmPackages.vala` so reloading refreshes rows whose update status changed.
- 💩 Also add `PackageUpdates.sync` and `update_since` checks to `server/tests/packages.vala`.
- 🚫 Do not add `DebPackages.send_pending` or `RpmPackages.send_pending`.
- 🚫 Do not update `os_version`, `deb_packages`, or `rpm_packages` from `PackageUpdates.sync`.
- 🚫 Do not soft-delete rows in `package_updates` (`deleted_dt`); missing names are deleted.
- 🚫 Do not update `since` when a package name is already present in `package_updates`.
- 🚫 Do not send an empty `PackageUpdates` list when `UpdatesAvailable.check` throws.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### 1. `shared/OSQuery/PackageUpdates.vala` — new fake osquery table

**Why:** store pending package updates per agent with `id`, `agent_id`, `name`, and `since` so `OSQuery.sync` updates them directly.

**Where:** new file `shared/OSQuery/PackageUpdates.vala`, plus entries in `shared/meson.build`, `docs/meson.build`, `shared/OSQuery/namespace.vala`, `server/OSQuery.vala`, and `agent/Application.vala`.

**Depends on:** none.

#### Add — new file `shared/OSQuery/PackageUpdates.vala`

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

namespace Argus.Shared.OSQuery
{
	/**
	 * One ''package_updates'' row.
	 *
	 * Fake osquery row sent through ''OSQuery.sync'' with the
	 * package names that have an update waiting on an agent.
	 * Existing names stay with their original {@link since} time,
	 * new names are inserted, and names left out of the snapshot
	 * are deleted.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
	 * rows.add(new Argus.Shared.OSQuery.PackageUpdates() { name = "bash" });
	 * }}}
	 */
	public class PackageUpdates : Row
	{
		/**
		 * Apply one agent's pending-update snapshot to ''package_updates''.
		 *
		 * A name already stored for ''agent_id'' is left untouched so
		 * {@link since} does not change. A new name is inserted with
		 * ''since'' set to now. A stored name missing from ''rows''
		 * is deleted.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows pending package names
		 * @return true when every row has type {@link PackageUpdates}
		 */
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != typeof(PackageUpdates)) {
					return false;
				}
			}
			var query = new SQ.Query<PackageUpdates>(db, "package_updates");
			var stored = new Gee.ArrayList<PackageUpdates>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var index = new Gee.HashMap<string, PackageUpdates>();
			foreach (var old in stored) {
				if (!index.has_key(old.name)) {
					index.set(old.name, old);
					continue;
				}
				query.deleteId(old.id);
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			var seen = new Gee.HashMap<string, bool>();
			foreach (var row in rows) {
				var pkg = (PackageUpdates) row;
				if (pkg.name == "" || seen.has_key(pkg.name)) {
					continue;
				}
				seen.set(pkg.name, true);
				if (index.has_key(pkg.name)) {
					index.unset(pkg.name);
					continue;
				}
				pkg.id = 0;
				pkg.agent_id = agent_id;
				pkg.since = now;
				query.insert(pkg);
			}
			foreach (var old in index.values) {
				query.deleteId(old.id);
			}
			return true;
		}

		public override string table_name() { return "package_updates"; }

		public override string rpc_name() { return "PackageUpdates"; }

		/**
		 * Create ''package_updates''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS package_updates (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id INTEGER NOT NULL,
					name     TEXT NOT NULL DEFAULT '',
					since    INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("package_updates create failed: %s", db.db.errmsg());
			}
			var idx = """
				CREATE INDEX IF NOT EXISTS package_updates_agent_name
				ON package_updates (agent_id, name);
				""";
			if (Sqlite.OK != db.db.exec(idx, null, out errmsg)) {
				GLib.warning("package_updates index failed: %s", db.db.errmsg());
			}
		}

		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("PackageUpdates", typeof(PackageUpdates));
		}

		/**
		 * Package name that has an update waiting.
		 */
		public string name { get; set; default = ""; }
		/**
		 * Unix time this update was first recorded for the agent.
		 */
		public int since { get; set; default = 0; }
	}
}
```

#### Add — `shared/OSQuery/Row.vala`, in `bin_write_prop` after `case "os-status":`

```vala
				// Server-assigned timestamp on PackageUpdates.
				case "since":
```

#### Add — `shared/meson.build`, in `shared_osquery_sources` after `'OSQuery/Programs.vala',`

```meson
	'OSQuery/PackageUpdates.vala',
```

#### Add — `docs/meson.build`, in `valadoc_sources` after `'../shared/OSQuery/Programs.vala',`

```meson
  '../shared/OSQuery/PackageUpdates.vala',
```

#### Add — `shared/OSQuery/namespace.vala`, in `init_db` after `Programs.init_db(db);`

```vala
		PackageUpdates.init_db(db);
```

#### Add — `server/OSQuery.vala`, in `rpc_register` after `Argus.Shared.OSQuery.Programs.rpc_register();`

```vala
			Argus.Shared.OSQuery.PackageUpdates.rpc_register();
```

#### Add — `agent/Application.vala`, in `command_line` after `Argus.Shared.OSQuery.Programs.rpc_register();`

```vala
			Argus.Shared.OSQuery.PackageUpdates.rpc_register();
```

### 2. `shared/OSQuery/AgentInfo.vala` — remove `update-available` from `compare`

**Why:** `deb_packages` and `rpm_packages` no longer store `update_available`.

**Where:** `compare()` property skip `switch`.

**Depends on:** ### 3 and ### 4.

#### Remove

```vala
					case "pkgs-updated":
					case "pkgs-status":
					case "update-available":
						continue;
```

#### Replace with

```vala
					case "pkgs-updated":
					case "pkgs-status":
						continue;
```

### 3. `shared/OSQuery/DebPackages.vala` — remove `update_available` and look up `package_updates`

**Why:** `DebPackages.list` looks up pending updates in `package_updates` instead of reading `deb_packages.update_available`.

**Where:** `init_db()`, `list()` (`since <= 0` branches), and properties at the bottom of `DebPackages`.

**Depends on:** ### 1.

#### Remove

```vala
					priority         TEXT NOT NULL DEFAULT '',
					update_available INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("deb_packages create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "deb_packages");
			db.db.exec("ALTER TABLE deb_packages ADD COLUMN update_available INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
```

#### Replace with

```vala
					priority   TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("deb_packages create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "deb_packages");
```

#### Remove

```vala
			if (since <= 0 && agent_id > 0) {
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					""".printf(agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						name,
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(section, '')) AS section,
						GROUP_CONCAT(DISTINCT NULLIF(priority, '')) AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(maintainer, '')) AS maintainer,
						MIN(version || '-' || revision) AS min_version,
						MAX(version || '-' || revision) AS max_version,
						MAX(size) AS max_size,
						COUNT(DISTINCT agent_id) AS installed
					FROM
						deb_packages
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						deleted_dt = 0
					GROUP BY
						name
					ORDER BY
						name
					""", rows);
			}
```

#### Replace with

```vala
			if (since <= 0 && agent_id > 0) {
				query.selectQuery("""
					SELECT
						%s,
						COALESCE(package_updates.since, 0) AS update_since
					FROM
						deb_packages
					LEFT JOIN
						package_updates
					ON
						package_updates.agent_id = deb_packages.agent_id
					AND
						package_updates.name = deb_packages.name
					WHERE
						deb_packages.agent_id = %d
					AND
						deb_packages.deleted_dt = 0
					""".printf(
						string.joinv(", ", query.getColsExcept(null, "deb_packages.")),
						agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						name,
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(section, '')) AS section,
						GROUP_CONCAT(DISTINCT NULLIF(priority, '')) AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(maintainer, '')) AS maintainer,
						MIN(version || '-' || revision) AS min_version,
						MAX(version || '-' || revision) AS max_version,
						MAX(size) AS max_size,
						COUNT(DISTINCT agent_id) AS installed,
						COALESCE((
							SELECT
								MIN(package_updates.since)
							FROM
								package_updates
							WHERE
								package_updates.name = deb_packages.name
							AND
								package_updates.agent_id IN (SELECT id FROM agent)
						), 0) AS update_since
					FROM
						deb_packages
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						deleted_dt = 0
					GROUP BY
						name
					ORDER BY
						name
					""", rows);
			}
```

#### Remove

```vala
		/**
		 * A newer candidate is already on this host.
		 *
		 * ''1'' when an update is waiting. ''0'' when not.
		 */
		public int update_available { get; set; default = 0; }
```

#### Replace with

```vala
		/**
		 * Earliest unix time an update for this package has been waiting.
		 *
		 * Filled by ''list'' from ''package_updates''. Zero when none.
		 * Not stored on ''deb_packages''.
		 */
		public int update_since { get; set; default = 0; }
```

### 4. `shared/OSQuery/RpmPackages.vala` — remove `update_available` and look up `package_updates`

**Why:** `RpmPackages.list` looks up pending updates in `package_updates` instead of reading `rpm_packages.update_available`.

**Where:** `init_db()`, `list()` (`since <= 0` branches), and properties at the bottom of `RpmPackages`.

**Depends on:** ### 1.

#### Remove

```vala
					package_group    TEXT NOT NULL DEFAULT '',
					update_available INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("rpm_packages create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "rpm_packages");
			db.db.exec("ALTER TABLE rpm_packages ADD COLUMN update_available INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
```

#### Replace with

```vala
					package_group TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("rpm_packages create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "rpm_packages");
```

#### Remove

```vala
			if (since <= 0 && agent_id > 0) {
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					""".printf(agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						name,
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(package_group, '')) AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(vendor, '')) AS vendor,
						MIN(epoch || ':' || version || '-' || release) AS min_version,
						MAX(epoch || ':' || version || '-' || release) AS max_version,
						MAX(size) AS max_size,
						COUNT(DISTINCT agent_id) AS installed
					FROM
						rpm_packages
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						deleted_dt = 0
					GROUP BY
						name
					ORDER BY
						name
					""", rows);
			}
```

#### Replace with

```vala
			if (since <= 0 && agent_id > 0) {
				query.selectQuery("""
					SELECT
						%s,
						COALESCE(package_updates.since, 0) AS update_since
					FROM
						rpm_packages
					LEFT JOIN
						package_updates
					ON
						package_updates.agent_id = rpm_packages.agent_id
					AND
						package_updates.name = rpm_packages.name
					WHERE
						rpm_packages.agent_id = %d
					AND
						rpm_packages.deleted_dt = 0
					""".printf(
						string.joinv(", ", query.getColsExcept(null, "rpm_packages.")),
						agent_id), rows);
			}
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						name,
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(package_group, '')) AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(vendor, '')) AS vendor,
						MIN(epoch || ':' || version || '-' || release) AS min_version,
						MAX(epoch || ':' || version || '-' || release) AS max_version,
						MAX(size) AS max_size,
						COUNT(DISTINCT agent_id) AS installed,
						COALESCE((
							SELECT
								MIN(package_updates.since)
							FROM
								package_updates
							WHERE
								package_updates.name = rpm_packages.name
							AND
								package_updates.agent_id IN (SELECT id FROM agent)
						), 0) AS update_since
					FROM
						rpm_packages
					WHERE
						agent_id IN (SELECT id FROM agent)
					AND
						deleted_dt = 0
					GROUP BY
						name
					ORDER BY
						name
					""", rows);
			}
```

#### Remove

```vala
		/**
		 * A newer candidate is already on this host.
		 *
		 * ''1'' when an update is waiting. ''0'' when not.
		 */
		public int update_available { get; set; default = 0; }
```

#### Replace with

```vala
		/**
		 * Earliest unix time an update for this package has been waiting.
		 *
		 * Filled by ''list'' from ''package_updates''. Zero when none.
		 * Not stored on ''rpm_packages''.
		 */
		public int update_since { get; set; default = 0; }
```

### 5. `agent/linux/PackageMonitor.vala` — send `PackageUpdates` via `OSQuery.sync`

**Why:** run `UpdatesAvailable.check` on startup and every twelve hours, and sync the pending names to the server through `OSQuery.sync("PackageUpdates", rows)`.

**Where:** class overview, `pending_id` field after `later`, `start()`, and `send_pending()` after `start()`.

**Depends on:** ### 1.

#### Remove

```vala
	 * queries osquery. {@link start} reads the startup
	 * ''os_version'' row and calls {@link apt} or {@link rpm}.
```

#### Replace with

```vala
	 * queries osquery. {@link start} reads the startup
	 * ''os_version'' row and calls {@link apt} or {@link rpm}.
	 * {@link send_pending} posts the names that need updating
	 * through ''OSQuery.sync'' as ''PackageUpdates'' every
	 * twelve hours.
```

#### Add — after `later`, the twelve-hour timer id

```vala
		/**
		 * Source id of the twelve-hour update check.
		 *
		 * Zero when {@link start} did not arm it.
		 */
		private uint pending_id = 0;
```

#### Remove

```vala
		/**
		 * Start the watch this host uses.
		 *
		 * {@link Application.os_version} is the startup osquery
		 * row. {@link Argus.Shared.OSQuery.OsVersion.package_manager}
		 * chooses the watch. APT calls {@link apt}. DNF calls
		 * {@link rpm}. Any other value returns.
		 */
		public void start()
		{
			switch (this.application.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					this.apt();
					return;
				case Argus.Shared.OSQuery.PackageManager.DNF:
					this.rpm();
					return;
				default:
					return;
			}
		}
```

#### Replace with

```vala
		/**
		 * Start the watch this host uses, then the update check.
		 *
		 * {@link Application.os_version} is the startup osquery
		 * row. {@link Argus.Shared.OSQuery.OsVersion.package_manager}
		 * chooses the watch. APT calls {@link apt}. DNF calls
		 * {@link rpm}. Either one then calls {@link send_pending}
		 * and repeats that every twelve hours. Any other value
		 * returns.
		 */
		public void start()
		{
			switch (this.application.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					this.apt();
					break;

				case Argus.Shared.OSQuery.PackageManager.DNF:
					this.rpm();
					break;

				default:
					return;
			}
			this.send_pending();
			this.pending_id = GLib.Timeout.add_seconds(12 * 60 * 60, () => {
				this.send_pending();
				return true;
			});
		}

		/**
		 * Post the names that need updating through ''OSQuery.sync''.
		 *
		 * {@link UpdatesAvailable.check} reads the host. A failure
		 * is not sent. An empty list clears stored pending updates.
		 */
		public void send_pending()
		{
			var names = new Gee.ArrayList<string>();
			try {
				names = new UpdatesAvailable().check(this.application.os_version);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			if (this.application.connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			foreach (var name in names) {
				if (name == "") {
					continue;
				}
				rows.add(new Argus.Shared.OSQuery.PackageUpdates() {
					name = name
				});
			}
			try {
				var response = this.application.connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", "PackageUpdates", rows)
				});
				if (response.error != null) {
					GLib.debug("PackageUpdates sync failed %s", response.error.message);
				}
			} catch (GLib.Error e) {
				Application.connection_down = true;
				GLib.warning("%s", e.message);
			}
		}
```

### 6. `controller/store/DebPackages.vala` and `controller/store/RpmPackages.vala` — refresh on `update_since` change

**Why:** reload diffing skips row replacement when only `update_since` changed unless `update_since` is compared.

**Where:** equality check inside `load()` in `controller/store/DebPackages.vala` and `controller/store/RpmPackages.vala`.

**Depends on:** ### 3 and ### 4.

#### `controller/store/DebPackages.vala` — Remove

```vala
						have.max_size == row.max_size &&
						have.installed == row.installed) {
```

#### `controller/store/DebPackages.vala` — Replace with

```vala
						have.max_size == row.max_size &&
						have.installed == row.installed &&
						have.update_since == row.update_since) {
```

#### `controller/store/RpmPackages.vala` — Remove

```vala
						have.max_size == row.max_size &&
						have.installed == row.installed) {
```

#### `controller/store/RpmPackages.vala` — Replace with

```vala
						have.max_size == row.max_size &&
						have.installed == row.installed &&
						have.update_since == row.update_since) {
```

### 7. `docs/rpc-commands.md` and `docs/plans/4.0-data-types.md` — schema and RPC docs

**Why:** document `PackageUpdates` in `OSQuery.sync` and `package_updates` in `4.0-data-types.md`, and remove `update_available` from `deb_packages` and `rpm_packages`.

**Where:** `OSQuery.sync`, `DebPackages.list`, and `RpmPackages.list` in `docs/rpc-commands.md`; Debian packages, RPM packages, and new Package updates section in `docs/plans/4.0-data-types.md`.

**Depends on:** ### 1, ### 3, ### 4.

#### `docs/rpc-commands.md` — Remove

```markdown
- Tables: `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, and `os_version`, then one package class.
- The package class follows `os_version.package_manager`. APT sends `DebPackages`. DNF sends `RpmPackages`. WIN sends `Programs`. Any other value sends no package class.
- A row left out of that full snapshot gets `deleted_dt`.
- The machine tables are posted even when the array is empty. After the first package send, an empty package query is not posted.
- The row objects are `Argus.Shared.OSQuery`. The property name is the column name.
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `InterfaceAddresses`, `OsVersion`, `DebPackages`, `RpmPackages`, `Programs`.
```

#### `docs/rpc-commands.md` — Replace with

```markdown
- Tables: `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, and `os_version`, then one package class, plus `package_updates` on Linux (`APT` / `DNF`) from `PackageMonitor.send_pending`.
- The package class follows `os_version.package_manager`. APT sends `DebPackages`. DNF sends `RpmPackages`. WIN sends `Programs`. Any other value sends no package class.
- A row left out of a standard table snapshot gets `deleted_dt`. For `PackageUpdates`, existing names keep their `since` time, new names are inserted, and names left out are deleted.
- The machine tables are posted even when the array is empty. After the first package send, an empty package query is not posted. An empty `PackageUpdates` list is posted when `UpdatesAvailable.check` succeeds with no updates.
- The row objects are `Argus.Shared.OSQuery`. The property name is the column name.
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `InterfaceAddresses`, `OsVersion`, `DebPackages`, `RpmPackages`, `Programs`, `PackageUpdates`.
```

#### `docs/rpc-commands.md` — Remove

```markdown
- When `agent_id` and `since` are zero, the reply fills `arch`, `section`, `priority`, `source`, `maintainer`, `min_version`, `max_version`, `max_size`, and `installed`. Those are not stored columns. `min_version` and `max_version` are the minimum and maximum of `version`, a hyphen, and `revision`. An empty revision leaves the trailing hyphen.
```

#### `docs/rpc-commands.md` — Replace with

```markdown
- When `since` is zero, the reply fills `update_since` from `package_updates` (`0` when no update is waiting). When `agent_id` and `since` are zero, the reply also fills `arch`, `section`, `priority`, `source`, `maintainer`, `min_version`, `max_version`, `max_size`, and `installed`. Those are not stored columns. `min_version` and `max_version` are the minimum and maximum of `version`, a hyphen, and `revision`. An empty revision leaves the trailing hyphen.
```

#### `docs/rpc-commands.md` — Remove

```markdown
- When `agent_id` and `since` are zero, the reply fills `arch`, `package_group`, `source`, `vendor`, `min_version`, `max_version`, `max_size`, and `installed`. Those are not stored columns. `min_version` and `max_version` are the minimum and maximum of `epoch`, a colon, `version`, a hyphen, and `release`.
```

#### `docs/rpc-commands.md` — Replace with

```markdown
- When `since` is zero, the reply fills `update_since` from `package_updates` (`0` when no update is waiting). When `agent_id` and `since` are zero, the reply also fills `arch`, `package_group`, `source`, `vendor`, `min_version`, `max_version`, `max_size`, and `installed`. Those are not stored columns. `min_version` and `max_version` are the minimum and maximum of `epoch`, a colon, `version`, a hyphen, and `release`.
```

#### `docs/plans/4.0-data-types.md` — Remove

~~~~markdown
## Debian packages

`deb_packages` is one installed package from osquery.

- 🔷 `update_available` is not an osquery column. [5.10](../plans/done/5.10-DONE-data-enrichment.md) fills it.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
version               TEXT
source                TEXT
size                  INT64
arch                  TEXT
revision              TEXT
status                TEXT
maintainer            TEXT
section               TEXT
priority              TEXT
update_available      INTEGER
added_dt              INTEGER
updated_dt            INTEGER
deleted_dt            INTEGER
```

## RPM packages

`rpm_packages` is one installed package from osquery.

- 🔷 `update_available` is not an osquery column. [5.10](../plans/done/5.10-DONE-data-enrichment.md) fills it.
- ℹ️ `install_time` is the osquery column.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
version               TEXT
release               TEXT
source                TEXT
size                  INT64
sha1                  TEXT
arch                  TEXT
epoch                 INTEGER
install_time          INT64
vendor                TEXT
package_group         TEXT
update_available      INTEGER
added_dt              INTEGER
updated_dt            INTEGER
deleted_dt            INTEGER
```
~~~~

#### `docs/plans/4.0-data-types.md` — Replace with

~~~~markdown
## Debian packages

`deb_packages` is one installed package from osquery.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
version               TEXT
source                TEXT
size                  INT64
arch                  TEXT
revision              TEXT
status                TEXT
maintainer            TEXT
section               TEXT
priority              TEXT
added_dt              INTEGER
updated_dt            INTEGER
deleted_dt            INTEGER
```

## RPM packages

`rpm_packages` is one installed package from osquery.

- ℹ️ `install_time` is the osquery column.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
version               TEXT
release               TEXT
source                TEXT
size                  INT64
sha1                  TEXT
arch                  TEXT
epoch                 INTEGER
install_time          INT64
vendor                TEXT
package_group         TEXT
added_dt              INTEGER
updated_dt            INTEGER
deleted_dt            INTEGER
```

## Package updates

`package_updates` is a fake osquery table of package names that currently have an update waiting on an agent.

```
id                    INTEGER
agent_id              INTEGER
name                  TEXT
since                 INTEGER
```
~~~~

## Attempts / changelog

- ℹ️ 2026-11-13: Rejected [5.10.1-REJECTED-package-updates.md](../../plans/done/5.10.1-REJECTED-package-updates.md) (`DebPackages.send_pending` / `RpmPackages.send_pending` + `update_available` columns) and drafted this bug proposal with `package_updates` via `OSQuery.sync`.
- 🔷 2026-11-13: Removed `os_version` updates from `PackageUpdates.sync` (only `package_updates` is touched) and dropped redundant `agent_id IN (SELECT id FROM agent)` from the `agent_id > 0` `list()` queries.
- ✔️ 2026-11-13: Applied `### 1`–`### 7`. Moved `since` omission in `bin_write_prop` from `PackageUpdates.vala` into `Row.bin_write_prop` (`shared/OSQuery/Row.vala`, matching `os-updated` / `os-status`) because `Row.bin_write_prop` is `override` on `OLLMrpc.Bin.Serializable`.
- ✔️ 2026-11-13: `ninja -C build` and `ninja -C build docs/valadoc` succeeded. `meson test -C build` passed 5/6 (`packages` failed in pre-existing `Package.sync` on `SQ.Query<Package>` instantiating abstract `Package`). Verified `PackageUpdates.sync` (preserving `since`, inserting new, deleting removed) and `DebPackages.list` / `RpmPackages.list` `update_since` queries via standalone test binary against a temporary SQLite database.
- ✅ 2026-11-13: User closed as fixed (`Package.sync` was also resolved in [2026-11-13-windows-no-packages.md](../2026-11-13-windows-no-packages.md), with `meson test -C build` passing 6/6).

## Next

- ✅ Closed. `package_updates` sync, `DebPackages.list` / `RpmPackages.list` `update_since` lookup, and `PackageMonitor.send_pending` are in the tree.
