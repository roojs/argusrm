# Machines `OS status` / `S/W status` tooltips and `pkgs_status` reporting

**Status:** ✔️ implemented (`PackageUpdates.sync`, `SystemInfo.list`, `Base.column_factory` tooltips, `Filters.SystemInfo`, `PackageMonitor`); compiled & 6/6 tests pass, awaiting live UI check

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-os-update-reporting.md](done/2026-11-13-FIXED-os-update-reporting.md), [2026-11-13-FIXED-package-updates.md](done/2026-11-13-FIXED-package-updates.md), [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md)

---

## Problem

- 🔷 On the Machines grid (`controller/tab/Asset/SystemInfo.vala`), this machine (`Ubuntu 25.04`) displays a red circle in `OS status`, with no mouseover tooltip explaining whether it is end of life or what state the machine is in.
- 🔷 Both `OS status` (`os-status`) and `S/W status` (`pkgs-status`) need mouseover tooltips indicating the machine's state so the status dot has clear meaning.
- 🔷 `S/W status` (`pkgs-status`) is currently not working at all (blank for every machine).

---

## Evidence

- ✔️ Checked local host OS and `osinfo-query` (`2026-11-14`):
  - Host runs `Ubuntu 25.04` (`Plucky Puffin`, `major = 25`, `minor = 4`).
  - `osinfo-query` (`ubuntu25.04`) reports `Release date = 2025-04-17`, `End of life = 2026-01-15`. Because `2026-01-15 < 2026-11-14`, `os_status == 0` (red) is genuinely end of life.
- ✔️ `controller/tab/Base.vala` (`column_factory`, `case "status":`) creates a 12×12 `Gtk.Box` (`.status-dot`) and sets `.status-ok` (`1`), `.status-warn` (`2`), or `.status-bad` (`0`), but never sets `tooltip_text`.
- ✔️ Reproduced `S/W status` failure in `/tmp/argus-status-probe.vala`:
  - `shared/OSQuery/PackageUpdates.vala` (`sync()`) updates `package_updates`, leaving `os_version.pkgs_updated = 0` and `os_version.pkgs_status = 0` even after syncing pending updates (`a1`) or zero updates (`a2`).
  - `shared/OSQuery/SystemInfo.vala` lacks `pkgs_updated`, `pkgs_status`, `pkgs_updates`, `os_eol`, and `os_latest` properties, and `SystemInfo.list(true)` does not select them (`find_property("pkgs-status") == null`).
  - `controller/filter/SystemInfo.vala` (`match()`) has no `case "S/W needs update":` (falls into `default: return false;`), even though `controller/tab/Asset/SystemInfo.vala` lists `"S/W needs update"` in the Status dropdown.
  - `agent/linux/PackageMonitor.vala` calls `send_pending()` on startup and every 12 hours, but not after `apt()` / `rpm()` rescans (`send_packages()`).
- ✔️ Verified the proposed `PackageUpdates.sync` `os_version` update and `SystemInfo.list(true)` SQL in `/tmp/argus-status-probe.vala` against a temporary SQLite database:
  - `a1` (`Ubuntu 25.04`, 2 pending packages): `os_status = 0`, `os_eol = '2026-01-15'`, `pkgs_updated > 0`, `pkgs_updates = 2`, `pkgs_status = 0`.
  - `a2` (`Ubuntu 24.04`, 0 pending packages): `os_status = 2`, `os_eol = '2034-04-25'`, `os_latest = '25.04'`, `pkgs_updated > 0`, `pkgs_updates = 0`, `pkgs_status = 1`.
  - `a3` (Windows 11, unchecked): `os_status = -1`, `pkgs_updated = 0`, `pkgs_updates = 0`, `pkgs_status = -1`.

---

## Root cause

- ✔️ `Base.column_factory` renders `status` dots without a cell wrapper or `tooltip_text`, and `SystemInfo` / `SystemInfo.list(true)` lacked `os_eol` / `os_latest` context for `os-status` tooltips.
- ✔️ `PackageUpdates.sync` did not record `pkgs_updated` / `pkgs_status` on `os_version`, `SystemInfo.list(true)` did not select `pkgs_updated` / `pkgs_status` / `pkgs_updates`, and `Filters.SystemInfo` omitted `"S/W needs update"`.

---

## Proposed fix

- 🔷 Update `shared/OSQuery/PackageUpdates.vala` (`sync()`) to write `pkgs_updated = now` and `pkgs_status = (seen.size == 0 ? 1 : 0)` onto matching `os_version` rows (`deleted_dt = 0`).
- 🔷 Extend `shared/OSQuery/SystemInfo.vala` (`list(true)` + properties) with `os_eol`, `os_latest`, `pkgs_updated`, `pkgs_updates`, and `pkgs_status` (`-1` when `pkgs_updated == 0` or no `os_version` row, `0` when `package_updates` has rows, `1` when checked with zero pending updates), plus derived `tooltip_os_status` and `tooltip_pkgs_status` properties (`owned get`, omitted on the wire and in `AgentInfo.compare` via `GLib.ParamFlags.WRITABLE`).
- 🔷 Update `controller/tab/Base.vala` (`column_factory`, `case "status":`) generically to wrap the centered `.status-dot` in a full-cell `Gtk.Box` and set `cell.tooltip_text` from the row's `tooltip-<name>` string property when present (`null` when empty/absent).
- 🔷 Update `controller/filter/SystemInfo.vala` to handle `"S/W needs update"` (`row.pkgs_status == 0`).
- 💩 Call `this.send_pending()` after `this.application.osquery.send_packages()` in `agent/linux/PackageMonitor.vala` (`apt()` / `rpm()`).
- 🔷 Update `docs/rpc-commands.md` for the new `SystemInfo.list` fields and `server/tests/packages.vala` to test `PackageUpdates.sync` -> `os_version` and `SystemInfo.list(true)`.

### 1. `shared/OSQuery/PackageUpdates.vala` — update `os_version.pkgs_updated` and `pkgs_status`

**Why:** distinguish an agent checked with zero pending updates (`pkgs_updated > 0`, `pkgs_status = 1`) from an unchecked or unsupported host (`pkgs_updated = 0`).

**Where:** end of `PackageUpdates.sync()` in `shared/OSQuery/PackageUpdates.vala`.

#### Remove

```vala
			foreach (var old in index.values) {
				query.deleteId(old.id);
			}
			return true;
```

#### Replace with

```vala
			foreach (var old in index.values) {
				query.deleteId(old.id);
			}
			var os_query = new SQ.Query<OsVersion>(db, "os_version");
			var os_rows = new Gee.ArrayList<OsVersion>();
			os_query.selectWhere(
				"WHERE agent_id = $agent_id AND deleted_dt = 0",
				int_binds, null, os_rows);
			foreach (var os_row in os_rows) {
				var updated_os = new OsVersion();
				updated_os.copy_from(os_row, {});
				updated_os.pkgs_updated = now;
				updated_os.pkgs_status = seen.size == 0 ? 1 : 0;
				os_query.updateOld(os_row, updated_os);
			}
			return true;
```

### 2. `shared/OSQuery/SystemInfo.vala` — select `os_eol`, `os_latest`, `pkgs_updated`, `pkgs_updates`, and `pkgs_status`

**Why:** provide `pkgs_status` / `pkgs_updated` for the Machines grid and release/update context for status tooltips.

**Where:** `SystemInfo.list(true)` and overlaid properties in `shared/OSQuery/SystemInfo.vala`.

#### Remove

```vala
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
```

#### Replace with

```vala
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
						COALESCE(os_releases.eol, '') as os_eol,
						COALESCE((
							SELECT version
							FROM os_releases
							WHERE platform = os_version.platform
							AND released <= date('now')
							ORDER BY released DESC
							LIMIT 1
						), '') as os_latest,
						COALESCE(os_version.pkgs_updated, 0) as pkgs_updated,
						(
							SELECT COUNT(*)
							FROM package_updates
							WHERE package_updates.agent_id = system_info.agent_id
						) as pkgs_updates,
						CASE
							WHEN os_version.id IS NULL OR os_version.pkgs_updated = 0 THEN -1
							WHEN EXISTS (
								SELECT 1
								FROM package_updates
								WHERE package_updates.agent_id = system_info.agent_id
							) THEN 0
							ELSE 1
						END as pkgs_status,
```

#### Add — after `os_status` property in `shared/OSQuery/SystemInfo.vala`

```vala
		/**
		 * Matched release end-of-life date in ''YYYY-MM-DD'' format.
		 *
		 * Empty when unknown or unmatched. Not stored on ''system_info''.
		 */
		public string os_eol { get; set; default = ""; }
		/**
		 * Latest released version string for this host's platform.
		 *
		 * Empty when unmatched. Not stored on ''system_info''.
		 */
		public string os_latest { get; set; default = ""; }
		/**
		 * Unix time this host last synced pending package updates.
		 *
		 * ''0'' when unchecked. Not stored on ''system_info''.
		 */
		public int pkgs_updated { get; set; default = 0; }
		/**
		 * Joined package update status for the grid.
		 *
		 * ''1'' up to date, ''0'' updates available, and ''-1'' when
		 * unchecked or unsupported. Not stored on ''system_info''.
		 */
		public int pkgs_status { get; set; default = -1; }
		/**
		 * Number of pending package updates stored for this host.
		 *
		 * Not stored on ''system_info''.
		 */
		public int pkgs_updates { get; set; default = 0; }
		/**
		 * Mouseover text for {@link os_status} in the Machines grid.
		 *
		 * Derived from {@link os_status}, {@link os_eol}, and
		 * {@link os_latest}. Not stored or sent on the wire.
		 */
		public string tooltip_os_status {
			owned get {
				switch (this.os_status) {
					case 0:
						return "End of life (" + this.os_eol + ")";

					case 2:
						return "Update available (" + this.os_latest + ")";

					case 1:
						if (this.os_eol != "") {
							return "Up to date (EOL " + this.os_eol + ")";
						}
						return "Up to date";

					default:
						return "";
				}
			}
		}
		/**
		 * Mouseover text for {@link pkgs_status} in the Machines grid.
		 *
		 * Derived from {@link pkgs_status} and {@link pkgs_updates}.
		 * Not stored or sent on the wire.
		 */
		public string tooltip_pkgs_status {
			owned get {
				switch (this.pkgs_status) {
					case 0:
						if (this.pkgs_updates == 1) {
							return "1 package update available";
						}
						return this.pkgs_updates.to_string() + " package updates available";

					case 1:
						return "Packages up to date";

					default:
						return "";
				}
			}
		}
```

### 3. `controller/tab/Base.vala`, `shared/OSQuery/Row.vala`, and `shared/OSQuery/AgentInfo.vala` — generic `tooltip-<name>` lookup on `status` cells

**Why:** keep `Tab.Base` completely generic with no column-specific logic, while allowing any `status` column to supply a `tooltip-<name>` derived string property on its row model (skipped by wire serialization and snapshot comparison).

**Where:** `column_factory` docblock, `setup`, and `bind` (`case "status":`) in `controller/tab/Base.vala`, `Row.bin_write_prop`, and `AgentInfo.compare`.

#### `controller/tab/Base.vala` — Remove

```vala
		 *  * ''status'' and ''tick'' are an image.
```

#### `controller/tab/Base.vala` — Replace with

```vala
		 *  * ''status'' is a centered circle. If the row has a
		 *    ''tooltip-<name>'' string property, it is used as the
		 *    mouseover tooltip.
		 *  * ''tick'' is an image.
```

#### `controller/tab/Base.vala` — Remove

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

#### `controller/tab/Base.vala` — Replace with

```vala
					case "status":
						var dot = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							css_classes = { "status-dot" },
							halign = Gtk.Align.CENTER,
							valign = Gtk.Align.CENTER,
							hexpand = true,
							visible = false
						};
						var cell = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
							hexpand = true,
							vexpand = true
						};
						cell.append(dot);
						item.child = cell;
						break;
```

#### `controller/tab/Base.vala` — Remove

```vala
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
```

#### `controller/tab/Base.vala` — Replace with

```vala
					case "status":
						var flag = -1;
						if (prop.value_type == GLib.Type.INT) {
							flag = value.get_int();
						}
						var cell = (Gtk.Box) item.child;
						var dot = (Gtk.Box) cell.get_first_child();
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
						cell.tooltip_text = null;
						var tip_prop = row.get_class().find_property("tooltip-" + name);
						if (tip_prop != null && tip_prop.value_type == GLib.Type.STRING) {
							var tip_val = GLib.Value(GLib.Type.STRING);
							row.get_property("tooltip-" + name, ref tip_val);
							var tip = tip_val.get_string();
							if (tip != null && tip != "") {
								cell.tooltip_text = tip;
							}
						}
						break;
```

### 4. `controller/filter/SystemInfo.vala` — `"S/W needs update"` filter

**Why:** wire the existing Status dropdown choice to `row.pkgs_status == 0`.

**Where:** `status`, `match` docblocks and `switch (this.status)` in `controller/filter/SystemInfo.vala`.

#### Remove

```vala
		/**
		 * Empty means every row. ''OS needs update'' keeps rows with
		 * ''os_status == 0'' or ''os_status == 2''.
		 */
		public string status { get; set; default = ""; }
```

#### Replace with

```vala
		/**
		 * Empty means every row. ''OS needs update'' keeps rows with
		 * ''os_status == 0'' or ''os_status == 2''. ''S/W needs update''
		 * keeps rows with ''pkgs_status == 0''.
		 */
		public string status { get; set; default = ""; }
```

#### Remove

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

#### Replace with

```vala
		 *  * ''OS needs update'' keeps rows with ''os_status'' ''0'' or ''2''.
		 *  * ''S/W needs update'' keeps rows with ''pkgs_status'' ''0''.
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

				case "S/W needs update":
					if (row.pkgs_status != 0) {
						return false;
					}
					break;

				default:
					return false;
			}
```

### 5. `agent/linux/PackageMonitor.vala` — refresh `PackageUpdates` after package rescans

**Why:** update `package_updates` and `pkgs_status` immediately after package installs or upgrades on Linux instead of waiting 12 hours.

**Where:** `apt()` and `rpm()` timeout callbacks in `agent/linux/PackageMonitor.vala`.

#### Remove

```vala
					this.application.osquery.send_packages();
					foreach (var fd in fds) {
						Posix.close(fd);
					}
```

#### Replace with

```vala
					this.application.osquery.send_packages();
					this.send_pending();
					foreach (var fd in fds) {
						Posix.close(fd);
					}
```

#### Remove

```vala
					this.application.osquery.send_packages();
					foreach (var held in fds) {
						Posix.close(held);
					}
```

#### Replace with

```vala
					this.application.osquery.send_packages();
					this.send_pending();
					foreach (var held in fds) {
						Posix.close(held);
					}
```

### 6. `docs/rpc-commands.md` & `server/tests/packages.vala`

**Why:** document the new `SystemInfo.list` fields and cover `PackageUpdates.sync` -> `os_version` and `SystemInfo.list(true)` in unit tests.

#### `docs/rpc-commands.md` — Remove

```markdown
- With the flag, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `os_updated`, `os_status`, and `reboot_required`. `os_updated` and `os_status` come from `os_releases` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked or unmatched). `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
```

#### `docs/rpc-commands.md` — Replace with

```markdown
- With the flag, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `os_updated`, `os_status`, `os_eol`, `os_latest`, `pkgs_updated`, `pkgs_status`, `pkgs_updates`, and `reboot_required`. `os_updated`, `os_status`, `os_eol`, and `os_latest` come from `os_releases` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked or unmatched). `pkgs_updated`, `pkgs_status`, and `pkgs_updates` come from `os_version` and `package_updates` (`1` up to date, `0` updates available, `-1` unchecked or unsupported). `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
```

---

## Attempts / changelog

- ✔️ 2026-11-14: Reproduced in `/tmp/argus-status-probe.vala`: `Ubuntu 25.04` is past EOL (`2026-01-15 < 2026-11-14`), `PackageUpdates.sync` left `os_version.pkgs_updated` / `pkgs_status` at `0`, `SystemInfo` lacked `pkgs-status` / `pkgs-updated` / `os-eol` / `os-latest` / `pkgs-updates`, and `Base.column_factory` set no tooltips on `status` dots.
- ✔️ 2026-11-14: Verified the `PackageUpdates.sync` `os_version` update and `SystemInfo.list(true)` SQL in `/tmp/argus-status-probe.vala`.
- ✔️ 2026-11-14: Applied ### 1–### 6 (`shared/OSQuery/PackageUpdates.vala`, `shared/OSQuery/SystemInfo.vala`, `controller/tab/Base.vala`, `controller/filter/SystemInfo.vala`, `agent/linux/PackageMonitor.vala`, `docs/rpc-commands.md`, `server/tests/packages.vala`) and removed `/tmp/argus-status-probe*`.
- ✔️ 2026-11-14: Moved tooltip formatting out of `controller/tab/Base.vala` into `SystemInfo.tooltip_os_status` / `tooltip_pkgs_status` (avoiding ternary string ownership and redundant empty-date/empty-count fallbacks), made `Base.column_factory` look up `tooltip-<name>` generically, and skipped non-writable derived properties in `Row.bin_write_prop` and `AgentInfo.compare`.
- ✔️ 2026-11-14: `ninja -C build` and `meson test -C build` (6/6) passed.

## Next

- ⏳ 🔷 Restart `argusrm-server`, `argusrm-agent`, and `argusrm-controller` from `build/` (or updated package) and verify `OS status` and `S/W status` dots and mouseover tooltips on the live Machines tab.
