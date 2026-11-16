# Debian package catalog: install log, attribution, controller (phase 2 product)

**Status:** ⏳ opened — Slice **E** design drafted (apt history); confirm before code

**Pointer:** `docs/bug-fix-process.md`, prerequisites [2026-11-16-FIXED-server-apt-repository-dependency-catalog.md](done/2026-11-16-FIXED-server-apt-repository-dependency-catalog.md), [2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md](done/2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md), [5.9.2.1](../plans/5.9.2.1-assets-software-filters-debian.md), [5.5](../plans/5.5-controller-user-interface.md), [rpc-commands.md](../rpc-commands.md), [`agent/linux/PackageMonitor.vala`](../../agent/linux/PackageMonitor.vala)

---

## Problem

- 🔷 Catalog + **`apt_sources`** bridge are in tree; the **product** still lacks install reasoning, queryable attribution, and Debian UI that uses the dependency graph.
- 🔷 **Expected:** apt history hints → server **`apt_explicit_install`** → attribution joins → controller RPC/UI.
- 🔷 **Actual:** none of E–G implemented.

---

## Suggested order

1. ⏳ **Slice E** — apt history → explicit install names on server.
2. ⏳ **Slice F** — attribution SQL (repos join; explicit vs dependency hint).
3. ⏳ **Slice G** — controller + RPC.

---

### Slice E — apt history (explicit installs)

#### Decisions

- ✅ **Log source:** **`/var/log/apt/history.log`** and rotated **`history.log.*.gz`** under **`/var/log/apt/`** — not **`dpkg.log`**.
- 🔷 **Agent code:** new directory **`agent/linux/Apt/`** (e.g. `History.vala`, wired from Linux `Application` / service startup beside **`PackageMonitor`**).
- 🔷 **Semantics (v1):** one row per binary package name that appeared on an **`apt install`** (or `apt-get install`) **Commandline:** line, with the transaction **`Start-Date`** beside it. Not a full event timeline. A later install of the same name is not a second row.
- 🔷 **Server:** per-agent rows keyed by **`name`** (matches **`deb_packages.name`**) plus **`installed_dt`**. Not a local agent SQLite **`packages`** table and not **`apt_pkg`** catalog ids.
- 🔷 **Sync is incremental.** Unlike **`sync_rows`**, the agent sends only names whose stanza **`Start-Date`** is after the local watermark. The server inserts those names and does not tombstone rows missing from the batch. **`sync_rows`** would delete every earlier explicit install the moment the batch is a delta.
- 🔷 **Watermark:** one unix time in the agent data dir — “nothing after this date.” It is the latest **`End-Date`** of a complete stanza already accepted (sent, or a pass with nothing new). A stanza with no **`End-Date`** yet is left for the next pass, and the watermark does not move past it. Failed send does not move the watermark.
- 💩 **Schedule:** daily pass (aligned with package update cadence) plus optional **`FileMonitor`** on **`history.log`** with debounce like **`UserMonitor`**.
- 🚫 Do not infer user install from **`deb_packages`** alone.
- 🚫 **No `zcat` subprocess** in product code if **`Gio.ZlibDecompressor`** / stream read suffices.
- 🚫 Do not call **`sync_rows`** for this table.

#### Evidence — apt history line shape

```text
Start-Date: 2026-11-06  11:41:54
Commandline: apt install libnftables-dev
Requested-By: alan (1001)
Install: libnftables-dev:amd64 (1.1.1-1build1)
End-Date: 2026-11-06  11:41:57
```

- ✔️ **Date is on the stanza, not the package token.** **`Start-Date:`** is `YYYY-MM-DD`, two spaces, `HH:MM:SS`. Every package named on that **`Commandline:`** shares it. On this machine, 68/68 install commands in **`/var/log/apt/history.log`** and **`history.log.*.gz`** had a **`Start-Date`** (0 missing).
- ℹ️ The clock is local wall time. The line has no timezone.
- 🔷 Tokenize after **`install`**; stop at **`=`** version pins; skip tokens starting with **`-`**; skip empty tokens.
- 💩 **`apt upgrade` / `dist-upgrade` / `autoremove`** — out of scope for v1 explicit set. Their stanzas still advance the watermark.
- ℹ️ **`aptdaemon role='role-commit-packages'`** lines have a **`Start-Date`** and no package tokens. They do not create rows. The watermark still moves past a complete stanza.

#### Add — server DDL (`AptExplicitInstall.init_db` on server, with other OSQuery tables)

```sql
CREATE TABLE IF NOT EXISTS apt_explicit_install (
	id              INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
	agent_id        INTEGER NOT NULL,
	name            TEXT NOT NULL DEFAULT '',
	installed_dt    INTEGER NOT NULL DEFAULT 0
);
-- UNIQUE (agent_id, name). First installed_dt wins. No deleted_dt tombstone.
CREATE UNIQUE INDEX IF NOT EXISTS apt_explicit_install_agent_name
ON apt_explicit_install (agent_id, name);
```

#### Add — shared row (`shared/OSQuery/AptExplicitInstall.vala`)

```vala
public class AptExplicitInstall : Row {
	public string name { get; set; default = ""; }
	/** Unix time from the stanza Start-Date. 0 means unset. */
	public int installed_dt { get; set; default = 0; }
	public override bool sync (...) {
		// Insert-only. A name already stored for this agent is left
		// alone (first installed_dt stays). Rows not in this batch stay.
		// Do not call sync_rows.
	}
}
```

#### Add — agent (`agent/linux/Apt/History.vala`)

- Watermark file under the agent data dir: one unix time, “nothing after this date.” The process keeps that value in **`cached`** and reads the file only when **`cached`** is unset.
- Empty watermark: **`archive`** reads **`history.log.*.gz`** oldest first, then **`history.log`**.
- A stored watermark checks **`history.log`** mtime. Not newer than the watermark: return. Newer: read only **`history.log`**.
- **`read`** — one stream. The watermark, the name map, and the latest **`End-Date`** stay on the object. For each new **`Commandline:`** install, collect target names and the stanza **`Start-Date`** (parsed as local time → **`installed_dt`**). Tokenize after **`install`**; stop at **`=`**; skip tokens starting with **`-`**.
- Send only those new names. After the server accepts the batch (or the batch was empty), write the watermark to the latest **`End-Date`** consumed. A failed send leaves the watermark where it was, so the same new names are tried again; the unique index drops a duplicate if a previous attempt had already landed.
- If one pass sees the same name twice, the earlier **`installed_dt`** is the one sent.

#### Draft mapping (chat prototype → Argus)

| Draft idea | Argus v1 |
|------------|----------|
| Local **`explicit_installs(pkg_id)`** + **`packages`** table | Server **`apt_explicit_install(agent_id, name, installed_dt)`** |
| Shared **`pkg_cache`** with catalog | **No** — names align with **`deb_packages.name`** only |
| Agent **`Sqlite.Database`** ingest | Agent parses logs; server **insert-only** (not **`sync_rows`**) |
| Full set every sync | Delta after the watermark date |
| **`zcat`** pipe | **`Gio`** read of **`.gz`** |

---

### Slice F — attribution queries

**Repos on this machine**

- 🔷 `apt_sources` ⋈ `apt_url` **ON `url_key`** WHERE `agent_id = ?` AND `apt_sources.deleted_dt = 0`.

**Explicit vs dependency (hint)**

- 🔷 **`deb_packages`** LEFT JOIN **`apt_explicit_install`** ON `agent_id` AND `name` WHERE `deleted_dt = 0` on both sides.
- 🔷 Installed + row in **`apt_explicit_install`** → treat as **explicit**. **`installed_dt`** is the first retained **`Start-Date`**, not the server insert time.
- 🔷 Installed + no row → **dependency hint** (not proof — pre-agent installs and missed log lines exist).
- 🚫 No **`apt_url_agent`**.

---

### Slice G — controller / RPC

- 🔷 **`AptCatalog.*`** in **`docs/rpc-commands.md`** — depends closure, remove preview.
- 🔷 Debian software UI: explicit/dependency column when Slice F queries exist.
- 🚫 Header bar controls — page toolbar only.
- ℹ️ **`|`** depends alternatives — phase 1 import skips clauses; preview stays conservative.

---

## Next

- 🔷 User confirms Slice **E** (table name, **`installed_dt`**, insert-only sync, date watermark) before implementation.
- 🔷 Then land **`agent/linux/Apt/`** + server table + one offline parse test (fixture **`history.log`** snippet, no network).

---

## Attempts / changelog

- ✔️ 2026-11-16: Closed bridge A–D — [done/2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md](done/2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md).
- ✔️ 2026-11-16: Slice E — **apt history** chosen; draft Vala/SQL reframed for **`agent/linux/Apt/`** + **`apt_explicit_install`** (not local agent **`packages`** / **`pkg_id`**).
- ✔️ 2026-11-16: **`Start-Date`** is present on every install stanza in this machine’s apt history (68/68). Sync is a date watermark plus insert-only rows, not a **`sync_rows`** snapshot.

---

## LLM notes

- 🚫 No `apt_url_agent`.
- ℹ️ Catalog graph remains **`apt_pkg`** / **`apt_pkg_depends`**; explicit installs are **per-agent facts**, separate concern.