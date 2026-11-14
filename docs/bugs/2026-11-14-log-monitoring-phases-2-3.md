# Agent log monitoring — slow host state and security events (phases 2–3)

**Status:** ⏳ Open. Phase 1 (`UserMonitor`) closed in [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md). Controller cache for live tables: [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md).

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/1.1-implementation.md`, `docs/plans/5.5-controller-user-interface.md`, [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md)

---

## Problem

- 🔷 After boot, **`os_version`** and **`interface_addresses`** still sync only at startup (`Execute.send_startup()`). Network and OS identity can change without an agent push.
- 🔷 No **filtered** security or system log pipeline: Linux journal/auth volume and Windows Security/System beyond phase‑1 IDs are not monitored; executable and socket monitoring from `docs/plans/1.1-implementation.md` is not built.
- ℹ️ Phase 1 covers **`logged_in_users`** and local account tables only.

---

## Evidence

- ✔️ Startup snapshot (`agent/OSQuery/Execute.vala`): `os_version`, `interface_addresses`, `system_info`, `cpu_info` run once with certificate connect / registration — no timer or event resync for `os_version` / `interface_addresses`.
- ✔️ **`PackageMonitor`:** package DB changes + 12h `PackageUpdates` on Linux; Windows MSI events only — not a model for host networking or security log shipping.
- 🚫 No generic log-monitoring class, filtered journal reader, or Windows Security/System monitor for phase‑3 scope exists in the tree.

---

## Assumption

- 🔷 Managed **Linux agents** include **LXC guests on SysV init** (no systemd inside the guest). Phase 2 timers should not assume journald on every host.

---

## Plan

### Phase 2 — slow-changing host state

| Piece | Action |
|-------|--------|
| Tables | `os_version`, `interface_addresses` (optionally `system_info` if product wants live hostname drift — not in startup-only plan unless requested) |
| Trigger | **Daily timer** (same family as Linux 12h `PackageUpdates` in `PackageMonitor`), or a **debounced network trigger** later (e.g. netlink / route or address change) |
| Agent API | Existing `OSQuery.sync` / table classes used at startup — no new RPC unless a new notification is required |
| Controller | Include tables in [2026-11-14-package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md) when agent starts pushing them live |

Out of scope for phase 2 unless folded in explicitly: `cpu_info` (static), `system_info` bulk refresh.

### Phase 3 — security / log events

- 🔷 **Filtered** journal (Linux) or Windows Security/System event IDs — server-side filter DB per `docs/plans/1.1-implementation.md` and monitoring UI in `docs/plans/5.5-controller-user-interface.md`.
- 🔷 May **ship events** to the server (not only `OSQuery.sync` table refresh).
- 🚫 **Not** tied to refreshing `logged_in_users` / `users` (phase 1).
- 🚫 **No** unfiltered `/var/log/auth.log` or full auth journal — SSH failure noise would overwhelm agents and server (same constraint as phase 1).

---

## Proposed fix

💩 Not designed in detail yet. Likely:

1. **Phase 2:** New monitor class or extend an existing agent timer module; register daily (and document interval) sync for `OsVersion` and `InterfaceAddresses`; wire `Application` / `Service` like `UserMonitor`.
2. **Phase 3:** Separate design spike — agent subscription surface, server ingest + filter replication, controller display; may need new RPC and tables beyond osquery sync.

Stop for approval before any phase‑3 API or persistence design lands (major change per `docs/bug-fix-process.md`).

---

## Next

- ⏳ Phase 2: pick interval (daily vs 12h), implement timer + sync, add controller notification table list.
- ⏳ Phase 3: align with `1.1-implementation` event filter schema; draft agent channel list and server storage.