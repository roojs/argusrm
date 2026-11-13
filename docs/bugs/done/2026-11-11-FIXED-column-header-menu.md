# Column header menu closes on a tick

**Status:** ✅ closed 2026-11-13. Owned `PopoverMenu` and capture claim are applied in `Base.column_menu` and `controller/resources/style.css` (`controller/tab/Agent.vala` still uses `header_menu`, deferred).

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 Right-click a column header and tick a column.
- 🔷 The menu stays open, so several columns can be chosen.
- 🔷 It closes when the click is outside the menu.
- 🔷 It stays a menu. A check list in its place was rejected.
- ℹ️ The same menu is `Gtk.ColumnViewColumn.header_menu` on the machines grid (`controller/tab/Base.vala`) and on the agent grid (`controller/tab/Agent.vala`).

## Evidence

- ℹ️ GTK 4.18.5. `gtk_model_button_clicked` calls `gtk_popover_popdown` before it activates the action, unless the private `keep_open` flag is set. That flag is set only for the Space key (`toggle_cb` in `gtkmodelbutton.c`). A mouse click always closes the menu. There is no public attribute that sets the flag.
- ℹ️ The header menu's popover is created by `gtkcolumnviewtitle.c` `show_menu` and parented on that column's header. It stays parented after it closes.
- ✔️ `/tmp/header-menu.vala` is a window with three check items on a column header menu. It is not in this tree. `valac --pkg gtk4 -o /tmp/header-menu-probe /tmp/header-menu.vala`. Clicks were driven with `xdotool` under `GDK_BACKEND=x11 xvfb-run`.
- ✔️ `plain`. Tick Beta or Alpha. `RESULT` closed. A click outside the menu stays closed.
- ✔️ `focus`. This is the lookup in `Base.column_menu`: the focus widget's popover ancestor, then `popup()` on idle. The focus widget's css name was `row`. It is outside the menu, so there is no ancestor to reopen. `RESULT` closed for Beta and for Alpha.
- ✔️ `saved`. Remember the popover when it opens, and call `popup()` in `change_state`. Beta stayed open. Alpha, the header that owns the popover, stayed open. A click outside stayed closed (`SETTLED closed`).
- ✔️ `saved-idle`. The same popover, reopened on idle. `NOW` was closed and `RESULT` was open, so the menu shuts and then returns.
- ✔️ `reparent`. Move the popover onto the grid when its parent header is hidden, then `popup()`. Also stayed open. `saved` already stayed open for Alpha, so the move is not required.
- ℹ️ The row's `clicked` signal cannot stop the close. The class handler pops the menu down before any connected handler. `keep_open` is private. The button's action name is empty. GTK activates a private menu-tracker item from that same `clicked` signal, and only a normal item is closed again there. A check is closed by the class handler.
- ✔️ `intercept`. A primary `Gtk.GestureClick` on the popover, capture phase, exclusive, claimed on press. Capture reaches the popover before the row, so the row never receives the click and does not close the menu. The tick is the row's label, then `change_state` on our action. Beta: `INTERCEPT Beta`, no `CLOSED`, `RESULT` open. A click outside still closes. Alpha hides the header that owns the popover, and that hide closes it (`CLOSED` after `NOW` open).
- ℹ️ `controller/tab/Agent.vala` has the same menu and does not reopen it. Its page also has the row menu, so a walk that takes the first popover would be the wrong one there.

## Root cause

- ✔️ The menu row claims the primary click in the capture phase and closes the popover before the action runs. A handler on `clicked` is too late. The row's action name is empty, so the tick has to come from the row label.

## Proposed fix

- 🔷 The menu is a `Gtk.PopoverMenu` we create, parented on `this.grid`.
- 🔷 Each column adds its row with a primary `Gtk.GestureClick` on that row. Capture phase, exclusive, claimed on press. The claim is taken before the row's own click, so the click does not go on and close the menu.
- 🔷 The gesture is connected in the same place as the action, so release calls that action. `change_state` still shows or hides the column, and it still refuses the last visible column. The check shows the action state afterwards.
- 🔷 A right-click on the grid opens the menu at the click's `x` and `y`.
- ℹ️ One gesture on the menu, as in the probe, does stop the click going down. It then has to find which row was hit. The gesture on the row does not, because that row was given the action when it was built.
- ℹ️ The popover's parent is the grid, so hiding a column does not hide the menu.
- ℹ️ A right-click on a cell opens the same menu. The column header widget is private, so a header-only click has to inspect the widget under the pointer.
- 💩 Leave `controller/tab/Agent.vala` until that menu is the same code. That page also has the row menu.
- 🚫 `column.header_menu`. GTK builds that popover in private and never returns it.
- 🚫 A check row whose `action_name` handles the click with no capture claim.
- 🚫 Walking parents or children from `pick()` to find a header, a menu row, or a label.
- 🚫 A timer that walks every widget under the grid.
- 🚫 Reopen with `popup()` after the click.
- 🚫 Reparent the popover.

### 1. `controller/tab/Base.vala` — `column_menu`

Drop the focus lookup.

#### Remove

```vala
					var focus = this.get_root().get_focus();
					var menu_popup = (Gtk.Popover) focus.get_ancestor(typeof(Gtk.Popover));
					GLib.Idle.add(() => {
						menu_popup.popup();
						return false;
					});
```

### 2. `controller/tab/Base.vala` — `column_menu`

The column header does not own the menu.

#### Remove

```vala
				column.header_menu = menu;
```

### 3. `controller/tab/Base.vala` — `column_menu`

Create the menu before the column loop, after `var menu = new GLib.Menu();`.

#### Add

```vala
			var menu_popup = new Gtk.PopoverMenu.from_model(menu) {
				has_arrow = false,
				position = Gtk.PositionType.BOTTOM
			};
			menu_popup.set_parent(this.grid);
```

### 4. `controller/tab/Base.vala` — `column_menu`

The row is the action. `append_item` updates the menu before `add_child` runs.

#### Remove

```vala
				menu.append(title, this.table + "." + name);
```

#### Replace with

```vala
				var item = new GLib.MenuItem(null, null);
				item.set_attribute("custom", "s", name);
				menu.append_item(item);
				var row = new Gtk.CheckButton.with_label(title) {
					active = starts
				};
				var tick = new Gtk.GestureClick() {
					button = 1,
					exclusive = true,
					propagation_phase = Gtk.PropagationPhase.CAPTURE
				};
				tick.pressed.connect((n_press, x, y) => {
					tick.set_state(Gtk.EventSequenceState.CLAIMED);
				});
				tick.released.connect((n_press, x, y) => {
					var on = !action.state.get_boolean();
					action.change_state(new GLib.Variant.boolean(on));
					row.active = action.state.get_boolean();
				});
				row.add_controller(tick);
				menu_popup.add_child(row, name);
```

### 5. `controller/tab/Base.vala` — `column_menu`

After the column loop, and before `return group`. Capture runs before the header's own click, which would otherwise take the right-click and show nothing.

#### Add

```vala
			var open = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY,
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			open.pressed.connect((n_press, x, y) => {
				open.set_state(Gtk.EventSequenceState.CLAIMED);
				var where = Gdk.Rectangle() {
					x = (int) x,
					y = (int) y,
					width = 1,
					height = 1
				};
				menu_popup.set_pointing_to(where);
				menu_popup.popup();
			});
			this.grid.add_controller(open);
```

## Attempts

- 🚫 The header menu was replaced with a check list on the page. Rejected. The control stays a menu.
- 🚫 A timer walked every widget under the grid to find GTK's private popover and attach the gesture there. Rejected.
- ✔️ `Base.column_menu` now looks up a popover from the focus and calls `popup()` on idle. The probe's `focus` mode does that and the menu stays closed.
- ✔️ The owned menu, the capture claim on each row, and the right-click on the grid are in `controller/tab/Base.vala`. `ninja -C build controller/argusrm-controller` built.
- ✔️ The rows are check buttons, so they drew as form checkboxes. `popover.menu.column-menu` in `controller/resources/style.css` copies the Adwaita menu row: 32px, padding `0 12px`, flat hover, and a checkmark with no box.
- ✔️ The release handler set the column, then the check button flipped `active` afterwards, so a tick hid the column. The column now follows `row.toggled`. The capture claim still keeps the menu open. The last visible column still cannot be hidden, and the tick is put back when that refusal happens.
- ℹ️ The probe source is `/tmp/header-menu.vala`. The binary from that run is `/tmp/header-menu-probe`.

## Next

- ✅ Closed. Owned `PopoverMenu`, capture claim, and flat menu styling are in `Base.column_menu` and `controller/resources/style.css` (`controller/tab/Agent.vala` deferred).
