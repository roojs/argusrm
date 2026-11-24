# Server in-memory DB empty while on-disk `argus.sqlite` has agents

**Status:** ✅ — `opt_data_dir = ""` in `server/Application.vala` (user confirmed 2026-11-24)

**Pointer:** `docs/bug-fix-process.md`, `.cursor/rules/debugging.mdc`, `OLLMchat/libocsqlite/Database.vala`

---

## Problem

- 🔷 On-disk `/var/lib/argusrm/argus.sqlite`: **3** `agent` rows (15–17). Offline copy reproduces load + select + RPC pack OK.
- 🔷 Live `argusrm-server`: `Agent.list` / controller Agents UI show **0** or wrong ids (1–2); memory does not match file.
- 🔷 **Expected:** `SQ.Database` constructor loads file into `:memory:`; same row count as file after `Agent.init_db`.

---

## Evidence

- ✔️ `build-probe/tests/argus-agent-list-offline` on copy: 3 rows, encode OK (user run 2026-11-22).
- ✔️ `build-probe/tests/argus-db-startup-probe /tmp/argus.sqlite.copy`: disk=3, memory after load=3, after `init_db`=3, `filename` set (build-probe ocsqlite).
- ✔️ `argus-list-probe` vs live server: 1–2 rows on wire while file snapshot has 15–17.
- ℹ️ Journal: **no** `discarding zero-byte`; **yes** `g_file_test: filename != NULL` before unix socket (`SocketListen.start` suspect, separate).
- ℹ️ Previously added server `note_agent_table` — **reverted** (broke debugging rules).

---

## Root cause

- ✔️ **`backing path empty` / `empty :memory: backing not loaded:`** (2026-11-22 11:28) — `SQ.Database` opened in `Application()` **before** `command_line` zeroed `opt_data_dir`. Uninitialized static `opt_data_dir` is **null**; `null != ""` is true in Vala, so `data_dir` stayed null, `g_build_filename(null, "argus.sqlite")` → null path, load skipped. Later logs show `/var/lib/argusrm/argus.sqlite` because `command_line` sets `opt_data_dir = ""` then uses `Argus.SERVER_DATA_DIR` — but **the same `this.db` instance** stays on empty `:memory:`.
- ✔️ Throwaway `/tmp/null-opt-dir.vala`: `null` ternary → `data_dir` null; after `opt_data_dir = ""` → `/var/lib/argusrm`.
- ✔️ **`after init_db row_count=0`** and TLS `cert lookup rows=0` — downstream of empty RAM DB.
- ℹ️ Construct-time libocsqlite `GLib.debug` was **missing from `server.log` until** `GLib.Log.set_default_handler` moved before `new SQ.Database`.
- ⏳ **Secondary:** graceful shutdown `backup_real()` may have written empty memory over good file earlier; disk restored manually while process still holds empty RAM until restart + successful load.
- 💩 Installed `libocsqlite.so` vs build tree mismatch (`db.filename` empty in an earlier accidental log).

---

## Throwaway repro

```bash
ninja -C build-probe tests/argus-db-startup-probe
# copy of live db
build-probe/tests/argus-db-startup-probe /tmp/argus.sqlite.copy
# or live path (readable by user)
build-probe/tests/argus-db-startup-probe /var/lib/argusrm/argus.sqlite
```

Interpretation:

| Output | Meaning |
|--------|---------|
| disk=N, memory after load=0 | **load_from_file failure** on that path (prove before ocsqlite fix) |
| disk=N, memory=N | Load OK in probe; live server differs (path, timing, or different binary/lib) |
| disk open failed | Permissions or wrong path |

---

## Proposed fix (after throwaway proves branch)

- ✔️ **argusrm** `server/Application.vala`: `public static string opt_data_dir = ""` (or equivalent null-safe `data_dir` resolver) so constructor opens the real backing path — **minor**, throwaway proved.
- 💩 **libocsqlite** `load_from_file`: log failure reason; guard empty path before `FileUtils.test`; check `Sqlite.open` / backup result — still useful for other callers.
- 💩 **libocrpc** `SocketListen.start`: null-check `parent.get_path()` before `FileUtils.test` — separate from row count.
- ⏳ GObject `type id '0'` on `.list` replies — separate throwaway in ocrpc.

---

## Attempts / changelog

- ✔️ `tests/agent-list-offline.vala` — full select + RPC pack on copy.
- ✔️ `tests/db-startup-probe.vala` — disk vs memory counts, `autosave=true`, `Agent.init_db` only.
- 🚫 Server `note_agent_table` helper — removed.
- ✔️ 11:28 log: `backing path empty` — `opt_data_dir` null before `command_line`; default `= ""`.
- ✔️ Removed temporary `GLib.debug` from server + reverted libocsqlite load debug in OLLMchat.