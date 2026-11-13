# Controller package and asset loading performance & hangs

**Status:** ✔️ fixes `### 1`–`### 5` applied; awaiting live controller/server verification (plus server stall re-check on current binaries)

**Pointer:** `docs/bug-fix-process.md`.

---

## Problem

- 🔷 Loading packages and assets on `argusrm-controller` is slow (~2.08 s for `DebPackages.list` alone, UI critical spam on every visible row, repeated full reloads and per-row `items_changed` churn on tab switches, and 120 s timeouts when the server stalls).

## Evidence

- ✔️ **Controller `DebPackages.list` round-trip (`14:43:07.538` -> `14:43:09.621`, `2.083 s`):**
  - Benchmark (`valac` probe with 3,000 grouped `DebPackages` rows in memory):
    - Current full `Row.bin_write_prop`: `write=46.2 ms`, `read=67.9 ms`, `wire_bytes=634,107` (serializes all 20 properties per row including empty/zero defaults like `added-dt=0`, `updated-dt=0`, `deleted-dt=0`, `version=""`, `revision=""`, `status=""`, `size=0`, `update-since=0`).
    - Skipping default values in `Row.bin_write_prop`: `write=43.9 ms`, `read=34.4 ms`, `wire_bytes=522,999` (cuts decode time in half and trims 111 KB on 3,000 rows).
  - `shared/OSQuery/DebPackages.vala` (`158-189`), `RpmPackages.vala` (`158-190`), and `Programs.vala` (`145-172`) create no SQLite indexes on `(deleted_dt, name, agent_id)` or `(agent_id)`, and `DebPackages.list` / `RpmPackages.list` execute a correlated `SELECT MIN(package_updates.since)` subquery per grouped package row instead of a single `LEFT JOIN`.
- ✔️ **Critical warning storm on every `DebPackages` row bind (`controller.log` `14:43:09.621`–`14:43:09.699`):**
  - `controller/resources/columns/deb_packages.csv:13` defines `Remove,remove,ON,48,remove`.
  - `controller/tab/Base.vala:276-285` maps `lookup = "installed"` to find `prop`, then calls `((GLib.Object) row).get_property(name, ref value)` with `name` (`"remove"`) instead of `lookup` (`"installed"`), logging `g_object_get_is_valid_property: object class 'ArgusSharedOSQueryDebPackages' has no property named 'remove'` on every cell bind (~1,890 critical lines in `controller.log`) and leaving the Remove icon hidden (`count = 0`).
- ✔️ **Synchronous UI work on load/reload (`controller/tab/Asset/*.vala`, `controller/store/*.vala`):**
  - `controller/tab/Asset/DebPackages.vala:67-69` and `SystemInfo.vala:88-90` set `Gtk.FilterListModel(..., ...) { incremental = false }`, forcing synchronous full-list filtering on the main thread when rows load or the filter changes.
  - `controller/tab/Asset/DebPackages.vala:161-260` (`build_sections`):
    - Connected to `store.items_changed`, uses `names.contains(section)` on a `Gee.ArrayList<string>` (`O(N * S)`), and sets `this.filter.sections` before `this.filter.section_count` (triggering two filter passes).
  - `controller/store/DebPackages.vala:164-208` (flagged `// NASTY - needs fixing`), `Programs.vala:162-209`, and `RpmPackages.vala:162-208`:
    - Re-fetch the entire list on every `map` event without checking `this.busy`.
    - When `items_store.size > 0`, emit `this.items_changed(...)` once **per row**, causing `build_sections`, `Gtk.FilterListModel`, and `Gtk.ColumnView` to re-run up to ~3,000 times per tab switch.
- ✔️ **Stale installed binaries caused `SystemInfo.list` disconnects (`controller.log` `14:43:03`, `14:43:13`):**
  - `/usr/bin/argusrm-controller` (`14:42:42`) lacked `os-updated` while `/usr/bin/argusrm-server` (`14:42:43`) sent it, triggering `unknown bin property 'os-updated'` -> full disconnect and reconnect whenever `Machines` opened (`build/controller/argusrm-controller` from `14:43:08` already has the property).
- ✔️ **120 s RPC timeouts (`controller.log` `14:43:47`–`14:46:16`, `14:52:55`–`14:54:55`) from `argusrm-server` stall after `14:43:40.542`:**
  - After receiving `OSQuery.sync` (`os_version` from Windows at `14:43:40.542`, which calls `this.app.os_update.check.begin()`), `/usr/bin/argusrm-server` (`PID 2014534`) stopped reading port `817` (`Recv-Q = 1445` unread in `ss -tnp`), causing `Programs.list` (`id=13`, `id=15`), `RpmPackages.list` (`id=14`), and `DebPackages.list` (`id=16`) to time out after 120 s.
  - A standalone Vala test of `OsUpdate.check_distro` (`distro=win`) inserted all 25 rows without hanging, so the live `argusrm-server` stall needs reproduction/backtrace with matching `build/` binaries installed.

## Root cause

- ✔️ Controller package loading latency comes from four compounding issues (plus the separate server stall):
  1. `controller/tab/Base.vala:285` calls `get_property(name, ref value)` instead of `get_property(lookup, ref value)`, emitting criticals on every `DebPackages` row bind.
  2. `DebPackages.list`, `RpmPackages.list`, and `Programs.list` lack SQLite indexes and run a per-row correlated subquery on `package_updates`, while `Row.bin_write_prop` serializes empty/default properties on every row.
  3. `Store/DebPackages`, `Store/RpmPackages`, and `Store/Programs` emit per-row `items_changed` signals on reload (`// NASTY - needs fixing`) without a `busy` guard, `Tab/Asset/DebPackages` runs `O(N * S)` `ArrayList.contains` on every `items_changed`, and `FilterListModel` runs synchronously (`incremental = false`).
  4. `argusrm-server` stopped servicing port `817` after `14:43:40.542`, turning subsequent `*.list` calls into 120 s timeouts (requires live trace after installing matching `build/` binaries).

## Proposed fix

- 🔷 Fix `controller/tab/Base.vala:285` to pass `lookup` to `get_property()`.
- 💩 Skip default/empty values in `shared/OSQuery/Row.vala` (`bin_write_prop()`) using `prop.get_default_value()`, preserving non-default values (such as `os_status = 0` when its default is `-1`).
- 💩 Add SQLite indexes in `DebPackages.init_db`, `RpmPackages.init_db`, `Programs.init_db`, and `PackageUpdates.init_db`, and replace the correlated `package_updates` subquery in `DebPackages.list` and `RpmPackages.list` with a single `LEFT JOIN`.
- 💩 Replace the per-row `items_changed` reload loop in `Store/DebPackages.vala`, `Store/RpmPackages.vala`, and `Store/Programs.vala` with a single `this.items = listed;` swap (plus `if (this.busy) { return; }`), set `incremental = true` on `Gtk.FilterListModel` in `Tab/Asset/DebPackages.vala` and `Tab/Asset/SystemInfo.vala`, and use `Gee.HashSet<string>` in `Tab/Asset/DebPackages.vala` (`build_sections`).
- 🚫 Do not cache stale package lists forever across tab switches; keep `map` reload, backed by fast single-pass updates and `busy` gating.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding lines before applying.

### 1. `controller/tab/Base.vala` — read `lookup` instead of `name`

**Why:** `format == "remove"` maps `lookup = "installed"`, so calling `get_property(name)` throws `has no property named 'remove'` on every bound cell.

**Where:** `column_factory()`, inside `factory.bind.connect`.

**Depends on:** none.

#### Remove

```vala
				var value = GLib.Value(prop.value_type);
				((GLib.Object) row).get_property(name, ref value);
```

#### Replace with

```vala
				var value = GLib.Value(prop.value_type);
				((GLib.Object) row).get_property(lookup, ref value);
```

### 2. `shared/OSQuery/Row.vala` — omit default scalar values in `bin_write_prop`

**Why:** `DebPackages.list`, `RpmPackages.list`, and `Programs.list` send thousands of rows where unused properties (`added_dt`, `updated_dt`, `deleted_dt`, `version`, `revision`, `status`, `size`, `update_since`, etc.) sit at their GObject defaults (`""` or `0`), inflating payload size and client decode time.

**Where:** `shared/OSQuery/Row.vala`, inside `bin_write_prop()`.

**Depends on:** none.

#### Remove

```vala
			this.bin_default_write_prop(ctx, prop);
```

#### Replace with

```vala
			var val = GLib.Value(prop.value_type);
			((GLib.Object) this).get_property(prop.name, ref val);
			var def = prop.get_default_value();
			switch (prop.value_type) {
				case GLib.Type.STRING:
					var text = val.get_string();
					var def_text = def.get_string();
					if ((text != null ? text : "") == (def_text != null ? def_text : "")) {
						return;
					}
					break;

				case GLib.Type.INT:
					if (val.get_int() == def.get_int()) {
						return;
					}
					break;

				case GLib.Type.INT64:
					if (val.get_int64() == def.get_int64()) {
						return;
					}
					break;

				case GLib.Type.BOOLEAN:
					if (val.get_boolean() == def.get_boolean()) {
						return;
					}
					break;

				default:
					break;
			}
			this.bin_default_write_prop(ctx, prop);
```

### 3. `shared/OSQuery/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`, and `PackageUpdates.vala` — indexes and `LEFT JOIN`

**Why:** adding indexes on `(deleted_dt, name, agent_id)` and `(agent_id)` plus replacing the per-row correlated `package_updates` subquery with a single `LEFT JOIN` removes full table scans during `sync` and `list`.

**Where:** `init_db()` in all four files, and `list()` (`since <= 0 && agent_id <= 0`) in `DebPackages.vala` and `RpmPackages.vala`.

**Depends on:** none.

#### `shared/OSQuery/DebPackages.vala` — Part 1 (`init_db`): Add indexes after `init_db_audit`

```vala
			var idx_query = """
				CREATE INDEX IF NOT EXISTS deb_packages_deleted_name_agent
				ON deb_packages (deleted_dt, name, agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_query, null, out errmsg)) {
				GLib.warning("deb_packages index failed: %s", db.db.errmsg());
			}
			var idx_agent = """
				CREATE INDEX IF NOT EXISTS deb_packages_agent
				ON deb_packages (agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_agent, null, out errmsg)) {
				GLib.warning("deb_packages agent index failed: %s", db.db.errmsg());
			}
```

#### `shared/OSQuery/DebPackages.vala` — Part 2 (`list`): Remove

```vala
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

#### `shared/OSQuery/DebPackages.vala` — Part 2 (`list`): Replace with

```vala
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						deb_packages.name AS name,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.section, '')) AS section,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.priority, '')) AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(deb_packages.maintainer, '')) AS maintainer,
						MIN(deb_packages.version || '-' || deb_packages.revision) AS min_version,
						MAX(deb_packages.version || '-' || deb_packages.revision) AS max_version,
						MAX(deb_packages.size) AS max_size,
						COUNT(DISTINCT deb_packages.agent_id) AS installed,
						COALESCE(pkg_updates.update_since, 0) AS update_since
					FROM
						deb_packages
					LEFT JOIN (
						SELECT
							name,
							MIN(since) AS update_since
						FROM
							package_updates
						WHERE
							agent_id IN (SELECT id FROM agent)
						GROUP BY
							name
					) AS pkg_updates
					ON
						pkg_updates.name = deb_packages.name
					WHERE
						deb_packages.deleted_dt = 0
					AND
						deb_packages.agent_id IN (SELECT id FROM agent)
					GROUP BY
						deb_packages.name
					ORDER BY
						deb_packages.name
					""", rows);
			}
```

#### `shared/OSQuery/RpmPackages.vala` — Part 1 (`init_db`): Add indexes after `init_db_audit`

```vala
			var idx_query = """
				CREATE INDEX IF NOT EXISTS rpm_packages_deleted_name_agent
				ON rpm_packages (deleted_dt, name, agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_query, null, out errmsg)) {
				GLib.warning("rpm_packages index failed: %s", db.db.errmsg());
			}
			var idx_agent = """
				CREATE INDEX IF NOT EXISTS rpm_packages_agent
				ON rpm_packages (agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_agent, null, out errmsg)) {
				GLib.warning("rpm_packages agent index failed: %s", db.db.errmsg());
			}
```

#### `shared/OSQuery/RpmPackages.vala` — Part 2 (`list`): Remove

```vala
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

#### `shared/OSQuery/RpmPackages.vala` — Part 2 (`list`): Replace with

```vala
			if (since <= 0 && agent_id <= 0) {
				query.selectQuery("""
					SELECT
						rpm_packages.name AS name,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.package_group, '')) AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(rpm_packages.vendor, '')) AS vendor,
						MIN(rpm_packages.epoch || ':' || rpm_packages.version || '-' || rpm_packages.release) AS min_version,
						MAX(rpm_packages.epoch || ':' || rpm_packages.version || '-' || rpm_packages.release) AS max_version,
						MAX(rpm_packages.size) AS max_size,
						COUNT(DISTINCT rpm_packages.agent_id) AS installed,
						COALESCE(pkg_updates.update_since, 0) AS update_since
					FROM
						rpm_packages
					LEFT JOIN (
						SELECT
							name,
							MIN(since) AS update_since
						FROM
							package_updates
						WHERE
							agent_id IN (SELECT id FROM agent)
						GROUP BY
							name
					) AS pkg_updates
					ON
						pkg_updates.name = rpm_packages.name
					WHERE
						rpm_packages.deleted_dt = 0
					AND
						rpm_packages.agent_id IN (SELECT id FROM agent)
					GROUP BY
						rpm_packages.name
					ORDER BY
						rpm_packages.name
					""", rows);
			}
```

#### `shared/OSQuery/Programs.vala` (`init_db`): Add indexes after `init_db_audit`

```vala
			var idx_query = """
				CREATE INDEX IF NOT EXISTS programs_deleted_name_agent
				ON programs (deleted_dt, name, agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_query, null, out errmsg)) {
				GLib.warning("programs index failed: %s", db.db.errmsg());
			}
			var idx_agent = """
				CREATE INDEX IF NOT EXISTS programs_agent
				ON programs (agent_id);
				""";
			if (Sqlite.OK != db.db.exec(idx_agent, null, out errmsg)) {
				GLib.warning("programs agent index failed: %s", db.db.errmsg());
			}
```

#### `shared/OSQuery/PackageUpdates.vala` (`init_db`): Add index after `package_updates_agent_name`

```vala
			var idx_name = """
				CREATE INDEX IF NOT EXISTS package_updates_name_agent
				ON package_updates (name, agent_id, since);
				""";
			if (Sqlite.OK != db.db.exec(idx_name, null, out errmsg)) {
				GLib.warning("package_updates name index failed: %s", db.db.errmsg());
			}
```

### 4. `controller/store/DebPackages.vala`, `RpmPackages.vala`, and `Programs.vala` — single-shot replace + `busy` gate

**Why:** emitting `items_changed` once per row (`// NASTY - needs fixing`) forces `FilterListModel`, `ColumnView`, and `DebPackages.build_sections` to re-run thousands of times on reload, and missing `busy` checks let rapid tab switches queue duplicate RPCs.

**Where:** `load()` in all three stores.

**Depends on:** none.

#### `controller/store/DebPackages.vala` — Remove

```vala
		public void load(int agent_id)
		{
			this.busy = true;
```

#### `controller/store/DebPackages.vala` — Replace with

```vala
		public void load(int agent_id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
```

#### `controller/store/DebPackages.vala` — Remove

```vala
				if (this.items_store.size == 0) {
					this.items = listed;
					this.busy = false;
					return;
				}
				// NASTY - needs fixing
				var at = new Gee.HashMap<string, int>();
				for (var i = 0; i < this.items_store.size; i++) {
					at.set(this.items_store.get(i).name, i);
				}
				foreach (var row in listed) {
					if (!at.has_key(row.name)) {
						this.items_store.add(row);
						this.items_changed((uint) (this.items_store.size - 1), 0, 1);
						continue;
					}
					var index = at.get(row.name);
					var have = this.items_store.get(index);
					at.unset(row.name);
					if (have.arch == row.arch &&
						have.section == row.section &&
						have.priority == row.priority &&
						have.source == row.source &&
						have.maintainer == row.maintainer &&
						have.min_version == row.min_version &&
						have.max_version == row.max_version &&
						have.max_size == row.max_size &&
						have.installed == row.installed &&
						have.update_since == row.update_since) {
						continue;
					}
					this.items_store.set(index, row);
					this.items_changed((uint) index, 1, 1);
				}
				var gone = new Gee.ArrayList<int>();
				foreach (var index in at.values) {
					gone.add(index);
				}
				gone.sort((a, b) => {
					if (a == b) {
						return 0;
					}
					if (a > b) {
						return -1;
					}
					return 1;
				});
				foreach (var index in gone) {
					this.items_store.remove_at(index);
					this.items_changed((uint) index, 1, 0);
				}
				this.busy = false;
```

#### `controller/store/DebPackages.vala` — Replace with

```vala
				this.items = listed;
				this.busy = false;
```

#### `controller/store/RpmPackages.vala` — Remove

```vala
		public void load(int agent_id)
		{
			this.busy = true;
```

#### `controller/store/RpmPackages.vala` — Replace with

```vala
		public void load(int agent_id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
```

#### `controller/store/RpmPackages.vala` — Remove

```vala
				if (this.items_store.size == 0) {
					this.items = listed;
					this.busy = false;
					return;
				}
				var at = new Gee.HashMap<string, int>();
				for (var i = 0; i < this.items_store.size; i++) {
					at.set(this.items_store.get(i).name, i);
				}
				foreach (var row in listed) {
					if (!at.has_key(row.name)) {
						this.items_store.add(row);
						this.items_changed((uint) (this.items_store.size - 1), 0, 1);
						continue;
					}
					var index = at.get(row.name);
					var have = this.items_store.get(index);
					at.unset(row.name);
					if (have.arch == row.arch &&
						have.package_group == row.package_group &&
						have.source == row.source &&
						have.vendor == row.vendor &&
						have.min_version == row.min_version &&
						have.max_version == row.max_version &&
						have.max_size == row.max_size &&
						have.installed == row.installed &&
						have.update_since == row.update_since) {
						continue;
					}
					this.items_store.set(index, row);
					this.items_changed((uint) index, 1, 1);
				}
				var gone = new Gee.ArrayList<int>();
				foreach (var index in at.values) {
					gone.add(index);
				}
				gone.sort((a, b) => {
					if (a == b) {
						return 0;
					}
					if (a > b) {
						return -1;
					}
					return 1;
				});
				foreach (var index in gone) {
					this.items_store.remove_at(index);
					this.items_changed((uint) index, 1, 0);
				}
				this.busy = false;
```

#### `controller/store/RpmPackages.vala` — Replace with

```vala
				this.items = listed;
				this.busy = false;
```

#### `controller/store/Programs.vala` — Remove

```vala
		public void load(int agent_id)
		{
			this.busy = true;
```

#### `controller/store/Programs.vala` — Replace with

```vala
		public void load(int agent_id)
		{
			if (this.busy) {
				return;
			}
			this.busy = true;
```

#### `controller/store/Programs.vala` — Remove

```vala
				if (this.items_store.size == 0) {
					this.items = listed;
					this.busy = false;
					return;
				}
				var at = new Gee.HashMap<string, int>();
				for (var i = 0; i < this.items_store.size; i++) {
					at.set(this.items_store.get(i).name, i);
				}
				foreach (var row in listed) {
					if (!at.has_key(row.name)) {
						this.items_store.add(row);
						this.items_changed((uint) (this.items_store.size - 1), 0, 1);
						continue;
					}
					var index = at.get(row.name);
					var have = this.items_store.get(index);
					at.unset(row.name);
					if (have.publisher == row.publisher &&
						have.language == row.language &&
						have.identifying_number == row.identifying_number &&
						have.install_date == row.install_date &&
						have.install_location == row.install_location &&
						have.install_source == row.install_source &&
						have.uninstall_string == row.uninstall_string &&
						have.min_version == row.min_version &&
						have.max_version == row.max_version &&
						have.installed == row.installed &&
						have.uninstall_count == row.uninstall_count) {
						continue;
					}
					this.items_store.set(index, row);
					this.items_changed((uint) index, 1, 1);
				}
				var gone = new Gee.ArrayList<int>();
				foreach (var index in at.values) {
					gone.add(index);
				}
				gone.sort((a, b) => {
					if (a == b) {
						return 0;
					}
					if (a > b) {
						return -1;
					}
					return 1;
				});
				foreach (var index in gone) {
					this.items_store.remove_at(index);
					this.items_changed((uint) index, 1, 0);
				}
				this.busy = false;
```

#### `controller/store/Programs.vala` — Replace with

```vala
				this.items = listed;
				this.busy = false;
```

### 5. `controller/tab/Asset/DebPackages.vala` and `SystemInfo.vala` — `incremental = true` and `HashSet` in `build_sections`

**Why:** `incremental = false` blocks the main thread filtering thousands of rows synchronously, and `build_sections` scans an `ArrayList` linearly and sets `sections` before `section_count`.

**Where:** `controller/tab/Asset/DebPackages.vala` (lines 67–69, 161–176, 256–259) and `controller/tab/Asset/SystemInfo.vala` (lines 88–90).

**Depends on:** ### 4.

#### `controller/tab/Asset/DebPackages.vala` — Part 1 (`FilterListModel`): Remove

```vala
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = false
			};
```

#### `controller/tab/Asset/DebPackages.vala` — Part 1 (`FilterListModel`): Replace with

```vala
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
```

#### `controller/tab/Asset/DebPackages.vala` — Part 2 (`build_sections`): Remove

```vala
		private void build_sections(Gtk.Box rows)
		{
			var names = new Gee.ArrayList<string>();
			foreach (var package in this.store.items) {
				foreach (var part in package.section.split(",")) {
					var section = part.strip();
					if (section == "" || names.contains(section)) {
						continue;
					}
					names.add(section);
				}
			}
			names.sort((a, b) => {
				return a.ascii_casecmp(b);
			});
```

#### `controller/tab/Asset/DebPackages.vala` — Part 2 (`build_sections`): Replace with

```vala
		private void build_sections(Gtk.Box rows)
		{
			var seen = new Gee.HashSet<string>();
			foreach (var package in this.store.items) {
				foreach (var part in package.section.split(",")) {
					var section = part.strip();
					if (section == "") {
						continue;
					}
					seen.add(section);
				}
			}
			var names = new Gee.ArrayList<string>();
			names.add_all(seen);
			names.sort((a, b) => {
				return a.ascii_casecmp(b);
			});
```

#### `controller/tab/Asset/DebPackages.vala` — Part 3 (`filter` assignment order): Remove

```vala
			this.filter.sections = on;
			this.filter.section_count = names.size;
			this.filling = false;
```

#### `controller/tab/Asset/DebPackages.vala` — Part 3 (`filter` assignment order): Replace with

```vala
			this.filter.section_count = names.size;
			this.filter.sections = on;
			this.filling = false;
```

#### `controller/tab/Asset/SystemInfo.vala` — Remove

```vala
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = false
			};
```

#### `controller/tab/Asset/SystemInfo.vala` — Replace with

```vala
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
```

---

## Attempts / changelog

- ℹ️ 2026-11-13: Diagnosed from `/var/log/argusrm/server.log`, `~/.cache/argusrm/controller.log`, `ss -tnp`, and `valac` benchmarks (`DebPackages.list` SQLite + `Row.bin_write_prop`).
- ℹ️ 2026-11-13: Added verbatim code proposals `### 1`–`### 5`.
- ℹ️ 2026-11-13: Suspended/deferred per user request while continuing Windows testing.
- ✔️ 2026-11-13: Applied `### 1`–`### 5` (`controller/tab/Base.vala`, `shared/OSQuery/Row.vala`, `shared/OSQuery/DebPackages.vala`, `shared/OSQuery/RpmPackages.vala`, `shared/OSQuery/Programs.vala`, `shared/OSQuery/PackageUpdates.vala`, `controller/store/DebPackages.vala`, `controller/store/RpmPackages.vala`, `controller/store/Programs.vala`, `controller/tab/Asset/DebPackages.vala`, `controller/tab/Asset/SystemInfo.vala`).
- ✔️ 2026-11-13: Verified `meson compile -C build`, `meson test -C build` (6/6), `ninja -C build docs/valadoc`, `valac -C -D WINDOWS -D G_OS_WIN32`, and `Row.bin_write_prop` round-trip (`os_status = 0`, `1`, `-1`).

## Next

- ⏳ 🔷 Install `build/` (`sudo meson install -C build`), restart `argusrm-server` and `argusrm-controller`, verify package load latency and absence of `remove` criticals, and re-check whether `argusrm-server` still stalls on port `817`.
