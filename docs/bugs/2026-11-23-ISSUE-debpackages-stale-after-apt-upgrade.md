# Debian package list stays stale after apt update and upgrade

**Status:** ✔️

---

### User decisions required

None.

### User reported

- 🔷 `apt-get update` and upgrade completed successfully on the machine.
- 🔷 The package list did not update when returning to that view.
- 🔷 Expected flow: PackageMonitor → refreshed OSQuery on the server → server notifies the controller → partial `DebPackages.list` when the user opens the tab.

### Success scenario

- Package change on the host reaches the server via `OSQuery.sync` within the monitor’s quiet period.
- Connected controllers receive a server notification for that agent and package table.
- Opening the Debian packages tab issues `DebPackages.list` with `since` when a list is already loaded, and the grid matches server data.

### Current behavior

- What you said
  - Apt update and upgrade succeeded.
  - Navigating back to the package list left stale rows on screen.
- Observable outcome
  - UI did not show post-upgrade package data without restarting the controller or forcing a full reload.

### Codebase observed behavior

- Agent — [`agent/linux/PackageMonitor.vala`](../../agent/linux/PackageMonitor.vala)
  - `apt()` installs a directory monitor on `/var/lib/dpkg`.
  - Each `changed` signal (re)arms `GLib.Timeout.add_seconds(60, …)`.
  - The timeout handler waits for non-blocking dpkg locks, then calls `send_packages()`, `Apt.History` send, and `send_pending()`.
- Agent — [`agent/OSQuery/Package.vala`](../../agent/OSQuery/Package.vala)
  - `send()` runs `SELECT *` for the table and posts `OSQuery.sync` with the class name and row array.
- Server — [`server/OSQuery.vala`](../../server/OSQuery.vala)
  - `sync()` calls `model.sync`, `backupDB()`, optionally `os_update.check` for `OsVersion`, then replies `msg = "ok"`.
  - The method does not call `Application.broadcast`.

```vala
			this.app.db.backupDB();
			if (name == "OsVersion") {
				this.app.os_update.check.begin();
			}
			request.reply(new OLLMrpc.Response() { 
				msg = "ok" 
			});
```

- Controller — Asset package UI
  - [`controller/tab/Asset/DebPackages.vala`](../../controller/tab/Asset/DebPackages.vala), [`controller/tab/Asset/RpmPackages.vala`](../../controller/tab/Asset/RpmPackages.vala), and [`controller/tab/Asset/Programs.vala`](../../controller/tab/Asset/Programs.vala) do not connect `window.app.rpc.notification`.
  - [`controller/tab/Tasks.vala`](../../controller/tab/Tasks.vala) and [`controller/tab/Agent.vala`](../../controller/tab/Agent.vala) do connect notifications (`event.task`, `event.agent`, …).
- Controller — [`controller/store/DebPackages.vala`](../../controller/store/DebPackages.vala)
  - `load()` always passes `since` **0** and replaces `items` with the full reply.

```vala
				args = OLLMrpc.args("ii", agent_id, 0)
```

- Controller — [`controller/tab/Asset/Machine/Detail.vala`](../../controller/tab/Asset/Machine/Detail.vala)
  - Sub-tab `"debian"`: when `debian_loaded` is true, `notify["active-name"]` does not call `this.debian.load()` again.

```vala
					case "debian":
						if (this.debian_loaded) {
							break;
						}
						this.debian_loaded = true;
						this.debian.load(this.current_agent_id);
```

- RPC — [`docs/rpc-commands.md`](../../docs/rpc-commands.md)
  - Documents `DebPackages.list` arguments `ii` (`agent_id`, `since`); non-zero `since` returns rows changed after that time.
  - Documents `OSQuery.sync`; does not document a controller notification after sync.

### Debugging

#### Current debug output

- Source — `/var/log/argusrm/server.log`, 2026-11-23.

```
09:10:57  Task.submit
09:11:14  Command.ended  (agent 19)
09:11:30  DebPackages.list  (controller)
09:12:14  OSQuery.sync  (agent 19)
09:12:15  OSQuery.sync  (agent 19)
09:12:16  OSQuery.sync  (agent 19)
```

#### Debug code added (remove when complete)

None.

### Proposed fix

Wire path: agent `OSQuery.sync` → server `event.osquery` → [`Window`](../../controller/Window.vala) relays → [`Application.db_changed`](../../controller/Application.vala) → Debian package tabs filter on table name and call `Store.DebPackages.load(..., refresh: true)`.

Phase 2 is **Debian packages** first. RPM/Programs mirror later. Update [`docs/rpc-commands.md`](../../docs/rpc-commands.md) in the same change as Phase 1.

### Phase 1 — Server `event.osquery` after `OSQuery.sync`

**Where:** [`server/OSQuery.vala`](../../server/OSQuery.vala) `sync()`

**Depends on:** none.

#### Remove

```vala
			this.app.db.backupDB();
			if (name == "OsVersion") {
				this.app.os_update.check.begin();
			}
			request.reply(new OLLMrpc.Response() { 
				msg = "ok" 
			});
```

#### Replace with

```vala
			this.app.db.backupDB();
			this.app.broadcast(new OLLMrpc.Notification() {
				method = "event.osquery",
				action = name,
				args = OLLMrpc.args("i", (int) connection.user.id)
			});
			if (name == "OsVersion") {
				this.app.os_update.check.begin();
			}
			request.reply(new OLLMrpc.Response() { 
				msg = "ok" 
			});
```

- No table filter on the server. Every successful `OSQuery.sync` notifies all connected controllers; each subscriber ignores tables it does not use.

#### Add — [`docs/rpc-commands.md`](../../docs/rpc-commands.md) under **Notifications** (after `event.task`)

```markdown
### `event.osquery`

- Broadcast after every successful `OSQuery.sync`.
- Arguments `i`: `agent_id` of the connection that posted the sync.
- Action: the sync class name (`DebPackages`, `SystemInfo`, …).
- The controller relays this as {@link Argus.Controller.Application.db_changed}; listeners filter on `action`.
```

### Phase 2 — `db_changed`, partial `DebPackages.list`

**Depends on:** Phase 1.

#### `controller/Application.vala` — Add (after `public Window window { get; set; }`)

```vala
		/**
		 * Server data for a table changed (relay from ''event.osquery'').
		 *
		 * @param table server class name (notification action)
		 * @param agent_id host that posted the change
		 */
		public signal void db_changed(string table, int agent_id);
```

#### `controller/Window.vala` — Add (constructor, after `this.connection_check_id = GLib.Timeout.add_seconds(1, this.check_connection);`)

```vala
			this.app.rpc.notification.connect((notification) => {
				if (notification.method != "event.osquery") {
					return;
				}
				if (notification.args.size < 1 || notification.action == "") {
					return;
				}
				this.app.db_changed(
					notification.action,
					notification.args.get(0).get_int());
			});
```

#### `controller/android/Window.vala` — Add

Same block as desktop `Window` (after `this.connection_check_id = GLib.Timeout.add_seconds(1, this.check_connection);`).

#### `controller/store/DebPackages.vala` — Add (field with `loaded_agent`)

```vala
		private int list_since = 0;
```

#### `controller/store/DebPackages.vala` — Add (before `load`)

```vala
		private void apply_delta(Gee.ArrayList<Argus.Shared.OSQuery.DebPackages> delta)
		{
			var at = new Gee.HashMap<string, int>();
			for (var i = 0; i < this.items_store.size; i++) {
				at.set(this.items_store.get(i).name, i);
			}
			var drop = new Gee.ArrayList<int>();
			foreach (var row in delta) {
				if (row.deleted_dt <= 0) {
					continue;
				}
				if (!at.has_key(row.name)) {
					continue;
				}
				drop.add(at.get(row.name));
				at.unset(row.name);
			}
			drop.sort((a, b) => {
				if (a == b) {
					return 0;
				}
				if (a > b) {
					return -1;
				}
				return 1;
			});
			foreach (var index in drop) {
				this.items_store.remove_at(index);
				this.items_changed((uint) index, 1, 0);
			}
			at.clear();
			for (var i = 0; i < this.items_store.size; i++) {
				at.set(this.items_store.get(i).name, i);
			}
			foreach (var row in delta) {
				if (row.deleted_dt > 0) {
					continue;
				}
				if (!at.has_key(row.name)) {
					this.items_store.add(row);
					this.items_changed((uint) (this.items_store.size - 1), 0, 1);
					at.set(row.name, this.items_store.size - 1);
					continue;
				}
				var index = at.get(row.name);
				this.items_store.set(index, row);
				this.items_changed((uint) index, 1, 1);
			}
		}
```

#### `controller/store/DebPackages.vala` — Remove

```vala
		public void load(int agent_id)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent && agent_id > 0 && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>();
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "DebPackages.list",
				args = OLLMrpc.args("ii", agent_id, 0)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list Debian packages", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list Debian packages", response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>) response.retval.get_object();
				}
				this.items = listed;
				this.busy = false;
			});
		}
```

#### `controller/store/DebPackages.vala` — Replace with

```vala
		public void load(int agent_id, bool refresh = false)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			if (!refresh && agent_id == this.loaded_agent && this.items_store.size > 0) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent && agent_id > 0 && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>();
				this.list_since = 0;
			}
			this.loaded_agent = agent_id;
			var refresh_start = (int) GLib.DateTime.now_utc().to_unix();
			var query_since = 0;
			if (refresh && agent_id > 0 && this.items_store.size > 0 && this.list_since > 0) {
				query_since = this.list_since;
			}
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "DebPackages.list",
				args = OLLMrpc.args("ii", agent_id, query_since)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list Debian packages", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list Debian packages", response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.DebPackages>) response.retval.get_object();
				}
				if (query_since > 0) {
					this.apply_delta(listed);
				} else {
					this.items = listed;
				}
				this.list_since = refresh_start;
				this.busy = false;
			});
		}
```

- `refresh` true and `agent_id` **0**: full list (`since` 0); aggregated rows have no `since` delta on the server.
- `refresh` true and `agent_id` **> 0**: `since = list_since` and `apply_delta`.

#### `controller/tab/Asset/DebPackages.vala` — Remove

```vala
			this.map.connect(() => {
				this.store.load(0);
			});
```

#### `controller/tab/Asset/DebPackages.vala` — Add (field on class, with other private fields)

```vala
		private bool refresh = false;
```

#### `controller/tab/Asset/DebPackages.vala` — Replace with

```vala
			this.map.connect(() => {
				this.store.load(0, this.refresh);
				this.refresh = false;
			});
			this.window.app.db_changed.connect((table, agent_id) => {
				if (table != "DebPackages" && table != "PackageUpdates") {
					return;
				}
				if (this.get_mapped()) {
					this.store.load(0, true);
					return;
				}
				this.refresh = true;
			});
```

#### `controller/tab/Asset/Machine/DebPackages.vala` — Add (field with `agent_id`)

```vala
		private bool refresh = false;
```

#### `controller/tab/Asset/Machine/DebPackages.vala` — Add (constructor, before `var update = new Gtk.Button`)

```vala
			window.app.db_changed.connect((table, changed_id) => {
				if (table != "DebPackages" && table != "PackageUpdates") {
					return;
				}
				if (changed_id > 0 && this.agent_id > 0 && changed_id != this.agent_id) {
					return;
				}
				if (this.agent_id < 1) {
					this.refresh = true;
					return;
				}
				if (this.get_mapped()) {
					this.store.load(this.agent_id, true);
					return;
				}
				this.refresh = true;
			});
```

#### `controller/tab/Asset/Machine/DebPackages.vala` — Replace

```vala
		public void load(int agent_id)
		{
			this.agent_id = agent_id;
			this.store.load(agent_id);
		}
```

#### `controller/tab/Asset/Machine/DebPackages.vala` — Replace with

```vala
		public void load(int agent_id)
		{
			this.agent_id = agent_id;
			var do_refresh = this.refresh;
			this.refresh = false;
			this.store.load(agent_id, do_refresh);
		}
```

#### `controller/tab/Asset/Machine/Detail.vala` — Remove (field)

```vala
		private bool debian_loaded = false;
```

#### `controller/tab/Asset/Machine/Detail.vala` — Remove (`clear()`)

```vala
			this.debian_loaded = false;
```

#### `controller/tab/Asset/Machine/Detail.vala` — Remove (`show_machine()`, reset block)

```vala
			this.debian_loaded = false;
```

#### `controller/tab/Asset/Machine/Detail.vala` — Remove (`notify["active-name"]`, `case "debian"`)

```vala
					case "debian":
						if (this.debian_loaded) {
							break;
						}
						this.debian_loaded = true;
						this.debian.load(this.current_agent_id);
						break;
```

#### `controller/tab/Asset/Machine/Detail.vala` — Replace with (`notify["active-name"]`)

```vala
					case "debian":
						this.debian.load(this.current_agent_id);
						break;
```

#### `controller/tab/Asset/Machine/Detail.vala` — Remove (`show_machine()`, `case "debian"`)

```vala
				case "debian":
					if (this.debian_loaded) {
						break;
					}
					this.debian_loaded = true;
					this.debian.load(agent_id);
					break;
```

#### `controller/tab/Asset/Machine/Detail.vala` — Replace with (`show_machine()`)

```vala
				case "debian":
					this.debian.load(agent_id);
					break;
```

### LLM

- User (2026-11-23): application signal `db_changed`; no `mark_dirty`; Debian tabs filter `db_changed`; server broadcasts after every `OSQuery.sync` (no table switch).
- Pointer: [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md).
- Repro log: `DebPackages.list` 09:11:30 before `OSQuery.sync` 09:12:14–16; no later list that morning.