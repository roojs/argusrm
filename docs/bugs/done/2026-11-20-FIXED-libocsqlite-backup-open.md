# Agent: opened `SQ.Database` from every process lifetime

**Status:** ✅ closed 2026-11-20 — agent opens `client_db` only when persistence is required; shutdown backup gated on that.

**Pointer:** `docs/bug-fix-process.md`, [`agent/Application.vala`](../../../agent/Application.vala), [`agent/linux/Application.vala`](../../../agent/linux/Application.vala)

## Symptom

- `argusrm-agent --help`, unprivileged `argusrm-agent-gtk` → **SIGSEGV** on exit in `backup_real` / `sqlite3_backup_step`.
- PIN registration saves, then `service.restart()` reports the agent did not connect (service died on shutdown backup).

## Cause (Argus misuse, not libocsqlite)

- {@link Argus.Agent.Application} constructed `SQ.Database` with `autosave = true` for **every** launch, including `--help` and the gtk pkexec shell, pointing at root-owned {@link Argus.AGENT_DATA_DIR}.
- Shutdown always called `backup_real()` when the in-memory DB was dirty, even when this process never should have touched agent state.
- `backup_real` cannot succeed without a writable path; calling it after a failed setup was wrong.

## Fix

- **Do not** open `client_db` in the constructor.
- {@link Argus.Agent.Application.ensure_client_db} opens the DB only for **root** service or registration paths that persist credentials.
- Shutdown backups only when this process opened the DB and it is dirty.

## Evidence

- gdb backtrace on `argusrm-agent --help` (2026-11-20).