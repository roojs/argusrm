# Agent `--request` saves empty `server.sqlite` before restart & `Task.all_targets` `type id '0' is invalid`

**Status:** ✅ fixed in tree (agent DB save); upstream fix identified in `OLLMchat/libocrpc` (`OLLMrpc.val`)

### User reported

- 🔷 On fresh LXC container `cust-web-aspen`: `argusrm-agent --request --server 192.168.254.88` reached `Waiting for registration to be approved, try 2 of 15`, then failed with `Registered, but could not restart the Argus agent service: Argus Remote Manager agent service did not connect to the management server`.
- 🔷 On server `argusrm`: each `Task.all_targets` call logs three `G_LOG_LEVEL_CRITICAL` lines (`type id '0' is invalid`, `can't peek value table for type '<invalid>'`, `cannot initialize GValue with type '(null)'`).

### Root cause

1. **Agent `server.sqlite` empty on restart (`shared/Register.vala`, `agent/Application.vala`, `controller/Application.vala`):**
   - On a fresh host where `/var/lib/argusrm-agent/argus/server.sqlite` does not yet exist, `ensure_client_db()` (`agent/Application.vala`) calls `this.client_db.backupDB()`, writing an empty `server` table and setting `last_backup = T`.
   - `try_batch()` sleeps `1 * 20` seconds between try 1 and try 2 (`to_unix() - last_backup == 20`; `--pin` is `0`).
   - `Register.save()` called `db.backupDB()`. Because `SQ.Database.backupDB()` only runs `backup_real()` synchronously when `now - last_backup > 20` (strict `>`), it deferred the write to a 500 ms `GLib.Timeout` (`countdown = 5`).
   - CLI registration has no main loop running before `service.restart()`, so the timer never fires. The restarted `argusrm-agent --service` reads the empty `server.sqlite` (`no saved server`), never connects, and `service.restart()` times out after 10 s.
   - Both `agent/Application.vala` and `controller/Application.vala` `shutdown` handlers also called `backupDB()` instead of `backup_real()`, and `Register.remove_local()` did not flush to disk.
2. **Server `Task.all_targets` `G_LOG_LEVEL_CRITICAL` (upstream `OLLMchat/libocrpc`):**
   - `OLLMrpc.val("o", rows)` returns `GLib.Value(GLib.Type.INVALID)` when `rows.size == 0` (`OLLMchat/libocrpc/namespace.vala` lines 262 & 299, `OLLMchat/libocrpc/android/namespace.vala` lines 264 & 297).
   - In Vala, `GLib.Value(GLib.Type.INVALID)` compiles to `g_value_init(&tmp, 0)`, emitting the three `GLib-GObject-CRITICAL` lines on every empty list reply.

### Debugging

- Throwaway `/tmp/argus-repro-bugs.vala` proved:
  - `init_db` + `backupDB()` + `insert` + `backupDB()` → reopened `SQ.Database` had `0` rows; `backup_real()` → `1` row.
  - `OLLMrpc.val("o", empty)` emitted the exact three `GLib-GObject-CRITICAL` lines; `GLib.Value empty = {}; return empty;` returned `GLib.Type.INVALID` with zero criticals and round-tripped through `OLLMrpc.Response` + `Bin.Stream`.
  - Stripped PEM files written by `Agent.SQT.Server.store_certificates()` reload cleanly in `OLLMrpc.Transport.Cert.ensure()`.

### Fix applied

- [`shared/Register.vala`](../../shared/Register.vala): `save()` and `remove_local()` call `db.backup_real()` so disk persistence is synchronous before `service.restart()`.
- [`agent/Application.vala`](../../agent/Application.vala), [`controller/Application.vala`](../../controller/Application.vala): `shutdown` calls `backup_real()`.
- [`tests/registration-enroll.vala`](../../tests/registration-enroll.vala): call `db.backupDB()` after `init_db(db)` to mirror `ensure_client_db()` on a fresh host.
- Upstream (`OLLMchat`, not edited from this repo): replace `return GLib.Value(GLib.Type.INVALID);` with `GLib.Value empty = {}; return empty;` in `libocrpc/namespace.vala` (lines 262, 299) and `libocrpc/android/namespace.vala` (lines 264, 297).

### Verify

- `meson test registration-enroll registration-bootstrap registration-wire` — 3/3 OK.

### LLM

- `shared/Register.vala`
- `agent/Application.vala`
- `controller/Application.vala`
- `tests/registration-enroll.vala`
- `docs/bug-fix-process.md`
