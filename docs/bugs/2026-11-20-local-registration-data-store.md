# Local registration data — shared interface + SQLite (agent + controller only)

**Status:** ⏳ open — **blocks** controller link work and agent link cleanup; implement before further connection-layer migration

**Scope:** **Agent and controller client processes only** — each machine’s **local** SQLite file (and controller libsecret / Android credential files) that remembers *which management server this client is registered to* and holds TLS material for the management link. **Not in scope:** `argusrm-server`, its `server/` SQLite (`agent`, `agent_pending`, tasks, osquery, …), `server/Registration.vala`, firewall/allowlist, or any server-side registration RPC behaviour beyond unchanged wire types (`Registration.Data` over RPC).

**Pointer:** `docs/bug-fix-process.md`, [2.6.1-management-client-link-spec.md](../plans/2.6.1-management-client-link-spec.md) (**§ Names**, **§ State `checking_config`**), [2.6-management-connection.md](../plans/2.6-management-connection.md), [`shared/Registration/Data.vala`](../../shared/Registration/Data.vala), [`shared/Register.vala`](../../shared/Register.vala), [`controller/Connection.vala`](../../controller/Connection.vala), [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala), [`agent/Connection.vala`](../../agent/Connection.vala)

**Related:** [2026-11-19-management-link-application-migration.md](2026-11-19-management-link-application-migration.md) (call-site migration **after** this store exists), [done/5.2-DONE-controller-user-registration.md](../plans/done/5.2-DONE-controller-user-registration.md) (legacy `connections.json` + keyring design)

---

## Problem

- 🔷 **Saved management-server registration** (address, port, TLS material, download hints) is implemented three different ways. Agent, controller, and the live **link** classes each read, validate, or erase that data themselves.
- 🔷 **Expected:** **`Argus.Shared.SQT.Server`** = row + `init_db` + `query` only (shared schema). **`Argus.Controller.Store.Servers`** = controller-only store surface (same split as `SQT.Task` vs `Controller.Store.Pairing`). **🚫 No store in `shared/Registration/`** — the agent does **not** use `Controller.Store.Servers`; agent persistence is a separate follow-up (single row / own local DB + `SQT.Server`). Controller link, Bootstrap, and Settings call **`Controller.Store.Servers`** only. The **management server** is unchanged.
- 🔷 **Actual:**
  - **Agent** — flat files under `Application.data_dir` (`server`, `client.pem`, `ollmrpc-ca.pem`, …) written by `Register.try_connection`; read and existence-checked in `agent/Connection.vala` `on_checking_config()`; **`enter_dead(..., wipe_registration: true)`** removes PEMs when hello returns `CERT_NOT_REGISTERED`.
  - **Controller** — non-secret rows in `~/.config/argusrm/connections.json` as `Argus.Controller.Connection`; PEM triple in libsecret (JSON `Registration.Data`) or Android `credentials/<name>.json`; load/save/clear spread across `Bootstrap.check()`, `finish_registration()`, and `Registration.Data.clear_saved_login()`.
  - **`Registration.Data`** — overloaded: RPC wire type, secret blob, and deregister UI + file/keyring I/O; field overlap with `Controller.Connection` (name, addresses, port).
- 🔷 Finishing **controller `Connection` link** (spec X1) or agent **Application** migration without this store will duplicate config logic again or leave Bootstrap and `agent/Connection` as the source of truth for validation.

---

## Evidence (current tree)

### Shared registration types (client scope)

- ✔️ [`shared/Registration/Data.vala`](../../shared/Registration/Data.vala) — properties: `error`, PEM strings, `name`, `addresses`, `port`; `deregister()`, `clear_saved_login()` rewrites `connections.json` and clears libsecret / Android credential files.
- ✔️ [`controller/Connection.vala`](../../controller/Connection.vala) — JSON-serializable row only (name, addresses, port); no certs.

### Server (reference only — not this bug)

- ℹ️ [`server/RegistrationData.vala`](../../server/RegistrationData.vala) — RPC reply type for local controller certificate issue; **unchanged** by this work.
- 🚫 No edits under `server/` for client registration storage.

### Agent persistence and link

- ✔️ [`shared/Register.vala`](../../shared/Register.vala) — on success writes `client.pem`, `ollmrpc-ca.pem`, `server`, `download`, `download-path` under `data_dir`; single-server file layout.
- ✔️ [`agent/Connection.vala`](../../agent/Connection.vala) — `on_checking_config()` reads `server` file, checks three PEM paths, sets `attempt_host` / `attempt_port`; `on_connection_check()` runs hello + version compare; `enter_dead` optionally deletes registration files.
- ✔️ [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala) — builds `Registration.Data` from agent files for controller remote registration hand-off.

### Controller persistence and connect

- ✔️ [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) — `check()` loads `connections.json`, joins libsecret / Android credentials into `credentials` map; `finish_registration()` writes JSON array + secret; `use()` builds TLS from memory and opens `OLLMrpc.Client` (no link class).
- ✔️ [`controller/Window.vala`](../../controller/Window.vala) — reconnect loop polls `app.rpc.connected` and calls `rpc.connect` + hello (pre–2.6.1 link shape).

### SQLite pattern (client vs server)

- ℹ️ [`shared/SQT/Task.vala`](../../shared/SQT/Task.vala) — same **class pattern** for a new **client-only** table; `init_db` runs against a **separate file** on the agent/controller machine, not against the management server’s Argus database.
- ✔️ Management **server** already uses `shared/SQT` inside `server/Application.vala` — **out of scope** here.
- ✔️ [`shared/SQT/Server.vala`](../../shared/SQT/Server.vala) — client-local `server` table row; **not** in `Argus.Shared.SQT.init_db` (management server DB unchanged).
- 🚫 `Controller.Store.Servers` not in tree yet.

---

## Root cause

- ✔️ Registration storage grew per platform (agent files from Filesd-era `Register`; controller 5.2 split JSON + keyring) without a shared **local** persistence layer.
- ✔️ `Registration.Data` became the catch-all DTO plus I/O, so connection code inlined **validation** and **lifecycle** (wipe on reject) instead of delegating to a store.
- 💩 Controller multi-server vs agent single-server was never modeled in one schema; file layout masked that until link spec `checking_config` needed a single answer: “what is the active server material?”
- 💩 Connection code is split: **`agent/Connection`** vs controller **`Bootstrap.use()`** + **`Window.check_connection()`** — no shared link type that both compile against the same registration API.

---

## R1 — Plan (pending approval)

Names below are **proposed** for sign-off before any link or store implementation.

**Split (agreed direction):**

- **`SQT.Server`** — row fields, **`socket(index)`** → **`GLib.InetSocketAddress`**, plus **TLS material** API on the row (TBD; not a custom “attempt” type).
- **`Controller.Store.Servers`** — SQLite file, queries, active row, save/remove secrets — **not** host/port/PEM getters for the link.

### Types and ownership

| Name | Location | What it is |
| --- | --- | --- |
| `Argus.Shared.SQT.Server` | `shared/SQT/Server.vala` | SQLite **row** + **`socket(index)`** → `GLib.InetSocketAddress`. **✔️** columns/`init_db` in tree; **⏳** methods after approval. |
| `Argus.Controller.Store.Servers` | `controller/store/Servers.vala` | Controller **store** only: DB, list/save/remove rows, load secrets onto a row — **no** `connect_*` / TLS getters. |
| `Argus.Shared.Registration.Data` | `shared/Registration/Data.vala` | RPC / registration-flow DTO only; not the persistence API. |
| Agent registration access | TBD (e.g. `agent/…`) | Single-server read/write; **same row type**, **not** `Controller.Store.Servers`. |

### Client database path

| Client | Proposed path | Notes |
| --- | --- | --- |
| Controller | `$(XDG_CONFIG_HOME)/argusrm/servers.sqlite` | Opens in `Store.Servers`; calls `SQT.Server.init_db`. |
| Agent | TBD | Same table shape; different path (e.g. under `Application.data_dir`). |

### Secrets (not in SQLite)

| Platform | Where PEMs live | Lookup key |
| --- | --- | --- |
| Linux controller | libsecret schema `org.roojs.ArgusController` | `name` (+ CA fingerprint attribute as today) |
| Android controller | `$(XDG_CONFIG_HOME)/argusrm/credentials/<name>.json` | `name` |
| Agent | TBD in R1 agent row | Likely files or agent-local secret; **not** controller store |

### `server` table columns (implemented)

| Column | What it stores |
| --- | --- |
| `id` | Row id. |
| `name` | Server label; secret lookup key. |
| `port` | Management app TLS port. |
| `addresses` | Listen hosts to try, one per line. |
| `last_host` | Host that last answered a probe (Bootstrap), or empty. |
| `download` | Agent download socket `host:port`. |
| `download_path` | Download path from registration. |
| `is_active` | Controller: which row is selected for the live link. |
| `added_dt`, `updated_dt`, `deleted_dt` | Audit via `init_db_audit`. |

### `SQT.Server` — row helpers (proposed)

| Name | Kind | What it does |
| --- | --- | --- |
| `address_list` | property (✔️) | Host strings parsed from `addresses`; loop with `i < row.address_list.length`. |
| `socket` | method `(int index)` | Returns **`GLib.InetSocketAddress`** for `address_list[index]` and row **`port`**. This is the **GIO socket endpoint** to dial — not a connection, not an Argus type. **Throws** if index invalid or `port` unset. |
| `clear_registration` | method | Drop stored credentials for this row after server rejects cert. |

- 🔷 **Construction:** e.g. `new GLib.InetSocketAddress(address_list[index], (uint16) port)` — same pattern as [`server/tests/rdp-start.vala`](../../server/tests/rdp-start.vala), [`controller/Rdp/Viewer.vala`](../../controller/Rdp/Viewer.vala).
- 🔷 **TLS identity** (client cert, CA) stays on the **`Server` row** / platform subclass — **separate** from `socket`; the link passes address + row material into `OLLMrpc.Transport.TlsClient` (or `Client`) in `connecting` / `connection_check` — **method names TBD in R1**.
- 🚫 **No** custom wrapper types (`Attempt`, `Session`, …).
- 🚫 **`connect_host` / `connect_port` on the store** — rejected.

### `socket(index)` — return type (fixed)

| | |
| --- | --- |
| **Returns** | `GLib.InetSocketAddress` |
| **Contains** | IP or hostname + TCP port for the **management app socket** (not TLS yet). |
| **Used for** | `Gio.SocketClient.connect_async`, or host/port passed to `OLLMrpc.Transport.TlsClient` as today. |

**Lifecycle (link) — address loop only:**

```
for (i = 0; i < row.address_list.length; i++) {
    var where = row.socket(i);   // GLib.InetSocketAddress
    // connecting: TlsClient from where + TLS material from this Server row
    // on failure try i + 1
}
```

- 💩 **TLS on row:** how the link gets `GLib.TlsCertificate` / trust for that row after `checking_config` — next R1 bullet (subclass methods on `Server`, not a second custom type).

### `Controller.Store.Servers` — proposed methods (persistence only)

| Method | What it does | Typical caller |
| --- | --- | --- |
| `open` | Open/create client DB; run `SQT.Server.init_db`. | Bootstrap, Settings, app startup |
| `list` | All non-deleted `SQT.Server` rows. | Bootstrap choose-server, Settings |
| `get` | One row by `name` (secrets on row for TLS — **how** TBD). | Settings, switch server |
| `active` | Row with `is_active` (secrets loaded). | Link picks registration |
| `set_active` | Mark one `name` active; clear others. | User picks server |
| `save` | Upsert row + write secrets. | Registration finish |
| `remove` | Delete row + clear secrets. | Deregister locally |

- 🚫 **No** `ready`, `clear`, `tls_*`, `connect_*` on the store — link uses **`SQT.Server`** after the store returns a row.

### Management link — what `checking_config` / `connecting` use (controller)

| Step | Uses (proposed) |
| --- | --- |
| Pick row | `Store.Servers.active` → `SQT.Server` |
| Validate row fields + secrets | Row + secrets present before dial (**API TBD**) |
| Try each host | `for (i …)` → `where = row.socket(i)` → TLS dial + hello |
| Endpoint | **`GLib.InetSocketAddress`** from row — not store methods |
| Server rejected cert | `row.clear_registration()` |

### Agent (not `Controller.Store.Servers`)

| Need | Owner |
| --- | --- |
| Load one row + secrets | Agent-local DB access TBD |
| Open TLS / retry hosts | Same **`SQT.Server.socket(index)`** + row TLS material |

### Open decisions (need yes/no)

| # | Question |
| --- | --- |
| 1 | Controller DB path: `servers.sqlite` under `argusrm` config — OK? |
| 2 | `socket(index)` only uses `address_list`, or index `0` is `last_host` when set? |
| 3 | TLS material API on **`Server`** (subclass): method names to feed `TlsClient` / `Client` — specify next. |
| 4 | Store `get` / `active`: plain row vs subclass with secrets — which? |
| 5 | Agent DB path and how agent loads secrets onto `Server`? |

---

## Target architecture

**`SQT.Server`** holds row data **and** `socket(index)` for the link. **`Controller.Store.Servers`** holds DB + CRUD only — see **R1** tables.

### `Argus.Shared.SQT.Server` (✔️ schema in tree)

- 🔷 Columns, `query`, `init_db`, `address_list` — **✔️**.
- ⏳ **`socket(index)`**, **`clear_registration`**, TLS helpers on row — **R1**; not on the store. Loop **`address_list.length`**.
- 🔷 **`Argus.Shared.SQT.init_db`** does **not** call `Server.init_db`.

### `Argus.Controller.Store.Servers` (controller only)

- 🔷 Persistence API only — **R1** store table.
- 🔷 Link gets a **`SQT.Server`** from `active` / `get`, then **`socket(i)`** for each try.
- 🚫 Agent does not use this store.

### Agent (separate from controller store)

- 🔷 **One** management server per machine; may use the same **`SQT.Server`** row type against an **agent-local** DB path (R1 path TBD) with thin agent-side read/write — **not** `Controller.Store.Servers`.
- 🔷 Agent **`Connection`** / **`Register`** cutover tracked after controller store (R4–R6).

### Client DB (behind the store)

- 🔷 Paths and columns — **R1 — Plan** tables.
- 🔷 **No migration** — greenfield cutover only.

- 💩 Optional later: **shared management link class** in `shared/` (spec X1). Minimum here: **`Controller.Store.Servers`** + thin controller link.

### Slim `Registration.Data`

- 🔷 **Keep** — RPC / registration-flow DTO (`RegisterWindow.issued`, CLI JSON). Controller persists via **`Controller.Store.Servers.save()`** after registration.
- 🔷 **Move to store** — `clear_saved_login()` → `Servers.remove(name)` on the **controller** store.
- 🔷 **Keep or colocate** — `deregister()` server RPC + dialog flow; calls `remove` after server answers.

### Retire controller-only row type

- 🔷 **`Argus.Controller.Connection`** and **`connections.json`** — replace with **`SQT.Server`** + **`Controller.Store.Servers`**.

### Link layer (`checking_config`)

- 🔷 **Controller** — **R1** table *Management link — what checking_config needs*.
- 🔷 **Agent** — parallel table under R1; separate owner.
- 🔷 **Policy** — `CERT_NOT_REGISTERED` → `Store.Servers.clear`; link does not delete PEM files itself.

### Legacy layout (remove, do not import)

- 🔷 **Drop** agent flat-file registration layout (`server`, `client.pem`, … as the source of truth) and controller **`connections.json`** persistence once the store is wired — delete the writers and readers, not a one-time importer.
- 💩 If `OLLMrpc.Transport.Cert` still needs paths on disk, the store may **export** PEMs when opening a link; that is runtime materialization, not a second canonical store.

---

## Proposed work (ordered)

| ID | Item | Provenance |
| --- | --- | --- |
| R1 | ⏳ Approve **§ R1 — Plan** tables (paths, store methods, link steps, open decisions) | 🔷 user |
| R2 | ✔️ `shared/SQT/Server` (row + `init_db` + `query` only; no link virtuals until R1) | 🔷 user |
| R3 | ⏳ `controller/store/Servers` — DB open, CRUD, load secrets onto row (persistence only) | 🔷 user |
| R4 | ⏳ Agent: `Register` / link → agent-local `SQT.Server` (not controller store) | ⏳ after R1 path |
| R5 | ⏳ Controller: Bootstrap / Settings / deregister → `Store.Servers`; drop `Connection` + `connections.json` | ⏳ after R3 |
| R6 | ⏳ Agent `Connection` `checking_config` → agent registration data API | ⏳ after R4 |
| R7 | ⏳ Controller link + Bootstrap → `Store.Servers`; retire `Window.check_connection` inline TLS | ℹ️ [management-link migration](2026-11-19-management-link-application-migration.md) X1 |
| R8 | 💩 Shared management link class in `shared/` (optional consolidation with agent `Connection`) | 💩 after R6–R7 |

---

## Out of scope (this bug)

- 🚫 **`argusrm-server` entirely** — `server/Application.vala`, `server/Agent.vala`, `server/Net/*`, management server SQLite, `agent` / `agent_pending` / allowlist / pairing windows on the server.
- 🚫 **`server/Registration.vala`**, local `pkexec` certificate issue on the server host (server behaviour stays as today; clients only change **where they save** after RPC).
- 🚫 Redesigning agent `Connection` state machine enum or scheduler (stable per migration log).
- 🚫 **Import/migration** from `connections.json` or legacy agent certificate files (greenfield cutover only).
- 🚫 RDP second socket / `stream_connection()` (separate bugs).

---

## Conclusions

- **Root issue** is fragmented **local registration persistence**, **no shared interface for link code**, and **controller-specific** connection/bootstrap paths — not the TLS state machine enum.
- **Do not** put **`socket`** or TLS helpers on **`Controller.Store.Servers`** — they belong on **`SQT.Server`**.
- **Do not** add catalog methods (`list`, `save`, …) on the row — those stay on the store.
- **Do not** put **`Controller.Store.Servers`** in the agent binary or `shared/` registration namespace.
- **Do not** conflate client registration SQLite with the management server database — two different files on two different roles.

---

## Next steps

1. Approve or edit **§ R1 — Plan** (names, tables, open decisions).
2. Implement **`Controller.Store.Servers`** (R3) per approved table.
3. Wire controller Bootstrap/Settings (R5), then controller link (R7).
4. Agent local `SQT.Server` usage (R4–R6) — separate from controller store.
5. Resume [management-link application migration](2026-11-19-management-link-application-migration.md) after controller store + link.

---

## Attempts / changelog

- ✔️ 2026-11-20 — Log opened from controller/agent registration storage review; no product code changes yet.
- ✔️ 2026-11-20 — User: **no migration path** — greenfield SQLite store; re-register after cutover; remove `connections.json` / file layout without import.
- ✔️ 2026-11-20 — User: **agent + controller only** — not management server registration or server SQLite.
- ✔️ 2026-11-20 — User: **`shared/` owns the store interface** — link/connection code uses registration data through that API; controller generic (multi-server, flip active); same connection pattern as agent.
- ✔️ 2026-11-20 — User: **SQT row vs store** — `SQT.Server` is row/query/`init_db` only; store is **`Controller.Store.Servers`** (not in `shared/`); **agent does not use controller store**.
- ✔️ 2026-11-20 — **`shared/SQT/Server.vala`** added; `meson.build` + valadoc list; builds into `libargus-shared*`.
- ✔️ 2026-11-20 — Virtual TLS/credential placeholders on `SQT.Server`; rejected separate `Registration.Access` type.
- ✔️ 2026-11-20 — Removed premature link API on `SQT.Server` (`dial_host`, `dial_port`, PEM virtuals, …); **R1 plan** before any connection-facing methods.
- ✔️ 2026-11-20 — **§ R1 — Plan** added: tables for types, paths, columns, store vs row split, link steps, open decisions.
- ✔️ 2026-11-20 — R1 corrected: **`connection(index)`** on **`SQT.Server`**; removed **`connect_host` / `connect_port` / tls_*** from store; use **`address_list.length`**, not a separate length property.
- ✔️ 2026-11-20 — R1: dropped **`Server.Attempt`**; **`socket(index)`** → **`GLib.InetSocketAddress`**; TLS from row API TBD.
- ✔️ 2026-11-20 — R1: method name **`socket(index)`** (not `connection` / `socket_address`).