# Software page: machines for a package name

**Status:** ✅ closed 2026-11-17 — double-click or hold opens the machines for that package name. The dialog colors version, and can uninstall or upgrade.

**Pointer:** `docs/bug-fix-process.md`, [../plans/done/5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [5.5-controller-user-interface.md](../plans/5.5-controller-user-interface.md), [`controller/dialog/Distribute.vala`](../../controller/dialog/Distribute.vala), [`controller/tab/Distributables.vala`](../../controller/tab/Distributables.vala), [../rpc-commands.md](../rpc-commands.md)

---

## Problem

- 🔷 On Software, each sub-tab is one row per package name. The operator needs the machines that have the selected name.
- 🔷 **Expected:** a double-click, or a long press on a touch screen, opens a dialog. The dialog lists those machines. The shell is the distributable install dialog: title, search, a column view, a spinner while the list loads, an empty state, and Cancel.
- 🔷 **Actual:** only the aggregate grids. Per-machine package grids exist under Machine detail, not under Software.

---

## Evidence

- ✔️ `DebPackages.list`, `RpmPackages.list`, and `Programs.list` are `agent_id` plus `since`. `agent_id` zero is one row per name. Greater than zero is that one agent's rows. None of those replies is "this name, every machine" with a display name. [rpc-commands.md](../rpc-commands.md).
- ✔️ `Programs.machines` is the per-machine `programs` rows for one exact name. The reply is `Programs`. It has `agent_id` and `version`. It does not have the machine name or the logged-in users.
- ✔️ [`controller/dialog/Distribute.vala`](../../controller/dialog/Distribute.vala) is the install dialog. The title is the product name. Search filters by machine name or logged-in user. The grid columns are a tick, Machine, Logged in users, Existing, and Version. Select all, Cancel, and Start the task now sit on the dialog. A spinner, the list, and "No machines" share one stack.
- ✔️ [`controller/tab/Distributables.vala`](../../controller/tab/Distributables.vala) opens that dialog from `Gtk.GestureClick` when `n_press` is at least 2, and from `Gtk.GestureLongPress` with `touch_only`. Both use `Tab.Base.pick`.
- ✔️ `DistributeMachine.machines` names a machine as `system_info.computer_name`, then `agent.hostname`, then `agent.requester`, then the agent id. Logged in users is `GROUP_CONCAT(DISTINCT logged_in_users.user)` for the live sessions. That call lists every registered host on the platform, including a host that does not have the product.
- 🚫 `controller/tab/Asset/Software.vala` has no second grid, and the three package grids do not open a dialog.

---

## Root cause

- ✔️ Software never asks for the machines that have one name, and it has nowhere to show that list.

---

## Proposed fix

- 🔷 Debian, RPM, and Windows each open one dialog from their own Software grid. The gesture is the pair on the Distributables grid.
- 🔷 The dialog lists only the machines that have this name. The title is the package name. Search matches the machine name or a logged-in user. The columns are Machine, Logged in users, and Version. Version is the version installed on that machine. Machine and Logged in users use the same two expressions as `DistributeMachine.machines`.
- 🔷 Cancel closes the dialog. While the call is in flight the body is the spinner. No rows shows "No machines".
- 🚫 No lower pane and no second grid on the Software page. The picture in [5.5](../plans/5.5-controller-user-interface.md) is not this dialog.
- 🚫 No tick, Select all, or Start the task now. Those belong to the install dialog. This one does not queue a task.
- 🚫 Do not list machines that do not have the package. That is the install dialog, and it already exists.
- 🚫 Do not reuse `Programs.machines` for these columns. That reply stays the uninstall rows. Do not mix Debian, RPM, and Windows in one list. Do not replace the Machine detail package tabs.

The list call returns those three columns for one exact name. Debian reads `deb_packages`, RPM reads `rpm_packages`, and Windows reads `programs`. A live row only (`deleted_dt = 0`), and the agent is still in `agent`.

#### Add — `controller/tab/Asset/DebPackages.vala`, `RpmPackages.vala`, and `Programs.vala` (the grid, as in `Distributables.vala`)

```vala
			var click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_PRIMARY
			};
			click.pressed.connect((n_press, x, y) => {
				if (n_press < 2) {
					return;
				}
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					return;
				}
				this.machines.open(this.window, row_item.item);
			});
			var hold = new Gtk.GestureLongPress() {
				touch_only = true
			};
			hold.pressed.connect((x, y) => {
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					return;
				}
				this.machines.open(this.window, row_item.item);
			});
			this.grid.add_controller(click);
			this.grid.add_controller(hold);
```

`this.machines` is that tab's dialog. `open` takes the aggregate row and loads the machines for its name.

---

## Next

- ✔️ `Dialog.PackageMachines` opens from the Debian, RPM, and Windows Software grids. `PackageMachine.machines` is the list. The row types are `Argus.Shared.SQV`.
- ✔️ A green version is up to date. A red version has a row in `package_updates`. Hold uninstalls that machine: Debian opens the dependency preview, Windows queues `silent_command`. Update available and Upgrade all, at the bottom left, queue `apt` or `dnf` update or upgrade for every red row. RPM has no uninstall. Windows has no upgrade script.
- ✔️ The Machines list right-click is gone. Update and Upgrade sit on the selected machine's Debian or RPM Software bar. An up arrow at the right of the Machines bar opens `Dialog.Upgrade`, titled Update Upgrade. Debian packages and RPM packages use the Software switcher. The list is every machine of that platform. Select all sits beside search. Update selected and Upgrade selected queue the ticked rows. Upgrade selected stays hidden when that tab has no update waiting.
- ✔️ The dialog title is the package name. The machine column is "Installed on this machine" for one row, and "Installed on these machines" otherwise.
- ✅ The machines dialog is in use. Update Upgrade on the Machines bar is part of the same close.
