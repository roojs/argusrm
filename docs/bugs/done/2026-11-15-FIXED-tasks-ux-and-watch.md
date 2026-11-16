# Tasks tab: Pending vs Queued state, 15m Active retention, live watch, and startup dispatch delay

**Status:** ✅ closed 2026-11-15 — fixes `#1`–`#4` implemented (`ninja -C build`, `meson test -C build` 6/6 passed) and archived

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/7.1-tasks-implementation.md`, `docs/plans/7.2-tasks-ui-and-signing.md`, [2026-11-15-FIXED-machines-package-update-phase4-ui.md](2026-11-15-FIXED-machines-package-update-phase4-ui.md)

---

## Problem

- 🔷 Submitting an `apt update` task from **Machines** showed the task in **Tasks** with `State = Queued` and an empty `Start` column, and the task did not start immediately (~60s delay).
  - 🔷 Expected: a task waiting to run right now (not scheduled in the future) should show `Pending` rather than `Queued`; `Queued` should only be used when the task has a scheduled future time, and that scheduled time should display and live-update in `Start` (including when bumped `+60`s on retry).
  - 🔷 Expected: if the target agent is not connected, show an indicator that the agent is offline/not connected; when it connects, due tasks should dispatch immediately instead of waiting 60 seconds.
- 🔷 Once the task ran and finished (in ~2.8s), it immediately disappeared from the default `Active` view and closed the terminal log pane.
  - 🔷 Expected: keep completed (and recently ended) tasks in the `Active` filter for at least 15 minutes with status `Completed` (or `Failed` / `Cancelled`) so users can watch fast tasks finish and inspect their output without switching filters.
- 🔷 Selecting a running `apt update` task missed trailing stdout lines (`Reading package lists...`), and the saved stdout ended at `Reading package lists...` without a final `Done` / package summary line.
  - 🔷 Expected: live output should stream for already-running tasks, and the terminal viewer should end with `\n\nCommand succeeded (exit 0)` / `Command failed (exit N)` so completion is unambiguous without emulating a TTY.

---

## Evidence

- ℹ️ Logs inspected from live run (`2026-11-15 10:22–10:27`): `/var/log/argusrm/server.log`, `/var/log/argusrm/agent.log`, `~/.cache/argusrm/controller.log`, and `/var/log/argusrm/commands/2026/11/15/16-{1,2,3}.stdout`.
- ✔️ **60-second startup delay (`server.log` + `agent.log` + `controller.log`):**
  - `10:22:50.805` `argusrm-server` and `argusrm-agent` restarted (`agent.log` logged `Connection refused` while server was initializing, entering its reconnect wait).
  - `10:23:05.241` Controller called `Task.submit` (`id=9`, task 1, target 1 on agent 16) with `watch = false`.
  - `10:23:05` `Task.run` (`server/SQT/Task.vala`) failed `sender.dispatch` because agent 16 had not connected yet, and set `target.scheduled = now + 60` (`10:24:05`).
  - `10:23:21.468` Agent 16 connected to `server/Net/SslListen.vala`, which broadcast `event.agent` (`connected`) but did **not** call `this.app.scheduler.reschedule()`. Even if it had, `target.scheduled` had already been bumped to `10:24:05`.
  - `10:24:05.424` Task 1 finally dispatched (`run command 1 on agent 16`), 60 seconds after submit and 44 seconds after the agent connected.
- ✔️ **`Queued` vs `Pending` and blank `Start` (`shared/SQT/TaskTarget.vala`, `controller/resources/columns/task_targets.csv`):**
  - `TaskTarget.display_state` returns `"Queued"` for every unstarted, non-draft, non-cancelled target (`started == 0 && ended == 0`), even when `scheduled <= now`.
  - `TaskTarget.display_started` returns `""` whenever `this.started < 1`, leaving the `Start` column empty for all queued/pending rows (`task_id_scheduled` and `scheduled` are `off` by default and use `date` format without time).
- ✔️ **Immediate disappearance from `Active` (`controller/filter/Tasks.vala`, `controller.log`):**
  - `controller/tab/Tasks.vala` defaults `state_drop` to `"Active"`.
  - `Filters.Tasks.match()` returns `false` for `"Active"` as soon as `row.ended > 0 || row.is_cancelled`.
  - At `10:26:47.514` (`~2.8s` after submit), `event.task` (`ended`) triggered `this.store.load()`; the finished row immediately failed the `"Active"` filter, disappeared from the grid, and closed `term_box` (`selection_changed` received `row == null`).
- ✔️ **Live streaming missing for already-started tasks (`server/SQT/Task.vala`, `server/Command.vala`, `controller.log`):**
  - On runs 2 (`10:25:54`) and 3 (`10:26:44`), `Task.submit` dispatched immediately (`watch = false`).
  - User clicked the running row in Tasks (`10:26:46.091` `Task.logs`, `10:26:46.101` `Task.watch`).
  - `Task.watch` called `Argus.Server.Command.watch(target_id, request.connection)`, which only populates `Command.tasks[target_id]` (read only inside `Command.dispatch`) and **never** sets `Command.controllers[row.identifier]`.
  - `server.log` received `Command.stdout` at `10:26:46.123` and `10:26:47.484`, and `Command.ended` at `10:26:47.511`, but `controller.log` received **zero** `controller.stdout` or `controller.ended` notifications for runs 2 and 3.
  - Only run 1 received live notifications because `Task.watch` had been called at `10:23:09` *before* `Command.dispatch` ran at `10:24:05`.
- ✔️ **`apt-get update` output ending at `Reading package lists...` (`/var/log/argusrm/commands/2026/11/15/16-2.stdout`, `16-3.stdout`):**
  - Both files on disk are complete (587 bytes, ending with `Reading package lists...\n`, `Command.ended` arrived 27ms after the final `Command.stdout`).
  - `server/resources/scripts/linux.json` runs `DEBIAN_FRONTEND=noninteractive apt-get update` over a pipe (`STDOUT_PIPE`, no TTY).
  - `apt-get` (`OpTextProgress::Done()`) omits `"Done"` when stdout is not a TTY, and `apt-get` does not emit `"N packages can be upgraded"` / `"All packages are up to date."` (that summary is only printed by the `apt` CLI wrapper).

---

## Root cause

1. ✔️ **State & Start column (`shared/SQT/TaskTarget.vala`):** `display_state` does not distinguish between due-now (`scheduled <= now`, `"Pending"`) and future-scheduled (`scheduled > now`, `"Queued"`), and `display_started` returns `""` whenever `started < 1` instead of displaying the scheduled timestamp.
2. ✔️ **Active filter (`controller/filter/Tasks.vala`):** `"Active"` rejects all rows with `row.ended > 0` immediately instead of retaining recently ended rows for 15 minutes.
3. ✔️ **Live watch on running commands (`server/SQT/Task.vala`, `server/Command.vala`, `controller/tab/Tasks.vala`):** `Task.watch` never registers `Command.controllers[identifier]` when `identifier > 0`, and `Tasks.vala` never re-fetches `Task.logs` when a watched row transitions to `ended > 0` to close any gap between `Task.logs` and `Task.watch`.
4. ✔️ **Agent reconnect scheduling & bumped-time updates (`server/Net/SslListen.vala`, `server/SQT/Task.vala`, `controller/tab/Tasks.vala`):** `SslListen` does not notify `app.scheduler.reschedule()` when an agent connects, `Task.run` writes `target.scheduled = now + 60` without broadcasting `event.task` (so bumped retry times never live-update in the grid), `Task.all_targets` does not report whether the target agent is currently connected, and `Tasks.vala` does not reload on `event.agent`. Also, if `Task.watch` was clicked in the UI before dispatch while the agent is offline, `Task.run` fails the queued target with exit 127 on next retry.
5. ✔️ **`apt-get update` trailing lines & TTY trade-offs (`server/resources/scripts/linux.json`, `controller/tab/Tasks.vala`):** No bytes were dropped by `agent/linux/Command.vala` or `server/Command.vala`; `apt-get update` naturally ends with `Reading package lists...\n` when stdout is non-TTY.
  - 🚫 **Do not emulate a TTY (PTY) for batch task execution:** A PTY merges stdout and stderr into one stream (breaking `.stdout`/`.stderr` separation and red stderr highlighting), introduces ANSI escape codes / `\r` progress spinners / line wrapping into `Gtk.TextView` and log files, causes interactive tools and pagers to prompt or hang on `isatty(0)`, translates `\n` to `\r\n`, and echoes stdin. Keep pipes and add a UI completion footer instead.

---

## Proposed fix

### 1. `shared/SQT/TaskTarget.vala` & `controller/resources/columns/task_targets.csv` — `Offline` / `Pending` / `Queued` state, connected indicator, and scheduled `Start`

- 🔷 Show `"Offline"` when unstarted and `!this.agent_id_connected`, `"Pending"` when connected and effective `scheduled <= now`, and `"Queued"` when connected and `scheduled > now`.
- 🔷 Display the scheduled time in `display_started` when `started == 0` and effective `scheduled > 0`.
- 🔷 Add `agent_id_connected` on `TaskTarget` and a `Connected` (`tick-connected`) column in `task_targets.csv`.

**Why:** Indicate when a target cannot run because its agent is disconnected, distinguish pending-now from future-scheduled tasks, and display the scheduled (or bumped retry) time in `Start`.

**Where:** `shared/SQT/TaskTarget.vala` (`agent_id_connected`, `construct`, `display_state`, `display_started`), `controller/resources/columns/task_targets.csv`, and `controller/tab/Base.vala` (`column_factory` `tick-connected`).

#### Add — `shared/SQT/TaskTarget.vala`, right after `public string agent_id_hostname { get; set; default = ""; }`

Carry live agent connection status from `Task.all_targets` to the controller grid.

```vala
		/**
		 * True while the target agent's app-socket connection is open.
		 *
		 * ''Task.all_targets'' sets this from live connections.
		 * It is not a column.
		 */
		public bool agent_id_connected { get; set; default = false; }
```

#### Remove — `shared/SQT/TaskTarget.vala` (`construct`)

```vala
			this.notify["started"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-started");
				this.notify_property("display-duration");
				this.notify_property("dimmed");
			});
```

#### Replace with

```vala
			this.notify["agent-id-connected"].connect(() => {
				this.notify_property("display-state");
			});
			this.notify["scheduled"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-started");
			});
			this.notify["task-id-scheduled"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-started");
			});
			this.notify["started"].connect(() => {
				this.notify_property("display-state");
				this.notify_property("display-started");
				this.notify_property("display-duration");
				this.notify_property("dimmed");
			});
```

#### Remove — `shared/SQT/TaskTarget.vala` (`display_state` and `display_started`)

```vala
		public string display_state {
			owned get {
				if (this.is_cancelled) {
					return "Cancelled";
				}
				if (this.ended > 0) {
					return this.success == 0 ? "Completed" : "Failed";
				}
				if (this.started > 0) {
					return "Running";
				}
				if (this.task_id_is_draft) {
					return "Draft";
				}
				return "Queued";
			}
		}

		/**
		 * Local time of {@link started} when today, date and time when
		 * earlier, or empty when not yet started.
		 */
		public string display_started {
			owned get {
				if (this.started < 1) {
					return "";
				}
				var when = new GLib.DateTime.from_unix_local(this.started);
```

#### Replace with

```vala
		public string display_state {
			owned get {
				if (this.is_cancelled) {
					return "Cancelled";
				}
				if (this.ended > 0) {
					return this.success == 0 ? "Completed" : "Failed";
				}
				if (this.started > 0) {
					return "Running";
				}
				if (this.task_id_is_draft) {
					return "Draft";
				}
				if (!this.agent_id_connected) {
					return "Offline";
				}
				var target_time = this.scheduled > this.task_id_scheduled ?
					this.scheduled : this.task_id_scheduled;
				if (target_time > new GLib.DateTime.now_utc().to_unix()) {
					return "Queued";
				}
				return "Pending";
			}
		}

		/**
		 * Local time of {@link started} (or scheduled time while waiting)
		 * when today, date and time when another day, or empty if unset.
		 */
		public string display_started {
			owned get {
				var target_time = this.started > 0 ? this.started :
					(this.scheduled > this.task_id_scheduled ?
						this.scheduled : this.task_id_scheduled);
				if (target_time < 1) {
					return "";
				}
				var when = new GLib.DateTime.from_unix_local(target_time);
```

#### Add — `controller/resources/columns/task_targets.csv`, right after `Machine,agent-id-hostname,ON,160,text,ON`

Show a live-connected tick beside the machine name.

```csv
Connected,agent-id-connected,ON,84,tick-connected,ON
```

#### Remove — `controller/tab/Base.vala` (`column_factory` `tick-connected`)

```vala
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"connected", item.child, "visible",
								GLib.BindingFlags.SYNC_CREATE));
```

#### Replace with

```vala
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								lookup, item.child, "visible",
								GLib.BindingFlags.SYNC_CREATE));
```

---

### 2. `controller/filter/Tasks.vala` & `controller/tab/Tasks.vala` — 15m Active retention, live agent/schedule refresh, and completion footer

- 🔷 Retain ended tasks (`Completed` / `Failed` / `Cancelled`) in the `"Active"` filter for 15 minutes (`900` seconds) after `ended`.
- 🔷 Append a terminal completion footer (`\n\nCommand succeeded (exit 0)` / `Command failed (exit N)` / `Command cancelled`) when an ended target's logs load instead of emulating a TTY.
- 🔷 Reload `this.store.load()` on `event.agent` as well as `event.task` so `Offline` / `Connected` state updates live.
- 💩 Add a 60-second timer while the Tasks tab is mapped so tasks age out of `"Active"` after 15 minutes even when idle, and re-fetch `Task.logs` once when the watched row transitions to `ended > 0`.

**Why:** Fast tasks stay visible in `"Active"` with `Completed` status, output clearly marks success/failure at the bottom without TTY side effects, and agent connection / bumped-time updates refresh live.

**Where:** `controller/filter/Tasks.vala` (`match`) and `controller/tab/Tasks.vala` (`watched_ended` / `expiry_timer` fields and `Tasks()` constructor).

#### Remove — `controller/filter/Tasks.vala` (`match`)

```vala
				case "Active":
					if (row.ended > 0 || row.is_cancelled) {
						return false;
					}
					break;
```

#### Replace with

```vala
				case "Active":
					var cutoff = new GLib.DateTime.now_utc().to_unix() - 900;
					if (row.ended > 0 && row.ended < cutoff) {
						return false;
					}
					if (row.is_cancelled && row.ended == 0) {
						return false;
					}
					break;
```

#### Add — `controller/tab/Tasks.vala`, right after `private int watched_identifier = 0;`

Track `ended` timestamp of the watched target and periodic refilter timer.

```vala
		private int64 watched_ended = 0;
		private uint expiry_timer = 0;
```

#### Add — `controller/tab/Tasks.vala`, right after `term_view.buffer.create_tag("stdin", "foreground", "#79c0ff", null);`

Style the completion footer when a command succeeds.

```vala
			term_view.buffer.create_tag("status-ok", "foreground", "#3fb950", null);
```

#### Remove — `controller/tab/Tasks.vala` (`logs_loaded`, `items_changed`, `selection_changed`)

```vala
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
```

#### Replace with

```vala
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
				foreach (var item in this.store.items) {
					if (item.id != this.watched_id || (item.ended == 0 && !item.is_cancelled)) {
						continue;
					}
					var prefix = "";
					if (term_view.buffer.get_char_count() > 0) {
						term_view.buffer.get_end_iter(out end);
						var tail = end;
						tail.backward_char();
						prefix = tail.get_char() == '\n' ? "\n" : "\n\n";
					}
					if (item.is_cancelled) {
						term_view.buffer.get_end_iter(out end);
						term_view.buffer.insert_with_tags_by_name(
							ref end, prefix + "Command cancelled\n", -1, "stderr");
						break;
					}
					if (item.success == 0) {
						term_view.buffer.get_end_iter(out end);
						term_view.buffer.insert_with_tags_by_name(
							ref end, prefix + "Command succeeded (exit 0)\n", -1, "status-ok");
						break;
					}
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert_with_tags_by_name(
						ref end,
						prefix + "Command failed (exit " + item.success.to_string() + ")\n",
						-1, "stderr");
					break;
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
					if (item.ended > 0 && this.watched_ended == 0) {
						this.watched_ended = item.ended;
						this.store.fetch_logs((int) this.watched_id);
					}
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
					this.watched_ended = 0;
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
				this.watched_ended = row.ended;
```

#### Remove — `controller/tab/Tasks.vala` (`notification` and `map`)

```vala
			this.window.app.rpc.notification.connect((notification) => {
				switch (notification.method) {
					case "event.task":
						this.store.load();
						break;
```
```vala
			this.map.connect(() => {
				this.store.load();
			});
```

#### Replace with

```vala
			this.window.app.rpc.notification.connect((notification) => {
				switch (notification.method) {
					case "event.task":
					case "event.agent":
						this.store.load();
						break;
```
```vala
			this.map.connect(() => {
				this.store.load();
				if (this.expiry_timer == 0) {
					this.expiry_timer = GLib.Timeout.add_seconds(60, () => {
						this.filter.changed(Gtk.FilterChange.DIFFERENT);
						return true;
					});
				}
			});
			this.unmap.connect(() => {
				if (this.expiry_timer != 0) {
					GLib.Source.remove(this.expiry_timer);
					this.expiry_timer = 0;
				}
			});
```

---

### 3. `server/Command.vala` & `server/SQT/Task.vala` — Fix `Task.watch` for already-running tasks

- 🔷 Register `Command.controllers[identifier]` when `Task.watch` is called on a target that already has `identifier > 0`.

**Why:** Clicking a running task in **Tasks** calls `Task.watch` after `Command.dispatch` already started the command, so `Command.controllers` never got the controller connection and missed all live `controller.stdout`, `controller.stderr`, and `controller.ended` notifications.

**Where:** `server/Command.vala` (`watch`) and `server/SQT/Task.vala` (`watch`).

#### Remove — `server/Command.vala` (`watch`)

```vala
		public static void watch(int target_id, OLLMrpc.Transport.Connection connection)
		{
			if (Command.tasks == null) {
				Command.tasks = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
			}
			Command.tasks.set(target_id, connection);
		}
```

#### Replace with

```vala
		/**
		 * Remember the controller watching one target.
		 *
		 * Output for a later dispatch goes to this connection when it is
		 * still up. {@link Argus.Shared.SQT.TaskTarget.is_watched} is the
		 * flag that this stream was asked for. When ''identifier'' is
		 * already running, also register the live output route now.
		 *
		 * @param target_id ''task_target.id''
		 * @param connection controller that asked to watch
		 * @param identifier active ''Command.identifier'', or ''0'' if not started
		 */
		public static void watch(
			int target_id,
			OLLMrpc.Transport.Connection connection,
			int identifier = 0
		) {
			if (Command.tasks == null) {
				Command.tasks = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
			}
			Command.tasks.set(target_id, connection);
			if (identifier > 0) {
				if (Command.controllers == null) {
					Command.controllers = new Gee.HashMap<int, OLLMrpc.Transport.Connection>();
				}
				Command.controllers.set(identifier, connection);
			}
		}
```

#### Remove — `server/SQT/Task.vala` (`watch`)

```vala
			Argus.Server.Command.watch(target_id, request.connection);
```

#### Replace with

```vala
			Argus.Server.Command.watch(target_id, request.connection, rows.get(0).identifier);
```

---

### 4. `server/Net/SslListen.vala` & `server/SQT/Task.vala` — Agent connect wakeup, `agent_id_connected`, and live reschedule broadcast

- 🔷 Populate `agent_id_connected` in `Task.all_targets` from `ssl_listen.connections`.
- 🔷 Broadcast `event.task` (`action = "queued"`) from `Task.run` whenever `rescheduled` is true so bumped `scheduled` times live-update in open controllers.
- 💩 When a known agent connects in `SslListen`, clear any offline-retry backoff on its unstarted targets (where parent `task.scheduled <= now`) and call `this.app.scheduler.reschedule()` so waiting tasks run immediately instead of waiting 60 seconds.
- 💩 Open question: `Task.run` currently fails a target with exit `127` if `controller != null && controller.running` (designed for CLI `--command` in `7.1-tasks-implementation.md`), which also kills a UI-submitted task if the user selects it (`Task.watch`) while the agent is offline. Confirm whether `Task.run` should keep retrying offline targets (`now + 60`) regardless of `is_watched` (or only fail immediately for `--command` / invalid scripts).

**Why:** Eliminates the 60-second stall when an agent connects and ensures controllers immediately see `Offline` state and bumped retry times.

**Where:** `server/SQT/Task.vala` (`all_targets`, `run`) and `server/Net/SslListen.vala` (`listen` handshake callback).

#### Remove — `server/SQT/Task.vala` (`all_targets`)

```vala
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
```

#### Replace with

```vala
			var live = new Gee.HashMap<int, bool>();
			if (this.app != null && this.app.ssl_listen != null) {
				foreach (var connection in this.app.ssl_listen.connections) {
					if (!connection.running || connection.user.id < 1) {
						continue;
					}
					live.set((int) connection.user.id, true);
				}
			}
			foreach (var row in rows) {
				row.agent_id_connected = live.has_key((int) row.agent_id);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
```

#### Remove — `server/SQT/Task.vala` (`run`)

```vala
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

#### Replace with

```vala
			if (rescheduled || started) {
				this.app.db.backupDB();
			}
			if (rescheduled && !started) {
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.task",
					action = "queued"
				});
			}
			if (started) {
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.task",
					action = "started"
				});
			}
```

#### Remove — `server/Net/SslListen.vala` (`listen`)

```vala
					if (known) {
						this.app.broadcast(new OLLMrpc.Notification() {
							method = "event.agent",
							action = "connected"
						});
					}
```

#### Replace with

```vala
					if (known) {
						var now = new GLib.DateTime.now_utc().to_unix();
						var pending = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
						var pending_binds = new Gee.HashMap<string, int>();
						pending_binds.set("agent_id", (int) rpc.user.id);
						Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
							"WHERE agent_id = $agent_id AND started = 0 " +
								"AND ended = 0 AND is_cancelled = 0 AND scheduled > 0",
							pending_binds, null, pending);
						var changed = false;
						foreach (var target in pending) {
							var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
							var tbinds = new Gee.HashMap<string, int>();
							tbinds.set("id", (int) target.task_id);
							Argus.Shared.SQT.Task.query(this.app.db).selectWhere(
								"WHERE id = $id AND is_template = 0 AND is_draft = 0",
								tbinds, null, tasks);
							if (tasks.size == 0 || tasks.get(0).scheduled > now) {
								continue;
							}
							target.scheduled = 0;
							Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
							changed = true;
						}
						if (changed) {
							this.app.db.backupDB();
						}
						this.app.broadcast(new OLLMrpc.Notification() {
							method = "event.agent",
							action = "connected"
						});
						this.app.scheduler.reschedule();
					}
```

---

### 5. Terminal TTY trade-offs & `server/resources/scripts/linux.json`

- 🚫 **Do not emulate a TTY (PTY) in `agent/linux/Command.vala`:**
  - A PTY merges stdout and stderr onto a single master fd, breaking `.stdout`/`.stderr` separation and red stderr highlighting.
  - Interactive tools emit `\r` progress spinners, ANSI color escapes, and column wraps that corrupt `Gtk.TextView` and saved logs unless a full VT100/VTE widget is used.
  - `isatty(0)` causes tools and pagers to wait on prompts instead of running non-interactively, and PTY termios translates `\n` to `\r\n` and echoes stdin.
- 🔷 Using the UI completion footer in `#2` (`Command succeeded (exit 0)` / `Command failed (exit N)`) gives a clean end-of-output marker while keeping pipe separation intact.
- 💩 Optionally, if an upgradable package count is wanted in `apt update`, `linux.json` can append an extra command after `apt-get update` rather than enabling a TTY.

---

## Attempts / changelog

- ✔️ Inspected `/var/log/argusrm/server.log`, `/var/log/argusrm/agent.log`, `~/.cache/argusrm/controller.log`, `/var/log/argusrm/commands/2026/11/15/16-{1,2,3}.stdout`, and `shared/SQT/TaskTarget.vala`, `controller/filter/Tasks.vala`, `controller/tab/Tasks.vala`, `controller/tab/Base.vala`, `controller/resources/columns/task_targets.csv`, `server/SQT/Task.vala`, `server/Command.vala`, `server/Net/SslListen.vala`, and `server/resources/scripts/linux.json`.
- ✔️ Applied `#1`–`#4` across `shared/SQT/TaskTarget.vala`, `controller/resources/columns/task_targets.csv`, `controller/tab/Base.vala`, `controller/filter/Tasks.vala`, `controller/tab/Tasks.vala`, `server/Command.vala`, `server/SQT/Task.vala`, and `server/Net/SslListen.vala`.
- ✔️ Rebuilt (`ninja -C build`) and verified `meson test -C build --print-errorlogs` passes 6/6.

---

## Next

- ✅ Closed and archived to `docs/bugs/done/2026-11-15-FIXED-tasks-ux-and-watch.md` (`#1`–`#4` implemented and `meson test -C build --print-errorlogs` 6/6 passed).
