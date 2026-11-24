# Debian package list stays stale after apt update and upgrade

**Status:** ✅

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

- Agent — [`agent/linux/PackageMonitor.vala`](../../../agent/linux/PackageMonitor.vala)
  - `apt()` installs a directory monitor on `/var/lib/dpkg`.
  - Each `changed` signal (re)arms `GLib.Timeout.add_seconds(60, …)`.
  - The timeout handler waits for non-blocking dpkg locks, then calls `send_packages()`, `Apt.History` send, and `send_pending()`.
- Agent — [`agent/OSQuery/Package.vala`](../../../agent/OSQuery/Package.vala)
  - `send()` runs `SELECT *` for the table and posts `OSQuery.sync` with the class name and row array.
- Server — [`server/OSQuery.vala`](../../../server/OSQuery.vala)
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
  - [`controller/tab/Asset/DebPackages.vala`](../../../controller/tab/Asset/DebPackages.vala), [`controller/tab/Asset/RpmPackages.vala`](../../../controller/tab/Asset/RpmPackages.vala), and [`controller/tab/Asset/Programs.vala`](../../../controller/tab/Asset/Programs.vala) do not connect `window.app.rpc.notification`.
  - [`controller/tab/Tasks.vala`](../../../controller/tab/Tasks.vala) and [`controller/tab/Agent.vala`](../../../controller/tab/Agent.vala) do connect notifications (`event.task`, `event.agent`, …).
- Controller — [`controller/store/DebPackages.vala`](../../../controller/store/DebPackages.vala)
  - `load()` always passes `since` **0** and replaces `items` with the full reply.

```vala
				args = OLLMrpc.args("ii", agent_id, 0)
```

- Controller — [`controller/tab/Asset/Machine/Detail.vala`](../../../controller/tab/Asset/Machine/Detail.vala)
  - Sub-tab `"debian"`: when `debian_loaded` is true, `notify["active-name"]` does not call `this.debian.load()` again.

```vala
					case "debian":
						if (this.debian_loaded) {
							break;
						}
						this.debian_loaded = true;
						this.debian.load(this.current_agent_id);
```

- RPC — [`docs/rpc-commands.md`](../../../docs/rpc-commands.md)
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

Wire path: agent `OSQuery.sync` → server `event.osquery` → [`Window`](../../../controller/Window.vala) relays → [`Application.db_changed`](../../../controller/Application.vala) → Debian package tabs filter on table name and call `Store.DebPackages.load(..., refresh: true)`.

Phase 2 is **Debian packages** first. RPM/Programs mirror later. Update [`docs/rpc-commands.md`](../../../docs/rpc-commands.md) in the same change as Phase 1.

### Phase 1 — Server `event.osquery` after `OSQuery.sync` ✔️

**Where:** [`server/OSQuery.vala`](../../../server/OSQuery.vala) `sync()`

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

#### Add — [`docs/rpc-commands.md`](../../../docs/rpc-commands.md) under **Notifications** (after `event.task`)

```markdown
### `event.osquery`

- Broadcast after every successful `OSQuery.sync`.
- Arguments `i`: `agent_id` of the connection that posted the sync.
- Action: the sync class name (`DebPackages`, `SystemInfo`, …).
- The controller relays this as {@link Argus.Controller.Application.db_changed}; listeners filter on `action`.
```

### Phase 2 — `db_changed`, partial `DebPackages.list` ✔️

**Depends on:** Phase 1.

(Full verbatim proposals retained in git history; all phases landed in tree.)

### LLM

- User (2026-11-23): application signal `db_changed`; no `mark_dirty`; Debian tabs filter `db_changed`; server broadcasts after every `OSQuery.sync` (no table switch).
- Pointer (superseded umbrella): 2026-11-14-CLOSED-package-status-cache-notification.md.
- Repro log: `DebPackages.list` 09:11:30 before `OSQuery.sync` 09:12:14–16; no later list that morning.
- User (2026-11-23): confirmed closed; moved to `docs/bugs/done/`.