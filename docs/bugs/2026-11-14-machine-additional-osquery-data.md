# Machine detail: additional osquery inventory (uptime, storage, …)

**Status:** ⏳ opened — scope the first table; no implementation yet

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md), [done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md), [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md)

---

## Problem

- 🔷 Machine detail already shows startup-synced tables (`system_info`, `os_version`, `cpu_info`, `interface_addresses`, packages, `users` / `groups`). Several useful osquery tables are **not** collected or shown.
- 🔷 **Expected:** agents sync chosen extra tables at startup (and refresh where live updates matter); the controller exposes them on the machine (General and/or a dedicated tab), same patterns as existing `OSQuery.sync` + `*.list(agent_id)`.
- 🔷 **Actual:** no server rows and no UI for the candidates below.

---

## Evidence

✔️ Startup sync today (`agent/OSQuery/Execute.vala` `send_startup`):

- ✔️ `system_info`, `cpu_info`, `logged_in_users`, `users`, `groups`, `user_groups`, `interface_addresses`, `os_version`, one package class.

🚫 Not in startup or server schema (documented elsewhere):

| Table (osquery) | Notes |
| --- | --- |
| `uptime` | One row per host; seconds since boot ([5.8](../plans/5.8-assets-page.md)). |
| Mounts / disks | e.g. `mounts`, `disk_info` — not chosen in [4.0](../plans/4.0-data-types.md). |
| Listening ports / processes | Not in current schema. |
| Power state | Plan notes there is no field today. |

ℹ️ [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md) §6 listed `users` — now shipped ([2026-11-14-FIXED-machine-users-tab.md](done/2026-11-14-FIXED-machine-users-tab.md)). Remaining candidates are the rows above.

ℹ️ Live session refresh is [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md), not this bug.

---

## Proposed fix (phased — confirm first slice before code)

### Slice 1 (suggested): `uptime`

- 🔷 Add `shared/OSQuery/Uptime.vala` (`Row`), `init_db`, `list(agent_id)`, agent startup `sync_table("uptime", "Uptime")`, server `rpc_register`, `docs/rpc-commands.md`.
- 🔷 Show on **General** (`machine_general.csv` section + `MachineGeneral.load`) or a small **Uptime** row under OS version — match [done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md) placement style.
- 💩 Fields: at minimum boot time / elapsed seconds; format as human-readable duration in the controller.

### Later slices (separate bugs or follow-ups)

- 💩 Storage: pick osquery table(s), column set, and whether one tab or General section.
- 💩 Listening ports / processes — higher volume; may need filters and lazy load.
- 💩 Power state — only if a reliable osquery source exists on target platforms.

---

## Next

- ⏳ User picks **slice 1** table (`uptime` vs storage).
- ⏳ Update [4.0-data-types.md](../plans/4.0-data-types.md) when a table is accepted (schema is Argus-owned, not raw osquery only).
- ⏳ After ship, trim stale “not synced” bullets in [5.8-assets-page.md](../plans/5.8-assets-page.md).

---

## LLM notes

- 🚫 Do not fold this into [5.8](../plans/5.8-assets-page.md) as a new plan chapter; keep work here until closed.
- 🚫 Do not sync high-cardinality tables without an agreed UI and refresh story.
- 🚫 Do not duplicate `cpu_info` work — that is [done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md).