# Agent osquery refresh after startup (phases 2–3) — superseded

**Status:** 🚫 Closed — **no unique scope**. This file was an index; open work lives only in the links below.

**Pointer:** [2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md)

---

## Where work went

- ✔️ **Logins and local accounts**
  - [2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md](2026-11-14-FIXED-log-monitoring-phase1-user-monitor.md)
- ⏳ **Slow startup tables** (`os_version`, `interface_addresses`, `system_info`)
  - [2.3-future-monitoring.md](../../plans/2.3-future-monitoring.md)
- ⏳ **Processes and listening ports**
  - [2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md)
- ⏳ **Uptime, mounts, connection on General**
  - [2026-11-16-FIXED-machine-additional-osquery-data.md](2026-11-16-FIXED-machine-additional-osquery-data.md)
- ⏳ **Controller refresh when agent syncs**
  - [2026-11-14-package-status-cache-notification.md](../2026-11-14-package-status-cache-notification.md)
- ℹ️ **Packages**
  - `PackageMonitor` in the tree (no open bug required).

---

## Why this file existed

- 💩 Early drafts called “phase 3” **security log shipping** and **Monitoring alert lists**.
- 🚫 That is not osquery `sync_table` refresh.
- 🚫 Nothing here remains to implement after the split above.