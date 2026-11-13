# Windows agent shows no packages in controller

**Status:** ✅ fixed (`### 1`–`### 3` verified); follow-up `osquery.msi` launch fix closed in [2026-11-13-FIXED-windows-missing-gspawn-helper.md](2026-11-13-FIXED-windows-missing-gspawn-helper.md)

**Pointer:** `docs/bug-fix-process.md`. Related: [2026-11-13-FIXED-package-updates.md](2026-11-13-FIXED-package-updates.md) (notes `Package.sync` test failure).

---

## Problem

- 🔷 Windows agent (`0.1.15`) installs and pairs with the server, but the controller's Software -> Windows tab shows no packages.
- 🔷 Need to determine whether the database has no `programs` rows or the controller cannot read them.

## Evidence

- ✔️ `/var/log/argusrm/server.log` (run started `17:59:34`):
  - `18:22:34.825` received `Agent.request_registration` and added `192.168.88.244` to port `817` allowlist (`NFTables.vala:174`).
  - No `OSQuery.sync` call arrived in `server.log` after registration.
  - `18:22:55`, `18:22:59`, `18:23:00`, `18:23:03` received `Programs.list` from the controller. Each reply emitted `type id '0' is invalid` / `cannot initialize GValue with type '(null)'`, which `OLLMrpc` logs when returning an empty `Gee.ArrayList` (same as `RpmPackages.list` and `ScriptRepository.list`; `DebPackages.list` has rows and did not emit these criticals).
- ✔️ `~/.cache/argusrm/controller.log`:
  - `18:22:34.839` received `event.pair`, followed by `event.agent` notifications (`18:22:34.869`, `18:22:34.890`), showing the agent opened the app socket connection on `817`.
  - All four `Programs.list` requests received normal replies without controller-side deserialization errors.
- ✔️ `agent/Win32/Service.vala` (`tick()`):
  - After pairing succeeds (`attach == true`), line 381 calls only `this.application.attach_connection();`.
  - `OSQuery.Initialize.start()`, `osquery.send_startup()`, and `PackageMonitor.start()` only run in `agent/Application.vala` (`command_line()`) when `client.pem` already exists at process startup. On fresh Windows registration, the service stays running without restarting, so `osqueryi` is never downloaded/installed and no initial `OSQuery.sync` (`SystemInfo`, `OsVersion`, `Programs`, etc.) is sent until the service is restarted.
- ✔️ `shared/OSQuery/Package.vala` (`sync()`):
  - Line 58 creates `new SQ.Query<Package>(db, this.table_name())` where `Package` is `public abstract class Package : Row`.
  - `SQ.Query<T>` instantiates `typeof(T)` when reading rows back in `selectWhere`, which aborts GLib with `cannot create instance of abstract (non-instantiatable) type 'ArgusSharedOSQueryPackage'`.
  - ✔️ Confirmed in `build/meson-logs/testlog.txt`: test `6/6 packages` (`argus-packages-test`) fails with `killed by signal 5 SIGTRAP` on that exact error. `/usr/bin/argusrm-server` (built `Nov 12 17:44`) contains this code, so any `OSQuery.sync` for `Programs`, `DebPackages`, or `RpmPackages` will abort the server process.
- ℹ️ Controller UI (`controller/resources/columns/programs.csv`, `controller/store/Programs.vala`, `controller/tab/Asset/Programs.vala`, and `shared/OSQuery/Programs.vala`) property names match (`name`, `publisher`, `min-version`, `max-version`, `installed`, `uninstall-count`, etc.). No controller-side `Programs` mismatch was found.
- ℹ️ `/var/lib/argusrm/` is mode `0700` owned by `nobody`, so `argus.sqlite` was not opened directly; log evidence already confirms `programs` has no synced rows.
- ✔️ `snappr-win` (`C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache\argusrm\agent.log` and `C:\Program Files\osquery`):
  - `18:22:34.868` `Service.vala:288: registration 0`, `18:22:34.902` `Application.vala:255: watching the server connection`, followed only by `event.agent` and two-minute download socket probes.
  - `C:\Program Files\osquery` does not exist — `OSQuery.Initialize` never ran after pairing.

## Root cause

- ✔️ **Database has no `programs` rows (not a controller read failure)** for two compounding reasons:
  1. `agent/Win32/Service.vala` attaches the TLS connection after pairing without running `OSQuery.Initialize`, `osquery.send_startup()`, or `PackageMonitor.start()`, so a newly paired Windows agent sends no osquery tables until a service restart.
  2. `shared/OSQuery/Package.vala` instantiates `SQ.Query<Package>` on the abstract `Package` base class instead of a generic concrete row type `T` (matching `Row.sync_rows<T>`), which aborts `argusrm-server` as soon as any `Programs`, `DebPackages`, or `RpmPackages` snapshot is synced.

## Proposed fix

- 🔷 Run `OSQuery.Initialize`, `osquery.send_startup()`, and `PackageMonitor.start()` in `agent/Win32/Service.vala` right after `attach_connection()` succeeds on registration.
- 🔷 Refactor `Package.sync` in `shared/OSQuery/Package.vala` to `protected bool sync_packages<T>(...)` (the same generic pattern as `Row.sync_rows<T>`) and have `DebPackages`, `RpmPackages`, and `Programs` override `sync` to call `this.sync_packages<Self>(...)`.
- 🚫 Do not silence or guard `SQ.Query<Package>` around the abstract class; pass the concrete subclass type via `T`.

### 1. `agent/Win32/Service.vala` — start osquery after Windows pairing

**Why:** newly registered Windows agents stay running in the service process and never run `command_line()`'s existing-cert branch.

**Where:** `tick()`, inside `if (attach)`.

**Depends on:** none.

#### Remove

```vala
			if (attach) {
				this.application.attach_connection();
			}
```

#### Replace with

```vala
			if (attach) {
				this.application.attach_connection();
			}
			if (attach && this.application.connection != null) {
				new Argus.Agent.OSQuery.Initialize(this.application).start();
				this.application.osquery.send_startup();
				this.application.monitor = new Argus.Agent.PackageMonitor(this.application);
				this.application.monitor.start();
			}
```

### 2. `shared/OSQuery/Package.vala` — use concrete type parameter `T` in `SQ.Query<T>`

**Why:** `SQ.Query<Package>` tries to instantiate the abstract class `ArgusSharedOSQueryPackage` in `selectWhere`, aborting the server and `argus-packages-test`.

**Where:** `shared/OSQuery/Package.vala` (`sync` -> `protected bool sync_packages<T>`), plus `sync` overrides on `DebPackages`, `RpmPackages`, and `Programs`.

**Depends on:** none.

#### Remove

```vala
		/**
		 * Apply one package snapshot.
		 *
		 * The instance is the row class. {@link table_name} is
		 * the stored table. {@link pkg_name} is the hash key.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows complete table snapshot
		 * @return true when every row has this class
		 */
		public override bool sync(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != this.get_type()) {
					return false;
				}
			}
			var query = new SQ.Query<Package>(db, this.table_name());
			var stored = new Gee.ArrayList<Package>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var index = new Gee.HashMap<string, Package>();
			foreach (var old in stored) {
				var key = old.pkg_name();
				if (!index.has_key(key)) {
					index.set(key, old);
				}
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in rows) {
				var pkg = (Package) row;
				var key = pkg.pkg_name();
				var old = index.get(key);
				var newer = (Row) row;
				newer.agent_id = agent_id;
				if (old == null) {
					newer.id = 0;
					newer.added_dt = now;
					newer.updated_dt = 0;
					newer.deleted_dt = 0;
					query.insert(pkg);
					continue;
				}
				newer.id = old.id;
				newer.added_dt = old.added_dt;
				if (old.deleted_dt != 0) {
					newer.deleted_dt = 0;
					newer.updated_dt = now;
					query.updateOld(old, pkg);
					index.unset(key);
					continue;
				}
				newer.deleted_dt = 0;
				if (!old.compare(newer)) {
					newer.updated_dt = now;
					query.updateOld(old, pkg);
				}
				index.unset(key);
			}
			foreach (var old in index.values) {
				if (old.deleted_dt != 0) {
					continue;
				}
				old.deleted_dt = now;
				query.updateById(old);
			}
			return true;
		}
```

#### Replace with

```vala
		/**
		 * Apply one package snapshot.
		 *
		 * ''T'' is the concrete row class. {@link table_name} is
		 * the stored table. {@link pkg_name} is the hash key.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows complete table snapshot
		 * @return true when every row has type ''T''
		 */
		protected bool sync_packages<T>(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != typeof(T)) {
					return false;
				}
			}
			var query = new SQ.Query<T>(db, this.table_name());
			var stored = new Gee.ArrayList<T>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var index = new Gee.HashMap<string, Package>();
			foreach (var old in stored) {
				var pkg = (Package) old;
				var key = pkg.pkg_name();
				if (!index.has_key(key)) {
					index.set(key, pkg);
				}
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in rows) {
				var pkg = (Package) row;
				var key = pkg.pkg_name();
				var old = index.get(key);
				var newer = (Row) row;
				newer.agent_id = agent_id;
				if (old == null) {
					newer.id = 0;
					newer.added_dt = now;
					newer.updated_dt = 0;
					newer.deleted_dt = 0;
					query.insert((T) row);
					continue;
				}
				newer.id = old.id;
				newer.added_dt = old.added_dt;
				if (old.deleted_dt != 0) {
					newer.deleted_dt = 0;
					newer.updated_dt = now;
					query.updateOld((T) old, (T) row);
					index.unset(key);
					continue;
				}
				newer.deleted_dt = 0;
				if (!old.compare(newer)) {
					newer.updated_dt = now;
					query.updateOld((T) old, (T) row);
				}
				index.unset(key);
			}
			foreach (var old in index.values) {
				if (old.deleted_dt != 0) {
					continue;
				}
				old.deleted_dt = now;
				query.updateById((T) old);
			}
			return true;
		}
```

### 3. `shared/OSQuery/DebPackages.vala`, `RpmPackages.vala`, `Programs.vala` — delegate `sync` to `sync_packages<T>`

**Why:** each concrete package subclass supplies its own `GType` to `sync_packages<T>`.

**Where:** right after `private static SQ.Database db;` in each of the three files.

**Depends on:** ### 2.

#### `shared/OSQuery/DebPackages.vala` — Add

```vala
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_packages<DebPackages>(db, agent_id, rows);
		}
```

#### `shared/OSQuery/RpmPackages.vala` — Add

```vala
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_packages<RpmPackages>(db, agent_id, rows);
		}
```

#### `shared/OSQuery/Programs.vala` — Add

```vala
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_packages<Programs>(db, agent_id, rows);
		}
```

## Attempts / changelog

- ℹ️ 2026-11-13: Diagnosed from `/var/log/argusrm/server.log`, `~/.cache/argusrm/controller.log`, `build/meson-logs/testlog.txt`, and source inspection.
- ✔️ 2026-11-13: Applied `### 1`–`### 3` (`agent/Win32/Service.vala` was later refactored in [2026-11-13-FIXED-windows-tray-waiting-for-service.md](2026-11-13-FIXED-windows-tray-waiting-for-service.md) so `OSQuery.Initialize` runs from `Service.register` and deferred `Application.command_line`). `ninja -C build`, `ninja -C build docs/valadoc`, and `meson test -C build` (6/6, including `packages`) passed.
- ✔️ 2026-11-13: Rebuilt `/usr/bin/argusrm-server` and verified `0.1.17` on `snappr-win`: `argus-agent` ran `OSQuery.Initialize` and downloaded `C:\Windows\Temp\osquery.msi` (20.8 MB). Installing `osquery.msi` failed with `Failed to execute helper program (No such file or directory)` — split out to [2026-11-13-FIXED-windows-missing-gspawn-helper.md](2026-11-13-FIXED-windows-missing-gspawn-helper.md).

## Next

- ✅ Closed (verified end-to-end on `0.1.19` with `Programs` syncing to the server).
