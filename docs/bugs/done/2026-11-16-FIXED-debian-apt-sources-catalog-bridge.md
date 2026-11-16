# Debian: agent `apt_sources` → fleet `apt_url` (catalog bridge)

**Status:** ✅ closed 2026-11-16 — Slices A–D in tree; follow-ons split into separate open bugs.

**Pointer:** `docs/bug-fix-process.md`, phase 1 [2026-11-16-FIXED-server-apt-repository-dependency-catalog.md](2026-11-16-FIXED-server-apt-repository-dependency-catalog.md), [`shared/OSQuery/AptSources.vala`](../../../shared/OSQuery/AptSources.vala), [`agent/OSQuery/Execute.vala`](../../../agent/OSQuery/Execute.vala), [`server/Apt/CatalogImport.vala`](../../../server/Apt/CatalogImport.vala)

---

## Problem

- 🔷 Phase 1 can import **`Packages`** only for rows in **`apt_url`**, but the server had no per-machine repo configuration from agents.
- 🔷 **Expected:** APT agents sync osquery **`apt_sources`**; before each catalog refresh, distinct repos become **`apt_url`** rows (fleet union, `INSERT OR IGNORE`).
- ✅ **Resolved:** inventory table + view, agent send, reconcile on **`CatalogImport.run_update`**, offline test.

---

## Design (as built)

- 🔷 **`apt_sources`** — normal osquery inventory (`sync_rows` key `base_uri`, `release`, `components`, `source`).
- 🔷 **`apt_sources_catalog`** — SQL view only (`AptSources.init_db` after `SQT.init_db`).
- 🔷 **`reconcile_apt_url`** — **not** on `AptSources.sync`; only **`CatalogImport.run_update`**.
- 🚫 No **`apt_url_agent`** — join on `url_key` when needed (attribution bug).

---

## Shipped slices

| Slice | Deliverable |
|-------|-------------|
| A | `shared/OSQuery/AptSources.vala`, `server/Application.vala` init order |
| B | APT `send_packages` + `Argus.Shared.OSQuery.rpc_register()` |
| C | `AptSources.reconcile_apt_url` in `CatalogImport.run_update` |
| D | `server/tests/apt-url-sources.vala` — `meson test apt-url-sources` |

---

## Follow-on (open bugs)

- ⏳ Slices E–G — [2026-11-16-debian-package-catalog-integration.md](../2026-11-16-debian-package-catalog-integration.md).

---

## Attempts / changelog

- ✔️ 2026-11-16: Slices A–D; reconcile moved off inventory sync per user direction.
- ✅ 2026-11-16: Closed; E–G extracted to separate bug files.

---

## LLM notes

- 🚫 Do not re-add reconcile on **`AptSources.sync`**.
- 🚫 Do not fold **`Packages`** download into **`OSQuery.sync`**.