# Machine detail: additional osquery inventory (uptime, storage, connection)

**Status:** ⏳ opened — slice 1 (`uptime` on General, **Storage** tab); processes/ports out of scope here

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md), [done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md), [2026-11-14-machine-processes-ports-live.md](2026-11-14-machine-processes-ports-live.md)

---

## Problem

- 🔷 Machine detail already shows startup-synced tables (`system_info`, `os_version`, `cpu_info`, `interface_addresses`, packages, `users` / `groups`). Several useful osquery tables are **not** collected or shown.
- 🔷 **Expected:** low-cardinality startup sync — **`uptime`** on **General**; **storage** on its own machine tab with usage bars; high-cardinality **processes / listening ports** use view-driven live sync ([2026-11-14-machine-processes-ports-live.md](2026-11-14-machine-processes-ports-live.md)).
- 🔷 **Actual:** no server rows and no UI for the candidates below.

---

## Decisions (2026-11-14)

| Topic | Decision |
| --- | --- |
| `uptime` | Osquery **`uptime`** is **one row per host** (`total_seconds`, `days`, `hours`, …). Ship on **General**, human-readable duration + optional detail fields. |
| Storage | **Dedicated Storage tab** in machine detail — osquery **`mounts`** (and optional **`disk_info`** later). Each mount row shows **used space with a bar** (e.g. `Gtk.ProgressBar` / `Adw.LevelBar`), plus path, type, size/free labels. Startup sync; not on General. |
| Processes / ports | **Separate bug** — live watch while tab visible, not startup sync. |
| “Power state” | **Not** osquery power for v1. Show **agent connection** (`connected`, `last_connected` from `agent`) on machine **General** so offline machines read clearly when inventory is stale (today that tick lives on the **Agents** grid only). |
| Other candidates | Still out of scope here: `routes`, `interface_details` ([machines-detail-pane](done/2026-11-13-FIXED-machines-detail-pane.md) §3). |

---

## Evidence

✔️ Startup sync today (`agent/OSQuery/Execute.vala` `send_startup`):

- ✔️ `system_info`, `cpu_info`, `logged_in_users`, `users`, `groups`, `user_groups`, `interface_addresses`, `os_version`, one package class.

🚫 Not in startup or server schema:

| Table (osquery) | Notes |
| --- | --- |
| `uptime` | One row per host ([5.8](../plans/5.8-assets-page.md)). |
| `mounts` / `disk_info` | Storage / fullness — not in [4.0](../plans/4.0-data-types.md). |
| `processes` / `listening_ports` | [2026-11-14-machine-processes-ports-live.md](2026-11-14-machine-processes-ports-live.md). |
| `routes` / `interface_details` | Inspected in detail-pane bug; not synced. |

ℹ️ [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md) §6 — `users` shipped ([2026-11-14-FIXED-machine-users-tab.md](done/2026-11-14-FIXED-machine-users-tab.md)).

ℹ️ Live session refresh for logins is phase 1 — not this bug.

---

## Proposed fix (phased — confirm before code)

### Slice 1a: `uptime` on General

- 🔷 Add `shared/OSQuery/Uptime.vala` (`Row`), `init_db`, `list(agent_id)`, agent startup `sync_table("uptime", "Uptime")`, server `rpc_register`, `docs/rpc-commands.md`.
- 🔷 **General** only — new expander section in `machine_general.csv` + `Store.MachineGeneral` / `SystemInfo.list` join pattern per [done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md).
- 💩 Display: format `total_seconds` as duration; optional breakdown fields hidden by default.

### Slice 1b: **Storage** tab (`mounts`)

- 🔷 Add `shared/OSQuery/Mounts.vala` (`Row`), `init_db`, `Mounts.list(agent_id)`, agent startup `sync_table("mounts", "Mounts")`, server `rpc_register`, `docs/rpc-commands.md`.
- 🔷 New machine detail tab **`controller/tab/Asset/Machine/Storage.vala`** (name TBD: **Storage** / **Disks**) in `Machine/Detail.vala` toggle order — after **Interfaces** or **General**, product call.
- 🔷 **UI:** custom list, not a plain `Tab.Base` grid — one row per mount with mount point (row title), type/device, human-readable **total / used / free**, and a **horizontal usage bar** (`fraction = 1 - blocks_free/blocks` or `blocks_available` — pick one and document). Sort by path or by % full.
- 💩 Filter: hide noisy ephemeral mounts (`tmpfs`, `snap`, loop/docker) behind a toggle defaulting sensibly per OS.
- 💩 Optional v2: periodic resync (daily?) like [2026-11-14-log-monitoring-phases-2-3.md](2026-11-14-log-monitoring-phases-2-3.md) phase 2 — v1 startup-only is enough to ship the tab.
- 🚫 Do not cram storage into `machine_general.csv`.

### Slice 1c: agent connection on General

- 🔷 Join `agent.connected`, `agent.last_connected` (and optionally `agent.status`) into machine General / list query — same semantics as `controller/resources/columns/agent.csv` `tick-connected` / `recent-last-connected`.
- 🔷 When `connected` is false, General can still show **last synced** inventory with explicit stale/offline affordance (pairs with processes/ports live bug).

### Out of scope (this file)

- [2026-11-14-machine-processes-ports-live.md](2026-11-14-machine-processes-ports-live.md)
- `routes`, `interface_details`, security baseline / approved executable lists (`docs/plans/1.1-implementation.md`)

---

## Next

- ⏳ Implement order: **1a uptime** → **1b storage** → **1c connection** (or 1c early if cheap join).
- ⏳ Update [4.0-data-types.md](../plans/4.0-data-types.md) when each table is accepted.
- ⏳ After ship, trim stale bullets in [5.8-assets-page.md](../plans/5.8-assets-page.md).

---

## LLM notes

- 🚫 Do not fold this into [5.8](../plans/5.8-assets-page.md) as a new plan chapter; keep work here until closed.
- 🚫 Do not add processes/ports startup sync — see [2026-11-14-machine-processes-ports-live.md](2026-11-14-machine-processes-ports-live.md).
- 🚫 Do not duplicate `cpu_info` work — [done/2026-11-14-FIXED-machine-cpu-in-general.md](done/2026-11-14-FIXED-machine-cpu-in-general.md).