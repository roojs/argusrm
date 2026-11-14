# MachineGeneral store, ColumnSchema, and General tab

**Status:** ✔️ implemented (`machine_general.csv`, `ColumnSchema`, `Store.Base`, `KeyValue`, `MachineGeneral`, `OsVersion.tooltip_pkgs_status`, `Machine.General`, `Machine.Detail`, `.vertical-list` CSS; compiled, valadoc & 6/6 tests pass, awaiting live UI check)

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md`, `docs/coding-standards.md`, [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md)

---

## Summary of changes

- ✔️ `controller/resources/columns/machine_general.csv` & `controller/resources/argusrm.gresource.xml` — General vertical field CSV (`Indent | Column header | Database name [JSON] | Visible | Width in pixels | Format | Sort | Source`).
- ✔️ `controller/store/ColumnSchema.vala` & `controller/store/Base.vala` — generic `ColumnSchema` (with `indent`, `source`, and `display_value(GLib.Object row)` attaching the source row via `set_data("row", row)` and reading `css_class` / `tooltip-<name>`) + `Base.read_columns(string table, bool has_indent = false)` with `Tab.Base`, `Tab.Asset.SystemInfo`, and `Tab.Tasks` migrated.
- ✔️ `shared/OSQuery/OsVersion.vala` — `OsVersion.list()` maps `pkgs_updated == 0` to `pkgs_status = -1` and exposes derived `tooltip_pkgs_status`.
- ✔️ `controller/store/KeyValue.vala` — `KeyValue` data object with `key`, `val`, `indent`, `expander`, `expanded`, `css_class`, and `tooltip`.
- ✔️ `controller/store/MachineGeneral.vala` — `GLib.ListModel` of `KeyValue` implementing `Base`, loading `SystemInfo.list(agent_id, false)`, `OsVersion.list(agent_id)`, and `OsReleases.list(agent_id)` via `load_sections()` / `load_section()` and replacing `items` on load.
- ✔️ `controller/tab/Asset/Machine/General.vala` & `Detail.vala` — renders `Store.MachineGeneral` with `on_items_changed()`, `Gtk.Expander` sections (`Gtk.ListBox` with `show_separators`, no `boxed-list` or subtitle), `.status-dot` CSS classes, and `.vertical-list` styling in `controller/resources/style.css`; wired as the first tab (`"general"`) in `Machine.Detail`.
- ✔️ `controller/meson.build` & `docs/meson.build` — added `store/ColumnSchema.vala`, `store/Base.vala`, `store/KeyValue.vala`, `store/MachineGeneral.vala`, and `tab/Asset/Machine/General.vala`.

---

## Next

- ⏳ 🔷 Verify the **General** tab and expanders in the running `argusrm-server` / `argusrm-controller` UI.
