# Machines multi-select right-click package update (hardcoded task queue)

**Status:** ✔️ Phase 1 (Data modelling) & Phase 2 (Controller UI) implemented; Phase 3 (Handler & runner) -> Phase 4 (Connect UI & handlers) next

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/7.2-tasks-ui-and-signing.md`, `docs/plans/7.0-tasks.md`, `docs/plans/7.1-tasks-implementation.md`, `docs/plans/6.0-security-issues.md`, `docs/rpc-commands.md`

---

## Problem

- 🔷 On the Machines tab (`controller/tab/Asset/SystemInfo.vala`), select one or more machines and right-click **Update** or **Upgrade** (two hardcoded package commands, no library script required yet, swappable later).
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
  - 🔷 Hardcoded package commands (`script_id = 0`, swappable to configured `script.id` later; no extra enum — just plain commands):
    - **Update:** `APT` -> `DEBIAN_FRONTEND=noninteractive apt-get update`; `DNF` -> `dnf -y makecache --refresh`.
    - **Upgrade:** `APT` -> `DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y upgrade`; `DNF` -> `dnf -y upgrade`.
    - 🔷 `WIN` / `UNKNOWN`: Windows has no package updater; do not offer Update or Upgrade when only unsupported machines are selected.

### Phase 2 — Controller UI ✔️ (`controller/tab/`, `controller/filter/`, `controller/Window.vala`, `controller/resources/`)

**Depends on:** Phase 1 model properties.

- **Implemented:**
  - ✔️ `controller/tab/Base.vala`: tagged data-row cells (`argus-grid-row`), applied `.dim-label` when `dimmed` is true on a row, and restricted `column_menu` right-click capture to headers/empty grid space.
  - ✔️ `controller/tab/Asset/SystemInfo.vala`: wrapped `paned` in `Adw.ToastOverlay` and added row right-click `Gtk.PopoverMenu` (`row.update` / `row.upgrade`, hidden when only Windows/unknown machines are selected; action handlers deferred to Phase 4).
  - ✔️ `controller/filter/Tasks.vala` & `controller/tab/Tasks.vala` (mounted in `controller/Window.vala` for `"tasks"`): flat `task_targets` `ColumnView` with Search, State (`Active` default), Date range (`Any`/`Today`/`7 days`/`30 days`/From–To `Gtk.Calendar`), Refresh/Spinner, and copyable black-on-white `Gtk.TextView` terminal log viewer (`Start`, `Duration`, `Exit`, `State`).
  - ✔️ `controller/resources/columns/task_targets.csv` & `controller/resources/style.css` (`.tool-output`, `.tool-output-header`).

### Phase 3 — Server handler & task runner (`server/`, `agent/`, `docs/rpc-commands.md`)

**Depends on:** Phase 1 schema.

- **Specification:**
  - 🔷 **Task creation handler (`server/SQT/Task.vala`):**
    - 💩 Either add atomic `Task.submit` (`Task` + `agent_ids` + `approve` + `watch`) or keep `Task.create` -> `Task.target` -> `Task.approve` and fix immediate `scheduled <= 0` handling.
    - Record `created_by` / `approved_by` from `Argus.Shared.Agent.user(request).id`, and add the `controller_sig` verification hook (`docs/plans/6.0-security-issues.md`).
  - 🔷 **All tasks / targets & logs handlers (`server/SQT/Task.vala`):**
    - `Task.all_targets`: returns all `TaskTarget` rows joined with `task` and `agent` newest-first so queued, running, and completed runs load in one call.
    - `Task.logs` (`i` `target_id`): reads `{log_dir}/{agent_id}-{identifier}.stdin`, `.stdout`, `.stderr` and returns `[stdout, stderr, stdin]`.
  - 💩 **Runner & agent reliability fixes:**
    - `server/SQT/Task.vala`: write `task_target.log_dir` on dispatch; call `this.app.scheduler.reschedule()` in `Task.finish`; broadcast `event.task` on dispatch/finish.
    - `agent/linux/Command.vala`: send `Command.ended` (exit `127`) if `spawnv` fails, and guard `Command.ended` with `Command.send_lock` after stdout/stderr drain.
    - `agent/linux/PackageMonitor.vala`: call `this.send_pending()` after `apt()` / `rpm()` rescans so `package_updates` updates right after upgrades.
  - 🔷 Update `docs/rpc-commands.md` for all new/changed RPCs and notifications.
- **Open for review:**
  - ⏳ 🔷 Confirm `Task.submit` vs 3-step `Task.create`/`target`/`approve`, and `[stdout, stderr, stdin]` return shape for `Task.logs`.

### Phase 4 — Connect UI & handlers (`controller/store/`, `controller/tab/`)

**Depends on:** Phase 2 UI and Phase 3 handlers.

- **Specification:**
  - 💩 Add `controller/store/TaskTargets.vala` (`GLib.ListModel`) calling `Task.all_targets`, `Task.logs`, and the create/submit RPC, plus listening to `event.task`, `controller.stdout`, `controller.stderr`, and `controller.ended` (filtered by `identifier`).
  - 🔷 Connect `Asset/SystemInfo.vala` `row.update` / `row.upgrade` action handlers to collect selected `APT` / `DNF` machines, construct the task payload (including `payload_hash` / signing hook), submit to the server, and show an `Adw.Toast` (no confirmation dialog; 💩 optional `"View Tasks"` action).
  - 🔷 Connect `Tab/Tasks.vala` selection to call `Task.logs(target.id)` for saved output and `Task.watch(target.id)` when `ended == 0` so live output streams into the terminal `Gtk.TextView`.

---

## Next

- ⏳ 🔷 Review the four phases above (and `docs/plans/7.2-tasks-ui-and-signing.md`) and resolve the open points in Phases 1–3.
- ⏳ 💩 Once confirmed, write verbatim `Remove` / `Replace with` / `Add` code proposals phase by phase, starting with Phase 1.
