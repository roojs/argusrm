# Software page: machines grid for selected package name

**Status:** ⏳ opened — design stub; not in tree

**Pointer:** `docs/bug-fix-process.md`, [../plans/done/5.9-DONE-assets-software.md](../plans/done/5.9-DONE-assets-software.md), [5.5-controller-user-interface.md](../plans/5.5-controller-user-interface.md)

---

## Problem

- 🔷 On Software, each sub-tab is one row per package **name** (aggregate). Operators need the list of **machines** that have the selected name and per-machine package fields (version, `update_since`, etc.).
- 🔷 **Expected:** select one row in the upper grid → lower region shows one row per machine for that name (Debian, RPM, or Windows table). Hidden when nothing selected.
- 🔷 **Actual:** only aggregate grids; per-machine package grids exist under **Machine detail** (`DebPackages.list(agent_id > 0)`), not under Software.

---

## Evidence

✔️ `DebPackages.list`, `RpmPackages.list`, `Programs.list` support `agent_id > 0` ([rpc-commands.md](docs/rpc-commands.md)).

✔️ `controller/tab/Asset/Machine/DebPackages.vala` etc. already load per-agent rows.

🚫 `controller/tab/Asset/Software.vala` has no paned selection or second grid.

---

## Proposed fix (sketch)

1. **`Software.vala` or per-tab:** `Gtk.Paned` or fixed lower `ScrolledWindow`; bind selection on aggregate `ColumnView`.
2. **Store:** reuse `Store.DebPackages` (etc.) with `load` for selected `name` — may need new RPC or `list` filter by name + all agents (confirm SQL).
3. **Columns:** per-machine columns TBD (`hostname` join, version, `update_since`, …).
4. **Picture:** [5.5](../plans/5.5-controller-user-interface.md) lower region.

---

## Next

- ⏳ Confirm list API: `agent_id` + `name` vs client filter.
- ⏳ Choose status columns before implementation.

---

## LLM notes

- 🚫 Do not mix platforms in the lower grid.
- 🚫 Do not replace Machine detail package tabs.