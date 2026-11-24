# Windows agent never reconnects after in-place upgrade

**Status:** ⏳ blocked on OLLMchat

**Upstream (canonical):** 2026-11-23-ISSUE-windows-sqlite-new-orphan-backup.md — `libocsqlite/Database.vala` (`load_from_file`, `backup_real`).

**Pointer:** `docs/bug-fix-process.md`, [`agent/Application.vala`](../../agent/Application.vala) (`ensure_client_db`), [`agent/Connection.vala`](../../agent/Connection.vala)

### User reported

- 🔷 After installing **0.1.42** over **0.1.41**, the machine loses controller connection and does not reconnect.

### Success scenario

- In-place NSIS upgrade stops the service, replaces binaries, starts the service; existing registration in `server.sqlite` is loaded; TLS reconnects within seconds.

### Current behavior

- Tray stays **Disconnected**; controller tick does not return.
- PEMs and legacy `server` / `download` files remain under systemprofile `argus`.

### Codebase observed behavior

- **libocsqlite** `backup_real()` writes `filename.new` then `rename` to `filename`. On Windows, `g_rename` may not replace an existing destination; there is no delete-then-rename or copy fallback in the build Argus links today.
- **libocsqlite** `load_from_file()` opens only `filename`. After a failed promote at shutdown/upgrade, only `server.sqlite.new` remains → constructor loads an empty in-memory DB → `Connection` logs `no saved server` forever.
- Argus agent opens client `server.sqlite` with `autosave = true` on the Windows service ([`ensure_client_db`](../../agent/Application.vala)); no Argus-side duplicate of libocsqlite backup semantics is intended.

### Debugging

#### Current debug output

- **Source:** `snappr-win`, service `agent.log`, 2026-11-23 after **0.1.42** install

```text
14:33:55.918441: G_LOG_LEVEL_DEBUG : Database.vala:176: disk backup requested
14:33:56.851648: G_LOG_LEVEL_WARNING : Connection.vala:199: no saved server
(repeats every ~5s)
```

- **On disk:** `argus\client.pem` present; **`server.sqlite` missing**; `server.sqlite.new` present (12 KiB, 14:33).

#### Debug code added (remove when complete)

None.

### Proposed fix

**OLLMchat (primary)**

- ✔️ Bug filed: upstream canonical (orphan `*.new` recovery + Windows-safe promote in `backup_real`).
- ✔️ **OLLMchat** `v1.4.17` published; MSYS `libocsqlite` on `v1.4.17-packages`.
- ⏳ Argus **0.1.43** Windows installer bundles that runtime (build on `snappr-win`).

**Argus (after upstream)**

- ⏳ Re-test in-place NSIS upgrade on `snappr-win` without manual rename.

**Workaround (ops, not product)**

- 💩 Stop service, promote `server.sqlite.new` → `server.sqlite` under systemprofile `argus`, start service.

### LLM

- ℹ️ Separate from `address_list()` host:port fix (**0.1.41**); certs survived but server row did not load.
- ℹ️ Implement fix in OLLMchat only; Argus picks up release version.