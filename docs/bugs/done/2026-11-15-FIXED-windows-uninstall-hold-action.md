# Windows uninstall trash icon: press-and-hold confirmation (`HoldButton` and `Tab.Base`)

**Status:** ✅ closed 2026-11-16 — Phase 1 (`HoldButton` widget) and Phase 2 (`Tab.Base` shared `toasts`, `overlay`/`spinner`, `HoldButton` grid wiring, `Store.SystemInfo.busy`) implemented (`ninja -C build`, `meson test -C build` 6/6 passed); Phase 3 moved to [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-FIXED-windows-uninstall-task-queue.md)

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [5.9-DONE-assets-software.md](../../plans/done/5.9-DONE-assets-software.md), [1.0-DONE-overview.md](../../plans/done/1.0-DONE-overview.md), [5.5-controller-user-interface.md](../../plans/5.5-controller-user-interface.md), [7.2-tasks-ui-and-signing.md](../../plans/7.2-tasks-ui-and-signing.md), [2026-11-14-software-filters-remaining.md](../2026-11-14-software-filters-remaining.md), [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-FIXED-windows-uninstall-task-queue.md)

---

## Problem

- 🔷 On Windows software, clicking the trash icon (`user-trash-symbolic`) should require a ~2-second press-and-hold to confirm uninstalling rather than acting on a single click:
  - 🔷 A short click (releasing before the hold completes) shows a toast: `"Click and hold to remove"`.
  - 🔷 Pressing and holding changes the control to a red button with a progress slider counting/climbing down over ~2 seconds (`2000` ms).
  - 🔷 Releasing early (or moving the pointer off) cancels the hold without queuing a task.
  - 🔷 Holding for the full ~2 seconds creates and queues the uninstall task on the server.
- 🔷 **Actual:** `HoldButton` exists in `controller/widget/HoldButton.vala`, while the `Uninstall` column in `controller/tab/Base.vala` still renders a passive `Gtk.Image`, `Tab.Base` has no shared `Adw.ToastOverlay` or shared loading `overlay`/`spinner` (each subclass duplicates them), and task queuing is not wired yet.

---

## Evidence

✔️ Current UI and task-queuing pieces in the tree:

### 1. Trash icon column and `Tab.Base` shared UI (`controller/tab/Base.vala`, `controller/resources/columns/*.csv`)

- ✔️ `controller/resources/columns/programs.csv` defines `Uninstall,uninstall-count,ON,80,bin,ON`.
- ✔️ `controller/tab/Base.vala` (`column_factory()`) handles `format == "bin"` and `format == "remove"` by creating a plain `Gtk.Image` (`icon_name = "user-trash-symbolic"`, `visible = false`), showing it when `count > 0`, and setting `tooltip_text` to `count.to_string() + " uninstallable"` for `"bin"`.
- 🚫 Neither `"bin"` nor `"remove"` attaches a click or press-and-hold controller, and `Base` has no `remove_confirmed` signal.
- 🚫 `controller/tab/Base.vala` currently has no `Adw.ToastOverlay` (`Tab.Agent`, `Tab.Repository`, `Tab.Tasks`, and `Tab.Asset.SystemInfo` each create their own `Adw.ToastOverlay`, while `Tab.Asset.Programs`, `DebPackages`, `RpmPackages`, and `Machine.*` have none).
- 🚫 Nine `Tab.Base` subclasses (`Asset.Programs`, `Asset.DebPackages`, `Asset.RpmPackages`, `Machine.Programs`, `Machine.DebPackages`, `Machine.RpmPackages`, `Machine.InterfaceAddresses`, `Machine.Users`, `Machine.Groups`) duplicate the same centered `Adw.Spinner` + `Gtk.Overlay` + `ScrolledWindow(this.grid)` + `refreshing` logic.
- ℹ️ `controller/resources/columns/programs_machine.csv` (`Machine.Detail` -> `Windows programs`, `controller/tab/Asset/Machine/Programs.vala`) does not currently include an `Uninstall` / `"bin"` column.

### 2. Hold-to-confirm widget and styling (`controller/widget/HoldButton.vala`, `controller/tab/Settings.vala`, `controller/resources/style.css`)

- ✔️ `controller/widget/HoldButton.vala` implements `Argus.Controller.Widget.HoldButton` (`Gtk.Box` wrapping a flat `Gtk.Button` + bottom `Gtk.ProgressBar` inside `Gtk.Overlay`), defaulting to `icon_name = "user-trash-symbolic"` and `duration = 2000`.
- ✔️ `controller/resources/style.css` defines `.hold-button`, `.hold-button.holding` (`#c01c28` background, white icon/label), and `.hold-bar` (`min-height: 4px`, transparent trough, `#ffffff` progress).

### 3. Windows uninstall data and task execution (`shared/OSQuery/Programs.vala`, `server/SQT/Task.vala`, `agent/Win32/Command.vala`)

- ✔️ `shared/OSQuery/Programs.vala` (`Programs.list(0, 0)`) aggregates `programs` by `name` and returns `installed`, `uninstall_count`, and `GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string`. It does not return per-agent `agent_id`s or per-agent `uninstall_string`s.
- ✔️ `Programs.list(agent_id, 0)` (`agent_id > 0`) returns per-machine `Programs` rows with that machine's `agent_id` and `uninstall_string`.
- ✔️ `server/SQT/Task.vala` (`Task.submit`) creates one `Argus.Shared.SQT.Task` (one `command` or one `script_id`) and one `TaskTarget` per `agent_id`; `Task.run` sends that single command line to every target of the task, and `agent/Win32/Command.vala` runs it via `cmd.exe /c`.
- ℹ️ As noted in [1.0-DONE-overview.md](../../plans/done/1.0-DONE-overview.md), osquery's `programs` table only collects `uninstall_string` (often `MsiExec.exe /I{GUID}` or an interactive uninstaller, not `QuietUninstallString`), whereas `agent/Win32/Command.vala` runs non-interactively in the Windows service (Session 0).

---

## Root cause

- ✔️ The `"bin"` column in `controller/tab/Base.vala` renders a passive `Gtk.Image` instead of `Argus.Controller.Widget.HoldButton`, `Tab.Base` does not provide a shared `Adw.ToastOverlay` or shared grid `overlay`/`spinner` for its subclasses, and Phase 3 task queuing is not connected yet.

---

## Phases

- ✔️ **Phase 1 — Reusable `HoldButton` widget:** `controller/widget/HoldButton.vala`, `controller/resources/style.css`, `controller/meson.build`, `docs/meson.build`.
- ✔️ **Phase 2 — Shared `toasts` + `overlay`/`spinner` on `Tab.Base` & wire `HoldButton` into the grid:** `controller/tab/Base.vala` (`Base(...)` constructor + `public Gtk.Box content` + `public Adw.ToastOverlay toasts` + `public Gtk.Overlay overlay` + `public Adw.Spinner spinner` + `HoldButton`), `controller/store/SystemInfo.vala` (`busy` property), and all 13 `Tab.Base` subclasses.
- ℹ️ **Phase 3 (task queuing):** moved to [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-FIXED-windows-uninstall-task-queue.md).

---

## Phase 1 — Reusable `HoldButton` widget ✔️

- ✔️ `controller/widget/HoldButton.vala` (`Argus.Controller.Widget.HoldButton`) — `Gtk.Box` (`overflow = Gtk.Overflow.HIDDEN`) wrapping a flat `Gtk.Button` + bottom `Gtk.ProgressBar` (`"hold-bar"`) inside `Gtk.Overlay`, with `icon_name` (`"user-trash-symbolic"` default), `label`, `duration` (`2000` ms default), `holding`, `reset()`, `short_click()`, and `confirmed()`.
- ✔️ `controller/resources/style.css` — `.hold-button` and `.hold-button.holding` (`#c01c28` background, white icon/label).
- ✔️ `controller/meson.build`, `docs/meson.build` — registered `widget/HoldButton.vala`.
- 💩 Optional follow-up: `controller/tab/Settings.vala` still uses its own inline hold row and was left untouched.

---

## Phase 2 — Shared `toasts` + `overlay`/`spinner` on `Tab.Base` & wire `HoldButton` into the grid ✔️

### 1. `controller/tab/Base.vala` — `Adw.Bin` base, `Base(...)` constructor, `toasts`, `content`, `overlay`, `spinner`, and `HoldButton`

**Why:** Give `Tab.Base` a proper constructor creating a public `content` `Gtk.Box` inside `toasts` (`Adw.ToastOverlay`) as the `Adw.Bin` child (avoiding `construct` blocks and wrapper methods), move the centered loading `spinner` + `overlay` (`ScrolledWindow(this.grid)`) + `refreshing` state into `column_grid()`, replace the passive `Gtk.Image` in `"bin"` / `"remove"` cells with `Argus.Controller.Widget.HoldButton`, show `"Click and hold to remove"` on `short_click`, and emit `remove_confirmed(GLib.Object row)` on full hold.

**Where:** `controller/tab/Base.vala` (class header, fields/constructor after `expand_column`, `column_grid()`, and `column_factory()` `setup`, `unbind`, and `bind` handlers).

**Depends on:** Phase 1 (`Argus.Controller.Widget.HoldButton`).

##### Part 1 — Class parent, `toasts`, `content`, `overlay`, `spinner`, `refreshing`, `remove_confirmed`, and `Base(...)` constructor

#### Remove — `controller/tab/Base.vala` (class declaration through `expand_column`)

```vala
	public abstract class Base : Gtk.Box, Argus.Controller.Store.Base
	{
		/**
		 * File name under columns, without ''.csv''.
		 */
		public string table { get; set; default = ""; }
		/**
		 * Grid that receives the columns.
		 */
		public Gtk.ColumnView grid { get; set; }
		/**
		 * Bold the first column as a row header.
		 */
		public bool bold_header { get; set; default = true; }
		/**
		 * Database name of the column that expands to fill spare width.
		 */
		public string expand_column { get; set; default = ""; }
```

#### Replace with — `controller/tab/Base.vala`

```vala
	public abstract class Base : Adw.Bin, Argus.Controller.Store.Base
	{
		/**
		 * File name under columns, without ''.csv''.
		 */
		public string table { get; set; default = ""; }
		/**
		 * Grid that receives the columns.
		 */
		public Gtk.ColumnView grid { get; set; }
		/**
		 * Bold the first column as a row header.
		 */
		public bool bold_header { get; set; default = true; }
		/**
		 * Database name of the column that expands to fill spare width.
		 */
		public string expand_column { get; set; default = ""; }
		/**
		 * Toast overlay wrapping {@link content}.
		 */
		public Adw.ToastOverlay toasts { get; private set; }
		/**
		 * Vertical box inside {@link toasts} where subclasses pack widgets.
		 */
		public Gtk.Box content { get; private set; }
		/**
		 * Scrolled grid overlay carrying {@link spinner}.
		 */
		public Gtk.Overlay overlay { get; private set; }
		/**
		 * Centered loading spinner over {@link grid} when empty.
		 */
		public Adw.Spinner spinner { get; private set; }
		/**
		 * True while a later list call is in flight and rows are already
		 * shown.
		 */
		public bool refreshing { get; protected set; default = false; }

		/**
		 * Emitted when a hold button in a ''bin'' or ''remove'' cell is
		 * held for the full duration.
		 *
		 * @param row model item bound to that grid row
		 */
		public signal void remove_confirmed(GLib.Object row);

		/**
		 * Build the shared vertical {@link content} container inside
		 * {@link toasts}.
		 *
		 * @param table file name under columns without ''.csv''
		 * @param expand_column database name of the expanding column
		 */
		protected Base(string table, string expand_column = "")
		{
			Object(
				table: table,
				expand_column: expand_column
			);
			this.hexpand = true;
			this.vexpand = true;
			this.content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			this.toasts = new Adw.ToastOverlay() {
				child = this.content,
				hexpand = true,
				vexpand = true
			};
			this.child = this.toasts;
		}
```

##### Part 2 — `column_grid()` builds `overlay`, `spinner`, and store `busy` binding

#### Remove — `controller/tab/Base.vala` (`column_grid()`)

```vala
		protected GLib.SimpleActionGroup column_grid(GLib.ListModel model, bool multi = false)
		{
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(multi
				? (Gtk.SelectionModel) new Gtk.MultiSelection(sorted)
				: (Gtk.SelectionModel) new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
			return this.column_menu();
		}
```

#### Replace with — `controller/tab/Base.vala` (`column_grid()`)

```vala
		protected GLib.SimpleActionGroup column_grid(GLib.ListModel model, bool multi = false)
		{
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = false
			};
			this.grid = new Gtk.ColumnView(multi
				? (Gtk.SelectionModel) new Gtk.MultiSelection(sorted)
				: (Gtk.SelectionModel) new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = this.grid.sorter;
			this.spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false,
				css_classes = { "package-wait" }
			};
			this.overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			this.overlay.add_overlay(this.spinner);
			var source = model;
			while (source is Gtk.FilterListModel) {
				source = ((Gtk.FilterListModel) source).model;
			}
			((GLib.Object) source).notify["busy"].connect(() => {
				var busy_val = GLib.Value(GLib.Type.BOOLEAN);
				((GLib.Object) source).get_property("busy", ref busy_val);
				var busy = busy_val.get_boolean();
				var count = source.get_n_items();
				this.spinner.visible = busy && count == 0;
				this.refreshing = busy && count > 0;
			});
			return this.column_menu();
		}
```

##### Part 3 — `column_factory()` setup for `"bin"` / `"remove"`

#### Remove — `controller/tab/Base.vala` (`column_factory()`, `factory.setup`)

```vala
					case "bin":
					case "remove":
						item.child = new Gtk.Image() {
							icon_name = "user-trash-symbolic",
							halign = Gtk.Align.CENTER,
							hexpand = true,
							visible = false
						};
						break;
```

#### Replace with — `controller/tab/Base.vala` (`column_factory()`, `factory.setup`)

```vala
					case "bin":
					case "remove":
						var hold_button = new Argus.Controller.Widget.HoldButton() {
							halign = Gtk.Align.CENTER,
							valign = Gtk.Align.CENTER,
							visible = false
						};
						hold_button.short_click.connect(() => {
							this.toasts.add_toast(new Adw.Toast("Click and hold to remove"));
						});
						hold_button.confirmed.connect(() => {
							if (item.item != null) {
								this.remove_confirmed((GLib.Object) item.item);
							}
						});
						item.child = hold_button;
						break;
```

##### Part 4 — `column_factory()` unbind reset

#### Add — `controller/tab/Base.vala` (`column_factory()`, `factory.unbind`, after `remove_css_class("argus-this-controller")`)

Reset any active hold animation or styling when a recycled cell is unbound.

```vala
				if (item.child is Argus.Controller.Widget.HoldButton) {
					((Argus.Controller.Widget.HoldButton) item.child).reset();
				}
```

##### Part 5 — `column_factory()` bind for `"bin"` / `"remove"`

#### Remove — `controller/tab/Base.vala` (`column_factory()`, `factory.bind`)

```vala
					case "bin":
					case "remove":
						var count = 0;
						if (prop.value_type == GLib.Type.INT) {
							count = value.get_int();
						}
						var image = (Gtk.Image) item.child;
						image.visible = count > 0;
						image.tooltip_text = count.to_string();
						if (format == "bin") {
							image.tooltip_text = count.to_string() + " uninstallable";
						}
						break;
```

#### Replace with — `controller/tab/Base.vala` (`column_factory()`, `factory.bind`)

```vala
					case "bin":
					case "remove":
						var count = 0;
						if (prop.value_type == GLib.Type.INT) {
							count = value.get_int();
						}
						var button = (Argus.Controller.Widget.HoldButton) item.child;
						button.reset();
						button.visible = count > 0;
						button.tooltip_text = count.to_string();
						if (format == "bin") {
							button.tooltip_text = count.to_string() + " uninstallable";
						}
						break;
```

---

### 2. Update `Tab.Base` subclasses to chain `base(...)` and use `this.content`, `this.toasts`, and `this.overlay`

**Why:** Every `Tab.Base` subclass chains to `Base(table, expand_column)`, packs widgets into `this.content.append(...)`, and drops duplicated `toasts`, `spinner`, `overlay`, and `refreshing` code in favour of `Base`'s inherited members.

**Where:** All 13 `Tab.Base` subclasses under `controller/tab/`.

**Depends on:** #1 (`Base(...)`, `Base.toasts`, `Base.content`, `Base.overlay`, `Base.spinner`, `Base.refreshing`).

#### Remove — `controller/tab/Asset/Programs.vala` (and identical `Machine/Programs.vala`, `Machine/DebPackages.vala`, `Machine/RpmPackages.vala`, `Machine/InterfaceAddresses.vala`, `Asset/RpmPackages.vala`)

Example shown for `controller/tab/Asset/Programs.vala`; the same `refreshing` / `spinner` / `overlay` removal applies to `Asset/RpmPackages.vala`, `Asset/Machine/Programs.vala`, `Asset/Machine/DebPackages.vala`, `Asset/Machine/RpmPackages.vala`, and `Asset/Machine/InterfaceAddresses.vala` with their own `base(table, expand_column)` values (`"rpm_packages"`, `"programs_machine"`, `"deb_packages_machine"`, `"rpm_packages_machine"`, `"interface_addresses_machine"`).

```vala
		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "programs",
				expand_column: "name"
			);
			this.hexpand = true;
			this.vexpand = true;
```

```vala
			var spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			spinner.add_css_class("package-wait");
			var overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(spinner);
			this.store.notify["busy"].connect(() => {
				spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = this.store.busy && this.store.get_n_items() > 0;
			});
			this.append(overlay);
```

#### Replace with — `controller/tab/Asset/Programs.vala` (and `Asset/RpmPackages.vala`, `Machine/*`)

```vala
		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			base("programs", "name");
```

```vala
			this.content.append(this.overlay);
```

#### Remove — `controller/tab/Asset/DebPackages.vala`

```vala
		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public DebPackages(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "deb_packages",
				expand_column: "name"
			);
			this.hexpand = true;
			this.vexpand = true;
```

```vala
			var spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			spinner.add_css_class("package-wait");
			var overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(spinner);
			this.store.notify["busy"].connect(() => {
				spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = this.store.busy && this.store.get_n_items() > 0;
			});
```

```vala
			this.append(bar);
			this.append(overlay);
```

#### Replace with — `controller/tab/Asset/DebPackages.vala`

```vala
		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public DebPackages(Argus.Controller.Window window)
		{
			base("deb_packages", "name");
```

```vala
			this.content.append(bar);
			this.content.append(this.overlay);
```

#### Remove — `controller/tab/Asset/Machine/Groups.vala`

```vala
		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }
```

```vala
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "groups",
				expand_column: "groupname"
			);
			this.hexpand = true;
			this.vexpand = true;
```

```vala
			var spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 32,
				height_request = 32,
				visible = false
			};
			spinner.add_css_class("package-wait");
			var overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(spinner);
			this.store.notify["busy"].connect(() => {
				spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = this.store.busy && this.store.get_n_items() > 0;
			});
			this.append(overlay);
```

#### Replace with — `controller/tab/Asset/Machine/Groups.vala`

```vala
			base("groups", "groupname");
```

```vala
			this.content.append(this.overlay);
```

#### Remove — `controller/tab/Asset/Machine/Users.vala`

```vala
		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the split groups / users page.
		 *
		 * @param window the window this page belongs to
		 */
		public Users(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "users",
				expand_column: "username"
			);
			this.hexpand = true;
			this.vexpand = true;
```

```vala
			var users_spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			users_spinner.add_css_class("package-wait");
			var users_overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			users_overlay.add_overlay(users_spinner);
			this.store.notify["busy"].connect(() => {
				users_spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			this.groups.notify["refreshing"].connect(() => {
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = groups_box,
				end_child = users_overlay,
				resize_start_child = false,
				shrink_start_child = false,
				position = 340,
				hexpand = true,
				vexpand = true
			};
			this.append(filter_bar);
			this.append(paned);
```

#### Replace with — `controller/tab/Asset/Machine/Users.vala`

```vala
		/**
		 * Build the split groups / users page.
		 *
		 * @param window the window this page belongs to
		 */
		public Users(Argus.Controller.Window window)
		{
			base("users", "username");
```

```vala
			this.store.notify["busy"].connect(() => {
				if (this.groups.refreshing) {
					this.refreshing = true;
				}
			});
			this.groups.notify["refreshing"].connect(() => {
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = groups_box,
				end_child = this.overlay,
				resize_start_child = false,
				shrink_start_child = false,
				position = 340,
				hexpand = true,
				vexpand = true
			};
			this.content.append(filter_bar);
			this.content.append(paned);
```

#### Remove — `controller/tab/Agent.vala` (fields and constructor)

```vala
		private Adw.Spinner spinner;
		private Adw.ToastOverlay toasts;
```

```vala
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "agent",
				expand_column: "display-name"
			);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Agent(window.app);
			this.spinner = new Adw.Spinner() {
				visible = false
			};
```

```vala
			var scroll = new Gtk.ScrolledWindow() {
				child = this.grid,
				vexpand = true,
				hexpand = true
			};
			var empty = new Adw.StatusPage() {
				title = "No machines",
				description = "Register a machine to see it here.",
				icon_name = "computer-symbolic",
				vexpand = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(scroll, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			this.toasts = new Adw.ToastOverlay() {
				child = this.body,
				hexpand = true,
				vexpand = true
			};
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(this.spinner);
			toolbar.append(removing_label);
			toolbar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			toolbar.append(register_add);
			this.append(toolbar);
			this.append(this.toasts);
			this.store.bind_property("busy", this.spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
```

#### Replace with — `controller/tab/Agent.vala`

```vala
			base("agent", "display-name");
			this.window = window;
			this.store = new Argus.Controller.Store.Agent(window.app);
			var bar_spinner = new Adw.Spinner() {
				visible = false
			};
```

```vala
			var empty = new Adw.StatusPage() {
				title = "No machines",
				description = "Register a machine to see it here.",
				icon_name = "computer-symbolic",
				vexpand = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(this.overlay, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(bar_spinner);
			toolbar.append(removing_label);
			toolbar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			toolbar.append(register_add);
			this.content.append(toolbar);
			this.content.append(this.body);
			this.store.bind_property("busy", bar_spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
```

#### Remove — `controller/tab/Repository.vala` (fields and constructor)

```vala
		private Adw.Spinner spinner;
		private Adw.ToastOverlay toasts;
```

```vala
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "repository",
				expand_column: "display-name"
			);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Repository(window.app);
			this.dialog = new Argus.Controller.Dialog.Repository(this.store);
			this.spinner = new Adw.Spinner() {
				visible = false
			};
```

```vala
			toolbar.append(this.spinner);
```

```vala
			var scroll = new Gtk.ScrolledWindow() {
				child = this.grid,
				vexpand = true,
				hexpand = true
			};
			var empty = new Adw.StatusPage() {
				title = "No repositories",
				description = "Clone a git repository onto this server.",
				icon_name = "folder-symbolic",
				vexpand = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(scroll, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			this.toasts = new Adw.ToastOverlay() {
				child = this.body,
				hexpand = true,
				vexpand = true
			};
			this.append(toolbar);
			this.append(this.toasts);
			this.append(bottom);
			this.store.bind_property("busy", this.spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
```

#### Replace with — `controller/tab/Repository.vala`

```vala
			base("repository", "display-name");
			this.window = window;
			this.store = new Argus.Controller.Store.Repository(window.app);
			this.dialog = new Argus.Controller.Dialog.Repository(this.store);
			var bar_spinner = new Adw.Spinner() {
				visible = false
			};
```

```vala
			toolbar.append(bar_spinner);
```

```vala
			var empty = new Adw.StatusPage() {
				title = "No repositories",
				description = "Clone a git repository onto this server.",
				icon_name = "folder-symbolic",
				vexpand = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(this.overlay, "list");
			this.body.add_named(empty, "empty");
			this.body.visible_child_name = "list";
			this.content.append(toolbar);
			this.content.append(this.body);
			this.content.append(bottom);
			this.store.bind_property("busy", bar_spinner, "visible",
				GLib.BindingFlags.SYNC_CREATE);
```

#### Remove — `controller/tab/Tasks.vala` (`Tasks()` constructor)

```vala
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "task_targets",
				expand_column: "display-task"
			);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
```

```vala
			var spinner = new Adw.Spinner() {
				visible = false
			};
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(new Gtk.Label("State"));
			bar.append(state_drop);
			bar.append(date_button);
			bar.append(spinner);
```

```vala
			var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				start_child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				end_child = term_box,
				resize_start_child = true,
				resize_end_child = true,
				hexpand = true,
				vexpand = true
			};
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
```

```vala
			this.append(bar);
			this.append(toasts);
```

#### Replace with — `controller/tab/Tasks.vala` (`Tasks()` constructor)

```vala
			base("task_targets", "display-task");
			this.window = window;
```

```vala
			var bar_spinner = new Adw.Spinner() {
				visible = false
			};
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(new Gtk.Label("State"));
			bar.append(state_drop);
			bar.append(date_button);
			bar.append(bar_spinner);
```

```vala
			var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				start_child = this.overlay,
				end_child = term_box,
				resize_start_child = true,
				resize_end_child = true,
				hexpand = true,
				vexpand = true
			};
			this.store.bind_property("busy", bar_spinner, "visible", GLib.BindingFlags.SYNC_CREATE);
			refresh.clicked.connect(() => {
				this.store.load();
			});
			this.store.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
```

```vala
			this.content.append(bar);
			this.content.append(paned);
```

#### Remove — `controller/tab/Asset/SystemInfo.vala` (`SystemInfo()` constructor)

```vala
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "system_info",
				expand_column: "cpu-brand"
			);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
```

```vala
			var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				start_child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				end_child = detail,
				resize_start_child = true,
				resize_end_child = true,
				hexpand = true,
				vexpand = true
			};
```

```vala
			var toasts = new Adw.ToastOverlay() {
				child = paned,
				hexpand = true,
				vexpand = true
			};
			var row_model = new GLib.Menu();
			row_model.append("Update", "row.update");
			row_model.append("Upgrade", "row.upgrade");
			var row_menu = new Gtk.PopoverMenu.from_model(row_model) {
				has_arrow = false
			};
			row_menu.set_parent(this.grid);
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
```

```vala
			this.append(bar);
			this.append(toasts);
```

#### Replace with — `controller/tab/Asset/SystemInfo.vala` (`SystemInfo()` constructor)

```vala
			base("system_info", "cpu-brand");
			this.window = window;
```

```vala
			var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				start_child = this.overlay,
				end_child = detail,
				resize_start_child = true,
				resize_end_child = true,
				hexpand = true,
				vexpand = true
			};
```

```vala
			var row_model = new GLib.Menu();
			row_model.append("Update", "row.update");
			row_model.append("Upgrade", "row.upgrade");
			var row_menu = new Gtk.PopoverMenu.from_model(row_model) {
				has_arrow = false
			};
			row_menu.set_parent(this.grid);
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
```

```vala
			this.content.append(bar);
			this.content.append(paned);
```

---

## Next

- ✅ Phase 1 (`HoldButton`) and Phase 2 (`Tab.Base` shared `toasts`, `overlay`/`spinner`, `HoldButton` wiring, and `Store.SystemInfo.busy`) verified and archived in `docs/bugs/done/2026-11-15-FIXED-windows-uninstall-hold-action.md`.
- ℹ️ Task queuing follow-up tracked in [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-FIXED-windows-uninstall-task-queue.md).
