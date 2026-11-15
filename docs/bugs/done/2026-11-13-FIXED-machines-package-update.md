# Machines multi-select right-click package update (script-backed task queue)

**Status:** ✔️ Phases 1–3 implemented (Data modelling, Controller UI skeletons, Server handler/default scripts/runner); Phase 4 split out → [2026-11-15-FIXED-machines-package-update-phase4-ui.md](2026-11-15-FIXED-machines-package-update-phase4-ui.md)

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/7.2-tasks-ui-and-signing.md`, `docs/plans/7.0-tasks.md`, `docs/plans/7.1-tasks-implementation.md`, `docs/plans/6.0-security-issues.md`, `docs/rpc-commands.md`, [2026-11-15-FIXED-machines-package-update-phase4-ui.md](2026-11-15-FIXED-machines-package-update-phase4-ui.md)

---

## Problem

- 🔷 On the Machines tab (`controller/tab/Asset/SystemInfo.vala`), select one or more machines and right-click **Update** or **Upgrade** to run library scripts matched by `(platform, app, action)` (e.g. `linux`/`apt`/`update`, `linux`/`apt`/`upgrade`, `linux`/`dnf`/`update`, `linux`/`dnf`/`upgrade`) auto-imported on the server from JSON resource catalogs.
- 🔷 Both actions must queue tasks on the server (`task` / `task_target`) and run selected machines concurrently (with per-machine queueing so each machine runs one task at a time).
- 🔷 Build the **Tasks** tab (`controller/Window.vala` currently has an empty `Gtk.Box` for `"tasks"`) to show queued, running, and completed tasks and open a terminal-style text viewer (black screen, white monospace text) for task stdin/stdout/stderr logs.
- 🔷 Incorporate signed-task support (`docs/plans/6.0-security-issues.md`) into the task data model and controller-to-server creation path.
- ℹ️ Earlier UI plans (`docs/plans/5.5-controller-user-interface.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/1.2-aim-debian-update.md`) placed Bulk update on Software; this adds machine-level Update and Upgrade on Machines and delivers the Tasks view.

---

## Evidence

✔️ Inventory of what is already in the tree vs what blocks this workflow:

- ✔️ `controller/tab/Asset/SystemInfo.vala` already uses `Gtk.MultiSelection` (`column_grid(rows, true)`), and `Argus.Shared.OSQuery.SystemInfo` carries `agent_id`, `platform`, and `platform_like` when loaded via `SystemInfo.list(true)`.
- 🚫 `controller/tab/Base.vala` (`column_menu`) attaches a `CAPTURE`-phase `Gdk.BUTTON_SECONDARY` gesture across the entire `this.grid` and `column_factory` does not tag row widgets, blocking row context menus.
- 🚫 `controller/Window.vala` renders an empty `Gtk.Box` for `"tasks"` — there is no Tasks tab, store, or terminal log viewer.
- ✔️ `task` (`shared/SQT/Task.vala`), `task_target` (`shared/SQT/TaskTarget.vala`), `server/SQT/Task.vala`, `server/SQT/Scheduler.vala`, and `server/Command.vala` are already in the tree and already run `script_id = 0` commands concurrently across machines while queueing `+60` s per busy machine.
- 🚫 `task` and `task_target` lack controller audit/signing columns and `log_dir`, there is no all-targets or log-read RPC, `Task.approve` rejects immediate `scheduled <= now`, `Task.finish` does not reschedule queued targets, `agent/linux/Command.vala` skips `Command.ended` on `spawnv` failure and lacks `send_lock` on `ended`, and `PackageMonitor.vala` does not call `send_pending()` after package rescans.

---

## Root cause

- ✔️ **UI:** `Base.column_menu` captures all secondary clicks on `this.grid`, `SystemInfo` has no row context menu or **Update** / **Upgrade** actions, and `controller/Window.vala` has no Tasks page or log viewer.
- ✔️ **Data & server/agent wiring:** `task` / `task_target` lack signing/audit and log-directory fields, the server lacks all-targets and log-read RPCs, and runner/agent edges (`Task.approve`, `Task.finish`, `agent/linux/Command.vala`, `PackageMonitor.vala`) affect multi-machine queued runs.

---

## Phased specification & proposed fix

### Phase 1 — Task data modelling ✔️ (`shared/SQT/`, `shared/OSQuery/`, `docs/plans/7.0-tasks.md`)

- **Already in tree:**
  - ✔️ `task` (`id`, `name`, `is_script`, `command`, `script_id`, `run_as`, `is_template`, `is_draft`, `scheduled`, `completed`) and `task_target` (`id`, `task_id`, `agent_id`, `scheduled`, `started`, `ended`, `success`, `is_cancelled`, `is_watched`, `timeout`, `identifier`) already exist in `Argus.Shared.SQT.init_db`.
- **Implemented:**
  - ✔️ Extended `task` (`shared/SQT/Task.vala`) with `created_by`, `approved_by`, `payload_hash`, `controller_sig`, `server_sig`, and `expires_at` (`CREATE TABLE` and `ALTER TABLE`).
  - ✔️ Extended `task_target` (`shared/SQT/TaskTarget.vala`) with `log_dir` (`CREATE TABLE` and `ALTER TABLE`) plus non-DB joined/display properties (`task_id_name`, `task_id_command`, `task_id_is_draft`, `task_id_scheduled`, `agent_id_hostname`, `display_task`, `display_state`, `display_started`, `display_duration`, `display_exit`, `dimmed`, with `bin_write_prop` omitting `display-*` and `dimmed`).
  - ✔️ Added `SystemInfo.package_manager()` (`shared/OSQuery/SystemInfo.vala`) delegating directly to `OsVersion.package_manager()` (`Argus.Shared.OSQuery.PackageManager`).
  - 🔷 Script-backed package actions (`(platform, app, action)`, replacing the earlier `script_id = 0` hardcoded command plan):
    - **Update:** `APT` -> `("linux", "apt", "update")` (`DEBIAN_FRONTEND=noninteractive apt-get update`); `DNF` -> `("linux", "dnf", "update")` (`dnf -y makecache --refresh`).
    - **Upgrade:** `APT` -> `("linux", "apt", "upgrade")` (`DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y upgrade`); `DNF` -> `("linux", "dnf", "upgrade")` (`dnf -y upgrade`).
    - 🔷 `WIN` / `UNKNOWN`: Windows has no package updater; do not offer Update or Upgrade when only unsupported machines are selected.
    - 🔷 `⏳` Extend `shared/SQT/Script.vala` (currently only `id`, `script_repository_id`, `path`, `filetype`) with `platform`, `app`, and `action` columns in Phase 3; dotted names are UI-only action-map keys on the controller, never stored or sent to the server.

### Phase 2 — Controller UI ✔️ (`controller/tab/`, `controller/filter/`, `controller/Window.vala`, `controller/resources/`)

**Depends on:** Phase 1 model properties.

- **Implemented:**
  - ✔️ `controller/tab/Base.vala`: tagged data-row cells (`argus-grid-row`), applied `.dim-label` when `dimmed` is true on a row, and restricted `column_menu` right-click capture to headers/empty grid space.
  - ✔️ `controller/tab/Asset/SystemInfo.vala`: wrapped `paned` in `Adw.ToastOverlay` and added row right-click `Gtk.PopoverMenu` (`row.update` / `row.upgrade`, hidden when only Windows/unknown machines are selected; action handlers deferred to Phase 4).
  - ✔️ `controller/filter/Tasks.vala` & `controller/tab/Tasks.vala` (mounted in `controller/Window.vala` for `"tasks"`): flat `task_targets` `ColumnView` with Search, State (`Active` default), Date range (`Any`/`Today`/`7 days`/`30 days`/From–To `Gtk.Calendar`), Refresh/Spinner, and copyable black-on-white `Gtk.TextView` terminal log viewer (`Start`, `Duration`, `Exit`, `State`).
  - ✔️ `controller/resources/columns/task_targets.csv` & `controller/resources/style.css` (`.tool-output`, `.tool-output-header`).

### Phase 3 — Server handler, default scripts & task runner ✔️ (`server/`, `agent/`, `docs/rpc-commands.md`)

**Depends on:** Phase 1 schema.

- ✔️ `agent/linux/PackageMonitor.vala` already calls `this.send_pending()` after `apt()` / `rpm()` rescans.

#### Schemas

- **`script` (`shared/SQT/Script.vala`):**

```
id                    INTEGER   row id
script_repository_id  INTEGER   0 = scripts/ or defaults, >0 = script_repository.id
path                  TEXT      relative path on disk (empty for 'inline')
filetype              TEXT      'script', 'file', or 'inline' (body stored in DB)
platform              TEXT      OS family, e.g. 'linux', 'windows'
app                   TEXT      tool/subsystem, e.g. 'apt', 'dnf'
action                TEXT      verb, e.g. 'update', 'upgrade'
body                  TEXT      script contents when filetype = 'inline'
allow_all             INTEGER   1 = runs on any active agent without script_perm; 0 = requires script_perm
added_dt              INTEGER   unix time created (already in SQL via init_db_audit)
updated_dt            INTEGER   unix time updated (already in SQL via init_db_audit)
deleted_dt            INTEGER   unix time deleted (already in SQL via init_db_audit)
```

- **`script_perm` (`shared/SQT/ScriptPerm.vala`, renamed from `script_agent` / `ScriptAgent.vala`):**

```
id         INTEGER   row id
script_id  INTEGER   script.id
agent_id   INTEGER   agent.id allowed to run this script when script.allow_all = 0
added_dt   INTEGER   unix time created
updated_dt INTEGER   unix time updated
deleted_dt INTEGER   unix time deleted
```

- **Default script JSON catalog (`server/resources/scripts/*.json`):**

```json
[
  {
    "platform": "linux",
    "app": "apt",
    "action": "update",
    "allow_all": true,
    "body": "#!/bin/sh\nset -e\nDEBIAN_FRONTEND=noninteractive apt-get update\n"
  }
]
```

#### 1. `shared/SQT/Script.vala`, `Task.vala` & `ScriptPerm.vala` — `Script` fields, `Task.script()`, and `ScriptAgent` -> `ScriptPerm`

**Why:** Store structured lookup metadata, inline body, `allow_all` flag, and audit timestamps on `script`, add `Task.script()` to return the `Script` object, and rename `script_agent` (`ScriptAgent`) to `script_perm` (`ScriptPerm`).

**Where:** `shared/SQT/Script.vala`, `shared/SQT/Task.vala`, `shared/SQT/ScriptAgent.vala` -> `shared/SQT/ScriptPerm.vala`, `shared/SQT/namespace.vala`, `shared/meson.build`, and `docs/meson.build`.

**Depends on:** none.

##### Remove — `shared/SQT/Script.vala`

```vala
	public class Script : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public int64 script_repository_id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string filetype { get; set; default = ""; }
```

##### Replace with

```vala
	public class Script : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable, Json.Serializable
	{
		public int64 id { get; set; default = 0; }
		public int64 script_repository_id { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public string filetype { get; set; default = ""; }
		public string platform { get; set; default = ""; }
		public string app { get; set; default = ""; }
		public string action { get; set; default = ""; }
		public string body { get; set; default = ""; }
		public bool allow_all { get; set; default = false; }
		public int added_dt { get; set; default = 0; }
		public int updated_dt { get; set; default = 0; }
		public int deleted_dt { get; set; default = 0; }
```

##### Remove — `shared/SQT/Script.vala` (`init_db`)

```vala
			var ddl = """
				CREATE TABLE IF NOT EXISTS script (
					id                    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_repository_id  INTEGER NOT NULL DEFAULT 0,
					path                  TEXT NOT NULL DEFAULT '',
					filetype              TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "script");
```

##### Replace with

```vala
			var ddl = """
				CREATE TABLE IF NOT EXISTS script (
					id                    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_repository_id  INTEGER NOT NULL DEFAULT 0,
					path                  TEXT NOT NULL DEFAULT '',
					filetype              TEXT NOT NULL DEFAULT '',
					platform              TEXT NOT NULL DEFAULT '',
					app                   TEXT NOT NULL DEFAULT '',
					action                TEXT NOT NULL DEFAULT '',
					body                  TEXT NOT NULL DEFAULT '',
					allow_all             INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "script");
			db.db.exec(
				"ALTER TABLE script ADD COLUMN platform TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN app TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN action TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN body TEXT NOT NULL DEFAULT '';",
				null, out errmsg);
			db.db.exec(
				"ALTER TABLE script ADD COLUMN allow_all INTEGER NOT NULL DEFAULT 0;",
				null, out errmsg);
```

##### Add — `shared/SQT/Task.vala` (`db` field, `init_db`, and `script()`)

Store `db` on `Task.init_db` and add `script()` to look up the associated `Script` row (`id == 0` when unset or missing).

```vala
	public class Task : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		private static SQ.Database db;
```
```vala
		/**
		 * Library script for {@link script_id}, or an empty {@link Script}
		 * (''id == 0'') when unset or not found.
		 *
		 * @return matching {@link Script} row
		 */
		public Script script()
		{
			if (this.script_id < 1 || Task.db == null) {
				return new Script();
			}
			var rows = new Gee.ArrayList<Script>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", (int) this.script_id);
			Script.query(Task.db).selectWhere(
				"WHERE id = $id AND deleted_dt = 0", binds, null, rows);
			if (rows.size == 0) {
				return new Script();
			}
			return rows.get(0);
		}
```
```vala
		public static void init_db(SQ.Database db)
		{
			Task.db = db;
```

##### Rename — `shared/SQT/ScriptAgent.vala` -> `shared/SQT/ScriptPerm.vala`

Rename `ScriptAgent` to `ScriptPerm`, wire name `'Argus.ScriptPerm'`, table `'script_perm'`, with `ALTER TABLE script_agent RENAME TO script_perm;` migration before `CREATE TABLE`.

```vala
	public class ScriptPerm : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		public int64 id { get; set; default = 0; }
		public int64 script_id { get; set; default = 0; }
		public int64 agent_id { get; set; default = 0; }

		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.ScriptPerm", typeof(ScriptPerm));
		}

		public static SQ.Query<ScriptPerm> query(SQ.Database db)
		{
			return new SQ.Query<ScriptPerm>(db, "script_perm");
		}

		public static void init_db(SQ.Database db)
		{
			var errmsg = "";
			db.db.exec("ALTER TABLE script_agent RENAME TO script_perm;", null, out errmsg);
			var ddl = """
				CREATE TABLE IF NOT EXISTS script_perm (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					script_id  INTEGER NOT NULL DEFAULT 0,
					agent_id   INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("script_perm create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "script_perm");
		}
	}
```

##### Remove — `shared/SQT/namespace.vala`, `shared/meson.build`, `docs/meson.build`

```vala
 * {@link ScriptAgent} enables a script on a machine.
```
```vala
		ScriptAgent.init_db(db);
```
```meson
	'SQT/ScriptAgent.vala',
```
```meson
  '../shared/SQT/ScriptAgent.vala',
```

##### Replace with

```vala
 * {@link ScriptPerm} permits a script on a machine.
```
```vala
		ScriptPerm.init_db(db);
```
```meson
	'SQT/ScriptPerm.vala',
```
```meson
  '../shared/SQT/ScriptPerm.vala',
```

#### 2. `server/resources/` & `server/meson.build` — default script GResource catalogs

**Why:** Bundle `linux.json` into `argusrm-server` for startup import (Windows catalog commented out for now).

**Where:** New resource files under `server/resources/` and `server/meson.build`.

**Depends on:** none.

##### Add — `server/resources/argusrm-server.gresource.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gresources>
  <gresource prefix="/argusrm">
    <file>scripts/linux.json</file>
    <!-- <file>scripts/windows.json</file> -->
  </gresource>
</gresources>
```

##### Add — `server/resources/scripts/linux.json`

```json
[
  {
    "platform": "linux",
    "app": "apt",
    "action": "update",
    "allow_all": true,
    "body": "#!/bin/sh\nset -e\nDEBIAN_FRONTEND=noninteractive apt-get update\n"
  },
  {
    "platform": "linux",
    "app": "apt",
    "action": "upgrade",
    "allow_all": true,
    "body": "#!/bin/sh\nset -e\nDEBIAN_FRONTEND=noninteractive apt-get update\nDEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y upgrade\n"
  },
  {
    "platform": "linux",
    "app": "dnf",
    "action": "update",
    "allow_all": true,
    "body": "#!/bin/sh\nset -e\ndnf -y makecache --refresh\n"
  },
  {
    "platform": "linux",
    "app": "dnf",
    "action": "upgrade",
    "allow_all": true,
    "body": "#!/bin/sh\nset -e\ndnf -y upgrade\n"
  }
]
```

##### Add — `server/meson.build`, before `deps = [` at top of file

Compile the server script catalog resources.

```meson
gnome = import('gnome')
server_resources = gnome.compile_resources(
	'argus-server-resources',
	'resources/argusrm-server.gresource.xml',
	source_dir: 'resources',
	c_name: 'argus_server_resources',
)
```

##### Remove — `server/meson.build` (`argusrm-server` executable)

```meson
executable(
	'argusrm-server',
	sources,
	files('main.vala'),
```

##### Replace with

```meson
executable(
	'argusrm-server',
	sources,
	server_resources,
	files('main.vala'),
```

#### 3. `server/SQT/Script.vala` & `server/Application.vala` — `Script.search`, `import_defaults`, `import_json`, `import_script`, and `'inline'` support

**Why:** Import JSON script arrays directly into `script` (`filetype = 'inline'`, `body` in DB, no `path`) using `import_json(json, script_repository_id)` / `import_script(entry, script_repository_id)`, preserve `'inline'` rows across `scan()`, and handle `'inline'` in `read`, `update`, `enable`, and `search`.

**Where:** `server/SQT/Script.vala` and `server/Application.vala` (`command_line`).

**Depends on:** #1 (`shared/SQT/Script.vala`) and #2 (`server/resources/`).

##### Remove — `server/SQT/Script.vala` (`rpc_register`)

```vala
			Argus.Shared.SQT.Script.rpc_register();
			Argus.Shared.SQT.ScriptAgent.rpc_register();
			OLLMrpc.Request.add_class(
				"Script", typeof(Script),
				"create", "ss",
				"update", "is",
				"read", "i",
				"list", "i",
				"enable", "ii",
				"disable", "ii",
				"agents", "i"
			);
```

##### Replace with

```vala
			Argus.Shared.SQT.Script.rpc_register();
			Argus.Shared.SQT.ScriptPerm.rpc_register();
			OLLMrpc.Request.add_class(
				"Script", typeof(Script),
				"create", "ss",
				"update", "is",
				"read", "i",
				"list", "i",
				"search", "sss",
				"enable", "ii",
				"disable", "ii",
				"agents", "i"
			);
```

##### Add — `server/SQT/Script.vala`, inside `update()` after `if (rows.size == 0) { ... return; }` and before `var scripts_dir = ...`

Update `body` and `updated_dt` in DB when editing an `'inline'` script instead of writing to `scripts/`.

```vala
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			if (rows.get(0).filetype == "inline") {
				rows.get(0).body = body;
				rows.get(0).updated_dt = now;
				Argus.Shared.SQT.Script.query(this.app.db).updateById(rows.get(0));
				this.app.db.backupDB();
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", rows.get(0)),
					msg = "ok"
				});
				return;
			}
```

##### Remove — `server/SQT/Script.vala` (`update` filesystem tail)

```vala
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
```

##### Replace with

```vala
			rows.get(0).updated_dt = now;
			Argus.Shared.SQT.Script.query(this.app.db).updateById(rows.get(0));
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
```

##### Add — `server/SQT/Script.vala`, inside `read()` after `if (rows.size == 0) { ... return; }` and before `var root = ...`

Return stored `body` from DB for `'inline'` scripts instead of reading a file on disk.

```vala
			if (rows.get(0).filetype == "inline") {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("s", rows.get(0).body),
					msg = "ok"
				});
				return;
			}
```

##### Add — `server/SQT/Script.vala`, immediately after `list()`

Add `search()`, `import_defaults()`, `import_json()`, and `import_script()`.

```vala
		/**
		 * Search executable scripts by ''platform'', ''app'', and ''action''.
		 *
		 * Empty filters match any value. Results order repository 0
		 * scripts first, then cloned repository rows.
		 *
		 * @param request inbound RPC from the controller
		 * @param platform target OS family, or empty
		 * @param app target tool, or empty
		 * @param action target action, or empty
		 */
		public void search(OLLMrpc.Request request, string platform, string app, string action)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var clauses = "deleted_dt = 0 AND filetype IN ('script', 'inline')";
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			if (platform != "") {
				clauses += " AND platform = $platform";
				text_binds.set("platform", platform);
			}
			if (app != "") {
				clauses += " AND app = $app";
				text_binds.set("app", app);
			}
			if (action != "") {
				clauses += " AND action = $action";
				text_binds.set("action", action);
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE " + clauses + " ORDER BY script_repository_id ASC, id ASC",
				int_binds, text_binds, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Import missing default scripts from bundled JSON catalogs.
		 */
		public void import_defaults()
		{
			var changed = false;
			var linux = (string) GLib.resources_lookup_data(
				"/argusrm/scripts/linux.json", GLib.ResourceLookupFlags.NONE).get_data();
			if (this.import_json(linux, 0)) {
				changed = true;
			}
			/*
			var windows = (string) GLib.resources_lookup_data(
				"/argusrm/scripts/windows.json", GLib.ResourceLookupFlags.NONE).get_data();
			if (this.import_json(windows, 0)) {
				changed = true;
			}
			*/
			if (changed) {
				this.app.db.backupDB();
			}
		}

		/**
		 * Parse a JSON array of script definitions and import missing rows.
		 *
		 * @param json JSON array text of script objects
		 * @param script_repository_id repository id, or 0 for defaults
		 * @return true when at least one row was inserted
		 */
		public bool import_json(string json, int64 script_repository_id = 0)
		{
			var parser = new Json.Parser();
			try {
				parser.load_from_data(json);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return false;
			}
			var root = parser.get_root();
			if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
				return false;
			}
			var changed = false;
			var list = root.get_array();
			var count = list.get_length();
			for (var i = 0; i < (int) count; i++) {
				var element = list.get_element(i);
				if (element.get_node_type() != Json.NodeType.OBJECT) {
					continue;
				}
				var obj = Json.gobject_deserialize(typeof(Argus.Shared.SQT.Script), element);
				if (obj == null) {
					continue;
				}
				if (this.import_script((Argus.Shared.SQT.Script) obj, script_repository_id)) {
					changed = true;
				}
			}
			return changed;
		}

		/**
		 * Import one inline script into ''script'' if no matching
		 * ''(script_repository_id, platform, app, action)'' row exists.
		 *
		 * @param entry script metadata and body
		 * @param script_repository_id repository id, or 0 for defaults
		 * @return true when inserted
		 */
		public bool import_script(Argus.Shared.SQT.Script entry, int64 script_repository_id = 0)
		{
			if (entry.platform == "" || entry.app == "" ||
				entry.action == "" || entry.body == "") {
				return false;
			}
			var existing = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds.set("script_repository_id", (int) script_repository_id);
			text_binds.set("platform", entry.platform);
			text_binds.set("app", entry.app);
			text_binds.set("action", entry.action);
			Argus.Shared.SQT.Script.query(this.db).selectWhere(
				"WHERE script_repository_id = $script_repository_id " +
					"AND platform = $platform AND app = $app AND action = $action " +
					"AND deleted_dt = 0",
				int_binds, text_binds, existing);
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			if (existing.size > 0) {
				if (entry.updated_dt > 0 && entry.updated_dt > existing.get(0).updated_dt) {
					existing.get(0).body = entry.body;
					existing.get(0).allow_all = entry.allow_all;
					existing.get(0).updated_dt = entry.updated_dt;
					Argus.Shared.SQT.Script.query(this.db).updateById(existing.get(0));
					return true;
				}
				return false;
			}
			entry.id = 0;
			entry.script_repository_id = script_repository_id;
			entry.path = "";
			entry.filetype = "inline";
			entry.added_dt = now;
			entry.updated_dt = entry.updated_dt > 0 ? entry.updated_dt : now;
			entry.deleted_dt = 0;
			Argus.Shared.SQT.Script.query(this.db).insert(entry);
			return true;
		}
```

##### Remove — `server/SQT/Script.vala` (`enable`, `disable`, `agents`)

```vala
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE id = $id AND filetype = 'script'", script_binds, null, scripts);
```
```vala
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			binds.set("agent_id", agent_id);
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere(
				"WHERE script_id = $script_id AND agent_id = $agent_id",
				binds, null, rows);

			if (rows.size == 0) {
				var row = new Argus.Shared.SQT.ScriptAgent() {
					script_id = script_id,
					agent_id = agent_id
				};
				Argus.Shared.SQT.ScriptAgent.query(this.app.db).insert(row);
```
```vala
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).deleteWhere("WHERE script_id = $script_id AND agent_id = $agent_id",
				binds, null);
```
```vala
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere("WHERE script_id = $script_id", binds, null, rows);
```

##### Replace with

```vala
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE id = $id AND filetype IN ('script', 'inline')",
				script_binds, null, scripts);
```
```vala
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptPerm>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			binds.set("agent_id", agent_id);
			Argus.Shared.SQT.ScriptPerm.query(this.app.db).selectWhere(
				"WHERE script_id = $script_id AND agent_id = $agent_id",
				binds, null, rows);

			if (rows.size == 0) {
				var row = new Argus.Shared.SQT.ScriptPerm() {
					script_id = script_id,
					agent_id = agent_id
				};
				Argus.Shared.SQT.ScriptPerm.query(this.app.db).insert(row);
```
```vala
			Argus.Shared.SQT.ScriptPerm.query(this.app.db).deleteWhere("WHERE script_id = $script_id AND agent_id = $agent_id",
				binds, null);
```
```vala
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptPerm>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			Argus.Shared.SQT.ScriptPerm.query(this.app.db).selectWhere("WHERE script_id = $script_id", binds, null, rows);
```

##### Remove — `server/SQT/Script.vala` (`scan`)

```vala
			query.selectWhere("WHERE script_repository_id = $script_repository_id", binds, null, old_scripts);
```

##### Replace with

```vala
			query.selectWhere(
				"WHERE script_repository_id = $script_repository_id AND filetype != 'inline'",
				binds, null, old_scripts);
```

##### Add — `server/Application.vala`, inside `command_line()` right after `Argus.Shared.SQT.init_db(this.db);`

Import default script catalogs before opening RPC listeners.

```vala
			new SQT.Script.for_rpc(this).import_defaults();
```

#### 4. `server/Command.vala` & `server/SQT/Task.vala` — `Task.submit`, `Task.all_targets`, `Task.logs`, `'inline'` support, and runner fixes

**Why:** Support `'inline'` DB-stored scripts alongside filesystem scripts, atomic task submission (`created_by`, `approved_by`, `controller_sig` verification hook), enforce `script.allow_all` vs `script_perm` (`ScriptPerm`), store `log_dir`, list all targets, read logs, reschedule immediately on finish, and broadcast `event.task`.

**Where:** `server/Command.vala` (`logs` visibility) and `server/SQT/Task.vala` (`rpc_register`, `create`, `update`, `target`, `approve`, `submit`, `all_targets`, `logs`, `run`, `finish`, `command_text`).

**Depends on:** #1 (`shared/SQT/Script.vala`) and Phase 1 schema (`shared/SQT/Task.vala`, `shared/SQT/TaskTarget.vala`).

##### Remove — `server/Command.vala`

```vala
		private static Gee.HashMap<int, string> logs;
```

##### Replace with

```vala
		internal static Gee.HashMap<int, string> logs;
```

##### Remove — `server/SQT/Task.vala` (`rpc_register`)

```vala
				"approve", "ib",
				"duplicate", "i",
				"targets", "i"
			);
```

##### Replace with

```vala
				"approve", "ib",
				"submit", "ovb",
				"duplicate", "i",
				"targets", "i",
				"all_targets", "",
				"logs", "i"
			);
```

##### Remove — `server/SQT/Task.vala` (`create`)

```vala
			if (row.script_id > 0) {
				var scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
				var binds = new Gee.HashMap<string, int>();
				binds.set("id", (int) row.script_id);
				Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
					"WHERE id = $id AND filetype = 'script'", binds, null, scripts);
				if (scripts.size == 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
			}
			row.id = 0;
```

##### Replace with

```vala
			if (row.script_id > 0) {
				var script = row.script();
				if (script.id < 1 || (script.filetype != "script" && script.filetype != "inline")) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
			}
			row.created_by = Argus.Shared.Agent.user(request).id;
			row.approved_by = 0;
			row.id = 0;
```

##### Remove — `server/SQT/Task.vala` (`update`)

```vala
			if (row.script_id > 0) {
				var scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
				var script_binds = new Gee.HashMap<string, int>();
				script_binds.set("id", (int) row.script_id);
				Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
					"WHERE id = $id AND filetype = 'script'",
					script_binds, null, scripts);
				if (scripts.size == 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
			}
```

##### Replace with

```vala
			if (row.script_id > 0) {
				var script = row.script();
				if (script.id < 1 || (script.filetype != "script" && script.filetype != "inline")) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
			}
```

##### Remove — `server/SQT/Task.vala` (`target`)

```vala
			if (tasks.get(0).script_id > 0) {
				var enabled = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
				var enabled_binds = new Gee.HashMap<string, int>();
				enabled_binds.set("script_id", (int) tasks.get(0).script_id);
				Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere(
					"WHERE script_id = $script_id", enabled_binds, null, enabled);
				foreach (var script_agent in enabled) {
					allowed.set((int) script_agent.agent_id, true);
				}
			} else {
				var agents = new Gee.ArrayList<Argus.Shared.Agent>();
				Argus.Shared.Agent.query(this.app.db).select("WHERE status = 1", agents);
				foreach (var agent in agents) {
					allowed.set((int) agent.id, true);
				}
			}
```

##### Replace with

```vala
			var needs_perm = tasks.get(0).script_id > 0 && !tasks.get(0).script().allow_all;
			if (needs_perm) {
				var enabled = new Gee.ArrayList<Argus.Shared.SQT.ScriptPerm>();
				var enabled_binds = new Gee.HashMap<string, int>();
				enabled_binds.set("script_id", (int) tasks.get(0).script_id);
				Argus.Shared.SQT.ScriptPerm.query(this.app.db).selectWhere(
					"WHERE script_id = $script_id", enabled_binds, null, enabled);
				foreach (var perm in enabled) {
					allowed.set((int) perm.agent_id, true);
				}
			} else {
				var agents = new Gee.ArrayList<Argus.Shared.Agent>();
				Argus.Shared.Agent.query(this.app.db).select("WHERE status = 1", agents);
				foreach (var agent in agents) {
					allowed.set((int) agent.id, true);
				}
			}
```

##### Remove — `server/SQT/Task.vala` (`approve`)

```vala
			if (tasks.get(0).scheduled <= new GLib.DateTime.now_utc().to_unix()) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("task schedule has passed")
				});
				return;
			}
```

##### Replace with

```vala
			var now = new GLib.DateTime.now_utc().to_unix();
			if (tasks.get(0).scheduled < 1) {
				tasks.get(0).scheduled = now;
			}
			if (tasks.get(0).scheduled < now) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("task schedule has passed")
				});
				return;
			}
```

##### Remove — `server/SQT/Task.vala` (`approve`)

```vala
			tasks.get(0).is_draft = !approved;
			Argus.Shared.SQT.Task.query(this.app.db).updateById(tasks.get(0));
```

##### Replace with

```vala
			tasks.get(0).is_draft = !approved;
			tasks.get(0).approved_by = approved ? Argus.Shared.Agent.user(request).id : 0;
			Argus.Shared.SQT.Task.query(this.app.db).updateById(tasks.get(0));
```

##### Add — `server/SQT/Task.vala`, immediately after `targets()`

Add `submit()`, `all_targets()`, and `logs()` handlers.

```vala
		/**
		 * Create, target, optionally watch, and approve a task atomically.
		 *
		 * @param request inbound RPC from the controller
		 * @param row task values (with optional signing fields)
		 * @param agent_ids variant containing an ''ai'' array of agent ids
		 * @param watch true to stream target output to this connection
		 */
		public void submit(
			OLLMrpc.Request request,
			Argus.Shared.SQT.Task row,
			GLib.Variant agent_ids,
			bool watch
		) {
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (row.script_id < 0 || (!row.is_script && row.script_id > 0) ||
				(row.script_id == 0 && row.command == "") ||
				!agent_ids.is_of_type(new GLib.VariantType("ai")) ||
				agent_ids.n_children() < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid task")
				});
				return;
			}
			var needs_perm = false;
			if (row.script_id > 0) {
				var script = row.script();
				if (script.id < 1 || (script.filetype != "script" && script.filetype != "inline")) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
					});
					return;
				}
				needs_perm = !script.allow_all;
			}
			var allowed = new Gee.HashMap<int, bool>();
			if (needs_perm) {
				var enabled = new Gee.ArrayList<Argus.Shared.SQT.ScriptPerm>();
				var enabled_binds = new Gee.HashMap<string, int>();
				enabled_binds.set("script_id", (int) row.script_id);
				Argus.Shared.SQT.ScriptPerm.query(this.app.db).selectWhere(
					"WHERE script_id = $script_id", enabled_binds, null, enabled);
				foreach (var perm in enabled) {
					allowed.set((int) perm.agent_id, true);
				}
			} else {
				var agents = new Gee.ArrayList<Argus.Shared.Agent>();
				Argus.Shared.Agent.query(this.app.db).select("WHERE status = 1", agents);
				foreach (var agent in agents) {
					allowed.set((int) agent.id, true);
				}
			}
			for (var i = 0; i < agent_ids.n_children(); i++) {
				var agent_id = agent_ids.get_child_value(i).get_int32();
				if (allowed.has_key(agent_id)) {
					continue;
				}
				var message = needs_perm ?
					"script is not enabled on agent " + agent_id.to_string() :
					"unknown agent " + agent_id.to_string();
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(message)
				});
				return;
			}
			var caller_id = Argus.Shared.Agent.user(request).id;
			var now = new GLib.DateTime.now_utc().to_unix();
			row.id = 0;
			row.completed = 0;
			row.is_template = false;
			row.is_draft = false;
			row.created_by = caller_id;
			row.approved_by = caller_id;
			if (row.scheduled < 1) {
				row.scheduled = now;
			}
			/* Hook for 6.0-security-issues controller_sig verification */
			Argus.Shared.SQT.Task.query(this.app.db).insert(row);
			var created_targets = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var seen = new Gee.HashMap<int, bool>();
			for (var i = 0; i < agent_ids.n_children(); i++) {
				var agent_id = agent_ids.get_child_value(i).get_int32();
				if (seen.has_key(agent_id)) {
					continue;
				}
				seen.set(agent_id, true);
				var target = new Argus.Shared.SQT.TaskTarget() {
					task_id = row.id,
					agent_id = agent_id,
					is_watched = watch
				};
				Argus.Shared.SQT.TaskTarget.query(this.app.db).insert(target);
				if (watch) {
					Argus.Server.Command.watch((int) target.id, request.connection);
				}
				created_targets.add(target);
			}
			this.app.db.backupDB();
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.task",
				action = "queued"
			});
			this.app.scheduler.reschedule();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", created_targets),
				msg = "ok"
			});
		}

		/**
		 * List all task targets joined with task and agent display fields.
		 *
		 * @param request inbound RPC from the controller
		 */
		public void all_targets(OLLMrpc.Request request)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var query = Argus.Shared.SQT.TaskTarget.query(this.app.db);
			var columns = string.joinv(", ", query.getColsExcept(null, "task_target."));
			query.selectQuery(@"
				SELECT
					$(columns),
					COALESCE(task.name, '') as task_id_name,
					COALESCE(task.command, '') as task_id_command,
					COALESCE(task.is_draft, 0) as task_id_is_draft,
					COALESCE(task.scheduled, 0) as task_id_scheduled,
					COALESCE(NULLIF(agent.hostname, ''),
						COALESCE(agent.requester, '')) as agent_id_hostname
				FROM
					task_target
				LEFT JOIN
					task
				ON
					task.id = task_target.task_id
				LEFT JOIN
					agent
				ON
					agent.id = task_target.agent_id
				ORDER BY
					task_target.id DESC
			", rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Read saved stdout, stderr, and stdin logs for one target.
		 *
		 * @param request inbound RPC from the controller
		 * @param target_id ''task_target.id''
		 */
		public void logs(OLLMrpc.Request request, int target_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", target_id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE id = $id", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown target")
				});
				return;
			}
			var row = rows.get(0);
			string[] result = { "", "", "" };
			if (row.identifier < 1) {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("as", result),
					msg = "ok"
				});
				return;
			}
			var dir = row.log_dir;
			if (dir == "" && row.started > 0) {
				var when = new GLib.DateTime.from_unix_local(row.started);
				if (when != null) {
					dir = GLib.Path.build_filename(
						Argus.LOG_DIR, "commands",
						when.format("%Y"), when.format("%m"), when.format("%d"));
				}
			}
			if (dir == "") {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("as", result),
					msg = "ok"
				});
				return;
			}
			string[] exts = { ".stdout", ".stderr", ".stdin" };
			for (var i = 0; i < 3; i++) {
				var path = GLib.Path.build_filename(dir,
					row.agent_id.to_string() + "-" +
					row.identifier.to_string() + exts[i]);
				if (!GLib.FileUtils.test(path, GLib.FileTest.IS_REGULAR)) {
					continue;
				}
				var body = "";
				try {
					GLib.FileUtils.get_contents(path, out body);
				} catch (GLib.Error e) {
					body = "";
				}
				result[i] = body;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", result),
				msg = "ok"
			});
		}
```

##### Remove — `server/SQT/Task.vala` (`run`)

```vala
				busy_agents.set((int) target.agent_id, true);
				target.started = now;
				target.identifier = order.identifier;
				Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
				started = true;
				GLib.debug("task %d target %s started %d",
					task_id, target.agent_id.to_string(), order.identifier);
			}
			if (rescheduled || started) {
				this.app.db.backupDB();
			}
```

##### Replace with

```vala
				busy_agents.set((int) target.agent_id, true);
				target.started = now;
				target.identifier = order.identifier;
				if (Argus.Server.Command.logs != null &&
					Argus.Server.Command.logs.has_key(order.identifier)) {
					target.log_dir = Argus.Server.Command.logs.get(order.identifier);
				}
				Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
				started = true;
				GLib.debug("task %d target %s started %d",
					task_id, target.agent_id.to_string(), order.identifier);
			}
			if (rescheduled || started) {
				this.app.db.backupDB();
			}
			if (started) {
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.task",
					action = "started"
				});
			}
```

##### Remove — `server/SQT/Task.vala` (`finish`)

```vala
			Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(rows.get(0));
			this.complete_task((int) rows.get(0).task_id, now);
			this.app.db.backupDB();
		}
```

##### Replace with

```vala
			Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(rows.get(0));
			this.complete_task((int) rows.get(0).task_id, now);
			this.app.db.backupDB();
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.task",
				action = "ended"
			});
			this.app.scheduler.reschedule();
		}
```

##### Remove — `server/SQT/Task.vala` (`command_text`)

```vala
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", (int) task.script_id);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE id = $id", binds, null, rows);
			if (rows.size == 0) {
				error = "unknown script";
				return null;
			}
			var root = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "scripts");
			if (rows.get(0).script_repository_id > 0) {
				var repositories = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
				var repository_binds = new Gee.HashMap<string, int>();
				repository_binds.set("id", (int) rows.get(0).script_repository_id);
				Argus.Shared.SQT.ScriptRepository.query(this.app.db).selectWhere(
					"WHERE id = $id", repository_binds, null, repositories);
				if (repositories.size == 0) {
					error = "unknown repository";
					return null;
				}
				root = GLib.Path.build_filename(
					Argus.SERVER_DATA_DIR, "git", repositories.get(0).name);
			}
			var full_path = GLib.Path.build_filename(root, rows.get(0).path);
```

##### Replace with

```vala
			var script = task.script();
			if (script.id < 1) {
				error = "unknown script";
				return null;
			}
			if (script.filetype == "inline") {
				if (script.body == "") {
					error = "invalid script";
					return null;
				}
				return script.body;
			}
			var root = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "scripts");
			if (script.script_repository_id > 0) {
				var repositories = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
				var repository_binds = new Gee.HashMap<string, int>();
				repository_binds.set("id", (int) script.script_repository_id);
				Argus.Shared.SQT.ScriptRepository.query(this.app.db).selectWhere(
					"WHERE id = $id", repository_binds, null, repositories);
				if (repositories.size == 0) {
					error = "unknown repository";
					return null;
				}
				root = GLib.Path.build_filename(
					Argus.SERVER_DATA_DIR, "git", repositories.get(0).name);
			}
			var full_path = GLib.Path.build_filename(root, script.path);
```

#### 5. `agent/linux/Command.vala` — `spawnv` failure and `Command.ended` drain/lock

**Why:** Ensure `spawnv` failure reports exit `127` so targets do not stay open forever, and ensure `Command.ended` waits for stdout/stderr pipes to drain under `Command.send_lock`.

**Where:** `agent/linux/Command.vala` (`Command` fields, `run()`, and `finish(int code)`).

**Depends on:** none.

##### Add — `agent/linux/Command.vala`, immediately after `private GLib.InputStream stderr_pipe;`

Track completion of child wait and both pipe watches.

```vala
		private bool stdout_done = false;
		private bool stderr_done = false;
		private bool child_done = false;
		private int exit_code = 1;
```

##### Remove — `agent/linux/Command.vala` (`run`)

```vala
			GLib.Subprocess child;
			try {
				child = launcher.spawnv(argv);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
```

##### Replace with

```vala
			GLib.Subprocess child;
			try {
				child = launcher.spawnv(argv);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.report("Command.stderr", e.message + "\n");
				this.stdout_done = true;
				this.stderr_done = true;
				this.child_done = true;
				this.finish(127);
				return;
			}
```

##### Remove — `agent/linux/Command.vala` (`run`)

```vala
			stdout_ch.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(channel, condition) => {
					if ((condition & GLib.IOCondition.IN) != 0) {
						this.read_channel(channel, "Command.stdout");
					}
					if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						return false;
					}
					return true;
				});
			stderr_ch.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(channel, condition) => {
					if ((condition & GLib.IOCondition.IN) != 0) {
						this.read_channel(channel, "Command.stderr");
					}
					if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						return false;
					}
					return true;
				});
			this.child.wait_async.begin(null, (obj, res) => {
				var code = 1;
				try {
					this.child.wait_async.end(res);
					if (this.child.get_if_exited()) {
						code = this.child.get_exit_status();
					} else if (this.child.get_if_signaled()) {
						code = 128 + this.child.get_term_sig();
					}
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				try {
					this.connection.call(new OLLMrpc.Request() {
						method = "Command.ended",
						args = OLLMrpc.args("ii", this.identifier, code)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			});
```

##### Replace with

```vala
			stdout_ch.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(channel, condition) => {
					if ((condition & (GLib.IOCondition.IN | GLib.IOCondition.HUP)) != 0) {
						this.read_channel(channel, "Command.stdout");
					}
					if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						this.stdout_done = true;
						this.finish(this.exit_code);
						return false;
					}
					return true;
				});
			stderr_ch.add_watch(
				GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
				(channel, condition) => {
					if ((condition & (GLib.IOCondition.IN | GLib.IOCondition.HUP)) != 0) {
						this.read_channel(channel, "Command.stderr");
					}
					if ((condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR)) != 0) {
						this.stderr_done = true;
						this.finish(this.exit_code);
						return false;
					}
					return true;
				});
			this.child.wait_async.begin(null, (obj, res) => {
				var code = 1;
				try {
					this.child.wait_async.end(res);
					if (this.child.get_if_exited()) {
						code = this.child.get_exit_status();
					} else if (this.child.get_if_signaled()) {
						code = 128 + this.child.get_term_sig();
					}
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				this.exit_code = code;
				this.child_done = true;
				this.finish(code);
			});
```

##### Add — `agent/linux/Command.vala`, immediately after `run()`

Send `Command.ended` once both output pipes and child wait have completed.

```vala
		/**
		 * Send ''Command.ended'' once child exit and both output pipes finish.
		 *
		 * @param code process exit code
		 */
		private void finish(int code)
		{
			if (!this.child_done || !this.stdout_done || !this.stderr_done) {
				return;
			}
			Command.send_lock.lock();
			try {
				this.connection.call(new OLLMrpc.Request() {
					method = "Command.ended",
					args = OLLMrpc.args("ii", this.identifier, code)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			Command.send_lock.unlock();
		}
```

#### 6. `docs/rpc-commands.md` — document new calls and notifications

**Why:** Keep RPC reference synced with `Script.search`, `Task.submit`, `Task.all_targets`, `Task.logs`, and `event.task`.

**Where:** `docs/rpc-commands.md` (Notifications and Tasks sections).

**Depends on:** #3 and #4.

##### Add — `docs/rpc-commands.md`, under `## Notifications` after `### event.agent`

```markdown
### `event.task`

- 🔷 Broadcast when a task is queued, started, or ended.
- 🔷 Action `queued`, `started`, or `ended`.
```

##### Remove — `docs/rpc-commands.md` (`## Tasks`)

```markdown
- `Script.create` `ss`, `update` `is`, `read` `i`, `list` `i`, `enable` `ii`, `disable` `ii`, `agents` `i`
- `Task.create` `o`, `update` `o`, `list`, `target` `iv`, `watch` `i`, `approve` `ib`, `duplicate` `i`, `targets` `i`
```

##### Replace with

```markdown
- `Script.create` `ss`, `update` `is`, `read` `i`, `list` `i`, `search` `sss` (`platform`, `app`, `action` -> `o` array), `enable` `ii`, `disable` `ii`, `agents` `i`
- `Task.create` `o`, `update` `o`, `list`, `target` `iv`, `watch` `i`, `approve` `ib`, `submit` `ovb` (`task`, `ai` `agent_ids`, `watch` -> `o` targets), `duplicate` `i`, `targets` `i`, `all_targets` (no args -> `o` joined targets), `logs` `i` (`target_id` -> `as` `[stdout, stderr, stdin]`)
```

### Phase 4 — Connect UI & handlers (`controller/store/`, `controller/tab/`)

- ➡️ Split into [2026-11-15-FIXED-machines-package-update-phase4-ui.md](2026-11-15-FIXED-machines-package-update-phase4-ui.md).

---

## Next

- ✔️ Phases 1–3 implemented and verified (`ninja -C build`, `meson test -C build` 6/6 passed).
- ➡️ Continue Phase 4 in [2026-11-15-FIXED-machines-package-update-phase4-ui.md](2026-11-15-FIXED-machines-package-update-phase4-ui.md).

---

## LLM notes

- 🚫 Do not edit `docs/plans/7.2-tasks-ui-and-signing.md` or other `docs/plans/*`; keep work in this bug report.
