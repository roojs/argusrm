# Debian package catalog: install log, attribution, controller (phase 2 product)

**Status:** ✅ closed 2026-11-17 — Slices **E** and **F** are in the tree. Install and remove preview is 2026-11-17-FIXED-debian-install-remove-preview.md.

**Pointer:** `docs/bug-fix-process.md`, [5.9.2.1](../../plans/done/5.9.2.1-DONE-debian-filters-phase1.md), [5.5](../../plans/5.5-controller-user-interface.md), [rpc-commands.md](../../rpc-commands.md), [`agent/linux/PackageMonitor.vala`](../../../agent/linux/PackageMonitor.vala)

---

## Problem

- 🔷 Catalog + **`apt_sources`** bridge are in tree; the **product** still lacks install reasoning, queryable attribution, and Debian UI that uses the dependency graph.
- 🔷 **Expected:** apt history hints → server **`apt_explicit_install`** → attribution joins → controller RPC/UI.
- ✅ **Resolved:** Slice **E** posts explicit install names. Slice **F** is the Filters menu, the Leaf column, and the underline on an explicit name. Install and remove preview left this bug.

---

## Suggested order

1. ✔️ **Slice E** — apt history → explicit install names on server. Runs at startup and on the dpkg package-change trigger.
2. ✔️ **Slice F** — explicit and leaf flags, the Filters menu, and the Leaf column on both Debian lists.
3. ➡️ **Slice G** — moved to 2026-11-17-FIXED-debian-install-remove-preview.md.

---

### Slice E — apt history (explicit installs)

#### Decisions

- ✅ **Log source:** **`/var/log/apt/history.log`** and rotated **`history.log.*.gz`** under **`/var/log/apt/`** — not **`dpkg.log`**.
- 🔷 **Agent code:** new directory **`agent/linux/Apt/`** (e.g. `History.vala`, wired from Linux `Application` / service startup beside **`PackageMonitor`**).
- 🔷 **Semantics (v1):** one row per binary package name that appeared on an **`apt install`** (or `apt-get install`) **Commandline:** line, with the transaction **`Start-Date`** beside it. Not a full event timeline. A later install of the same name is not a second row.
- 🔷 **Server:** per-agent rows keyed by **`name`** (matches **`deb_packages.name`**) plus **`installed_dt`**. Not a local agent SQLite **`packages`** table and not **`apt_pkg`** catalog ids.
- 🔷 **Sync is incremental.** Unlike **`sync_rows`**, the agent sends only names whose stanza **`Start-Date`** is after the local watermark. The server inserts those names and does not tombstone rows missing from the batch. **`sync_rows`** would delete every earlier explicit install the moment the batch is a delta.
- 🔷 **Watermark:** one unix time in the agent data dir — “nothing after this date.” It is the latest **`End-Date`** of a complete stanza already accepted (sent, or a pass with nothing new). A stanza with no **`End-Date`** yet is left for the next pass, and the watermark does not move past it. Failed send does not move the watermark.
- ✅ **Schedule:** two calls. **`Execute.send_startup`** calls **`Apt.History.send`** after the package snapshot on an APT host. **`PackageMonitor.apt`** calls **`Apt.History.send`** after **`send_packages`**, once the dpkg locks are free.
- 🚫 No daily timer. No **`FileMonitor`** on **`history.log`**. The dpkg watch is the change trigger.
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

### Slice F — explicit and leaf on both Debian lists

Same control on the fleet Software grid (`controller/tab/Asset/DebPackages.vala`) and the machine Software grid (`controller/tab/Asset/Machine/DebPackages.vala`). History can miss installs, so a leaf (nothing installed depends on it) is the second hint that a person installed the package.

#### Decisions

- ✅ **Drop the Section menu.** That is the category list on the fleet grid. It goes. Search and **Versions differ** stay on the fleet grid.
- ✅ **Filters** menu in its place. The label is **Filters**, not Status. A `MenuButton` opens a menu of tick boxes, the same pattern as the Section menu today.
- ✅ **Ticks, all on by default:**
  - **Explicitly installed**
  - **Top level packages (leaf)**
  - **Update pending**
- ✅ **Each tick adds rows.** A row stays when it matches any tick that is on. **Update pending** is its own tick, so a package with an update stays in the default list whether or not it is a leaf or an explicit install.
- ✅ **An off tick does not hide a row.** Unticking **Update pending** drops a package only when that was the only tick keeping it. A leaf that also needs an update stays while **Top level packages (leaf)** is on. The same for **Explicitly installed**.
- ✅ **All ticks off** shows every installed package. Nothing is being excluded.
- ✅ **Leaf column** on both grids. Header text is **Leaf**. A leaf row shows a leaf icon in the cell. Other rows leave the cell empty. The icon's tooltip says this is a top-level package: nothing installed depends on it.
- ✅ **Explicit is an underline on the package name.** Both grids. When `explicit` is set, the Name label is underlined. The tooltip on that name says it was explicitly installed. A row can be underlined and show the leaf icon. This is the first mark to try. No separate Explicit column.
- ✅ The tick label is **Top level packages (leaf)**. The column header stays **Leaf**. The word in brackets ties the tick to that column.
- ✅ The Section **column** stays on both grids. Only the Section menu goes. That menu was the pointless part.
- 🔷 The machine grid has no filter bar today. It gains the Filters menu only. It does not gain search or **Versions differ**.
- ✅ **Update pending** uses the existing `update_since`. The tick is on when `update_since` is greater than zero, the same fact as the **Update waiting** column. That column stays a date. It is not the new version. `package_updates` stores `name` and `since` only.
- ℹ️ The red background with white text is `label.version-spread` on the fleet **Max version** cell, when that text differs from **Min version**. The machine **Version** cell is plain text. It does not turn red when an update is waiting.
- 💩 Still missing on the machine grid: the candidate version, and the red version cell when an update is waiting. That is separate from the Filters menu.
- 🚫 Header bar controls. The menu sits on the page toolbar, as the Section menu does now.

#### Flags (`DebPackages.list`)

Not stored on `deb_packages`. `list` fills them. The filter, the Name underline, and the Leaf cell read the same values.

- 🔷 **`explicit`** — `1` when this installed name has a row in `apt_explicit_install` for that `agent_id`. `installed_dt` stays the first retained `Start-Date`.
- 🔷 **`leaf`** — `1` when the name is installed on that machine and no other package installed on that machine depends on it.
- ℹ️ **Update pending** is not a new flag. `list` already fills `update_since` from `package_updates`. Greater than zero means pending.
- ℹ️ A name with no `apt_pkg` row (local `.deb`, unknown to the catalog) has no incoming edge, so it is a leaf.
- ℹ️ Edges are the catalog **Depends** and **Pre-Depends** only. Recommends are not edges. A `|` alternative that phase 1 skipped can make a package look like a leaf.
- 🚫 No `apt_url_agent`. The machine's repos are `apt_sources_catalog` joined to `apt_url` on `url_key`.

**Leaf, one machine.** A row in this query means the name is not a leaf:

```sql
SELECT
	parent.name
FROM
	deb_packages AS installed
JOIN
	apt_pkg AS child
ON
	child.name = installed.name
JOIN
	apt_pkg_depends
ON
	apt_pkg_depends.depends_pkg_id = child.id
JOIN
	apt_pkg AS parent
ON
	parent.id = apt_pkg_depends.pkg_id
JOIN
	deb_packages AS needed
ON
	needed.agent_id = installed.agent_id
AND
	needed.name = parent.name
AND
	needed.deleted_dt = 0
JOIN
	apt_url
ON
	apt_url.id = apt_pkg_depends.apt_url_id
JOIN
	apt_sources_catalog
ON
	apt_sources_catalog.agent_id = installed.agent_id
AND
	apt_sources_catalog.url_key = apt_url.url_key
WHERE
	installed.agent_id = ?
AND
	installed.name = ?
AND
	installed.deleted_dt = 0
```

#### Fleet grid (`agent_id = 0`)

One row per name. The flags have to collapse across machines.

- 💩 **`explicit` is 1** when any machine that still has the package installed has an `apt_explicit_install` row for that name.
- 💩 **`leaf` is 1** when any of those machines has it as a leaf. The fleet tooltip says top level on at least one machine.
- ℹ️ **Update pending** on the fleet grid is already any machine: `list` sets `update_since` from the earliest `package_updates.since` for that name.
- 💩 Confirm **any machine** before building. **Every machine** would hide a package that is a leaf on one host and a dependency on another.

#### Controller

- 🔷 `Filters.DebPackages`: drop `sections` / `section_count`. Add `explicit`, `leaf`, and `update_pending`, all default true. `match` keeps a row when every tick is off, or when a tick that is on hits that fact on the row. An off tick is not a reason to drop the row. Update pending hits `update_since` greater than zero. Search and spread stay.
- 🔷 Both pages build the Filters menu from those three properties. Unticking one refilters. The fleet page removes `build_sections` and the Section `MenuButton`.
- 🔷 Column `Leaf,leaf,ON` in both column csv files. A new cell format draws the icon from the bool and sets the tooltip. The icon name is not chosen yet. Adwaita has no leaf symbolic.
- 🔷 The Name cell is the existing text label. When `explicit` is set, that label uses a single underline and the tooltip **Explicitly installed**. The Name column stays `name`.

---

### Slice G — moved

- ➡️ Install preview, remove preview, and the dependency tree RPC are 2026-11-17-FIXED-debian-install-remove-preview.md.

---

## Follow-on

- ⏳ 2026-11-17-FIXED-debian-install-remove-preview.md — approve the dependency list before a Debian install or remove.
- ℹ️ The machine grid still does not show the candidate version, and the machine **Version** cell does not turn red when an update is waiting. That was left out of this bug and out of the preview bug.

---

## Attempts / changelog

- ✔️ 2026-11-16: Closed bridge A–D — 2026-11-16-FIXED-debian-apt-sources-catalog-bridge.md.
- ✔️ 2026-11-16: Slice E — **apt history** chosen; draft Vala/SQL reframed for **`agent/linux/Apt/`** + **`apt_explicit_install`** (not local agent **`packages`** / **`pkg_id`**).
- ✔️ 2026-11-16: **`Start-Date`** is present on every install stanza in this machine’s apt history (68/68). Sync is a date watermark plus insert-only rows, not a **`sync_rows`** snapshot.
- ✔️ 2026-11-16: Slice **E** landed in `d201fe4` (`agent/linux/Apt/History.vala`, `apt_explicit_install`, offline tests).
- ✔️ 2026-11-17: Schedule is startup and the dpkg package-change trigger. The daily pass and the `history.log` watch are out.
- ✔️ 2026-11-17: Slice **F** expanded. Section menu goes. Filters ticks are **Explicitly installed** and **Top level packages**, both on, union. Leaf column is an icon plus tooltip. Flags come from `DebPackages.list`.
- ✔️ 2026-11-17: Explicit installs underline the package name. Tooltip says explicitly installed. No Explicit column. First mark to try.
- ✔️ 2026-11-17: The top-level tick is labeled **Top level packages (leaf)**. The column header stays **Leaf**.
- ✔️ 2026-11-17: Section column stays. Machine **Update waiting** is a date, not the new version. The red version pill is fleet **Max version** when it differs from **Min version**.
- ✔️ 2026-11-17: **Update pending** is a third Filters tick, on by default. It adds rows on its own, including packages that are not leaves. It reads `update_since`.
- ✔️ 2026-11-17: Ticks only add. Unticking one hides a package only when no other tick still matches it. All off shows every installed package.
- ✔️ 2026-11-17: Slice **F** written. Filters is a menu of boolean actions. Leaf uses `leaf-symbolic`. Fleet explicit and leaf are true when any machine says so. Closed. Slice **G** moved out.

---

## LLM notes

- 🚫 No `apt_url_agent`.
- ℹ️ Catalog graph remains **`apt_pkg`** / **`apt_pkg_depends`**; explicit installs are **per-agent facts**, separate concern.