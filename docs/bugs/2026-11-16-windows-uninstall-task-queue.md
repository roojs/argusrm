# Windows uninstall: queue uninstall task on hold confirm

**Status:** ⏳ Phase 1 and Phase 2 approved and in the tree — verify on Windows controller

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [done/2026-11-15-FIXED-windows-uninstall-hold-action.md](done/2026-11-15-FIXED-windows-uninstall-hold-action.md), [2026-11-14-software-package-machines-grid.md](2026-11-14-software-package-machines-grid.md), [2026-11-14-software-filters-remaining.md](2026-11-14-software-filters-remaining.md), [1.0-DONE-overview.md](../plans/done/1.0-DONE-overview.md), [7.2-tasks-ui-and-signing.md](../plans/7.2-tasks-ui-and-signing.md)

---

## Problem

- 🔷 Holding the Windows uninstall trash button (`Argus.Controller.Widget.HoldButton`) for 2 seconds emits `Tab.Base.remove_confirmed(GLib.Object row)` and displays `"Click and hold to remove"` on short click, but nothing creates and queues the Windows uninstall task yet.
- 🔷 **Expected:**
  - 🔷 **Phase 1 — One machine at a time (`Machines -> Windows programs`):** add the trash icon to `programs_machine.csv` and wire `Machine/Programs.vala` `remove_confirmed` to convert `uninstall_string` to silent flags when needed (owned by the task builder, not `agent/Win32/Command.vala`) and queue the uninstall task straight away for that single machine via `Task.submit`.
  - 🔷 **Phase 2 — All machines (`Software -> Windows`):** add an RPC call (`Programs.machines`) to fetch every machine where that program is installed, show a destructive confirmation dialog requiring the user to type `"delete all"`, convert each machine's `uninstall_string` to silent flags, group machines by command, and queue a separate `Task.submit` task for each distinct uninstall command.
- 🔷 **Scope:** Windows only. Debian and RPM package removal stays out of scope until a proper dependency tree is available (not part of the original aims timeline). Debian preview is [2026-11-17-debian-install-remove-preview.md](2026-11-17-debian-install-remove-preview.md).
- 🔷 **Actual:** `programs_machine.csv` has no `Uninstall` column, `Argus.Shared.OSQuery.Programs` has no `silent_command()` helper, `Store.TaskTarget` has no `run_command(...)` method, there is no `Programs.machines` RPC to fetch per-machine rows for one program name, and neither `Machine/Programs.vala` nor `Programs.vala` connects `remove_confirmed`.

---

## Evidence

✔️ Current UI, store, and server state in the tree:

- ✔️ `controller/tab/Base.vala` emits `public signal void remove_confirmed(GLib.Object row)` when a `"bin"` or `"remove"` cell's `HoldButton` completes its 2-second hold, and provides `this.toasts` (`Adw.ToastOverlay`) on every `Tab.Base` page.
  - ℹ️ `Base.column_factory()` for `"bin"` reads an `int` property (`count > 0`) for visibility and tooltip (`"<N> uninstallable"`).
- ✔️ `controller/tab/Asset/Programs.vala` (`programs.csv`) already displays the `Uninstall` (`"bin"`) column (`uninstall-count`) over summary `Programs.list(0, 0)` rows.
- ℹ️ `controller/tab/Asset/Machine/Programs.vala` (`programs_machine.csv`) does not currently include `Uninstall,uninstall-count,ON,80,bin,ON`, and `Programs.list(agent_id > 0, 0)` leaves `uninstall_count == 0` because `uninstall_count` is not a stored column.
- ℹ️ `controller/resources/columns/deb_packages.csv` also has a `Remove` (`"remove"`) column from [5.9.2.1-DONE-debian-filters-phase1.md](../plans/done/5.9.2.1-DONE-debian-filters-phase1.md), while `rpm_packages.csv` has none; both Debian and RPM uninstall remain deferred until dependency-tree handling exists.
- ✔️ `shared/OSQuery/Programs.vala` only exposes `Programs.list(agent_id, since)`:
  - `Programs.list(agent_id > 0, 0)` returns per-machine rows for one `agent_id` (each row has `agent_id` and `uninstall_string`).
  - `Programs.list(0, 0)` returns one summary row per `name` (`installed`, `uninstall_count`, `GROUP_CONCAT(...)`) and does not list which machines have it.
  - 🚫 There is no RPC call yet to fetch the per-machine `Programs` rows for a given program `name` across all agents (also needed by [2026-11-14-software-package-machines-grid.md](2026-11-14-software-package-machines-grid.md)).
- ✔️ `server/SQT/Task.vala` (`Task.submit`) accepts an `Argus.Shared.SQT.Task` (`is_script = false`, `script_id = 0`, `command != ""`) and `ai` `agent_ids`, and `agent/Win32/Command.vala` runs `command` via `cmd.exe /c`.
- 🚫 `controller/store/TaskTarget.vala` only exposes `run_script(platform, app, action, agent_ids)` via `Script.search`, with no `run_command(...)` method to submit a direct `command` task.
- 🚫 `shared/OSQuery/Programs.vala` (`Argus.Shared.OSQuery.Programs`) owns `uninstall_string`, so converting it to silent flags belongs on `Programs` rather than on the generic `TaskTarget` store.
- ℹ️ As noted in [1.0-DONE-overview.md](../plans/done/1.0-DONE-overview.md), osquery's `programs` table only collects `uninstall_string` (often `MsiExec.exe /I{GUID}` or an interactive uninstaller, not `QuietUninstallString`), whereas `agent/Win32/Command.vala` runs non-interactively in the Windows service (Session 0).

---

## Root cause

- ✔️ `Store.TaskTarget` lacks `run_command(...)` for `Task.submit`, `Argus.Shared.OSQuery.Programs` lacks `silent_command()`, `programs_machine.csv` / `Programs.list(agent_id > 0)` / `Machine/Programs.vala` lack the trash column and `remove_confirmed` handler, and there is no `Programs.machines` RPC to fetch per-machine rows for bulk uninstall from `Software -> Windows`.

---

## Phases

- ⏳ **Phase 1 — Single-machine Windows uninstall:** `shared/OSQuery/Programs.vala` (`uninstall_count` for `agent_id > 0` + `silent_command()`), `controller/resources/columns/programs_machine.csv`, `controller/store/TaskTarget.vala` (`run_command`), and `controller/tab/Asset/Machine/Programs.vala` (`remove_confirmed` + toasts).
- ⏳ **Phase 2 — Bulk Windows uninstall from Software -> Windows:** `shared/OSQuery/Programs.vala` (`Programs.machines`), `docs/rpc-commands.md`, `controller/store/Programs.vala` (`load_machines` + `machines_loaded`), and `controller/tab/Asset/Programs.vala` (`remove_confirmed` -> fetch machines -> `"delete all"` dialog -> grouped `run_command`).

---

## Phase 1 — Single-machine Windows uninstall

### 1. `shared/OSQuery/Programs.vala` — set `uninstall_count` on per-machine `list` rows & add `silent_command()`

**Why:** Per-machine `Programs.list(agent_id > 0, 0)` rows do not populate `uninstall_count` (it is not a stored SQLite column), so `Base.column_factory()` `"bin"` would hide the trash button on `programs_machine.csv`. Setting `uninstall_count = 1` when `uninstall_string != ""` makes `"bin"` work in both grids without colliding with the existing `uninstall-string` column name in `programs_machine.csv`. Placing `silent_command()` on `Argus.Shared.OSQuery.Programs` keeps Windows `msiexec` flag conversion on the Windows package class that owns `uninstall_string` rather than on `Store.TaskTarget`. Fixed regex patterns do not need `try`/`catch`.

**Where:** `shared/OSQuery/Programs.vala`, `list()` in the `since <= 0 && agent_id > 0` branch, and `silent_command()` after `pkg_name()`.

**Depends on:** none.

#### Add — `shared/OSQuery/Programs.vala`, immediately after `pkg_name()`

Convert interactive Windows `msiexec` uninstall strings into silent flags on the `Programs` package row.

```vala
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
```

#### Remove — `shared/OSQuery/Programs.vala` (`list()`, `since <= 0 && agent_id > 0`)

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
```

#### Replace with — `shared/OSQuery/Programs.vala` (`list()`, `since <= 0 && agent_id > 0`)

Drop the redundant `agent_id IN (SELECT id FROM agent)` when `agent_id` is already fixed (same for the `since > 0 && agent_id > 0` branch).

```vala
			if (since <= 0 && agent_id > 0) {
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					""".printf(agent_id), rows);
				foreach (var row in rows) {
					row.uninstall_count = row.uninstall_string != "" ? 1 : 0;
				}
			}
```

---

### 2. `controller/resources/columns/programs_machine.csv` — add `Uninstall` column

**Why:** Display the trash `HoldButton` on each uninstallable row of the per-machine **Windows programs** grid.

**Where:** `controller/resources/columns/programs_machine.csv`, end of file after `Uninstall string`.

**Depends on:** #1 (`uninstall-count` populated on per-machine rows).

#### Add — `controller/resources/columns/programs_machine.csv`, after line 11

Append the `Uninstall` column using format `bin`.

```csv
Uninstall,uninstall-count,ON,80,bin,ON
```

---

### 3. `controller/store/TaskTarget.vala` — add `run_command()`

**Why:** Provide direct command submission via `Task.submit` (`is_script = false`, `script_id = 0`) without script lookup.

**Where:** `controller/store/TaskTarget.vala` (docblock and immediately after `run_script()`).

**Depends on:** none.

#### Remove — `controller/store/TaskTarget.vala` (class docblock)

```vala
	 * {@link items} is the backing list. {@link load} calls
	 * ''Task.all_targets''. {@link run_script} resolves a library script
	 * via ''Script.search'' and submits a task via ''Task.submit''.
```

#### Replace with — `controller/store/TaskTarget.vala` (class docblock)

```vala
	 * {@link items} is the backing list. {@link load} calls
	 * ''Task.all_targets''. {@link run_script} resolves a library script
	 * via ''Script.search'' and submits a task via ''Task.submit''.
	 * {@link run_command} submits a plain shell command directly.
```

#### Add — `controller/store/TaskTarget.vala`, immediately after `run_script()`

Add `run_command()` to queue a non-script `Task` via `Task.submit`.

```vala
		/**
		 * Submit a plain shell command task for ''agent_ids''.
		 *
		 * @param name task title
		 * @param command command line to run on each agent
		 * @param agent_ids target ''agent.id'' values
		 */
		public void run_command(
			string name,
			string command,
			Gee.ArrayList<int32> agent_ids
		) {
			if (command.strip() == "" || agent_ids.size < 1) {
				return;
			}
			var now = new GLib.DateTime.now_utc().to_unix();
			var builder = new GLib.VariantBuilder(new GLib.VariantType("ai"));
			string[] id_text = {};
			foreach (var id in agent_ids) {
				builder.add_value(new GLib.Variant.int32(id));
				id_text += id.to_string();
			}
			var canonical = command + "|0||" +
				now.to_string() + "|" + string.joinv(",", id_text);
			var task = new Argus.Shared.SQT.Task() {
				name = name,
				is_script = false,
				command = command,
				script_id = 0,
				scheduled = now,
				payload_hash = GLib.Checksum.compute_for_string(
					GLib.ChecksumType.SHA256, canonical)
			};
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.submit",
				args = OLLMrpc.args("ovb", task, builder.end(), false)
			}, (submit_obj, submit_res) => {
				OLLMrpc.Response submit_reply;
				try {
					submit_reply = this.app.rpc.call.end(submit_res);
				} catch (GLib.Error e) {
					this.failed("Could not queue task", e.message);
					return;
				}
				if (submit_reply.error != null) {
					this.failed("Could not queue task", submit_reply.error.message);
					return;
				}
				if (submit_reply.retval.type() == GLib.Type.INVALID ||
					!submit_reply.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.submitted(agent_ids.size);
					return;
				}
				var targets = (Gee.ArrayList<Argus.Shared.SQT.TaskTarget>)
					submit_reply.retval.get_object();
				this.submitted(targets.size);
			});
		}
```

---

### 4. `controller/tab/Asset/Machine/Programs.vala` — queue uninstall task on `remove_confirmed`

**Why:** Holding the trash button on a single machine's **Windows programs** row should immediately queue that machine's silent uninstall task via `Store.TaskTarget` and show confirmation or failure toasts on `this.toasts`.

**Where:** `controller/tab/Asset/Machine/Programs.vala`, `Programs()` constructor before `this.content.append(this.overlay);`.

**Depends on:** #1 (`Programs.silent_command`), #2, #3 (`Store.TaskTarget.run_command`).

#### Add — `controller/tab/Asset/Machine/Programs.vala`, immediately before `this.content.append(this.overlay);`

Wire `Store.TaskTarget` and `this.remove_confirmed` to queue a single-machine uninstall task and display toasts.

```vala
			var task_store = new Argus.Controller.Store.TaskTarget(window.app);
			task_store.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			task_store.submitted.connect((count) => {
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				this.toasts.add_toast(new Adw.Toast(label));
			});
			this.remove_confirmed.connect((obj) => {
				var row = obj as Argus.Shared.OSQuery.Programs;
				if (row == null || row.agent_id < 1) {
					return;
				}
				var cmd = row.silent_command();
				if (cmd == "") {
					this.toasts.add_toast(new Adw.Toast(
						"No uninstall command found for " + row.name));
					return;
				}
				var ids = new Gee.ArrayList<int32>();
				ids.add((int32) row.agent_id);
				task_store.run_command("Uninstall " + row.name, cmd, ids);
			});
```

---

## Phase 2 — Bulk Windows uninstall from `Software -> Windows`

### 1. `shared/OSQuery/Programs.vala` & `docs/rpc-commands.md` — add `Programs.machines(string name)` RPC

**Why:** Summary `Programs.list(0, 0)` rows do not contain individual machine IDs or separate per-machine uninstall commands. Fetching per-machine rows for `name` lets the controller show the target count in the confirmation dialog, convert each machine's `uninstall_string`, and group machines with different commands into separate tasks.

**Where:** `shared/OSQuery/Programs.vala` (`rpc_register()` and new `machines()` method after `list()`), plus `docs/rpc-commands.md` after `Programs.list`.

**Depends on:** none.

#### Remove — `shared/OSQuery/Programs.vala` (`rpc_register()`)

```vala
			OLLMrpc.Request.add_class(
				"Programs", typeof(Programs),
				"list", "ii"
			);
```

#### Replace with — `shared/OSQuery/Programs.vala` (`rpc_register()`)

```vala
			OLLMrpc.Request.add_class(
				"Programs", typeof(Programs),
				"list", "ii",
				"machines", "s"
			);
```

#### Add — `shared/OSQuery/Programs.vala`, immediately after `list()`

Add `machines()` returning live per-agent `Programs` rows matching `name`.

```vala
		/**
		 * List per-machine stored rows for one program ''name''.
		 *
		 * A controller calls this. Rows whose ''agent_id'' is not in
		 * ''agent'' or whose ''deleted_dt'' is set are omitted.
		 *
		 * @param request inbound RPC from a controller
		 * @param name exact ''programs.name''
		 */
		public void machines(OLLMrpc.Request request, string name)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Programs>();
			var query = new SQ.Query<Programs>(Programs.db, "programs");
			var binds = new Gee.HashMap<string, string>();
			binds.set("name", name);
			query.selectWhere(
				"WHERE name = $name AND deleted_dt = 0 " +
					"AND agent_id IN (SELECT id FROM agent) " +
					"ORDER BY agent_id",
				null, binds, rows);
			foreach (var row in rows) {
				row.uninstall_count = row.uninstall_string != "" ? 1 : 0;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
```

#### Add — `docs/rpc-commands.md`, immediately after `Programs.list`

Document `Programs.machines` in the RPC reference.

```markdown
### `Programs.machines`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `s`: exact `programs.name`.
- Reply `retval` `o`: an array of live `Programs` rows (`deleted_dt = 0`) for that `name` whose `agent_id` is in `agent`, ordered by `agent_id`, with `uninstall_count` set to `1` when `uninstall_string` is non-empty.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/Programs.vala`.
```

---

### 2. `controller/store/Programs.vala` — add `load_machines(string name)` and `machines_loaded`

**Why:** Fetch the per-machine `Programs` rows for bulk uninstall without replacing the summary grid's `items`.

**Where:** `controller/store/Programs.vala` (signal after `failed`, and method after `load()`).

**Depends on:** #1 (`Programs.machines`).

#### Add — `controller/store/Programs.vala`, immediately after `public signal void failed`

Add `machines_loaded` signal emitted when `Programs.machines` returns.

```vala
		/**
		 * ''Programs.machines'' returned per-machine rows for ''name''.
		 *
		 * @param name exact ''programs.name''
		 * @param rows per-machine rows matching ''name''
		 */
		public signal void machines_loaded(
			string name,
			Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows
		);
```

#### Add — `controller/store/Programs.vala`, immediately after `load()`

Add `load_machines()` to call `Programs.machines` for one program name.

```vala
		/**
		 * Fetch ''Programs.machines'' for one program ''name'' without
		 * replacing {@link items}.
		 *
		 * @param name exact ''programs.name''
		 */
		public void load_machines(string name)
		{
			if (name == "") {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Programs.machines",
				args = OLLMrpc.args("s", name)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not list machines for " + name, e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not list machines for " + name, response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.Programs>) response.retval.get_object();
				}
				this.machines_loaded(name, listed);
			});
		}
```

---

### 3. `controller/tab/Asset/Programs.vala` — `"delete all"` confirmation dialog & grouped task queuing

**Why:** On `Software -> Windows`, holding the trash button fetches every machine with that program, asks the user to type `"delete all"` to guard against accidental bulk uninstalls, then groups machines by converted silent command and submits one task per distinct command.

**Where:** `controller/tab/Asset/Programs.vala`, `Programs()` constructor before `this.content.append(this.overlay);`.

**Depends on:** Phase 1 #3 (`Store.TaskTarget`), Phase 2 #1 (`Programs.machines`), Phase 2 #2 (`Store.Programs.load_machines`).

#### Add — `controller/tab/Asset/Programs.vala`, immediately before `this.content.append(this.overlay);`

Wire `remove_confirmed` -> `store.load_machines` -> `"delete all"` confirmation `Adw.AlertDialog` -> grouped `task_store.run_command` calls and toasts.

```vala
			var task_store = new Argus.Controller.Store.TaskTarget(window.app);
			task_store.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			task_store.submitted.connect((count) => {
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				this.toasts.add_toast(new Adw.Toast(label));
			});
			this.remove_confirmed.connect((obj) => {
				var row = obj as Argus.Shared.OSQuery.Programs;
				if (row == null) {
					return;
				}
				this.store.load_machines(row.name);
			});
			this.store.machines_loaded.connect((name, rows) => {
				var grouped = new Gee.HashMap<string, Gee.ArrayList<int32>>();
				var total = 0;
				foreach (var row in rows) {
					if (row.agent_id < 1) {
						continue;
					}
					var cmd = row.silent_command();
					if (cmd == "") {
						continue;
					}
					if (!grouped.has_key(cmd)) {
						grouped.set(cmd, new Gee.ArrayList<int32>());
					}
					var ids = grouped.get(cmd);
					if (!ids.contains((int32) row.agent_id)) {
						ids.add((int32) row.agent_id);
						total++;
					}
				}
				if (total < 1) {
					this.toasts.add_toast(new Adw.Toast(
						"No uninstall command found for " + name));
					return;
				}
				var count_label = total == 1 ? "1 machine" : total.to_string() + " machines";
				var confirm = new Adw.AlertDialog(
					"Uninstall " + name,
					"This removes " + name + " from " + count_label +
						".\nType \"delete all\" to confirm.");
				var entry = new Gtk.Entry() {
					placeholder_text = "delete all"
				};
				confirm.set_extra_child(entry);
				confirm.add_response("cancel", "Cancel");
				confirm.add_response("uninstall", "Uninstall");
				confirm.set_response_appearance(
					"uninstall", Adw.ResponseAppearance.DESTRUCTIVE);
				confirm.set_response_enabled("uninstall", false);
				confirm.set_default_response("cancel");
				confirm.set_close_response("cancel");
				entry.changed.connect(() => {
					confirm.set_response_enabled(
						"uninstall", entry.text.strip() == "delete all");
				});
				confirm.response.connect((response) => {
					if (response != "uninstall" || entry.text.strip() != "delete all") {
						return;
					}
					foreach (var entry_cmd in grouped.entries) {
						task_store.run_command(
							"Uninstall " + name, entry_cmd.key, entry_cmd.value);
					}
				});
				confirm.present(this);
			});
```

---

## Next

- ⏳ Verify hold-to-uninstall on **Machines → Windows programs** (Phase 1) and **Software → Windows** with `"delete all"` (Phase 2) on a Windows controller against live agents.
