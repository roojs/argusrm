# Debian package catalog: integration (phase 2 — agents, install log, UI)

**Status:** ⏳ opened — **proposed fix below; confirm before code**

**Pointer:** `docs/bug-fix-process.md`, phase 1 [2026-11-16-server-apt-repository-dependency-catalog.md](2026-11-16-server-apt-repository-dependency-catalog.md), [`shared/OSQuery/Mounts.vala`](../shared/OSQuery/Mounts.vala), [`server/OSQuery.vala`](../server/OSQuery.vala), [5.9.2.1](../plans/5.9.2.1-assets-software-filters-debian.md), [5.5](../plans/5.5-controller-user-interface.md)

---

## Problem

- 🔷 Phase 1 fills the **repo catalog** on the server (`apt_url`, `apt_pkg`, `apt_pkg_depends`). Machines still only expose **installed** packages via osquery `deb_packages`.
- 🔷 **Expected:**
  - Agents sync osquery **`apt_sources`** to the server (per-agent snapshot, like `mounts`).
  - Server adds **fleet-wide** `apt_url` rows from **all** active `apt_sources` — same repo on many machines → **one** `apt_url` row; phase 1 `CatalogRefresh` indexes that union.
  - Later slices: install log, attribution joins, controller UI.
- 🔷 **Actual:** no `apt_sources` table, no SQL bridge to `apt_url`, no install-log table, no RPC/UI.
- ℹ️ User vs dependency install comes from **log**, not `deb_packages` alone.

---

## Out of scope (this bug vs phase 1)

- 🚫 Downloading `Packages` inside `OSQuery.sync` (stay in `CatalogImport`).
- 🚫 **`apt_url_agent`** junction table — per-machine repo list is `apt_sources` joined to `apt_url` on `url_key` when needed (Slice F).
- ℹ️ Phase 1 closed in [2026-11-16-server-apt-repository-dependency-catalog.md](2026-11-16-server-apt-repository-dependency-catalog.md).

---

## Evidence

- ℹ️ Osquery `apt_sources` columns (local `osqueryi`): `name`, `source`, `base_uri`, `release`, `version`, `maintainer`, `components`, `architectures` (space-separated list).
- ℹ️ Mapping to `apt_url`: `release` → `suite`; `architectures` → pick **`amd64`** when present else first token else `amd64` (must match `AptUrl.fetch()` path segment).
- ℹ️ `url_key` = `base_uri + "|" + suite + "|" + components + "|" + arch` (same string in view and `apt_url.url_key`).
- ℹ️ Existing pattern: `Row.sync_rows` + `OSQuery.sync` in [`server/OSQuery.vala`](../server/OSQuery.vala); agent [`agent/OSQuery/Execute.vala`](../agent/OSQuery/Execute.vala) `sync_table`.

---

## Design fork — fleet `apt_url` from SQL, not Vala upsert

- 🔷 **`apt_sources`** remains normal osquery inventory (`agent_id`, soft-delete audit columns).
- 🔷 View **`apt_sources_catalog`** is a **SQL helper only** (not a product table): DDL lives in **`AptSources`** next to the table DDL so the reconcile statement stays one obvious `INSERT … SELECT … FROM apt_sources_catalog`.
- 🔷 **`apt_url` rows** are created in the **same server path** as a successful **`AptSources`** sync — **`sync_rows` then one `db.exec` reconcile** — so new repos exist **before** the daily **`CatalogRefresh`** / `Packages` import runs (import still daily; no download in `OSQuery.sync`).
- 🚫 No **`apt_url_agent`**.
- 🚫 No separate **`UrlCatalog`** module for v1 — view + reconcile SQL on **`AptSources`**.

---

## Proposed fix (confirm before code)

### Slice A — `apt_sources` inventory + catalog view DDL

**Where:** `shared/OSQuery/AptSources.vala`; `server/Application.vala` calls `AptSources.init_db` **after** `SQT.init_db` (not in `OSQuery.init_db` — view references `apt_url`).

- 🔷 Snapshot sync: `sync_rows` key `{ "base_uri", "release", "components", "source" }` (deb + deb-src lines dedupe at `url_key` via view, not at inventory key).
- 🔷 **`init_db`** — table, audit index, and **`apt_sources_catalog`** view (same method; call after `SQT.init_db`).
- 💩 Skip agent send when host package manager is not APT (Slice B).

#### Add — DDL (`AptSources.init_db`)

```sql
CREATE TABLE IF NOT EXISTS apt_sources (
	id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	agent_id        INTEGER NOT NULL,
	name            TEXT NOT NULL DEFAULT '',
	source          TEXT NOT NULL DEFAULT '',
	base_uri        TEXT NOT NULL DEFAULT '',
	release         TEXT NOT NULL DEFAULT '',
	version         TEXT NOT NULL DEFAULT '',
	maintainer      TEXT NOT NULL DEFAULT '',
	components      TEXT NOT NULL DEFAULT '',
	architectures   TEXT NOT NULL DEFAULT ''
);
-- plus init_db_audit: added_dt, updated_dt, deleted_dt
CREATE INDEX IF NOT EXISTS apt_sources_agent ON apt_sources (agent_id);
```

#### Add — view DDL (end of same `AptSources.init_db`, after `apt_url` exists)

```sql
CREATE VIEW IF NOT EXISTS apt_sources_catalog AS
-- (same body as in shared/OSQuery/AptSources.vala)
```

#### Add — `Application.vala` init order

```vala
Argus.Shared.OSQuery.init_db(this.db);
Argus.Shared.SQT.init_db(this.db);
Argus.Shared.OSQuery.AptSources.init_db(this.db);
```

#### Add — row class (representative)

```vala
public class AptSources : Row {
	public override bool sync (SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows) {
		if (!this.sync_rows<AptSources>(db, agent_id, rows, "apt_sources",
				{ "base_uri", "release", "components", "source" })) {
			return false;
		}
		AptSources.reconcile_apt_url(db);
		return true;
	}
	// ... name, source, base_uri, release, version, maintainer, components, architectures
	public static void reconcile_apt_url (SQ.Database db) { /* Slice C SQL */ }
	public static void rpc_register () {
		OLLMrpc.Bin.register("AptSources", typeof(AptSources));
	}
}
```

---

### Slice B — agent sends `apt_sources`

**Where:** `agent/OSQuery/Execute.vala` `send_packages`; `agent/Application.vala` `rpc_register`; `server/OSQuery.vala` `rpc_register`.

- 🔷 On APT hosts, after `deb_packages` sync: `sync_table("apt_sources", "AptSources")`.
- 🚫 Do not send on DNF/Windows.

#### Replace with — `Execute.vala` (`send_packages`, APT branch)

```vala
case Argus.Shared.OSQuery.PackageManager.APT:
	var code = new DebPackages().send(this.application);
	code += this.sync_table("apt_sources", "AptSources");
	return code;
```

#### Add — registrations

```vala
// agent/Application.vala command_line rpc_register block
Argus.Shared.OSQuery.AptSources.rpc_register();

// server/OSQuery.vala rpc_register
Argus.Shared.OSQuery.AptSources.rpc_register();
```

---

### Slice C — reconcile `apt_url` (same code as `AptSources.sync`)

**Where:** `AptSources.reconcile_apt_url` in `shared/OSQuery/AptSources.vala`; called at end of **`sync()`** after `sync_rows` succeeds (server `OSQuery.sync` path — no extra hook).

- 🔷 One `db.exec`: fleet union into phase 1 `apt_url` (runs on **every** successful `AptSources` sync, **before** the next daily `CatalogRefresh` import).
- 🔷 `INSERT OR IGNORE` — does not clobber `last_synced_dt` / `packages_etag` on existing rows.
- 🚫 Does **not** call `CatalogImport` here — daily refresh still owns `Packages` download.

#### Add — SQL (`AptSources.reconcile_apt_url`)

```sql
INSERT OR IGNORE INTO apt_url (
	url_key,
	base_uri,
	suite,
	components,
	arch
)
SELECT DISTINCT
	url_key,
	base_uri,
	release,
	components,
	catalog_arch
FROM
	apt_sources_catalog;
```

#### Add — Vala

```vala
public static void reconcile_apt_url (SQ.Database db) {
	db.exec("""
		INSERT OR IGNORE INTO apt_url (
			url_key,
			base_uri,
			suite,
			components,
			arch
		)
		SELECT DISTINCT
			url_key,
			base_uri,
			release,
			components,
			catalog_arch
		FROM
			apt_sources_catalog;
		""");
}
```

---

### Slice D — proof test (offline)

**Where:** `server/tests/apt-url-sources.vala`; `meson test apt-url-sources`.

- 🔷 Temp DB: `OSQuery.init_db`, `SQT.init_db`, `AptSources.init_db`, insert one `agent`, one `apt_sources` row, call `AptSources.reconcile_apt_url`, assert one `apt_url` with expected `url_key`.
- 🚫 No network.

---

### Slice E — install log (major; after A–D)

- ⏳ 🔷 Agent persistent cursor on dpkg or apt history; daily delta to server; new table TBD.
- ⏳ 💩 Pick log file per derivative; `OSQuery.sync` vs dedicated RPC.

*(Proposal deferred — separate sub-section when log format chosen.)*

---

### Slice F — attribution queries (after E)

- ⏳ 🔷 “Repos on this machine”: `apt_sources` ⋈ `apt_url` ON `url_key` WHERE `agent_id = ?` AND `deleted_dt = 0`.
- ⏳ 🔷 “User vs dependency”: install-log events ⋈ `deb_packages`.

---

### Slice G — controller / RPC (after F)

- ⏳ 🔷 `AptCatalog.*` in [rpc-commands.md](../rpc-commands.md); remove preview; extra machine/package columns.
- 🚫 Header-bar controls.

---

## Suggested order

1. ✔️ 🔷 Slice A — `apt_sources` table + `apt_sources_catalog` view DDL on `AptSources`.
2. ⏳ 🔷 Slice B — agent + server RPC register; APT sends table.
3. ⏳ 🔷 Slice C — `reconcile_apt_url` at end of `AptSources.sync`.
4. ⏳ 🔷 Slice D — offline meson test.
5. ⏳ Slice E — install log.
6. ⏳ Slice F — attribution SQL.
7. ⏳ Slice G — UI/RPC.

---

## Next

- 💩 `⏳` User confirms Slices **A–D** (view on `AptSources`, reconcile in `sync()`, daily import unchanged).

---

## Attempts / changelog

- ✔️ 2026-11-16: Mistaken Part A implementation (including `apt_url_agent`) **reverted** — not in tree.
- ✔️ 2026-11-16: Proposed fix rewritten as **Slices A–G** with DDL/SQL/Vala fences per `docs/bug-fix-process.md`.
- ✔️ 2026-11-16: View DDL on **`AptSources`**; **`reconcile_apt_url`** in **`sync()`** (before daily `CatalogRefresh`); dropped **`UrlCatalog`** from proposal.
- ✔️ 2026-11-16: Slice A — `shared/OSQuery/AptSources.vala`; `AptSources.init_db` (table + view) after `SQT.init_db` in `server/Application.vala`.

---

## LLM notes

- 🚫 **Do not implement until user approves Slices A–D.**
- 🚫 **No `apt_url_agent`.**
- 🚫 Do not fold `Packages` download into `OSQuery.sync`.