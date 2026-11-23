# Windows Software fleet — wrong rows on the grid (symptom)

**Status:** ⏳

### User decisions required

None. Scope and filters are already tracked under Software plans and [`2026-11-14-software-filters-remaining.md`](2026-11-14-software-filters-remaining.md).

### User reported

- 🔷 Windows **Software** list is **massive** and hard to use because many rows are **not** software that was **installed** (background / system / services), not slow loading.
- 🔷 Asked whether **binary hash / signature lookup** is the cause — need a clear pointer to the existing work for that.

### Success scenario

- Same as [5.9 Assets — Software](../plans/done/5.9-DONE-assets-software.md) (**Windows**: one **installed program** per fleet row) once [5.9.2](../plans/5.9.2-assets-software-filters.md) Windows filter fields are written and implemented (see backlog below).

### Current behavior

- Fleet **Software → Windows** shows every aggregated `(source, name)` from stored `programs` rows.
- On a fleet copy DB (2026-11-23), per-machine live rows by `source`: `service` 641, `programs` 233, `appx` 127, `startup` 12 → fleet aggregate **949** names.
- User report: feels like inventory noise, not installed applications.

### Codebase observed behavior

- Collection: [5.9.1](../plans/done/5.9.1-DONE-assets-software-data.md) — Windows posts the `Programs` package class via `OSQuery.sync`; MSI log drives resync; exe/Store installs rely on the startup snapshot.
- Agent query: [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala) `snapshot_sql()` unions registry/`appx`, Chocolatey, non–System32 **services**, and **startup** into one table (see agent doc on `send()`).
- UI today: [`controller/filter/Programs.vala`](../../controller/filter/Programs.vala) — search, Versions differ, Can uninstall only ([`2026-11-14-software-filters-remaining.md`](2026-11-14-software-filters-remaining.md)).
- **Binary hashes:** [`2026-11-21-processes-exe-enrichment.md`](2026-11-21-processes-exe-enrichment.md) — **processes** only; not shipped; **not** this grid.

### Debugging

#### Current debug output

```
service|641
programs|233
appx|127
startup|12
```

Sample: `/tmp/argus.sqlite.copy`, 2026-11-23 (`sqlite3` per-machine counts, `deleted_dt = 0`).

#### Debug code added (remove when complete)

None.

### Proposed fix

**None in this file.** Implement only from the existing track:

| Where | What |
| ----- | ---- |
| [`2026-11-14-software-filters-remaining.md`](2026-11-14-software-filters-remaining.md) | Backlog: Windows filter fields **not chosen yet** ([5.9.2](../plans/5.9.2-assets-software-filters.md)); Debian **secondary packages** is the in-tree pattern for hiding non-primary rows ([5.9.2.1](../plans/5.9.2.1-assets-software-filters-debian.md) **Later — secondary packages**). |
| [`docs/plans/5.9.2-assets-software-filters.md`](../plans/5.9.2-assets-software-filters.md) | Write the Windows filter specification (phase 2 of Software). |
| [`docs/plans/5.5-controller-user-interface.md`](../plans/5.5-controller-user-interface.md) | Later: **type**, **sign-off**, Monitoring **Not permitted** — not a substitute for the Software list scope. |
| [`2026-11-21-processes-exe-enrichment.md`](2026-11-21-processes-exe-enrichment.md) | Executable trust / SHA256 — separate from installed-program inventory. |

### LLM

- 🚫 Do not add new product options (default filter hacks, drop sync unions, etc.) in this symptom log.
- ℹ️ Load-time issue (secondary): [`2026-11-23-ISSUE-programs-fleet-grid-slow.md`](2026-11-23-ISSUE-programs-fleet-grid-slow.md).
- User (2026-11-23): prior draft of this file invented fixes; replace with pointers to plans/bugs above.