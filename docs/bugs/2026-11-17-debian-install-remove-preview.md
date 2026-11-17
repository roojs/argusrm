# Debian: preview install and remove

**Status:** ⏳ preview is in the tree — all dependents, one query, and the dialog. Start does not queue a task yet

**Pointer:** `docs/bug-fix-process.md`, closed catalog [done/2026-11-16-FIXED-debian-package-catalog-integration.md](done/2026-11-16-FIXED-debian-package-catalog-integration.md), [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-windows-uninstall-task-queue.md), [2026-11-14-software-package-machines-grid.md](2026-11-14-software-package-machines-grid.md), [rpc-commands.md](../rpc-commands.md), [`controller/dialog/Distribute.vala`](../../controller/dialog/Distribute.vala), [`shared/SQV/PackageMachine.vala`](../../shared/SQV/PackageMachine.vala), [`server/SQV/PackageMachine.vala`](../../server/SQV/PackageMachine.vala), [`shared/SQT/AptPkg.vala`](../../shared/SQT/AptPkg.vala), [`shared/SQT/AptPkgDepends.vala`](../../shared/SQT/AptPkgDepends.vala)

---

## Problem

- 🔷 Debian remove is not queued. Before it is approved, the controller shows the packages that would be removed with it.
- 🔷 That list is the packages that depend on the one being removed and so have to be removed, and the packages that are likely to be removed with it.
- 🔷 Install is the same idea the other way. Before it is approved, the controller shows the packages that would be pulled in.
- 🔷 Both lists use one dialog. The shell is the distributable install dialog, which is also the shell the software machines dialog uses.
- 🔷 The other reason for this RPC is the dependency tree. `apt_pkg` / `apt_pkg_depends` answer what a package depends on, and what depends on it. Windows uninstall left Debian out until that tree existed.
- 🔷 **Actual:** no catalog RPC, no approval list, no Debian install or remove task.

---

## Carried from the catalog bug

- 🚫 Header bar controls. The preview is the dialog in **Window**. It is not a control in the window header, and not a second grid on the Software page.
- ℹ️ Phase 1 import skipped `|` alternatives. A preview does not guess which alternative. It stays conservative.
- 🚫 No `apt_url_agent`. A machine's repos stay `apt_sources_catalog` joined to `apt_url` on `url_key`.

---

## Window

The remove preview and the install preview are one `Adw.Dialog`. The shell is [`controller/dialog/Distribute.vala`](../../controller/dialog/Distribute.vala). [2026-11-14-software-package-machines-grid.md](2026-11-14-software-package-machines-grid.md) uses that same shell for the machines that have one package name. That dialog is not in the tree yet. This one is not either.

- 🔷 Title is the package name. `Distribute.open` sets `this.title` from the row name the same way.
- 🔷 Remove fills the column view with the packages that come off with it.
  - 🔷 Packages that depend on it, so they have to be removed.
  - 🔷 Packages that are likely to be removed with it.
- 🔷 Install fills the same column view with the packages that would be pulled in.
- 🔷 Search filters the package names in the list. The entry is the install dialog's `Gtk.SearchEntry`, `hexpand`, and `search_changed` writes `filter.search`.
- 🔷 While the call is in flight the body is the spinner. No rows shows "No packages". Cancel closes the dialog.
- 🔷 Approving queues the task, so the action row keeps the install dialog's **Start the task now** (`suggested-action`, on the right of Cancel). The software machines dialog leaves that button off. Upgrade and a per-machine uninstall sit on that dialog instead. Debian uninstall still opens this preview and does not queue a remove.
- 🚫 Tick column and Select all. On the install dialog those pick machines. Here the rows are the packages in the list.
- 🚫 A second grid or a lower pane on the Software page. The software machines bug already keeps the list in the dialog.

### How it is built

✔️ `Distribute` is an `Adw.Dialog` with `content_width` 880 and `content_height` 520. The preview uses those sizes.

✔️ The list model is a `Gtk.FilterListModel` (`incremental = true`) over the store and the filter, then a `Gtk.SortListModel` (`incremental = false`), then a `Gtk.SingleSelection`. The column view is `hexpand`, `vexpand`, `show_row_separators`. `sorted.sorter = grid.sorter`.

✔️ A text column is a `Gtk.SignalListItemFactory`. `setup` builds a `Gtk.Label` with `xalign` 0, `hexpand`, and ellipsize end. `bind` sets `label` and `tooltip_text` from the row. The column sorter is a `Gtk.StringSorter` on a `Gtk.PropertyExpression`, `ignore_case`. That is the Machine column in `Distribute`. The preview's package-name column is that factory.

✔️ The body is one `Gtk.Stack`, `transition_type` none, three named children:

- `wait` — `Adw.Spinner`, 48 by 48, centered.
- `list` — `Gtk.ScrolledWindow` around the column view, `min_content_height` 240.
- `empty` — `Gtk.Label`, centered, `wrap`.

✔️ `store.notify["busy"]` switches the stack. `busy` shows `wait`. `empty` shows `empty`. Otherwise `list`.

✔️ A failure calls `Argus.Shared.Notice` on the dialog, and only while `showing` is true. `closed` sets `showing` false.

✔️ `open` returns immediately when `showing` is already true. It sets the title, clears the search text and `filter.search`, sets `showing`, calls `present(parent)`, then loads.

The widget tree under the dialog, after the column view exists:

```vala
var search = new Gtk.SearchEntry() {
	placeholder_text = "Search packages",
	hexpand = true
};
var empty_label = new Gtk.Label("No packages") {
	halign = Gtk.Align.CENTER,
	valign = Gtk.Align.CENTER,
	wrap = true
};
var wait = new Adw.Spinner() {
	width_request = 48,
	height_request = 48,
	halign = Gtk.Align.CENTER,
	valign = Gtk.Align.CENTER
};
var body = new Gtk.Stack() {
	hexpand = true,
	vexpand = true,
	transition_type = Gtk.StackTransitionType.NONE
};
body.add_named(wait, "wait");
body.add_named(new Gtk.ScrolledWindow() {
	child = grid,
	hexpand = true,
	vexpand = true,
	min_content_height = 240
}, "list");
body.add_named(empty_label, "empty");
var cancel = new Gtk.Button.with_label("Cancel");
var start = new Gtk.Button.with_label("Start the task now") {
	css_classes = { "suggested-action" },
	sensitive = false
};
var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
	halign = Gtk.Align.END
};
actions.append(cancel);
actions.append(start);
var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
bar.append(search);
var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
	margin_top = 16,
	margin_bottom = 16,
	margin_start = 16,
	margin_end = 16
};
box.append(bar);
box.append(body);
box.append(actions);
this.child = box;
```

- ℹ️ The install dialog's bar also appends Select all. This preview does not.
- ✔️ **Start the task now** is on the dialog and stays insensitive. Queuing the remove is still open, so the button does not become active when the list loads.

---

## Rows

The column view is a flat list. Each row is one package in the dependency list for the package being installed or removed. The edges are the dependency tree. The dialog stays this column view.

- 🔷 Those rows use the SQV format. `PackageMachine` and `DistributeMachine` are that kind of row: a query result, not a stored table.
- 🔷 The other possibility is a direct reply of `apt_pkg_depends` or `apt_pkg`.
- ✔️ An `Argus.Shared.SQV` type implements `OLLMrpc.Bin.Serializable`. It has no `init_db`. `PackageMachine.machines` builds `SQ.Query<Argus.Shared.SQV.PackageMachine>` on `deb_packages`, `rpm_packages`, or `programs`. The SELECT fills `machine`, `logged_in_users`, and `version`, which are not columns of that table. `shared/SQV/namespace.vala` registers the wire type. `server/SQV/namespace.vala` registers the handler. `server/Application.vala` calls `SQV.PackageMachine.rpc_register` and `SQV.register`.
- ✔️ `apt_pkg_depends` is `apt_url_id`, `pkg_id`, `depends_pkg_id`, and `constraint_text`. `apt_pkg` is `id` and `name`.
- ✔️ A direct `AptPkgDepends` row is those ids. A direct `AptPkg` row is the name. The column shows the name. The two groups (has to go, likely to go) are not a column of either table.
- ✔️ The reply is `Argus.Shared.SQV.AptDepends`. `AptDepends.dependents` is one recursive query on `apt_pkg_depends` joined to `apt_pkg`. `AptDepends.removed` is the RPC. Holding Remove on the Debian Software grid opens `controller/dialog/AptDepends.vala`. The column view sorts the names.

---

## Open

- 💩 Packages that are likely to be removed (autoremove) are not in that list. The catalog has no Recommends edges and no installed set.
- 💩 Install preview uses this same dialog. The list of packages that would be installed is not designed yet.
- 💩 One machine, or every machine that has the package.
- 💩 **Start the task now** still has to become a task. The Windows hold button queues immediately. Debian does not copy that until this list is approved.
- ✔️ All dependents are tested offline in `server/tests/apt-depends.vala`. `apt dependents ok`.

---

## Next

- ✔️ The dialog and `AptDepends.removed` are in the tree. Start stays off. It does not queue a task.
- ⏳ 🔷 Install rows, the "likely" set, and the task after Start.

---

## Attempts / changelog

- ✔️ 2026-11-17: Split out of slice **G** of [done/2026-11-16-FIXED-debian-package-catalog-integration.md](done/2026-11-16-FIXED-debian-package-catalog-integration.md).
- ✔️ 2026-11-17: The preview dialog is the distributable install shell, shared with the software machines dialog. Remove lists dependents that have to go, and packages likely to go.
- ✔️ 2026-11-17: The list is an SQV view of the dependency list, the same kind of row as `PackageMachine`. The SELECT can still read `apt_pkg_depends`. A direct reply of that table is still open. `apt_pkg_depends` has no package name.
- ✔️ 2026-11-17: `AptDepends.removed` returns the reverse Depends / Pre-Depends closure. Holding Remove on Software → Debian opens the preview. `argus-apt-depends-test` passed. Start does not queue a task.
- ✔️ 2026-11-17: `AptDepends.dependents` is one recursive query. The RPC does not sort. The column view does.
