# Agent log monitoring — security and system events (phase 3)

**Status:** ⏳ Open — phase 3 only. Phase 1 (`UserMonitor`) closed in [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md). Slow-changing host state (former phase 2) moved to [2.3-future-monitoring.md](../plans/2.3-future-monitoring.md).

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/1.1-implementation.md`, `docs/plans/5.5-controller-user-interface.md`, `docs/plans/2.3-future-monitoring.md`, [done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](done/2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md), [2026-11-14-machine-processes-ports-live.md](2026-11-14-machine-processes-ports-live.md)

---

## Problem

- 🔷 No **filtered** security or system log pipeline exists: Linux journal/auth/syslog volume and Windows Security/System events beyond phase‑1 IDs are not monitored.
- 🔷 Executable and socket monitoring from `docs/plans/1.1-implementation.md` (Later — security) is not built.
- ℹ️ Phase 1 covers **`logged_in_users`** and local account tables (`users`, `groups`, `user_groups`) only.
- ℹ️ Slow-changing host state (`os_version`, `interface_addresses`, `system_info`) was removed from this bug and deferred to [2.3-future-monitoring.md](../plans/2.3-future-monitoring.md).

---

## Evidence

- ✔️ `agent/linux/UserMonitor.vala` and `agent/Win32/UserMonitor.vala` implement phase 1 only:
  - Linux watches utmp or `/run/systemd/sessions/` for logins and `/etc/passwd` + `/etc/group` for accounts.
  - Windows subscribes to Security log IDs `4624` / `4634` / `4647` (sessions) and `4720` / `4726` / `4738` (accounts) and triggers `OSQuery.sync`.
- ✔️ `agent/linux/PackageMonitor.vala` and `agent/Win32/PackageMonitor.vala` cover package DB changes and 12h `PackageUpdates` only — not a generic log or security event pipeline.
- 🚫 No generic log-monitoring class, filtered journal/syslog reader, Windows Security/System event shipper, or server-side event filter DB exists in the tree.

---

## Assumption

- 🔷 Managed **Linux agents** include **LXC guests on SysV init** (no systemd or journald inside the guest). Linux log monitoring cannot assume journald exists on every host.

---

## Plan — phase 3 security / log events

- 🔷 **Filtered** journal/syslog (Linux) or Windows Security/System event IDs, plus executable and socket event monitoring per `docs/plans/1.1-implementation.md` (Later — security).
- 🔷 **Server-side filter DB replicated to the agent:** the agent evaluates events locally against the replicated filter and only ships matching events.
- 🔷 **Event shipping pipeline:** ships events to the server (not only full-table `OSQuery.sync` snapshots).
- ℹ️ Controller **Monitoring** UI in `docs/plans/5.5-controller-user-interface.md` reserves space for new executable and unexpected socket tabs alongside **Needs update** and **Not permitted**.
- 🚫 **Not** tied to refreshing `logged_in_users` / `users` (phase 1 handles those).
- 🚫 **No** unfiltered `/var/log/auth.log` or full auth journal shipping — SSH failure noise would overwhelm agents and server (same constraint as phase 1).

---

## Proposed fix

💩 Not designed in detail yet. Requires a separate design spike covering:

- 💩 **Agent event sources & filter evaluation:** Linux journald / SysV syslog fallback, Windows Security/System subscriptions, and local matching against replicated filters.
- 💩 **Server filter DB & replication:** schema for event filters and sync/push mechanism to agents.
- 💩 **Server ingest & controller display:** new RPC/storage beyond `OSQuery.sync`, plus Monitoring page tabs.

🔷 Stop for approval before any phase‑3 API, RPC, or persistence design lands (major change per `docs/bug-fix-process.md`).

---

## Next

- ⏳ 🔷 Align with `docs/plans/1.1-implementation.md` event filter schema and `docs/plans/5.5-controller-user-interface.md` Monitoring UI.
- ⏳ 💩 Draft agent event channel list, filter replication model, and server storage/RPC proposal for approval.
