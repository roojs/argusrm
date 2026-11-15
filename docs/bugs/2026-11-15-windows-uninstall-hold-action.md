# Windows uninstall trash icon: press-and-hold confirmation and task queuing

**Status:** ⏳ investigation opened — awaiting UI and task-queuing design review

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [1.0-DONE-overview.md](../plans/done/1.0-DONE-overview.md), [5.5-controller-user-interface.md](../plans/5.5-controller-user-interface.md), [7.2-tasks-ui-and-signing.md](../plans/7.2-tasks-ui-and-signing.md), [2026-11-14-software-filters-remaining.md](2026-11-14-software-filters-remaining.md)

---

## Problem

- 🔷 On Windows software, clicking the trash icon (`user-trash-symbolic`) should require a ~2-second press-and-hold to confirm uninstalling rather than acting on a single click:
  - 🔷 A short click (releasing before the hold completes) shows a toast: `"Click and hold to remove"`.
  - 🔷 Pressing and holding changes the control to a red button with a progress slider counting/climbing down over ~2 seconds (`2000` ms).
  - 🔷 Releasing early (or moving the pointer off) cancels the hold without queuing a task.
  - 🔷 Holding for the full ~2 seconds creates and queues the uninstall task on the server.
- 🔷 **Actual:** the trash icon in the `Uninstall` column is a static `Gtk.Image` with no click/hold controller, no `Adw.ToastOverlay` on the Windows programs tab, and no server/controller path to create and queue a Windows uninstall task.

---

## Evidence

✔️ Current UI and task-queuing pieces in the tree:

### 1. Trash icon column (`controller/tab/Base.vala`, `controller/resources/columns/*.csv`)

- ✔️ `controller/resources/columns/programs.csv` defines `Uninstall,uninstall-count,ON,80,bin,ON`.
- ✔️ `controller/tab/Base.vala` (`column_factory()`) handles `format == "bin"` and `format == "remove"` by creating a plain `Gtk.Image` (`icon_name = "user-trash-symbolic"`, `visible = false`), showing it when `count > 0`, and setting `tooltip_text` to `count.to_string() + " uninstallable"` for `"bin"`.
- 🚫 Neither `"bin"` nor `"remove"` attaches a click or press-and-hold controller, and `Base` has no toast overlay or row-uninstall callback.
- ✔️ `controller/tab/Asset/Programs.vala` wraps `ScrolledWindow(this.grid)` in `Gtk.Overlay` for the loading spinner only, with no `Adw.ToastOverlay` and no `Store.TaskTarget`.
- ℹ️ `controller/resources/columns/programs_machine.csv` (`Machine.Detail` -> `Windows programs`, `controller/tab/Asset/Machine/Programs.vala`) does not currently include an `Uninstall` / `"bin"` column.

### 2. Existing press-and-hold pattern in the tree (`controller/tab/Settings.vala`, `controller/resources/style.css`)

- ✔️ `controller/tab/Settings.vala` already implements a 2-second press-and-hold confirmation for `"Deregister and disconnect"`:
  - Wraps the target widget in a `Gtk.Overlay` (`hold_row`) with a `Gtk.ProgressBar` (`css_classes = { "hold-bar" }`, `valign = Gtk.Align.END`, `hexpand = true`, `can_target = false`).
  - Runs `Adw.TimedAnimation(hold_row, 1, 0, 2000, countdown)` (`Adw.Easing.LINEAR`, `follow_enable_animations_setting = false`) driving `bar.fraction` from `1` down to `0`.
  - Uses `Gtk.EventControllerLegacy` (`BUTTON_PRESS` / `TOUCH_BEGIN` to start; `BUTTON_RELEASE` / `TOUCH_END` / `TOUCH_CANCEL` to abort) and `Gtk.EventControllerMotion` (`leave` to abort).
  - Checks `GLib.get_monotonic_time() - started < (int64) 1800 * 1000` in `animation.done` so a skipped animation cannot fire immediately.
- ✔️ `controller/resources/style.css` defines `.hold-disconnect.holding` (`background-color: #c01c28; color: #ffffff;` plus white label/image) and `.hold-bar` (`min-height: 4px`, transparent trough, `#ffffff` progress bar).

### 3. Windows uninstall data and task execution (`shared/OSQuery/Programs.vala`, `server/SQT/Task.vala`, `agent/Win32/Command.vala`)

- ✔️ `shared/OSQuery/Programs.vala` (`Programs.list(0, 0)`) aggregates `programs` by `name` and returns `installed`, `uninstall_count`, and `GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string`. It does not return per-agent `agent_id`s or per-agent `uninstall_string`s.
- ✔️ `Programs.list(agent_id, 0)` (`agent_id > 0`) returns per-machine `Programs` rows with that machine's `agent_id` and `uninstall_string`.
- ✔️ `server/SQT/Task.vala` (`Task.submit`) creates one `Argus.Shared.SQT.Task` (one `command` or one `script_id`) and one `TaskTarget` per `agent_id`; `Task.run` sends that single command line to every target of the task, and `agent/Win32/Command.vala` runs it via `cmd.exe /c`.
- 🚫 `controller/store/TaskTarget.vala` only exposes `run_script(platform, app, action, agent_ids)` via `Script.search`, and `server/resources/scripts/windows.json` is not enabled (`server/SQT/Script.vala` and `server/resources/argusrm-server.gresource.xml` have `windows.json` commented out).
- ℹ️ As noted in [1.0-DONE-overview.md](../plans/done/1.0-DONE-overview.md), osquery's `programs` table only collects `uninstall_string` (often `MsiExec.exe /I{GUID}` or an interactive uninstaller, not `QuietUninstallString`), whereas `agent/Win32/Command.vala` runs non-interactively in the Windows service (Session 0).

---

## Root cause

- ✔️ The `"bin"` column in `controller/tab/Base.vala` renders a passive `Gtk.Image` with no press-and-hold gesture/animation or short-click toast feedback, and neither `Tab.Asset.Programs` nor the server/store task API has a path to resolve a Windows program into queued uninstall `Task` / `TaskTarget` rows.

---

## Proposed direction (rough sketch)

### 1. Reusable `HoldButton` widget (`controller/widget/HoldButton.vala`, `controller/resources/style.css`, `controller/meson.build`, `docs/meson.build`)

- 🔷 Create a reusable stock widget `Argus.Controller.Widget.HoldButton` in `controller/widget/HoldButton.vala` (and register it in `controller/meson.build` and `docs/meson.build`) so any destructive hold-to-confirm control can share it:
  - 🔷 Subclasses `Gtk.Overlay` (or wraps an inner `Gtk.Button` / child widget inside a `Gtk.Overlay`) with a bottom `Gtk.ProgressBar` (`"hold-bar"`, `valign = Gtk.Align.END`, `can_target = false`).
  - 🔷 Supports an inactive (idle) state and an active (holding) state, defaulting to a generic trash icon (`icon_name = "user-trash-symbolic"`) with an option/property to customize the icon, label, or child widget and hold duration (`2000` ms default).
  - 🔷 **Inactive (idle):** renders in its neutral/flat state (or hidden/insensitive when disabled for a row).
  - 🔷 **Pressed / holding:** switches to active (`.holding` — red `#c01c28` background, white icon/label) and runs a `2000` ms linear `Adw.TimedAnimation` from `1` to `0` on the progress bar (`follow_enable_animations_setting = false`, plus the `1800 * 1000` us monotonic-time guard).
  - 🔷 **Short click (release before 2000 ms):** resets to inactive, clears `.holding`, hides the bar, and emits a short-click signal (`short_click` / `clicked`) so the caller can display `new Adw.Toast("Click and hold to remove")`.
  - 🔷 **Pointer leave while pressed (`Gtk.EventControllerMotion.leave`):** resets to inactive without firing the short-click or confirm signal.
  - 🔷 **Hold completed (2000 ms reached):** resets (or optionally marks finished) and emits the hold-confirmed signal (`confirmed`) to fire the action.
  - 💩 Expose `reset()` so `Gtk.ColumnView` cell recycling (`factory.unbind` / `factory.bind`) clears any active hold animation and `.holding` state cleanly.
  - 💩 Generalize `.hold-disconnect` in `controller/resources/style.css` to `.hold-button.holding` (keeping `.hold-disconnect` or updating `controller/tab/Settings.vala` to reuse `Widget.HoldButton`).

### 2. Wire `HoldButton` into the grid trash column (`controller/tab/Base.vala`)

- 🔷 Update `Base.column_factory()` for `"bin"` (and `💩` `"remove"` when Debian remove is wired later) to instantiate `HoldButton` instead of a static `Gtk.Image`:
  - 🔷 Bind `visible` / `sensitive` and `tooltip_text` from `count` (`uninstall_count` for `"bin"`), and pass the bound `Gtk.ListItem.item` (or look up `item.item`) when `HoldButton.confirmed` fires.
  - 🔷 Forward `short_click` and `confirmed` from `Base` (or connect to signals/properties on `Base` such as `bin_short_clicked` and `bin_confirmed(GLib.Object row)`), and call `hold_button.reset()` in `factory.unbind`.

### 3. Scope of views (`programs.csv` vs `programs_machine.csv`)

- 🔷 `Software -> Windows` (`controller/tab/Asset/Programs.vala`, `programs.csv`) already displays the `Uninstall` (`"bin"`) column.
- 💩 `Machines -> Detail -> Windows programs` (`controller/tab/Asset/Machine/Programs.vala`, `programs_machine.csv`) does not currently have an `Uninstall` (`"bin"`) column; confirm whether to add it there too (each row already has one `agent_id` and one `uninstall_string`).

### 4. Creating and queuing the Windows uninstall task (`controller/store/TaskTarget.vala`, `server/SQT/Task.vala`)

- 🔷 **No new server RPC and no script:** use the existing `Task.submit` RPC with `is_script = false`, `script_id = 0`, `command = row.uninstall_string`, and `name = "Uninstall " + row.name` (running the `uninstall_string` command directly via `cmd.exe /c` on the Windows agent).
- 💩 Add `run_command(string title, string command, Gee.ArrayList<int32> agent_ids)` on `controller/store/TaskTarget.vala` (alongside `run_script`) to build the `Argus.Shared.SQT.Task` (`is_script = false`, `script_id = 0`, `command = command`, `payload_hash`) and call existing `Task.submit`.
- ℹ️ **Data gap on the aggregated `Software -> Windows` grid (`shared/OSQuery/Programs.vala`):**
  - On a per-machine `Programs.list(agent_id > 0, 0)` row, `row.agent_id` and `row.uninstall_string` are single exact values ready for `Task.submit`.
  - On the aggregated `Programs.list(0, 0)` row (`Software -> Windows`), the SQL currently returns `uninstall_count` and `GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string`, with **no** `agent_id` list (and `GROUP_CONCAT` joins multiple distinct strings with `,` if machines have different `uninstall_string` values for the same program `name`).
  - Options to supply `(command, agent_ids)` to `Task.submit` from `Software -> Windows` without adding a new RPC:
    - 💩 **Option A — Extend `Programs` aggregate query (`shared/OSQuery/Programs.vala`):** add an `uninstall_agents` (or similar non-stored) property on `Programs.list(0, 0)` when all machines share one `uninstall_string` (or `GROUP_CONCAT` `agent_id`s), or have the controller fetch per-agent `Programs` rows when `uninstall_count > 0` and group `agent_id`s by `uninstall_string` (submitting one `Task` per distinct `uninstall_string` via `Task.submit`).
    - 💩 **Option B — Per-machine uninstall only:** move or add the trash button on `Machine -> Detail -> Windows programs` (`Machine/Programs.vala`) and/or the Software lower machines grid ([2026-11-14-software-package-machines-grid.md](2026-11-14-software-package-machines-grid.md)) where each row is already one `(agent_id, uninstall_string)`.
- ℹ️ **Caveat (`agent/Win32/Command.vala`):** running `uninstall_string` verbatim works for silent/unattended strings, whereas interactive strings (e.g. `MsiExec.exe /I{GUID}` without `/qn`) may prompt or hang in Session 0 unless rewritten later.

### 5. Toast overlay and feedback (`controller/tab/Asset/Programs.vala`)

- 🔷 Wrap `Programs.vala`'s `overlay` in an `Adw.ToastOverlay` (`toasts`) so short clicks show `"Click and hold to remove"` and RPC failures show error toasts.
- 💩 On task creation success, show an `Adw.Toast` matching `controller/tab/Asset/SystemInfo.vala` (`"Task created and running — view it in the Tasks tab"` / `count.to_string() + " tasks created and running — view them in the Tasks tab"`).

---

## Next

- ⏳ 🔷 Confirm `HoldButton` details:
  - 💩 Whether `HoldButton` wraps an inner `Gtk.Button` or `Gtk.Box` inside `Gtk.Overlay`, whether it uses the 4 px bottom `.hold-bar` (matching `Settings.vala`) or a full-height background slider, and whether `Settings.vala` should also be updated to use `Widget.HoldButton`.
- ⏳ 🔷 Confirm view scope: `Software -> Windows` (`Programs.vala`), `Machine -> Detail -> Windows programs` (`Machine/Programs.vala` + `programs_machine.csv`), or both.
- ⏳ 🔷 Confirm how `Software -> Windows` resolves `(agent_ids, uninstall_string)` for `Task.submit` (Option A: `Programs` returns/groups per-agent `uninstall_string` + `agent_id`s vs Option B: per-machine rows only).
- ⏳ 💩 Once confirmed, split into Phase 1 (`controller/widget/HoldButton.vala` + `Tab.Base` + `Programs.vala` toast wiring) and Phase 2 (`Store.TaskTarget.run_command` + task submission wiring) with verbatim `Remove` / `Replace with` / `Add` hunks before applying code changes.
