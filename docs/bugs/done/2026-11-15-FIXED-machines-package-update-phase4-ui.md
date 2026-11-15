# Machines package update & Tasks tab — Phase 4 (connect UI & handlers)

**Status:** ✅ closed 2026-11-15 — Phase 4 implemented (`ninja -C build`, `meson test -C build` 6/6 passed) and archived

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-machines-package-update.md](2026-11-13-FIXED-machines-package-update.md), [../2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)

---

## Problem

- 🔷 Phases 1–3 landed the data model (`task`, `task_target`, `script`, `script_perm`), controller UI skeletons (`SystemInfo` row menu, `Tab.Tasks` grid + terminal viewer), and server/agent RPCs (`Script.search`, `Task.submit`, `Task.all_targets`, `Task.logs`, `event.task`).
- 🔷 **Actual:**
  - `controller/tab/Asset/SystemInfo.vala` right-click `row.update` / `row.upgrade` actions have no activate handlers wired.
  - `controller/tab/Tasks.vala` uses an empty local `GLib.ListStore` instead of a server-backed store, and selecting a row clears the terminal buffer without calling `Task.logs` or `Task.watch`.
  - No `controller/store/TaskTarget.vala` exists yet to load targets, search scripts, submit tasks, fetch logs, or watch targets.

---

## Evidence

✔️ Ready in the tree from Phases 1–3:

- ✔️ `controller/tab/Asset/SystemInfo.vala` already builds `Adw.ToastOverlay` (`toasts`), `Gtk.MultiSelection`, and the row `Gtk.PopoverMenu` with `row.update` / `row.upgrade` (`update_action`, `upgrade_action`), hidden when only Windows/unknown machines are selected.
- ✔️ `controller/tab/Tasks.vala` already renders `task_targets` columns, `Filters.Tasks`, `refresh` button, `spinner`, `term_box`, `term_title`, `term_meta`, and `term_view` (with `"stderr"` and `"stdin"` tags).
- ✔️ Server RPCs ready (`docs/rpc-commands.md`):
  - `Script.search` `sss` (`platform`, `app`, `action` → `o` array of `Argus.Shared.SQT.Script`).
  - `Task.submit` `ovb` (`Argus.Shared.SQT.Task`, `ai` `agent_ids`, `watch` → `o` `TaskTarget` array).
  - `Task.all_targets` (`""` → `o` joined `TaskTarget` array).
  - `Task.logs` `i` (`target_id` → `as` `[stdout, stderr, stdin]`).
  - `Task.watch` `i` (`target_id` → `o` `TaskTarget`).
  - Notifications: `event.task` (`queued` / `started` / `ended`), `controller.stdout` (`is`), `controller.stderr` (`is`), `controller.ended` (`i`).

---

## Phase 4 — Connect UI & handlers (`controller/store/`, `controller/tab/`)

**Depends on:** Phases 1–3 ([2026-11-13-FIXED-machines-package-update.md](2026-11-13-FIXED-machines-package-update.md)).

### Specification

- 🔷 **Add `controller/store/TaskTarget.vala` (`Argus.Controller.Store.TaskTarget`, `GLib.ListModel` over `Argus.Shared.SQT.TaskTarget`, matching `Store.SystemInfo` / `Store.Repository`):**
  - `load()` calls `Task.all_targets` and updates `items` (with `busy` / `failed` signals).
  - `fetch_logs(int target_id)` calls `Task.logs` and emits `logs_loaded(int target_id, string stdout_text, string stderr_text, string stdin_text)`.
  - `watch(int target_id)` calls `Task.watch`.
  - `run_script(string platform, string app, string action, Gee.ArrayList<int32> agent_ids)` calls `Script.search(platform, app, action)`, constructs `Argus.Shared.SQT.Task` pointing at `script_id = script.id` (`is_script = true`, `command = ""`, `name = app + " " + action`, `payload_hash`), calls `Task.submit`, and emits `submitted(int count)`.
- 🔷 **Wire `controller/tab/Asset/SystemInfo.vala` right-click actions (`row.update`, `row.upgrade`):**
  - Keep only the two generic row actions (`"update"` and `"upgrade"`) on `row_actions` matching the right-click menu items.
  - Inline both handlers to call `task_store.run_script("linux", "apt", ..., this.selected_agents(APT))` and `task_store.run_script("linux", "dnf", ..., this.selected_agents(DNF))` (`run_script` is a no-op when `agent_ids.size < 1`).
  - 🔷 On `submitted(int count)`, show an `Adw.Toast` on `toasts` (`"Tasks created and running — view them in the Tasks tab"`) and stay on Machines without switching tabs; on `failed`, show an `Adw.Toast` on `toasts`.
- 🔷 **Wire `controller/tab/Tasks.vala`:**
  - Replace the placeholder `GLib.ListStore` with `Store.TaskTarget`, bind `refresh.clicked` and `map` to `store.load()`, bind `spinner.visible` to `store.busy`, and wrap `paned` in `Adw.ToastOverlay` for `store.failed` toasts.
  - On row selection: call `store.fetch_logs((int) row.id)` to populate `term_view.buffer`, and if `row.ended == 0 && !row.is_cancelled`, call `store.watch((int) row.id)`.
  - Connect `window.app.rpc.notification`: reload `store.load()` on `event.task`, append live `controller.stdout` / `controller.stderr` chunks matching `watched_identifier`, and reload on matching `controller.ended`.

### Concrete code proposals (Phase 4)

#### 1. `controller/store/TaskTarget.vala`, `controller/meson.build`, `docs/meson.build` — add `Store.TaskTarget`

**Why:** Provide a `GLib.ListModel` store for `Task.all_targets`, `Task.logs`, `Task.watch`, `Script.search`, and `Task.submit`.

**Where:** New file `controller/store/TaskTarget.vala`, plus `controller/meson.build` and `docs/meson.build`.

**Depends on:** Phase 3 RPCs (`Script.search`, `Task.submit`, `Task.all_targets`, `Task.logs`).

##### Add — `controller/store/TaskTarget.vala`

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

namespace Argus.Controller.Store
{
	/**
	 * Task target runs on the open server.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.SQT.TaskTarget}.
	 * {@link items} is the backing list. {@link load} calls
	 * ''Task.all_targets''. {@link run_script} resolves a library script
	 * via ''Script.search'' and submits a task via ''Task.submit''.
	 * {@link fetch_logs} and {@link watch} load saved output and enable
	 * live streaming for one target.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.TaskTarget(app);
	 * store.load();
	 * }}}
	 */
	public class TaskTarget : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.SQT.TaskTarget> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
		}
		private int epoch = 0;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.SQT.TaskTarget> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * True while ''Task.all_targets'' is in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * An RPC call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * ''Task.submit'' queued targets on the server.
		 *
		 * @param count number of target rows created
		 */
		public signal void submitted(int count);

		/**
		 * ''Task.logs'' returned saved output streams.
		 *
		 * @param target_id ''task_target.id''
		 * @param stdout_text saved stdout
		 * @param stderr_text saved stderr
		 * @param stdin_text saved stdin
		 */
		public signal void logs_loaded(
			int target_id,
			string stdout_text,
			string stderr_text,
			string stdin_text
		);

		/**
		 * @param app the controller process
		 */
		public TaskTarget(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.SQT.TaskTarget);
		}

		/**
		 * Number of target rows in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Target row at ''position''.
		 *
		 * @param position zero-based index
		 * @return the row, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''Task.all_targets'' and apply it to {@link items}.
		 */
		public void load()
		{
			this.busy = true;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.all_targets"
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list tasks", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list tasks", response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID ||
					!response.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.items = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
					this.busy = false;
					return;
				}
				this.items = (Gee.ArrayList<Argus.Shared.SQT.TaskTarget>) response.retval.get_object();
				this.busy = false;
			});
		}

		/**
		 * Search a script by ''platform'', ''app'', and ''action'', then
		 * submit a task for ''agent_ids''.
		 *
		 * @param platform target OS family
		 * @param app target tool
		 * @param action target action
		 * @param agent_ids selected ''agent.id'' values
		 */
		public void run_script(
			string platform,
			string app,
			string action,
			Gee.ArrayList<int32> agent_ids
		) {
			if (agent_ids.size < 1) {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Script.search",
				args = OLLMrpc.args("sss", platform, app, action)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not find script", e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not find script", response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID ||
					!response.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.failed("Could not find script",
						"No script found for " + platform + " " + app + " " + action);
					return;
				}
				var scripts = (Gee.ArrayList<Argus.Shared.SQT.Script>) response.retval.get_object();
				if (scripts.size == 0) {
					this.failed("Could not find script",
						"No script found for " + platform + " " + app + " " + action);
					return;
				}
				var script = scripts.get(0);
				var now = new GLib.DateTime.now_utc().to_unix();
				var builder = new GLib.VariantBuilder(new GLib.VariantType("ai"));
				string[] id_text = {};
				foreach (var id in agent_ids) {
					builder.add_value(new GLib.Variant.int32(id));
					id_text += id.to_string();
				}
				var canonical = script.id.to_string() + "|1||" +
					now.to_string() + "|" + string.joinv(",", id_text);
				var task = new Argus.Shared.SQT.Task() {
					name = app + " " + action,
					is_script = true,
					script_id = script.id,
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
			});
		}

		/**
		 * Fetch saved stdout, stderr, and stdin logs for one target.
		 *
		 * @param target_id ''task_target.id''
		 */
		public void fetch_logs(int target_id)
		{
			if (target_id < 1) {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.logs",
				args = OLLMrpc.args("i", target_id)
			}, (obj, res) => {
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.failed("Could not load logs", e.message);
					return;
				}
				if (response.error != null) {
					this.failed("Could not load logs", response.error.message);
					return;
				}
				if (response.retval.type() == GLib.Type.INVALID) {
					this.logs_loaded(target_id, "", "", "");
					return;
				}
				var parts = (string[]) response.retval;
				var stdout_text = parts.length > 0 ? parts[0] : "";
				var stderr_text = parts.length > 1 ? parts[1] : "";
				var stdin_text = parts.length > 2 ? parts[2] : "";
				this.logs_loaded(target_id, stdout_text, stderr_text, stdin_text);
			});
		}

		/**
		 * Subscribe this connection to live output for an active target.
		 *
		 * @param target_id ''task_target.id''
		 */
		public void watch(int target_id)
		{
			if (target_id < 1) {
				return;
			}
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.watch",
				args = OLLMrpc.args("i", target_id)
			}, (obj, res) => {
				try {
					this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.debug("%s", e.message);
				}
			});
		}
	}
}
```

##### Add — `controller/meson.build`, after `'store/MachineGeneral.vala',`

```meson
	'store/TaskTarget.vala',
```

##### Add — `docs/meson.build`, after `'../controller/store/MachineGeneral.vala',`

```meson
  '../controller/store/TaskTarget.vala',
```

---

#### 2. `controller/tab/Asset/SystemInfo.vala` — wire `row.update`, `row.upgrade`, and toast

**Why:** Wire `row.update` and `row.upgrade` directly to `task_store.run_script()` with `this.selected_agents()`, and show toasts on `toasts`.

**Where:** `controller/tab/Asset/SystemInfo.vala` (constructor `row_actions` / `row_click`, and `selected_agents()` helper).

**Depends on:** #1 (`Store.TaskTarget`).

##### Remove — `controller/tab/Asset/SystemInfo.vala` (constructor `row_actions` & `row_click`)

```vala
			var row_actions = new GLib.SimpleActionGroup();
			var update_action = new GLib.SimpleAction("update", null);
			var upgrade_action = new GLib.SimpleAction("upgrade", null);
			row_actions.add_action(update_action);
			row_actions.add_action(upgrade_action);
			this.grid.insert_action_group("row", row_actions);
			var row_click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			row_click.pressed.connect((n_press, x, y) => {
				var picked = this.grid.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (picked != null && picked != this.grid &&
					picked.get_data<Gtk.ListItem>("argus-grid-row") == null) {
					picked = picked.parent;
				}
				if (picked == null || picked == this.grid) {
					row_click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
				var row_item = picked.get_data<Gtk.ListItem>("argus-grid-row");
				if (row_item == null || row_item.item == null) {
					return;
				}
				if (!selection.is_selected(row_item.position)) {
					selection.select_item(row_item.position, true);
				}
				var has_linux = false;
				var total = selection.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					if (!selection.is_selected(i)) {
						continue;
					}
					var row = selection.get_item(i) as Argus.Shared.OSQuery.SystemInfo;
					if (row == null) {
						continue;
					}
					switch (row.package_manager()) {
						case Argus.Shared.OSQuery.PackageManager.APT:
						case Argus.Shared.OSQuery.PackageManager.DNF:
							has_linux = true;
							break;

						default:
							continue;
					}
					break;
				}
				if (!has_linux) {
					row_click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
```

##### Replace with

```vala
			var task_store = new Argus.Controller.Store.TaskTarget(window.app);
			task_store.failed.connect((heading, message) => {
				toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			task_store.submitted.connect((count) => {
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				toasts.add_toast(new Adw.Toast(label));
			});
			var row_actions = new GLib.SimpleActionGroup();
			var update_action = new GLib.SimpleAction("update", null);
			update_action.activate.connect(() => {
				task_store.run_script("linux", "apt", "update",
					this.selected_agents(Argus.Shared.OSQuery.PackageManager.APT));
				task_store.run_script("linux", "dnf", "update",
					this.selected_agents(Argus.Shared.OSQuery.PackageManager.DNF));
			});
			var upgrade_action = new GLib.SimpleAction("upgrade", null);
			upgrade_action.activate.connect(() => {
				task_store.run_script("linux", "apt", "upgrade",
					this.selected_agents(Argus.Shared.OSQuery.PackageManager.APT));
				task_store.run_script("linux", "dnf", "upgrade",
					this.selected_agents(Argus.Shared.OSQuery.PackageManager.DNF));
			});
			row_actions.add_action(update_action);
			row_actions.add_action(upgrade_action);
			this.grid.insert_action_group("row", row_actions);
			var row_click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			row_click.pressed.connect((n_press, x, y) => {
				if (this.selected_agents(Argus.Shared.OSQuery.PackageManager.APT).size == 0 &&
					this.selected_agents(Argus.Shared.OSQuery.PackageManager.DNF).size == 0) {
					row_click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
```

##### Add — `controller/tab/Asset/SystemInfo.vala`, immediately after `SystemInfo()` constructor

Add `selected_agents()` helper.

```vala
		/**
		 * Collect ''agent.id'' values for selected machines matching ''pm''.
		 *
		 * @param pm package manager family to match
		 * @return selected agent ids
		 */
		private Gee.ArrayList<int32> selected_agents(Argus.Shared.OSQuery.PackageManager pm)
		{
			var ids = new Gee.ArrayList<int32>();
			var selection = (Gtk.MultiSelection) this.grid.model;
			var total = selection.get_n_items();
			for (var i = (uint) 0; i < total; i++) {
				if (!selection.is_selected(i)) {
					continue;
				}
				var row = selection.get_item(i) as Argus.Shared.OSQuery.SystemInfo;
				if (row == null || row.package_manager() != pm) {
					continue;
				}
				ids.add((int32) row.agent_id);
			}
			return ids;
		}
```

---

#### 3. `controller/tab/Tasks.vala` — connect `Store.TaskTarget`, logs, watch, and live notifications

**Why:** Populate the Tasks grid from `Task.all_targets`, load saved logs and stream live output on selection, and refresh automatically on `event.task`.

**Where:** `controller/tab/Tasks.vala` (`store` field, `Tasks()` constructor).

**Depends on:** #1 (`Store.TaskTarget`).

##### Remove — `controller/tab/Tasks.vala`

```vala
		public Argus.Controller.Window window;
		private GLib.ListStore store;
		private Argus.Controller.Filters.Tasks filter;
```

##### Replace with

```vala
		public Argus.Controller.Window window;
		private Argus.Controller.Store.TaskTarget store;
		private Argus.Controller.Filters.Tasks filter;
		private int64 watched_id = 0;
		private int watched_identifier = 0;
```

##### Remove — `controller/tab/Tasks.vala`

```vala
			this.store = new GLib.ListStore(typeof(Argus.Shared.SQT.TaskTarget));
```

##### Replace with

```vala
			this.store = new Argus.Controller.Store.TaskTarget(window.app);
```

##### Remove — `controller/tab/Tasks.vala`

```vala
			selection.selection_changed.connect((position, n_items) => {
				var row = selection.selected_item as Argus.Shared.SQT.TaskTarget;
				if (row == null) {
					term_box.visible = false;
					term_title.label = "";
					term_meta.label = "";
					term_view.buffer.text = "";
					return;
				}
				if (!term_box.visible) {
					term_box.visible = true;
					paned.position = paned.get_height() / 2;
				}
				var host = row.agent_id_hostname != "" ?
					row.agent_id_hostname : "Agent " + row.agent_id.to_string();
				term_title.label = host + " — " + row.display_task;
				var exit_text = row.display_exit != "" ? " · exit " + row.display_exit : "";
				term_meta.label = row.display_state + exit_text;
				term_view.buffer.text = "";
			});
			this.append(bar);
			this.append(paned);
```

##### Replace with

```vala
			var toasts = new Adw.ToastOverlay() {
				child = paned,
				hexpand = true,
				vexpand = true
			};
			this.store.bind_property("busy", spinner, "visible", GLib.BindingFlags.SYNC_CREATE);
			refresh.clicked.connect(() => {
				this.store.load();
			});
			this.store.failed.connect((heading, message) => {
				toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			this.store.logs_loaded.connect((target_id, stdout_text, stderr_text, stdin_text) => {
				if ((int64) target_id != this.watched_id) {
					return;
				}
				term_view.buffer.text = "";
				Gtk.TextIter end;
				if (stdin_text != "") {
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert_with_tags_by_name(ref end, stdin_text, -1, "stdin");
				}
				if (stdout_text != "") {
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert(ref end, stdout_text, -1);
				}
				if (stderr_text != "") {
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert_with_tags_by_name(ref end, stderr_text, -1, "stderr");
				}
			});
			this.store.items_changed.connect((position, removed, added) => {
				if (this.watched_id < 1) {
					return;
				}
				foreach (var item in this.store.items) {
					if (item.id != this.watched_id) {
						continue;
					}
					this.watched_identifier = item.identifier;
					var exit_text = item.display_exit != "" ? " · exit " + item.display_exit : "";
					term_meta.label = item.display_state + exit_text;
					break;
				}
				var total = selection.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var shown = selection.get_item(i) as Argus.Shared.SQT.TaskTarget;
					if (shown == null || shown.id != this.watched_id) {
						continue;
					}
					selection.select_item(i, true);
					break;
				}
			});
			selection.selection_changed.connect((position, n_items) => {
				if (this.store.busy) {
					return;
				}
				var row = selection.selected_item as Argus.Shared.SQT.TaskTarget;
				if (row == null) {
					this.watched_id = 0;
					this.watched_identifier = 0;
					term_box.visible = false;
					term_title.label = "";
					term_meta.label = "";
					term_view.buffer.text = "";
					return;
				}
				if (row.id == this.watched_id) {
					return;
				}
				this.watched_id = row.id;
				this.watched_identifier = row.identifier;
				if (!term_box.visible) {
					term_box.visible = true;
					paned.position = paned.get_height() / 2;
				}
				var host = row.agent_id_hostname != "" ?
					row.agent_id_hostname : "Agent " + row.agent_id.to_string();
				term_title.label = host + " — " + row.display_task;
				var exit_text = row.display_exit != "" ? " · exit " + row.display_exit : "";
				term_meta.label = row.display_state + exit_text;
				term_view.buffer.text = "";
				this.store.fetch_logs((int) row.id);
				if (row.ended == 0 && !row.is_cancelled) {
					this.store.watch((int) row.id);
				}
			});
			this.window.app.rpc.notification.connect((notification) => {
				switch (notification.method) {
					case "event.task":
						this.store.load();
						break;

					case "controller.stdout":
						if (this.watched_identifier < 1 || notification.args.size < 2 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						Gtk.TextIter out_end;
						term_view.buffer.get_end_iter(out out_end);
						term_view.buffer.insert(
							ref out_end, notification.args.get(1).get_string(), -1);
						break;

					case "controller.stderr":
						if (this.watched_identifier < 1 || notification.args.size < 2 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						Gtk.TextIter err_end;
						term_view.buffer.get_end_iter(out err_end);
						term_view.buffer.insert_with_tags_by_name(
							ref err_end, notification.args.get(1).get_string(), -1, "stderr");
						break;

					case "controller.ended":
						if (this.watched_identifier < 1 || notification.args.size < 1 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						this.store.load();
						break;

					default:
						break;
				}
			});
			this.map.connect(() => {
				this.store.load();
			});
			this.append(bar);
			this.append(toasts);
```

---

## Next

- ✅ Implemented `#1`–`#3` (`controller/store/TaskTarget.vala`, `controller/tab/Asset/SystemInfo.vala`, `controller/tab/Tasks.vala`, `controller/meson.build`, `docs/meson.build`) and verified `ninja -C build` + `meson test -C build --print-errorlogs` (6/6 passed).
- ✅ Archived to `docs/bugs/done/2026-11-15-FIXED-machines-package-update-phase4-ui.md`.
