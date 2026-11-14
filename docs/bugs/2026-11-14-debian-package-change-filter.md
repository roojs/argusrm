# Debian Software grid: Change / Recent changes filter

**Status:** ⏳ opened — data is stored; bar control not built

**Pointer:** `docs/bug-fix-process.md`, [5.9.1-DONE-assets-software-data.md](../plans/done/5.9.1-DONE-assets-software-data.md), `controller/filter/DebPackages.vala`, `controller/tab/Asset/DebPackages.vala`, `controller/tab/Asset/SystemInfo.vala` (Status dropdown pattern)

---

## Problem

- 🔷 Debian Software filter bar has search, section, and **Versions differ**. Package install/remove/version changes are stored as `added_dt`, `updated_dt`, and `deleted_dt` on each `deb_packages` row ([5.9.1](../plans/done/5.9.1-DONE-assets-software-data.md)).
- 🔷 **Expected:** a **Change** dropdown on the bar (same control style as Machines **Status**): **Any** and **Recent changes**. Recent keeps aggregated rows where any underlying machine row changed in an agreed time window.
- 🔷 **Actual:** `Filters.DebPackages` comment says “Recent changes is not here”; no dropdown on the bar.

---

## Evidence

✔️ `controller/tab/Asset/DebPackages.vala` — bar: `SearchEntry`, section `MenuButton`, `Versions differ` check.

✔️ `controller/filter/DebPackages.vala` — filters `search`, `sections`, `spread` only.

✔️ `DebPackages.list` — aggregated list uses sync timestamps on stored rows; differential `since` load exists on the RPC ([rpc-commands.md](docs/rpc-commands.md)).

💩 Open design (was in archived [5.9.2.1](../plans/done/5.9.2.1-DONE-debian-filters-phase1.md)):

- Window length for “recent” (e.g. 24 h, 7 d) not chosen.
- Aggregated row: match if **any** agent row for that `name` has `added_dt`, `updated_dt`, or `deleted_dt` after `now - window` — may need SQL or client-side filter depending on what `DebPackages.list` returns today for aggregates.

---

## Proposed fix (sketch — review before apply)

1. **`Filters.DebPackages`:** add `change` enum or string (`"any"` / `"recent"`); in `match`, when recent, test row timestamps (properties must be present on aggregated rows or filter uses a server-side flag).
2. **`DebPackages.vala`:** append dropdown next to section; wire like `SystemInfo` status menu.
3. **`shared/OSQuery/DebPackages.vala` `list`:** if aggregated rows do not expose max change time, add a non-stored `last_change_dt` (or filter in SQL for `agent_id == 0` only).
4. **Docs:** `docs/rpc-commands.md` if `list` reply gains a field.

---

## Next

- ⏳ Confirm time window and whether filtering is server-side (preferred for large fleets) or client-side on loaded rows.
- ⏳ Implement and verify on a host with a known package add/remove.

---

## LLM notes

- 🚫 Do not conflate with **needs updating** (`update_since` / `package_updates`) — that is enrichment, not install/remove churn.
- 🚫 Do not add this control to RPM or Windows in this bug (see [2026-11-14-software-filters-remaining.md](2026-11-14-software-filters-remaining.md)).