# Agent and Repository column sorting (migrate to Base)

**Status:** ✅ closed 2026-11-14. Agents and Repositories on `Base.column_grid`; build OK; sort, column menu, and Remove verified in UI.

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md` (**Edit syntax contract**, **Code proposals — one place, not two**), [2026-11-11-FIXED-column-sort.md](done/2026-11-11-FIXED-column-sort.md)

---

## Problem

- 🔷 A left click on a column header on **Agents** (`controller/tab/Agent.vala`) and **Repositories** (`controller/tab/Repository.vala`) sorts that column; the next click reverses the order.
- 🔷 Both grids use `Argus.Controller.Tab.Base` (`column_grid`) and column CSV files (`agent.csv`, `repository.csv`), not per-column sorters in each tab.
- 🔷 On **Agents**, Remove must read `this.grid.model` (`Gtk.MultiSelection` over `Gtk.SortListModel`) so the removed row is the ticked row after a sort.

## Evidence

- ✅ `Agent.vala` and `Repository.vala` use `column_grid` and CSV column files.
- ✅ Agent Remove loops `Gtk.MultiSelection` over `this.grid.model` (sorted view order).
- ✔️ `Base.column_menu()` denies the header menu when the pick hits `argus-grid-row` (`Base.vala:150-158`).

## Root cause

- ✅ `Agent` and `Repository` did not call `column_grid` (fixed).
- ✅ `Base.column_factory()` lacked agent-specific **format** arms (fixed).

## Proposed fix

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding lines before applying.

- 🔷 Migrate tabs like `controller/tab/Tasks.vala` and `controller/tab/Asset/SystemInfo.vala`.
- 🚫 Per-column `column.sorter` in `Agent.vala` / `Repository.vala`.

### 1. `controller/resources/columns/agent.csv` — new column file

**Why:** `column_menu` reads `table` + CSV; sort flags live in the file like asset grids.

**Where:** new file under `controller/resources/columns/`.

**Depends on:** none.

#### Add — new file `controller/resources/columns/agent.csv`

```
Column header | Database name [JSON] | Visible | Width | Format | Sort

Hostname,display-name,ON,0,text,ON
Address,ip,ON,0,text,ON
User,username,ON,0,text,ON
Kind,display-kind,ON,0,controller-kind,ON
Registered,status,off,90,tick-registered,ON
Registered on,created,ON,0,recent-created,ON
Connected,connected,ON,90,tick-connected,ON
Last connected,last-connected,ON,0,recent-last-connected,ON
```

### 2. `controller/resources/columns/repository.csv` — new column file

**Why:** Repository grid uses the same Base column path.

**Where:** new file under `controller/resources/columns/`.

**Depends on:** none.

#### Add — new file `controller/resources/columns/repository.csv`

```
Column header | Database name [JSON] | Visible | Width | Format | Sort

Name,display-name,ON,0,text,ON
URL,url,ON,0,dim-text,ON
```

### 3. `controller/resources/argusrm.gresource.xml` — register column CSVs

**Why:** bundled columns must be in the gresource.

**Where:** inside `<gresource>`, with the other `columns/*.csv` entries.

**Depends on:** ### 1, ### 2.

#### Add — after existing `columns/task_targets.csv` entry

```xml
    <file>columns/agent.csv</file>
    <file>columns/repository.csv</file>
```

### 4. `shared/SQT/ScriptRepository.vala` — `display_name`

**Why:** Name column sorts and shows `url` when `name` is empty.

**Where:** after the `key` property.

**Depends on:** none.

#### Add — after `public string key { get; set; default = ""; }`

```vala
		/**
		 * ''name'' when set, otherwise ''url''.
		 */
		public string display_name {
			owned get {
				if (this.name != "") {
					return this.name;
				}
				return this.url;
			}
		}
```


### 6. `controller/tab/Base.vala` — `column_factory`

**Why:** `agent.csv` adds agent-only **format** values (not generic `tick` + `lookup`). Sort still uses the JSON name column; format chooses the cell factory arm only.

**Where:** `column_factory` docblock, `setup`, new `unbind`, and `bind` in `controller/tab/Base.vala`.

**Depends on:** ### 1.

#### 6.1 — docblock: agent/repository formats

#### Remove

```vala
		 *  * ''text'', ''date'', ''elapsed'', and ''cidr'' are labels.
```

#### Replace with

```vala
		 *  * ''text'', ''dim-text'', ''date'', ''elapsed'', and ''cidr'' are labels.
		 *  * ''dim-text'' is muted body text.
		 *  * ''controller-kind'' is ''display-kind'' text; ''argus-this-controller'' when this window owns the row.
		 *  * ''recent-created'' / ''recent-last-connected'' bind ''display-created'' / ''display-last''.
		 *  * ''tick-registered'' / ''tick-connected'' are ticks with live ''status'' / ''connected'' bindings.
```

#### 6.2 — `@param format` line

#### Remove

```vala
		 * @param format text, number, bytes, mhz, date, elapsed, cidr,
		 *   status, tick, bin, or remove
```

#### Replace with

```vala
		 * @param format text, dim-text, controller-kind, recent-created,
		 *   recent-last-connected, tick-registered, tick-connected, number,
		 *   bytes, mhz, date, elapsed, cidr, status, tick, bin, or remove
```

#### 6.3 — `setup`: label, dim-text, and agent tick widgets

#### Remove

```vala
					case "tick":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true
						};
						break;
```

#### Replace with

```vala
					case "tick":
					case "tick-registered":
					case "tick-connected":
						item.child = new Gtk.Image() {
							halign = Gtk.Align.CENTER,
							hexpand = true
						};
						break;
```

#### Remove

```vala
					case "date":
					case "elapsed":
					case "cidr":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					case "text":
```

#### Replace with

```vala
					case "controller-kind":
					case "recent-created":
					case "recent-last-connected":
					case "date":
					case "elapsed":
					case "cidr":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							attributes = header_column ? attrs : null
						};
						break;

					case "dim-text":
						item.child = new Gtk.Label("") {
							xalign = 0,
							hexpand = true,
							css_classes = { "dim-label" },
							attributes = header_column ? attrs : null
						};
						break;

					case "text":
```

#### 6.4 — `factory.unbind`: drop `bind_property` on recycle

**Where:** immediately after the `factory.setup.connect` closing `});`, before `factory.bind.connect`.

#### Add

```vala
			factory.unbind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				if (item.child == null) {
					return;
				}
				var binding = item.child.get_data<GLib.Binding>("argus-column-binding");
				if (binding != null) {
					binding.unbind();
				}
				item.child.set_data<GLib.Binding>("argus-column-binding", null);
				if (item.child is Gtk.Label) {
					((Gtk.Label) item.child).remove_css_class("argus-this-controller");
				}
			});
```

#### 6.5 — `bind` opening: row handles and `dim-text`

#### Remove

```vala
			factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (GLib.Object) item.item;
				item.child.remove_css_class("dim-label");
				var dim_prop = row.get_class().find_property("dimmed");
				if (dim_prop != null && dim_prop.value_type == GLib.Type.BOOLEAN) {
					var dim_val = GLib.Value(GLib.Type.BOOLEAN);
					row.get_property("dimmed", ref dim_val);
					if (dim_val.get_boolean()) {
						item.child.add_css_class("dim-label");
					}
				}
```

#### Replace with

```vala
			factory.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (GLib.Object) item.item;
				if (item.child == null) {
					return;
				}
				var prior = item.child.get_data<GLib.Binding>("argus-column-binding");
				if (prior != null) {
					prior.unbind();
				}
				item.child.set_data<GLib.Binding>("argus-column-binding", null);
				item.child.remove_css_class("dim-label");
				var dim_prop = row.get_class().find_property("dimmed");
				if (format != "dim-text" && dim_prop != null &&
					dim_prop.value_type == GLib.Type.BOOLEAN) {
					var dim_val = GLib.Value(GLib.Type.BOOLEAN);
					row.get_property("dimmed", ref dim_val);
					if (dim_val.get_boolean()) {
						item.child.add_css_class("dim-label");
					}
				}
				if (format == "dim-text") {
					item.child.add_css_class("dim-label");
				}
```

#### 6.6 — `bind`: agent format arms (one `switch (format)`)

**Why:** each agent column gets its own format string in `agent.csv`. Factory code branches on `format` only; `lookup` stays the sort/bind property name from the CSV JSON column.

**Where:** inside the existing `switch (format)` on `bind`, before `case "date":` and before `default`.

**Depends on:** #### 6.3, #### 6.5.

#### Add — before `case "date":` in `factory.bind.connect`

```vala
					case "controller-kind":
						((Gtk.Label) item.child).label = shown;
						((Gtk.Label) item.child).remove_css_class(
							"argus-this-controller");
						var mine = this.grid.get_data<string>(
							"argus-controller-fingerprint");
						if (mine == null || mine == "") {
							break;
						}
						var fp_val = GLib.Value(GLib.Type.STRING);
						row.get_property("fingerprint", ref fp_val);
						if (fp_val.get_string() != mine) {
							break;
						}
						((Gtk.Label) item.child).add_css_class(
							"argus-this-controller");
						break;

					case "recent-created":
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"display-created", item.child, "label",
								GLib.BindingFlags.SYNC_CREATE));
						break;

					case "recent-last-connected":
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"display-last", item.child, "label",
								GLib.BindingFlags.SYNC_CREATE));
						break;

```

#### 6.7 — `bind`: `tick-registered` and `tick-connected`

**Where:** replace the existing `case "tick":` arm in `switch (format)` with three separate arms. Generic `tick` (other grids) stays `!= 0`; agent formats use `== 1` and live `bind_property`.

**Depends on:** #### 6.6.

#### Remove

```vala
					case "tick":
						var tick_image = (Gtk.Image) item.child;
						var ticked = false;
						if (prop.value_type == GLib.Type.BOOLEAN) {
							ticked = value.get_boolean();
						}
						if (prop.value_type == GLib.Type.INT) {
							ticked = value.get_int() != 0;
						}
						if (prop.value_type == GLib.Type.INT64) {
							ticked = value.get_int64() != 0;
						}
						tick_image.icon_name = ticked ? "object-select-symbolic" : null;
						tick_image.visible = ticked;
						break;
```

#### Replace with

```vala
					case "tick-registered":
						var registered_tick = (Gtk.Image) item.child;
						var registered_on = false;
						if (prop.value_type == GLib.Type.INT) {
							registered_on = value.get_int() == 1;
						}
						if (prop.value_type == GLib.Type.INT64) {
							registered_on = value.get_int64() == 1;
						}
						registered_tick.icon_name = registered_on ?
							"object-select-symbolic" : null;
						registered_tick.visible = registered_on;
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"status", item.child, "visible",
								GLib.BindingFlags.SYNC_CREATE));
						break;

					case "tick-connected":
						var connected_tick = (Gtk.Image) item.child;
						var connected_on = prop.value_type == GLib.Type.BOOLEAN &&
							value.get_boolean();
						connected_tick.icon_name = connected_on ?
							"object-select-symbolic" : null;
						connected_tick.visible = connected_on;
						item.child.set_data("argus-column-binding",
							((GLib.Object) row).bind_property(
								"connected", item.child, "visible",
								GLib.BindingFlags.SYNC_CREATE));
						break;

					case "tick":
						var tick_image = (Gtk.Image) item.child;
						var ticked = false;
						if (prop.value_type == GLib.Type.BOOLEAN) {
							ticked = value.get_boolean();
						}
						if (prop.value_type == GLib.Type.INT) {
							ticked = value.get_int() != 0;
						}
						if (prop.value_type == GLib.Type.INT64) {
							ticked = value.get_int64() != 0;
						}
						tick_image.icon_name = ticked ? "object-select-symbolic" : null;
						tick_image.visible = ticked;
						break;
```

- 💩 `status` → `Gtk.Image.visible` may need `bind_property_full` (int to bool, `== 1`) if the plain bind rejects the property pair at compile time. `connected` → `visible` is bool-to-bool.

### 7. `controller/tab/Agent.vala` — migrate to `Base`

**Why:** sorting, shared columns, and `argus-grid-row` tagging.

**Where:** replace the whole file (license header unchanged).

**Depends on:** ### 1, ### 6.

#### Remove

Entire current `controller/tab/Agent.vala`.

#### Replace with

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

namespace Argus.Controller.Tab
{
	/**
	 * Agent page.
	 *
	 * A {@link Gtk.ColumnView} over
	 * {@link Argus.Controller.Store.Agent}.
	 * One button on the page opens registration.
	 * Right-click a row for a menu. Remove on that menu
	 * asks, then deletes the selection.
	 * Right-click a column header to show or hide columns.
	 * Registered starts hidden.
	 * The Kind cell of the controller this window is using
	 * has a green background.
	 * The store loads when the page is shown.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Agent(window);
	 * stack.add_named(page, "agents");
	 * }}}
	 */
	public class Agent : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Agent store;
		private Gtk.Stack body;
		private Adw.Spinner spinner;
		private Adw.ToastOverlay toasts;

		/**
		 * Build the list. One button opens registration.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Agent(Argus.Controller.Window window)
		{
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
			var removing_label = new Gtk.Label("Removing") {
				visible = false
			};
			var pending = new Gee.ArrayList<int>();
			var register_add = new Gtk.Button() {
				child = new Adw.ButtonContent() {
					icon_name = "list-add-symbolic",
					label = "Agent or Controller"
				},
				tooltip_text = "Register an agent or a controller"
			};
			register_add.clicked.connect(() => {
				this.activate_action("win.register", null);
			});
			this.column_grid(this.store, true);
			if (window.issued.client_certificate != "") {
				try {
					var cert = new GLib.TlsCertificate.from_pem(
						window.issued.client_certificate,
						window.issued.client_certificate.length);
					var mine = GLib.Checksum.compute_for_data(
						GLib.ChecksumType.SHA256, cert.certificate.data);
					this.grid.set_data("argus-controller-fingerprint", mine);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			}
			var row_model = new GLib.Menu();
			row_model.append("Remove", "row.remove");
			var row_menu = new Gtk.PopoverMenu.from_model(row_model) {
				has_arrow = false
			};
			row_menu.set_parent(this.grid);
			var remove_rows = new GLib.SimpleAction("remove", null);
			remove_rows.activate.connect(() => {
				if (this.store.busy || removing_label.visible) {
					return;
				}
				string[] names = {};
				var ids = new Gee.ArrayList<int>();
				var selection = (Gtk.MultiSelection) this.grid.model;
				var count = (int) selection.get_n_items();
				for (var i = 0; i < count; i++) {
					if (!selection.is_selected((uint) i)) {
						continue;
					}
					var row = selection.get_item((uint) i) as Argus.Shared.Agent;
					if (row == null) {
						continue;
					}
					names += row.display_name;
					ids.add((int) row.id);
				}
				if (ids.size < 1) {
					return;
				}
				var title = "Remove " + names[0];
				var detail = "This removes the machine from the server.";
				if (ids.size > 1) {
					title = "Remove " + ids.size.to_string() + " machines";
					detail = "This removes them from the server.";
				}
				var confirm = new Adw.AlertDialog(title,
					string.joinv("\n", names) + "\n" + detail);
				confirm.add_response("cancel", "Cancel");
				confirm.add_response("remove", "Remove");
				confirm.set_response_appearance(
					"remove", Adw.ResponseAppearance.DESTRUCTIVE);
				confirm.set_default_response("cancel");
				confirm.set_close_response("cancel");
				confirm.response.connect((response) => {
					if (response != "remove") {
						return;
					}
					pending.clear();
					foreach (var id in ids) {
						pending.add(id);
					}
					removing_label.visible = true;
					this.store.remove(pending.get(0));
				});
				confirm.present(this);
			});
			var row_actions = new GLib.SimpleActionGroup();
			row_actions.add_action(remove_rows);
			this.grid.insert_action_group("row", row_actions);
			var click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY
			};
			var selection = (Gtk.MultiSelection) this.grid.model;
			click.pressed.connect((n_press, x, y) => {
				var picked = this.grid.pick(x, y, Gtk.PickFlags.DEFAULT);
				while (picked != null && picked != this.grid &&
					picked.get_data<Gtk.ListItem>("argus-grid-row") == null) {
					picked = picked.parent;
				}
				if (picked == null || picked == view) {
					click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
				var row_item = picked.get_data<Gtk.ListItem>("argus-grid-row");
				if (row_item == null || this.store.busy || removing_label.visible) {
					return;
				}
				if (row_item.item == null) {
					return;
				}
				if (!selection.is_selected(row_item.position)) {
					selection.select_item(row_item.position, true);
				}
				var at_x = (int) x;
				var at_y = (int) y;
				var where = Gdk.Rectangle() {
					x = at_x,
					y = at_y,
					width = 1,
					height = 1
				};
				row_menu.set_pointing_to(where);
				row_menu.popup();
			});
			this.grid.add_controller(click);
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
			this.store.bind_property("busy", register_add, "sensitive",
				GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.INVERT_BOOLEAN);
			this.store.notify["empty"].connect(() => {
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.failed.connect((heading, message) => {
				pending.clear();
				removing_label.visible = false;
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.removed.connect(() => {
				if (pending.size < 1) {
					return;
				}
				pending.remove_at(0);
				if (pending.size > 0) {
					this.store.remove(pending.get(0));
					return;
				}
				removing_label.visible = false;
				this.toasts.add_toast(new Adw.Toast("Removed"));
				this.store.load();
			});
			this.window.app.rpc.notification.connect((notification) => {
				var refresh = notification.method == "event.agent";
				if (notification.method == "event.pair" && notification.action == "done") {
					refresh = true;
				}
				if (!refresh) {
					return;
				}
				this.store.load();
			});
			this.destroy.connect(() => {
				row_menu.unparent();
			});
			this.map.connect(() => {
				this.store.load();
			});
		}
	}
}
```

### 8. `controller/tab/Repository.vala` — migrate to `Base`

**Why:** same column and sort path as other Base grids.

**Where:** replace the whole file (license header unchanged).

**Depends on:** ### 2, ### 3, ### 4, ### 6.

#### Remove

Entire current `controller/tab/Repository.vala`.

#### Replace with

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

namespace Argus.Controller.Tab
{
	/**
	 * Repository page.
	 *
	 * A {@link Gtk.ColumnView} over {@link Argus.Controller.Store.Repository}.
	 * Clone, pull, and remove sit on this page. Clone opens
	 * {@link Argus.Controller.Dialog.Repository}. The store loads when the
	 * page is created.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Repository(window);
	 * stack.add_named(page, "repositories");
	 * }}}
	 */
	public class Repository : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Repository store;
		private Argus.Controller.Dialog.Repository dialog;
		private Gtk.SingleSelection selection;
		private Gtk.Stack body;
		private Gtk.Button pull_button;
		private Gtk.Button remove_button;
		private Gtk.Button clone_button;
		private Adw.Spinner spinner;
		private Adw.ToastOverlay toasts;

		/**
		 * Build the list, with Clone above it and pull and remove below it.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Repository(Argus.Controller.Window window)
		{
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
			this.clone_button = new Gtk.Button.with_label("Clone") {
				css_classes = { "suggested-action" },
				tooltip_text = "Clone a repository onto the server",
				halign = Gtk.Align.END
			};
			var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			toolbar.append(this.spinner);
			var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			};
			toolbar.append(spacer);
			toolbar.append(this.clone_button);
			this.pull_button = new Gtk.Button.with_label("Pull") {
				sensitive = false,
				tooltip_text = "Fetch this clone and refresh its scripts"
			};
			this.remove_button = new Gtk.Button.with_label("Remove library") {
				sensitive = false,
				css_classes = { "destructive-action" },
				tooltip_text = "Delete this clone from the server"
			};
			var bottom = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.END,
				margin_top = 12,
				margin_bottom = 12,
				margin_start = 12,
				margin_end = 12
			};
			bottom.append(this.pull_button);
			bottom.append(this.remove_button);
			this.column_grid(this.store);
			this.selection = (Gtk.SingleSelection) this.grid.model;
			this.selection.autoselect = false;
			this.selection.can_unselect = true;
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
			this.store.notify["empty"].connect(() => {
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.notify["busy"].connect(() => {
				this.clone_button.sensitive = !this.store.busy;
				if (this.store.busy) {
					this.pull_button.sensitive = false;
					this.remove_button.sensitive = false;
					return;
				}
				var on = this.selection.selected != Gtk.INVALID_LIST_POSITION;
				this.pull_button.sensitive = on;
				this.remove_button.sensitive = on;
			});
			this.selection.selection_changed.connect((position, n_items) => {
				if (this.store.busy) {
					return;
				}
				var on = this.selection.selected != Gtk.INVALID_LIST_POSITION;
				this.pull_button.sensitive = on;
				this.remove_button.sensitive = on;
			});
			this.store.failed.connect((heading, message) => {
				if (this.dialog.showing) {
					return;
				}
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.saved.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Cloned"));
			});
			this.store.pulled.connect((count) => {
				this.toasts.add_toast(new Adw.Toast(
					"Pulled " + count.to_string() + " scripts"));
			});
			this.store.removed.connect(() => {
				this.toasts.add_toast(new Adw.Toast("Removed"));
			});
			this.clone_button.clicked.connect(() => {
				if (this.store.busy) {
					return;
				}
				this.dialog.open(this);
			});
			this.pull_button.clicked.connect(() => {
				var row = this.selection.selected_item as Argus.Shared.SQT.ScriptRepository;
				if (row == null) {
					return;
				}
				this.store.pull((int) row.id);
			});
			this.remove_button.clicked.connect(() => {
				var row = this.selection.selected_item as Argus.Shared.SQT.ScriptRepository;
				if (row == null) {
					return;
				}
				var id = (int) row.id;
				var name = row.display_name;
				var confirm = new Adw.AlertDialog(
					"Remove " + name,
					"This deletes the clone on the server.");
				confirm.add_response("cancel", "Cancel");
				confirm.add_response("remove", "Remove");
				confirm.set_response_appearance(
					"remove", Adw.ResponseAppearance.DESTRUCTIVE);
				confirm.set_default_response("cancel");
				confirm.set_close_response("cancel");
				confirm.response.connect((response) => {
					if (response != "remove") {
						return;
					}
					this.store.remove(id);
				});
				confirm.present(this);
			});
			this.store.load();
		}
	}
}
```

## Attempts

- ℹ️ Split from [2026-11-11-FIXED-column-sort.md](2026-11-11-FIXED-column-sort.md) (sections 7–8) on 2026-11-13.
- ℹ️ 2026-11-14: added verbatim **### 6–8** hunks (guide **Edit syntax contract**).
- ℹ️ 2026-11-14: applied **### 1–8**; §7 row-menu guard uses `picked == this.grid` (not `view`).
- ℹ️ 2026-11-14: archived to `docs/bugs/done/2026-11-14-FIXED-agent-repository-column-sort.md`.

## Next

- ✅ Sort Agents and Repositories headers; reverse sort.
- ✅ Sort, tick an agent, sort again, Remove — removed row matches tick.
- ✅ Column menu show/hide; Registered column default off.
- ✅ Row right-click → Remove; header/empty right-click → column menu.
