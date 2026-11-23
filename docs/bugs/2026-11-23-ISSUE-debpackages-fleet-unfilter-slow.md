# Debian Software fleet grid slow when all Filters are off

**Status:** ✔️

**Pointer:** [`docs/bug-fix-process.md`](../bug-fix-process.md), [`done/2026-11-13-FIXED-controller-package-load-performance.md`](done/2026-11-13-FIXED-controller-package-load-performance.md), [`controller/filter/DebPackages.vala`](../../controller/filter/DebPackages.vala), [`controller/tab/Base.vala`](../../controller/tab/Base.vala)

**Scope:** Controller UI only — server SQL / RPC out of scope (user 2026-11-23).

---

### User decisions required

None.

### User reported

- 🔷 Debian **Software** (fleet): with all three **Filters** ticks off, the grid is very slow.
- 🔷 Default filters feel acceptable after Nov-13 load work.
- 🔷 Ignore server-side optimizations for this issue.

### Success scenario

- Full list is already in the store after the first load.
- User turns Explicit, Leaf, and Update pending **off**; the grid updates without a long main-thread freeze (~1 s order-of-magnitude on a low-thousands fleet).

### Current behavior

- Long stall when all three filter ticks are off (exact ms not logged yet).

### Codebase observed behavior

#### Client path

- [`controller/tab/Asset/DebPackages.vala`](../../controller/tab/Asset/DebPackages.vala) — `FilterListModel` with `incremental = true`.
- [`controller/filter/DebPackages.vala`](../../controller/filter/DebPackages.vala) — all ticks off → `Gtk.FilterMatch.ALL` (no per-row `match`).
- [`controller/tab/Base.vala`](../../controller/tab/Base.vala) `column_grid()` — had `Gtk.SortListModel` with **`incremental = false`**, so a large jump in visible rows after unfilter could sort the full filtered set synchronously on the UI thread.

#### Out of scope

- Server `DebPackages.list` aggregate / `leaf_names` / `explicit_names` (not changed for this issue).

### Debugging

#### Current debug output

None.

#### Debug code added (remove when complete)

None.

### Proposed fix ✔️

#### Phase A — Incremental sort on all `column_grid` tabs

**Why:** Match package `FilterListModel` behavior; defer bulk resort across idle when filter strictness goes to ALL.

**Where:** [`controller/tab/Base.vala`](../../controller/tab/Base.vala) `column_grid()`

#### Remove

```vala
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = false
			};
```

#### Replace with

```vala
			var sorted = new Gtk.SortListModel(model, null) {
				incremental = true
			};
```

### LLM

- User (2026-11-23): client-only; drop Phase B/C server work from this report.
- Applied Phase A in `Base.vala` — affects every tab using `column_grid` (spot-check Machines / Tasks after verify).
- If unfilter is still slow with data already loaded, next client-only ideas: profile `FilterListModel` strictness transitions, column bind cost on `ColumnView` — still no server changes unless user reopens scope.