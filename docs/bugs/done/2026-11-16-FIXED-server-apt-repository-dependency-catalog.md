# Server: APT repository dependency catalog (phase 1 — fetch and database)

**Status:** ✅ closed 2026-11-16 — archived; agent `apt_sources` bridge in [2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md](2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md); product UI in open follow-on bugs.

**Pointer:** `docs/bug-fix-process.md`, [2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md](2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md), [`shared/OSQuery/Package.vala`](../../../shared/OSQuery/Package.vala), [`server/Apt/CatalogImport.vala`](../../../server/Apt/CatalogImport.vala), [`server/Initialize.vala`](../../../server/Initialize.vala)

---

## Problem

- 🔷 Argus needs a **server-side reference** of Debian **`Packages`** indices and **Depends / Pre-Depends** edges, separate from per-agent installed rows in `deb_packages`.
- 🔷 **Expected:** `apt_url` / `apt_pkg` / `apt_pkg_depends`, fetch + staging merge, daily refresh.
- ✅ **Resolved:** schema, `CatalogImport`, `CatalogRefresh`, `meson test apt-catalog`.

---

## Out of scope (other bugs)

- 🚫 osquery **`apt_sources`** — [2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md](2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md).
- ✔️ Install log and attribution — [2026-11-16-FIXED-debian-package-catalog-integration.md](2026-11-16-FIXED-debian-package-catalog-integration.md).
- ⏳ Install and remove preview — [2026-11-17-debian-install-remove-preview.md](../2026-11-17-debian-install-remove-preview.md).

---

## What shipped

- ✔️ `shared/SQT/AptUrl.vala`, `AptPkg.vala`, `AptPkgDepends.vala`.
- ✔️ `server/Apt/CatalogImport.vala` — HEAD/GET, staging merge, `|` clauses skipped in v1.
- ✔️ `server/Apt/CatalogRefresh.vala` — run at server up, then every 24h.
- ✔️ `CatalogImport.run_update` also calls `AptSources.reconcile_apt_url` (fleet URLs from agents).
- ✔️ `meson test apt-catalog` (network).

---

## Attempts / changelog

- ✔️ Slice A–C implemented 2026-11-16; `ninja -C build` OK.
- ✅ 2026-11-16: Closed and moved to `docs/bugs/done/`.

---

## LLM notes

- 🚫 No `apt_url_agent`, no `Packages` download in `OSQuery.sync`.
- ℹ️ Osquery **`apt_sources`** (plural) vs server **`apt_url`** (singular).