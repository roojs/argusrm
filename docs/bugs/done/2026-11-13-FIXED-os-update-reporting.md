# Report OS update status in `SystemInfo.list` from `os_releases`

**Status:** ✅ closed 2026-11-13. `SystemInfo.list` SQL join, `Base.column_factory` status dots/dates, `Filters.SystemInfo`, and `docs/rpc-commands.md` are in the tree.

**Pointer:** `docs/bug-fix-process.md`. Split out of [2026-11-13-FIXED-os-updates.md](2026-11-13-FIXED-os-updates.md). Related: [5.11-REJECTED-os-update.md](../../plans/done/5.11-REJECTED-os-update.md).

---

## Problem

- 🔷 Clean `os_releases` (`platform`, `major`, `minor`) when `OsUpdate` loads `osinfo-query` so `SystemInfo.list` (`join = true`) uses a direct SQL `LEFT JOIN` and a simple subselect for the latest release date, with zero Vala post-processing and zero `LIKE` filtering.
- 🔷 Ignore LTS for now; report three simple states in `os_status`:
  - **Red (`0`)**: current OS release is past end of life (`eol < date('now')`).
  - **Orange (`2`)**: a newer release for that platform has been released (`MAX(released) <= date('now')` is later than `os_releases.released`).
  - **Green (`1`)**: up to date (neither EOL nor superseded).
  - **Hidden (`-1`)**: unchecked or unmatched.
- 🔷 Render the green / orange / red dot for `status` and `YYYY-MM-DD` for `date` in `Base.column_factory`, and wire `OS needs update` in `Filters.SystemInfo` to match red (`0`) and orange (`2`).
- 🔷 Document `os_updated`, `os_status`, and `reboot_required` on `SystemInfo.list` in `docs/rpc-commands.md`.

## Evidence

- ✔️ `shared/OsReleases.vala` and `server/OsUpdate.vala` currently store `version` as text without parsed `major` / `minor` columns and keep unreleased/variant rows (`released == ""`, `silverblue*`, `fedora-coreos*`, `centos-stream*`, `rhel-atomic*`, `almalinux-kitten*`) under the base `platform`.
- ✔️ `shared/OSQuery/SystemInfo.vala` (`list(bool join)`) joins `os_version` in one SQL `selectQuery` and does not yet join `os_releases` or `reboot_required`.
- ✔️ `controller/tab/Base.vala` (`column_factory`) currently creates an empty `Gtk.Image` for `status` and renders raw integer text for `date`.
- ✔️ `controller/filter/SystemInfo.vala` currently returns `false` whenever `this.status != ""`.
- ℹ️ Known osquery vs `osinfo-db` differences for follow-up if needed: Windows 11 and Windows Server 2016–2025 all report `major = 10, minor = 0` in osquery, and Rocky/AlmaLinux report point releases (`9.4`) while `osinfo-db` only carries major releases (`9`).

## Root cause

- ✔️ `os_releases` lacked numeric `major` / `minor` columns and variant cleanup at load time, and `SystemInfo.list` / `Base.column_factory` / `Filters.SystemInfo` were not yet wired to join, render, and filter them.

## Proposed fix

- 🔷 Add `major` and `minor` (`INTEGER`) to `shared/OsReleases.vala` (`CREATE TABLE` + `ALTER TABLE`) and `docs/plans/4.0-data-types.md`.
- 🔷 Add `platform_for(distro, short_id, name, default_platform)` helper in `server/OsUpdate.vala`, skip unreleased rows (`released == ""`), split variants (`fedora-silverblue`, `fedora-coreos`, `centos-stream`, `rhel-atomic`, `almalinux-kitten`, `windows-server`, `opensuse-tumbleweed`, `opensuse-leap`), and parse `major` / `minor` in `check_distro()`.
- 🔷 Join `os_releases` in `SystemInfo.list` (`shared/OSQuery/SystemInfo.vala`) on `(platform, major, minor)` with a `MAX(released)` subselect for `os_status`, and add overlaid `os_updated`, `os_status`, and `reboot_required` properties.
- 🔷 Update `controller/tab/Base.vala` and `controller/resources/style.css` to render `status` as a CSS dot (`.status-ok` green, `.status-warn` orange, `.status-bad` red) and format `date` as `YYYY-MM-DD`.
- 🔷 Update `controller/filter/SystemInfo.vala` so `OS needs update` keeps rows with `os_status` `0` or `2`.
- 🔷 Update `docs/rpc-commands.md` for `SystemInfo.list`.
- 🚫 Do not handle LTS rules (`is_lts`), Vala post-processing loops, or `LIKE` filtering in `SystemInfo.list`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### 1. `shared/OsReleases.vala` and `docs/plans/4.0-data-types.md` — add `major` and `minor`

**Why:** allow `SystemInfo.list` to join `os_releases` directly on `(platform, major, minor)` without string parsing in SQL.

**Where:** properties and `init_db()` in `shared/OsReleases.vala`, and `OS releases` in `docs/plans/4.0-data-types.md`.

**Depends on:** none.

#### `shared/OsReleases.vala` — Add after `version` property

```vala
		/**
		 * Numeric major version parsed from {@link version}.
		 */
		public int major { get; set; default = 0; }
		/**
		 * Numeric minor version parsed from {@link version}.
		 */
		public int minor { get; set; default = 0; }
```

#### `shared/OsReleases.vala` — Remove (`init_db`)

```vala
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
```

#### `shared/OsReleases.vala` — Replace with (`init_db`)

```vala
			var ddl = """
				CREATE TABLE IF NOT EXISTS os_releases (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					short_id TEXT NOT NULL DEFAULT '',
					distro   TEXT NOT NULL DEFAULT '',
					platform TEXT NOT NULL DEFAULT '',
					family   TEXT NOT NULL DEFAULT '',
					name     TEXT NOT NULL DEFAULT '',
					version  TEXT NOT NULL DEFAULT '',
					major    INTEGER NOT NULL DEFAULT 0,
					minor    INTEGER NOT NULL DEFAULT 0,
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
			db.db.exec("ALTER TABLE os_releases ADD COLUMN major INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
			db.db.exec("ALTER TABLE os_releases ADD COLUMN minor INTEGER NOT NULL DEFAULT 0;", null, out errmsg);
```

#### `docs/plans/4.0-data-types.md` — Remove

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

#### `docs/plans/4.0-data-types.md` — Replace with

```
id                    INTEGER
short_id              TEXT
distro                TEXT
platform              TEXT
family                TEXT
name                  TEXT
version               TEXT
major                 INTEGER
minor                 INTEGER
codename              TEXT
released              TEXT
eol                   TEXT
is_lts                INTEGER
updated               INTEGER
```

### 2. `server/OsUpdate.vala` — clean `platform`, `major`, `minor` in `check_distro`

**Why:** normalize `platform` via `platform_for()`, skip unreleased entries, and parse `major` / `minor` once at load time.

**Where:** `platform_for()` after `distro_for()`, and the row loop in `check_distro()` in `server/OsUpdate.vala`.

**Depends on:** ### 1.

#### Add — after `distro_for`

```vala
		/**
		 * Resolve the cleaned ''platform'' for one ''osinfo-query'' row.
		 *
		 * Splits product variants into distinct ''platform'' values so
		 * ''os_releases'' does not mix separate release tracks.
		 *
		 * @param distro ''osinfo-query'' distribution key
		 * @param short_id unique ''osinfo-query'' short identifier
		 * @param name full OS release name
		 * @param fallback default ''os_version.platform''
		 * @return cleaned platform name
		 */
		public string platform_for(string distro, string short_id, string name, string fallback)
		{
			switch (distro) {
				case "opensuse":
					return short_id == "opensusetumbleweed" ? "opensuse-tumbleweed" : "opensuse-leap";

				case "win":
					return name.contains("Server") ? "windows-server" : "windows";

				case "fedora":
					if (short_id.has_prefix("silverblue")) {
						return "fedora-silverblue";
					}
					if (short_id.has_prefix("fedora-coreos")) {
						return "fedora-coreos";
					}
					return fallback;

				case "centos":
					return short_id.has_prefix("centos-stream") ? "centos-stream" : fallback;

				case "rhel":
					return short_id.has_prefix("rhel-atomic") ? "rhel-atomic" : fallback;

				case "almalinux":
					return short_id.has_prefix("almalinux-kitten") ? "almalinux-kitten" : fallback;

				default:
					return fallback;
			}
		}
```

#### Remove (`check_distro`)

```vala
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
```

#### Replace with (`check_distro`)

```vala
				var short_id = fields[0].strip();
				var rel_ver = fields[2].strip();
				var rel_date = fields[5].strip();
				if (short_id == "" || short_id.has_suffix("-unknown") ||
					rel_ver == "unknown" || rel_date == "" || seen.has_key(short_id)) {
					continue;
				}
				seen.set(short_id, true);
				var rel_name = fields[1].strip();
				var rel_distro = fields[4].strip();
				var ver_parts = rel_ver.split(".");
				var newer = new Argus.Shared.OsReleases() {
					short_id = short_id,
					distro = rel_distro != "" ? rel_distro : distro,
					platform = this.platform_for(distro, short_id, rel_name, platform),
					family = fields[3].strip(),
					name = rel_name,
					version = rel_ver,
					major = ver_parts.length > 0 ? int.parse(ver_parts[0]) : 0,
					minor = ver_parts.length > 1 ? int.parse(ver_parts[1]) : 0,
					codename = fields[7].strip(),
					released = rel_date,
					eol = fields[6].strip(),
					is_lts = rel_name.contains("LTS") ? 1 : 0,
					updated = fetched
				};
```

### 3. `shared/OSQuery/SystemInfo.vala` — SQL join for `os_updated`, `os_status`, and `reboot_required`

**Why:** join `os_releases` directly on `(platform, major, minor)` and use a simple `MAX(released)` subselect for `os_status`.

**Where:** `list()` (`if (join)` branch) and overlaid properties after `arch` in `shared/OSQuery/SystemInfo.vala`.

**Depends on:** ### 1 and ### 2.

#### Remove

```vala
			if (join) {
				var columns = string.joinv(", ", query.getColsExcept(null, "system_info."));
				query.selectQuery(@"
					SELECT 
						$(columns),
						trim(COALESCE(os_version.name, '') || ' ' ||
							COALESCE(os_version.version, '')) as operating_system,
						CAST(os_version.major AS TEXT) as major,
						CAST(os_version.minor AS TEXT) as minor,
						CAST(os_version.patch AS TEXT) as patch,
						os_version.build as build,
						os_version.platform as platform,
						os_version.platform_like as platform_like,
						os_version.codename as codename,
						os_version.arch as arch,
						COALESCE((
							SELECT GROUP_CONCAT(DISTINCT logged_in_users.user)
							FROM logged_in_users
							WHERE logged_in_users.agent_id = system_info.agent_id
							AND logged_in_users.agent_id IN (SELECT id FROM agent)
							AND logged_in_users.user != ''
						), '') as logged_in_users
					FROM 
						system_info
					LEFT JOIN 
						os_version
					ON 
						os_version.agent_id = system_info.agent_id
						AND os_version.agent_id IN (SELECT id FROM agent)
					WHERE
						system_info.agent_id IN (SELECT id FROM agent)
					",rows);
			}
```

#### Replace with

```vala
			if (join) {
				var columns = string.joinv(", ", query.getColsExcept(null, "system_info."));
				query.selectQuery(@"
					SELECT 
						$(columns),
						trim(COALESCE(os_version.name, '') || ' ' ||
							COALESCE(os_version.version, '')) as operating_system,
						CAST(os_version.major AS TEXT) as major,
						CAST(os_version.minor AS TEXT) as minor,
						CAST(os_version.patch AS TEXT) as patch,
						os_version.build as build,
						os_version.platform as platform,
						os_version.platform_like as platform_like,
						os_version.codename as codename,
						os_version.arch as arch,
						COALESCE(os_version.reboot_required, 0) as reboot_required,
						COALESCE((
							SELECT MAX(updated)
							FROM os_releases
							WHERE platform = os_version.platform
						), 0) as os_updated,
						CASE
							WHEN os_releases.id IS NULL THEN -1
							WHEN os_releases.eol != '' AND os_releases.eol < date('now') THEN 0
							WHEN (
								SELECT MAX(released)
								FROM os_releases
								WHERE platform = os_version.platform
								AND released <= date('now')
							) > os_releases.released THEN 2
							ELSE 1
						END as os_status,
						COALESCE((
							SELECT GROUP_CONCAT(DISTINCT logged_in_users.user)
							FROM logged_in_users
							WHERE logged_in_users.agent_id = system_info.agent_id
							AND logged_in_users.agent_id IN (SELECT id FROM agent)
							AND logged_in_users.user != ''
						), '') as logged_in_users
					FROM 
						system_info
					LEFT JOIN 
						os_version
					ON 
						os_version.agent_id = system_info.agent_id
						AND os_version.deleted_dt = 0
						AND os_version.agent_id IN (SELECT id FROM agent)
					LEFT JOIN
						os_releases
					ON
						os_releases.platform = os_version.platform
						AND os_releases.major = os_version.major
						AND os_releases.minor = os_version.minor
					WHERE
						system_info.agent_id IN (SELECT id FROM agent)
					", rows);
			}
```

#### Add — after `arch` on `SystemInfo`, the three overlaid properties

```vala
		/**
		 * Unix time the server last synced this host's platform releases.
		 *
		 * ''0'' when unchecked or not in ''os_releases''.
		 */
		public int os_updated { get; set; default = 0; }
		/**
		 * Joined OS release status for the grid.
		 *
		 * ''1'' up to date, ''2'' update available, ''0'' EOL,
		 * and ''-1'' when unchecked or unmatched.
		 */
		public int os_status { get; set; default = -1; }
		/**
		 * Windows restart waiting on this host.
		 *
		 * ''1'' when waiting. ''0'' otherwise.
		 */
		public int reboot_required { get; set; default = 0; }
```

### 4. `controller/tab/Base.vala` and `controller/resources/style.css` — `status` dot and `date` cells

**Why:** render green (`1`), orange (`2`), and red (`0`) circles for `status` and `YYYY-MM-DD` for `date`.

**Where:** `setup` and `bind` inside `Base.column_factory`, and dot styles at the end of `controller/resources/style.css`.

**Depends on:** ### 3.

#### `controller/tab/Base.vala` — Remove (`setup`)

```vala
					case "status":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true
						};
						break;
```

#### `controller/tab/Base.vala` — Replace with (`setup`)

```vala
					case "status":
						item.child = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							css_classes = { "status-dot" },
							halign = Gtk.Align.CENTER,
							valign = Gtk.Align.CENTER,
							visible = false
						};
						break;
```

#### `controller/tab/Base.vala` — Remove (`bind`)

```vala
				switch (format) {
					case "status":
						break;
```

#### `controller/tab/Base.vala` — Replace with (`bind`)

```vala
				switch (format) {
					case "status":
						var flag = -1;
						if (prop.value_type == GLib.Type.INT) {
							flag = value.get_int();
						}
						var dot = (Gtk.Box) item.child;
						dot.remove_css_class("status-ok");
						dot.remove_css_class("status-warn");
						dot.remove_css_class("status-bad");
						dot.visible = flag == 0 || flag == 1 || flag == 2;
						switch (flag) {
							case 1:
								dot.add_css_class("status-ok");
								break;

							case 2:
								dot.add_css_class("status-warn");
								break;

							case 0:
								dot.add_css_class("status-bad");
								break;

							default:
								break;
						}
						break;

					case "date":
						var stamp = (int64) 0;
						if (prop.value_type == GLib.Type.INT64) {
							stamp = value.get_int64();
						}
						if (prop.value_type == GLib.Type.INT) {
							stamp = (int64) value.get_int();
						}
						var date_text = "";
						if (stamp > 0) {
							var when = new GLib.DateTime.from_unix_local(stamp);
							if (when != null) {
								var formatted = when.format("%Y-%m-%d");
								date_text = formatted != null ? formatted : "";
							}
						}
						((Gtk.Label) item.child).label = date_text;
						break;
```

#### `controller/resources/style.css` — Add at end of file

```css

.status-dot {
	min-width: 12px;
	min-height: 12px;
	border-radius: 6px;
}

.status-dot.status-ok {
	background-color: #2ec27e;
}

.status-dot.status-warn {
	background-color: #ff7800;
}

.status-dot.status-bad {
	background-color: #c01c28;
}
```

### 5. `controller/filter/SystemInfo.vala` — `OS needs update`

**Why:** the Status dropdown's `OS needs update` choice keeps machines with an update available (`2`) or EOL (`0`).

**Where:** `status` docblock, `match` docblock, and the start of `match`.

**Depends on:** ### 3.

#### Remove

```vala
		/**
		 * Empty means every row. A choice keeps machines that need that update. Nothing matches yet.
		 */
		public string status { get; set; default = ""; }
```

#### Replace with

```vala
		/**
		 * Empty means every row. ''OS needs update'' keeps rows with
		 * ''os_status == 0'' or ''os_status == 2''.
		 */
		public string status { get; set; default = ""; }
```

#### Remove

```vala
		 *  * A set Status keeps machines that need that update. Nothing matches yet.
		 *
		 * @param item a ''system_info'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			if (this.status != "") {
				return false;
			}
			var row = (Argus.Shared.OSQuery.SystemInfo) item;
```

#### Replace with

```vala
		 *  * ''OS needs update'' keeps rows with ''os_status'' ''0'' or ''2''.
		 *
		 * @param item a ''system_info'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.SystemInfo) item;
			switch (this.status) {
				case "":
					break;

				case "OS needs update":
					switch (row.os_status) {
						case 0:
						case 2:
							break;

						default:
							return false;
					}
					break;

				default:
					return false;
			}
```

### 6. `docs/rpc-commands.md` — `SystemInfo.list` fields

**Why:** document the joined `os_updated`, `os_status`, and `reboot_required` fields returned when `join` is true.

**Where:** `SystemInfo.list` bullet list.

**Depends on:** ### 3.

#### Remove

```markdown
- With the flag, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, and `arch`. `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
```

#### Replace with

```markdown
- With the flag, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `os_updated`, `os_status`, and `reboot_required`. `os_updated` and `os_status` come from `os_releases` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked or unmatched). `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
```

## Attempts / changelog

- ℹ️ 2026-11-13: Split `SystemInfo.list` OS status reporting and `docs/rpc-commands.md` out of [2026-11-13-FIXED-os-updates.md](2026-11-13-FIXED-os-updates.md).
- 🔷 2026-11-13: Replaced Vala post-processing in `SystemInfo.list` with normalized load-time columns (`product`, `major`, `minor`, `match_name`, `next_released`) on `os_releases`.
- 🔷 2026-11-13: Simplified `### 1`–`### 3`: extracted `platform_for()` helper in `OsUpdate.vala`, dropped `product` / `match_name` / `next_released` and the double-nested `foreach`, skipped unreleased rows (`released == ""`), and replaced the `SystemInfo.list` SQL with a direct `(platform, major, minor)` `LEFT JOIN` plus a `MAX(released)` subselect.
- ✔️ 2026-11-13: Applied `### 1`–`### 6` (`shared/OsReleases.vala`, `server/OsUpdate.vala`, `shared/OSQuery/SystemInfo.vala`, `controller/tab/Base.vala`, `controller/resources/style.css`, `controller/filter/SystemInfo.vala`, `docs/plans/4.0-data-types.md`, `docs/rpc-commands.md`). Tightened `platform_for()` signature and ternary returns to single lines and added blank lines after `break;` in `switch` blocks.
- ✔️ 2026-11-13: `ninja -C build`, `ninja -C build docs/valadoc`, and `meson test -C build` (6/6) passed. Verified `SystemInfo.list` SQL against a temporary SQLite database (`ubuntu 25.04` -> `0`, `ubuntu 24.04` -> `2`, `debian 12` -> `1`, `android` -> `-1`).
- ✅ 2026-11-13: User closed as fixed.

## Next

- ✅ Closed. `SystemInfo.list` SQL join, `Base.column_factory` status dots and dates, `Filters.SystemInfo`, and `docs/rpc-commands.md` are in the tree.
