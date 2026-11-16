# Server: APT repository dependency catalog (phase 1 — fetch and database)

**Status:** ✅ closed — server fetch + import done; [2026-11-16-debian-package-catalog-integration.md](2026-11-16-debian-package-catalog-integration.md) owns agents and UI.

**Pointer:** `docs/bug-fix-process.md`, integration follow-on [2026-11-16-debian-package-catalog-integration.md](2026-11-16-debian-package-catalog-integration.md), [`shared/OSQuery/Package.vala`](../shared/OSQuery/Package.vala), [`shared/SQT/ScriptRepository.vala`](../shared/SQT/ScriptRepository.vala), [`server/Initialize.vala`](../server/Initialize.vala)

---

## Problem

- 🔷 Argus needs a **server-side reference** of Debian **`Packages`** indices and **Depends / Pre-Depends** edges, separate from per-agent installed rows in `deb_packages`.
- 🔷 **Expected (this bug only):**
  - Define **`apt_url`** records on the server (one indexed repository URL + suite; how rows are first created is integration work — not here).
  - **Fetch** `Packages` / `Packages.gz` for each `apt_url`.
  - **Parse**, **stage**, and **merge** into SQLite (`apt_pkg`, `apt_pkg_depends`).
  - **Repeat** on a schedule so the catalog stays current.
- 🔷 **Actual:** no tables, no import, no fetch path.
- ℹ️ End goals (richer Debian UI, remove preview, install reasoning) need this catalog **plus** integration; they live in the sibling bug — **do not implement controller/RPC/agent sync in this file**.

---

## Out of scope (integration bug)

- 🚫 osquery **`apt_sources`** / agent reporting which repos a machine uses.
- 🚫 **`apt_url_agent`** (or any per-agent repo linkage table).
- 🚫 **Install log** / user vs dependency install attribution.
- 🚫 **`AptCatalog.*` RPC** and controller dialogs.
- ℹ️ See [2026-11-16-debian-package-catalog-integration.md](2026-11-16-debian-package-catalog-integration.md).

---

## Evidence

ℹ️ Installed state still uses `Package.sync_packages` in memory ([`shared/OSQuery/Package.vala`](../shared/OSQuery/Package.vala)) — right pattern for agent snapshots, wrong for full repo indices.

ℹ️ Prototype: `TEMP TABLE` staging + SQL delta merge; raw `Sqlite` + `stdout` — reframe to `SQ.Database` + project logging.

🚫 No staging import in tree today.

ℹ️ HTTP: `Soup.Session` in [`server/Initialize.vala`](../server/Initialize.vala).

---

## Design fork — staging merge vs in-memory sync

- 🔷 **`Packages` import** uses **`CREATE TEMP TABLE …_staging`** and reconcile SQL in one transaction — not `sync_packages` over the whole graph.
- 🔷 Catalog repo row table is **`apt_url`** — not `apt_source` (avoids confusion with osquery **`apt_sources`** and `deb_packages.source` = Debian **source package** name).
- 💩 Product tables: **`apt_url`**, `apt_pkg`, `apt_pkg_depends`.
- 🔷 **`Gee.HashMap<string, int64>`** only as a **parse-time name cache** (prototype `pkg_cache`), not whole-file dedupe in Vala.

---

## Proposed fix (phase 1 only — confirm before code)

### Slice A — schema

- ✔️ `apt_url` — `url_key` UNIQUE, `base_uri`, `suite`, `components`, `arch`, `last_synced_dt`, `last_error` (osquery in phase 2); index URL built in `AptUrl.head` / `fetch`.
- ✔️ `apt_pkg` — `name` UNIQUE.
- ✔️ `apt_pkg_depends` — `(apt_url_id, pkg_id, depends_pkg_id)`; index `(apt_url_id, depends_pkg_id)`; ✔️ `constraint_text` stored, unused in v1.
- 💩 Edge rows: **hard-delete** on reconcile (volume); audit `_dt` on `apt_url` only if needed.

**Where:** `shared/SQT/AptUrl.vala`, `AptPkg.vala`, `AptPkgDepends.vala`; `server/Application.vala` `init_db`.

#### Add — DDL (representative)

```sql
CREATE TABLE IF NOT EXISTS apt_url (
	id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	url_key         TEXT NOT NULL UNIQUE,
	base_uri        TEXT NOT NULL DEFAULT '',
	suite           TEXT NOT NULL DEFAULT '',
	components      TEXT NOT NULL DEFAULT '',
	arch            TEXT NOT NULL DEFAULT 'amd64',
	last_synced_dt  INTEGER NOT NULL DEFAULT 0,
	last_error      TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS apt_pkg (
	id   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS apt_pkg_depends (
	apt_url_id      INTEGER NOT NULL,
	pkg_id          INTEGER NOT NULL,
	depends_pkg_id  INTEGER NOT NULL,
	PRIMARY KEY (apt_url_id, pkg_id, depends_pkg_id)
);

CREATE INDEX IF NOT EXISTS apt_pkg_depends_reverse
ON apt_pkg_depends (apt_url_id, depends_pkg_id);
```

### Slice B — import from file (prove merge before network)

**Where:** ✔️ `server/Apt/CatalogImport.vala`.

- ✔️ `AptUrl.head()` / `AptUrl.fetch()` — HEAD compares remote etag/last-modified to stored fields; GET refreshes stored validators.
- ✔️ `new CatalogImport(db, apt_url_row).import()` — HEAD/GET on `AptUrl`; `SQ.Query` + `db.exec` for staging/merge.
- ✔️ `packages_etag` / `packages_last_modified` on `apt_url` for HEAD comparison.

- ✔️ Parse stanzas: `Package`, `Depends`, `Pre-Depends`, continuations.
- ✔️ Stream **package names** into temp `apt_pkg_depends_staging`; merge creates `apt_pkg` rows and resolves ids into `apt_pkg_depends`.
- ✔️ **Version constraints:** package name and parenthetical stored separately (`constraint_text` on `apt_pkg_depends`); no solver use in v1.
- 🚫 **Alternatives (`|`):** entire comma-clause **skipped** until policy chosen (see below).

#### Add — reconcile SQL (`apt_url_id` = `?1`)

```sql
DELETE FROM apt_pkg_depends
WHERE apt_url_id = ?1
  AND (pkg_id, depends_pkg_id) NOT IN (
    SELECT pkg_id, depends_pkg_id FROM apt_pkg_depends_staging
  );

INSERT OR IGNORE INTO apt_pkg (name)
SELECT pkg_name FROM apt_pkg_depends_staging
UNION
SELECT depends_pkg_name FROM apt_pkg_depends_staging
WHERE depends_pkg_name NOT IN (SELECT name FROM apt_pkg);

INSERT OR IGNORE INTO apt_pkg_depends (...)
SELECT ?1, apt_pkg.id, apt_pkg_depends.id, apt_pkg_depends_staging.constraint_text
FROM apt_pkg_depends_staging
INNER JOIN apt_pkg ON apt_pkg.name = apt_pkg_depends_staging.pkg_name
INNER JOIN apt_pkg AS apt_pkg_depends ON apt_pkg_depends.name = apt_pkg_depends_staging.depends_pkg_name;

DROP TABLE apt_pkg_depends_staging;
```

### Depends alternatives (`|`) — deferred

Apt treats `A | B` as **one logical requirement** (satisfy A **or** B). Flat edges `(pkg → A)` and `(pkg → B)` are not equivalent.

- 🔷 **Over-approx (all edges):** remove preview / closure assume **both** legs matter → false warnings when only one alternative is installed.
- 🔷 **Under-approx (first leg only):** wrong when the host satisfied the second alternative → missed deps in preview and incomplete graphs.
- 🔷 **Skip clauses with `|`:** graph is incomplete but not misleading; v1 import does this.
- 💩 **Proper model later:** OR-group id per clause, or hyperedge table; may need constraint-aware matching when `constraint_text` is used.
- ⏳ Choose policy before remove preview (integration bug) relies on catalog closure.

### Slice C — refresh scheduler

**Where:** `CatalogImport.run_update(db)`; `server/Apt/CatalogRefresh.vala` on `Application` (every 24 hours).

- ✔️ `CatalogImport.run_update` — `select` all `apt_url` rows, `import` each.
- ✔️ `CatalogRefresh.start()` — run once at server up, then `GLib.Timeout` 86400s.
- 💩 Private repo credentials — later.
- 💩 **v1 URL list:** however ops insert `apt_url` rows until integration supplies them from agents — not part of slice C design fight.

### Slice D — throwsaway proof (debugging rule)

- ✔️ `server/tests/apt-catalog.vala` — temp SQLite, `apt_url` → Ubuntu `noble` `main` `amd64`, full `CatalogImport.import()` (HEAD/GET live `Packages.gz`).
- ✔️ `meson test apt-catalog` (timeout 300s, needs network): `apt catalog import ok: ubuntu noble main amd64 (21255 depends edges)`.

---

## Suggested order

1. ✔️ Slice A — schema (`shared/SQT/AptUrl.vala`, `AptPkg.vala`, `AptPkgDepends.vala`; `SQT.init_db`).
2. ✔️ Slice B — `Argus.Server.Apt.CatalogImport` + `meson test apt-catalog`.
3. ✔️ Slice C — `CatalogImport.run_update`, `CatalogRefresh` daily timer.

---

## Next

- ✔️ Phase 2 in [2026-11-16-debian-package-catalog-integration.md](2026-11-16-debian-package-catalog-integration.md).

---

## Attempts / changelog

- ✔️ Slice A: `shared/SQT/AptUrl.vala`, `AptPkg.vala`, `AptPkgDepends.vala`; wired in `shared/SQT/namespace.vala` `init_db` (already called from `server/Application.vala` as `Argus.Shared.SQT.init_db`). No audit `_dt` on catalog tables per bug. `ninja -C build` OK.
- ✔️ Slice B: `CatalogImport(db, apt_url_row).import()`; `constraint_text`; `|` clauses skipped.
- ✔️ Slice C: `CatalogImport.run_update`, `CatalogRefresh` 24h on `Application`.

---

## LLM notes

- 🚫 No `apt_url_agent`, no `OSQuery.sync` for catalog bytes.
- ℹ️ Osquery table remains **`apt_sources`** (plural); server catalog row is **`apt_url`** (singular, our schema).
- 🚫 Do not block agent RPC on `Packages` download.