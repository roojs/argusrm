# Windows Software fleet — installed vs inventory noise

**Status:** ⏳

**Pointer:** [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala), `docs/bug-fix-process.md`, external corpus **CIRCL hashlookup** (`https://hashlookup.circl.lu`, bulk `/bulk/sha256`, Bloom filters).

---

### User decisions required

- ✔️ **Corpus:** CIRCL Hashlookup for post-hoc SHA256 lookups (not inventing a private hash DB first).
- ✔️ **System isolation:** match **code-signing identity** (verifiable id), not registry `publisher` string — build an ignore set of **trusted OS signer ids**; rows stay in DB, default UI hides them.
- ✔️ **Order:** (1) extract+log signing on binaries, (2) collect SHA256 + CIRCL lookup, (3) signer ignore set validated on real fleet before UI filter.
- ✔️ **Publisher (human review):** keep registry `publisher` where present; also store **signer display name** from Authenticode (`subject_name` / cert CN) — not used for ignore rules.
- ✔️ **Agent cache:** SQLite on the agent so PE hash + signing metadata is not recomputed every `Programs.send()` (invalidate on path + size + mtime).
- ✔️ **Certification / trust layer:** **server-only** — no further agent product code for this bug. Agents ship facts (`file_sha256`, `signing_result`, `signer_cert_sha256`, `signer_publisher`, registry `publisher`); server stores, dedupes, and applies rules. Clients do **not** re-run Authenticode on every sync or on server request; only refresh when `(size, mtime)` changes (agent `win_file_identity`).
- ✔️ **Server reference table:** `hashlookup` keyed by `file_sha256`; CIRCL Hashlookup enrichment async (~1 request / 30s). **`system_confidence`:** 0 unknown, 5 possible system library, 10 confirmed; **`user_determined`** bypasses auto scoring.
- ⏳ **Service rows in `Programs`:** keep in snapshot for now; fleet default view should not treat them as “installed apps” (signer/path-led). Revisit dropping or moving `service` out of this union separately if still pointless after tagging.

### User reported

- 🔷 Fleet **Software → Windows** is huge; many rows are not user-installed apps (`service` / `startup` / path-backed noise).
- 🔷 Registry **publisher** is not enough to prove “Microsoft OS binary”.
- 🔷 Want **hash + signature** pipeline; separate from grid load (2026-11-23-ISSUE-programs-fleet-grid-slow parked).

### Success scenario

- Default fleet grid emphasizes **installed application** rows (plan 5.9 intent).
- **System / in-box Microsoft-signed** binaries: stored, tagged, **hidden by default** (filter or scope), not deleted.
- Unknown or third-party signed rows remain visible; CIRCL enriches known software where hash hits.
- Logs and DB carry **verifiable** signer ids plus SHA256 for audit and filter rules.

### Current behavior

- Per-machine `programs` by `source` (sample DB 2026-11-23): `service` 641, `programs` 233, `appx` 127, `startup` 12 → **949** fleet names.
- [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala) `snapshot_sql()` unions registry, appx, chocolatey, **services** (non–System32 path), **startup**; `publisher` from registry/osquery only.
- Rows with PE paths: **`install_location`**, **`uninstall_string`**, service/startup **`path`** — no SHA256, no Authenticode fields today.
- 2026-11-21-processes-exe-enrichment.md: SHA256 + fingerprint store design for **processes** only — reuse ideas, not that table verbatim.

### Codebase observed behavior

| Area | Note |
|------|------|
| `programs` schema | `publisher`, `install_location`, `extra`; no `sha256`, no cert thumbprint |
| Path sources | `service` / `startup` → `path`; `programs` → `install_location` / parse `uninstall_string` for `.exe` |
| Agent Windows | `agent/windows/` product code; PE / FFI in top-level `win32/` (`win32.vapi`, `pe-authenticode.*`) |
| osquery `authenticode` | `subject_name`, `issuer_name`, `serial_number`, `result` — **no cert SHA256 thumbprint / SKI** |
| osquery `hash` | `sha256` per path — viable for file hash without re-reading in agent cache miss |
| Agent `client_db` | Registration (`server.sqlite`); **no PE cache table yet** |
| Controller filter | Search + Versions differ + Can uninstall — no “installed only” / signer scope |

### Debugging

#### Current debug output

```
service|641
programs|233
appx|127
startup|12
```

`/tmp/argus.sqlite.copy`, 2026-11-23.

**T1a POC** (`snappr-win` / DESKTOP-GITPJFF, 39 fleet PE paths, 2026-11-24):

```
exists=39  sha256_match_osq_ps=yes:38  subject_match yes:35 no:1
osq_result=missing:2  ps NotSigned:2  distinct signer_cert_sha256:11
```

Artifact: [`tests/poc-authenticode/compare.csv`](../../tests/poc-authenticode/compare.csv).

| Edge case | Paths |
|-----------|--------|
| Unsigned / osquery `missing` | `argus-agent.exe`, `OCSInventory-Service.exe` |
| Subject mismatch | `VBoxService.exe` — osquery `Oracle Corporation`, cert CN `Oracle America, Inc.` |
| SHA256 gap | OCS: hash via PS only (osquery auth row missing; hash may still run) |

**Microsoft Windows Production PCA 2011** cluster: `signer_cert_sha256=1308aad34660d785…` on **17** paths (candidate ignore-set seed — validate more before product).

#### Debug code added (remove when complete)

None in product. Phase 1 = throwaway only (see below).

### Proposed fix

#### 1. Snapshot (unchanged)

- Osquery union: `programs`, `appx`, `chocolatey`, `service`, `startup` → server `programs` table ([`snapshot_sql()`](../../shared/OSQuery/Programs.vala)).
- No hash/signer in SQL; enrichment after the select in agent Vala.
- Sync row key: `pkg_name()` = `source` + `name` + `identifying_number`.

```
source, name, version, publisher, architecture, scope, user_account,
install_date, install_location, identifying_number, install_source,
language, uninstall_string, extra
```

`identifying_number` by source: registry GUID (`programs`), package family (`appx`), `name@version` (`chocolatey`), SCM short name (`service`), startup `args` (`startup`).

#### 2. Service rows

- **Care about:** `install_location` → PE hash + signer.
- **Ignore for this bug:** service names for filtering; fleet grid should not treat these as installed apps.
- **Open:** keep in DB vs drop from union — separate from PE work.

#### 3. Pipeline (`Programs.send` → server → grid)

**Phase 1 — Osquery (inventory rows)**

- `Execute.init()`; skip if no `osqueryi`.
- Run `snapshot_sql()` → list of rows (all five `source` values).
- Empty snapshot guard (same as today).
- No hash or signer in this step.

**Phase 2 — Find EXE + cache gate (per unique path)**

- For each row, resolve zero or one PE path (`install_location`, uninstall `.exe`, strip service/startup command line).
- Build **one set of paths** (many rows can share one `.exe`).
- For each path:
  - `stat` file → **size** + **mtime**.
  - Look up path in agent `win_file_identity` SQLite.
  - If cached **size and mtime match** → reuse stored enrichment; **no** new checksum, **no** signature read.
  - Else → go to Phase 3 for this path only.

**Phase 3 — Full enrichment (cache miss or file changed)**

- Win32: `file_sha256`.
- Win32: Authenticode → `signer_cert_sha256`, SKI, `signer_publisher`, status.
- Write/update `win_file_identity` (path, size, mtime, all enrichment fields).
- Copy enrichment onto every row that uses that path.
- Registry `publisher` from osquery untouched.

**Phase 4 — Server update (and after)** — **certification layer lives here**

- Agent: `OSQuery.sync` enriched rows (same RPC, extra columns). **No** server callback to re-verify signatures.
- Server: upsert `programs` (inventory + agent enrichment columns on each row).
- Server: upsert **`hashlookup`** reference row per distinct `file_sha256` (fleet-wide; see workstreams B/E).
- Server: **trust rules** (centralized): combine `signer_cert_sha256` allowlist (C), `hashlookup.system_confidence`, and `user_determined`; **publisher** (registry + corpus) is a primary scoring input but not the sole proof.
- Server background: **Hashlookup** worker thread — one external query ~every 30s; never blocks sync.
- Controller: default view hides high-confidence system rows; show confidence + operator override.

#### 4. Agent classes (greenfield — **compiled, not wired**)

**Data model**

- **`Argus.Shared.OSQuery.Programs` row** (osquery + sync): carries enrichment on the **same** object as inventory fields (`file_sha256`, signer columns when added) — no separate “enrichment result” type for RPC.
- **`Argus.Agent.SQT.WinFileIdentity`**: one **SQLite row** per PE path on the agent ([`tests/win-file-identity-schema.sql`](../../tests/win-file-identity-schema.sql)); `SQ.Interface` + `init_db` — **agent-local identity**, not the sync payload.

| Piece | Location | Job |
|-------|----------|-----|
| **`ExeEnrichment`** | `agent/windows/ExeEnrichment.vala` | `locate` then `enrich`. One class. Constructor does no work. |
| **`WinFileIdentity`** | `agent/SQT/WinFileIdentity.vala` | Table ''win_file_identity'' on agent `client_db` (💩 init hook in `Application.ensure_client_db`). |
| **`WinPeAuthenticode`** | `win32/pe-authenticode.c` + `win32.vapi` (`namespace Win32`) | Authenticode read on cache miss (`win_pe_read_authenticode`). |
| **`win32/`** | `win32.vapi`, `pe-authenticode`, `register-pipe`, … | Top-level Windows FFI library (not under `agent/`). |
| **`agent/windows/`** | `Service`, `Tray`, `ExeEnrichment`, … | `namespace Argus.Agent.Windows` — Windows agent product code. |

**`Programs.send()` shape (design)**

- Phase 1: osquery → `rows`.
- Phase 2–3: `new ExeEnrichment()` then `locate(rows)` then `enrich(rows, application.client_db)`.
- Phase 4: `OSQuery.sync` with enriched **Programs** rows.

**Throwaway:** [`tests/programs-exe-pipeline-mock.vala`](../../tests/programs-exe-pipeline-mock.vala) (mock types); [`tests/programs-pe-pipeline-agent.vala`](../../tests/programs-pe-pipeline-agent.vala) compiles real agent classes on Linux.

**Wiring (2026-11-24):** `agent/windows/Programs.send` → `ExeEnrichment.locate` / `enrich` / `attach`; `WinFileIdentity.init_db` in `Application.ensure_client_db`; server `programs` table columns for enrichment fields. Linux agent compiles `agent/linux/Programs.vala` and `agent/linux/WinFileIdentity.vala`. Neither queries this table.

#### 5. Other files

- ✔️ `agent/windows/Programs.vala` — `ExeEnrichment.locate` / `enrich` / `attach` before sync. Linux uses `agent/linux/Programs.vala` and does not query this table.
- ✔️ `shared/OSQuery/Programs.vala` — enrichment columns + server `init_db` (`Programs.machines` returns them; fleet `list` aggregate unchanged).
- Server: `hashlookup` table + `Hashlookup` worker; trusted-signer list (C).
- `controller/filter/Programs.vala`; `docs/rpc-commands.md`.
- **Evidence:** `tests/programs-authenticode-compare.ps1`, `tests/poc-authenticode/compare.csv`, `tests/win-file-identity-schema.sql`.

---

#### Workstream A — Prove Win32 enrichment (throwaway → agent Phase 3) 

**Goal:** For each resolvable `.exe` (or `.dll` where needed) behind a `programs` row, record **file SHA256** and **stable signer id(s)** — not display name alone.

**Stable ids (store at least one; prefer thumbprint):**

| Field | Meaning |
|-------|---------|
| `file_sha256` | PE file hash |
| `signer_cert_sha256` | Signing certificate SHA-256 thumbprint (primary match key) |
| `signer_subject_key_id` | SKI when present (secondary) |
| `signer_issuer_serial` | Fallback if thumbprint routing needs it |
| `signing_status` | Valid / invalid / unsigned / catalog / error |

**Publisher vs ignore rules**

| Source | Use |
|--------|-----|
| Registry `publisher` (`programs` / `appx` rows) | Human review in grid; already in snapshot |
| osquery `authenticode.subject_name` | Human **signer** label when row has a PE path (services/startup often empty registry publisher) |
| Secondary Win32 (`Get-AuthenticodeSignature` / future agent Crypt32) | **`signer_cert_sha256`**, SKI, serial — **only** source for machine ignore set |

Registry and `subject_name` do not prove identity; they stay for operators. Filters use **`signer_cert_sha256`** only.

**Throwaway (prove before product):**

| Script | Role |
|--------|------|
| [`tests/programs-authenticode-export-paths.sh`](../../tests/programs-authenticode-export-paths.sh) | Paths; `--csv` adds `source`, `name`, `registry_publisher` |
| [`tests/programs-authenticode-probe.ps1`](../../tests/programs-authenticode-probe.ps1) | Secondary only: file SHA256, cert ids, `signer_publisher_cn` |
| [`tests/programs-authenticode-compare.ps1`](../../tests/programs-authenticode-compare.ps1) | **T1a:** osquery `hash` + `authenticode` vs secondary; columns `subject_match_osq_ps`, `sha256_match_osq_ps` |
| [`tests/win-file-identity-schema.sql`](../../tests/win-file-identity-schema.sql) | Agent table shape (path PK, size, mtime, hashes, signer ids, `signer_publisher`) |

```text
tests/programs-authenticode-export-paths.sh /tmp/argus.sqlite.copy 200 --csv > programs-paths.csv
# on Windows agent (osqueryi + paths):
powershell -File tests\programs-authenticode-compare.ps1 `
  -PathsFile paths.txt -RegistryCsv programs-paths.csv -OutFile compare.csv
```

- **T1a pass criteria:** `sha256_match_osq_ps=yes` for readable files; `subject_match_osq_ps` mostly yes/partial on signed EXEs; note gaps where osquery `result=missing` but PS shows Valid (catalog).
- Compare **`signer_cert_sha256`** clusters on System32-style paths vs third-party installs — draft ignore set (workstream C).

**Agent file identity (after throwaway):** 💩 separate DB under agent `data_dir`, or table `win_file_identity` in `client_db` — keyed by normalized path; refresh when `(size_bytes, mtime_unix)` differs. On hit: attach cached fields to program rows sent in sync. On miss: Win32 secondary for cert ids (required); optional osquery `hash`/`authenticode` only if throwaway shows parity and cost is acceptable. Same pattern as 2026-11-21-processes-exe-enrichment.md Windows SHA256 cache.

**Product target (after throwaway works):** enrich during agent `Programs.send()` / post-`snapshot_sql()` on Windows only; extend row schema + `OSQuery.sync` (API change — note in `docs/rpc-commands.md` when landed). Ship **`publisher`** (registry), **`signer_publisher`** (cert CN), **`signer_cert_sha256`**, **`file_sha256`** to server.

---

#### Workstream B — `hashlookup` reference table (SHA256) ⏳

**Goal:** Separate **reference** table from agent facts in `programs`. One row per distinct `file_sha256` fleet-wide; enriches from [CIRCL Hashlookup](https://hashlookup.circl.lu) out-of-band.

**Ingest (on `OSQuery.sync` `Programs`)**

- For each row with non-empty `file_sha256`: `INSERT OR IGNORE` into `hashlookup` (`file_sha256` PK).
- New rows: `lookup_status = 'pending'`, `system_confidence = 0`, `user_determined = 0`.
- Existing hash: no agent-triggered re-lookup; join reference data when listing programs.

**Table `hashlookup` (💩 column names follow CIRCL JSON when implemented)**

| Column | Role |
|--------|------|
| `file_sha256` | PK (lowercase hex, 64 chars) |
| `lookup_status` | `pending` \| `ok` \| `miss` \| `error` |
| `checked_dt` | Last successful or failed external check |
| `next_check_dt` | 💩 optional backoff after errors |
| `corpus_publisher` | 💩 label from hash corpus (primary human hint for “is this OS software?”) |
| `corpus_product` / `corpus_*` | 💩 other CIRCL fields we keep (product name, filename, source, …) |
| `corpus_payload` | 💩 raw JSON snippet or normalized text for audit |
| `system_confidence` | **0** = unknown; **5** = possibly in-box / system library; **10** = confirmed system library |
| `user_determined` | **1** = operator fixed confidence (or locked classification); worker does not overwrite confidence |

**Confidence scale (user 2026-11-24)**

| Value | Meaning |
|-------|---------|
| **0** | No server conclusion yet (pending lookup or no hit) |
| **5** | Plausible system / in-box (partial signals — corpus publisher, path heuristics, weak signer match) |
| **10** | Confirmed system library (strong corpus + signer allowlist and/or operator agreement) |

**Scoring (server rules — implement after T2 throwaway)**

- 💩 **Primary inputs:** `corpus_publisher` from Hashlookup; `signer_cert_sha256` vs trusted set (C); registry `publisher` / `signer_publisher` on linked `programs` rows for disagreement only.
- 💩 Exact mapping from CIRCL hit → 5 vs 10 is **out-of-band trial** (T2/T3), not guessed in product.
- `user_determined = 1`: controller or admin RPC sets `system_confidence`; background worker skips overwriting that column.

**Programs ↔ reference**

- `programs.file_sha256` FK-style join to `hashlookup` (no duplicate corpus columns on every program row unless profiling needs denormalized `system_confidence` later).
- UI / fleet filter: `JOIN hashlookup ON …` or materialized view — default hide where `system_confidence >= 10` and not user-overridden to show.

---

#### Workstream C — Signer ignore set (system Microsoft) ⏳

**Goal:** Server table or config of **`signer_cert_sha256`** values that bump confidence toward **10** (with corpus), not replace Hashlookup.

- 💩 Initial set built **only** from validated fleet sample — not a guessed publisher list.
- Catalog-signed / unsigned gaps may leave confidence at **0** until corpus helps (T1a gaps).
- **DB:** never delete program rows; filter by confidence + user flag.

---

#### Workstream D — Fleet SQL / aggregate ⏳

- Revisit fleet `Programs.list` when `hashlookup.system_confidence` is joinable (per-machine queries first).
- No default filter that only hides `source=service` without confidence or signer proof (rejected earlier).

#### Workstream E — `Hashlookup` background worker ⏳ (server only)

**Goal:** Gradual out-of-band enrichment — **not in a hurry**; sync path stays fast.

| Responsibility | Agent | Server |
|----------------|-------|--------|
| PE hash + Authenticode | ✔️ sync | Store on `programs`; seed `hashlookup` |
| CIRCL / external API | No | **`Hashlookup`** class + thread |
| Confidence / user override | No | `hashlookup` + rules + UI |

**Worker behaviour (design)**

- **Trigger:** server main loop starts one **background thread** (same pattern as other slow server work).
- **Cadence:** ~**one** lookup every **30 seconds** (configurable; no burst on large imports).
- **Pick:** oldest `lookup_status = 'pending'`, or `error` with backoff, or admin “force refresh”.
- **Call:** CIRCL Hashlookup HTTP API (`/bulk/sha256` single-hash or documented endpoint); 💩 DNS-style lookup only if throwaway shows a supported path — **default is API**.
- **On success:** fill `corpus_*`, set `lookup_status`, `checked_dt`, run **confidence scorer** (unless `user_determined`).
- **On miss:** `lookup_status = 'miss'`, `system_confidence` stays **0** unless signer rule (C) alone warrants **5** or **10**.
- **Tests:** out-of-band scripts first (T2 bulk CSV, T3 single-hash timer mock); product thread after scorer is validated.

**Class / file (💩 naming)**

- Server: `server/Hashlookup.vala` (or `server/Net/Hashlookup.vala`) — `init_db`, `note_from_programs_sync`, `worker_tick`, CIRCL client.
- Shares conceptual shape with 2026-11-21-processes-exe-enrichment.md `binary_fingerprint`; 💩 later merge one fleet-wide SHA256 reference table vs two tables.

**Nothing more on the agent** for B/E beyond synced columns already wired.

### Trials

| ID | What | Outcome |
|----|------|---------|
| T1a | `programs-authenticode-compare.ps1` on 39 fleet paths (`snappr-win`) | **PASS** — 39/39 exist; 38/39 SHA256 osq=ps; 35/36 subject on signed |
| T1b | Thumbprint cluster → ignore list draft | **PARTIAL** — 11 certs; `1308aad…` Microsoft Windows on 17 paths |
| T2 | CIRCL bulk on sample SHA256 set | **NOT RUN** |
| T3 | Manual scorer: corpus publisher + signer → confidence 0/5/10 | **NOT RUN** |
| T4 | Throwaway: one Hashlookup API call / 30s on pending queue | **NOT RUN** |

### LLM

- User (2026-11-24): CIRCL hashlookup; phases signing → hashes/CIRCL → signer ignore → UI; ignore set uses **cert codes**, not publisher name; system rows stay in DB.
- User (2026-11-24): keep **publisher for human review**; prove osquery vs secondary in throwaway; **agent SQLite cache** so enrichment is not repeated every sync.
- Grid load parked; fewer rows may follow from scope work but not a substitute for signing proof.
- T1a run on `snappr-win` 2026-11-24; artifact `tests/poc-authenticode/compare.csv`.
- Next: CIRCL bulk on distinct `file_sha256` from compare CSV; expand path set from full fleet DB.
- User (2026-11-24): agent `ExeEnrichment` (`locate` / `enrich`) must follow coding standards + plan before product; agent store = `WinFileIdentity` / `win_file_identity`; enrichment fields on `Programs` sync row.
- User (2026-11-24): one class `ExeEnrichment`; `locate` then `enrich`; no work in the constructor; fixed regex is not try/catched; locate ifs continue early.
- User (2026-11-24): certification / publisher-vs-cert validation and hash corpus (CIRCL, etc.) are **server-centralized**; server keeps SHA256 DB fleet-wide; clients must not keep re-authenticating — agent cache + one-time enrichment per file change is enough.
- User (2026-11-24): server **`hashlookup`** reference table by SHA256; background **`Hashlookup`** thread (~1 query / 30s); **`system_confidence`** 0 / 5 / 10; **`user_determined`** operator override; corpus publisher primary signal for “system library”; out-of-band API testing before product scorer.