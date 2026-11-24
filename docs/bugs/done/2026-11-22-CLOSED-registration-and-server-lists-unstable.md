# Registration and server list RPCs unstable (2026-11-22)

**Status:** ✅ parked — closed 2026-11-24 (evidence retained; reopen if instability returns)

**Pointer:** `docs/bug-fix-process.md`, `tests/list-probe.vala`, `server/Application.vala`

---

## Problem

- 🔷 After morning work on fastboy (`192.168.0.16:817`), **registration and Agents UI** feel unreliable: “already registered” with missing certs, thin **Agents** list, local agent Gtk **Connect locally** crash, Android phone row stored as **controller**.
- 🔷 **Expected:** Stable enroll, `Agent.list` matching sqlite, controller startup lists (`ScriptRepository`, `DebPackages`, …) usable.

---

## Evidence (fastboy, 2026-11-22)

- ✔️ **Server SEGV ~09:47** — `argusrm-server (deleted)`; systemd restart; `g_file_test: assertion 'filename != NULL' failed` on boot.
- ✔️ **Server log** — `type id '0' is invalid` / `g_value_get_boolean` failed on `ScriptRepository.list`, `Distributable.list`, `SystemInfo.list`, `DebPackages.list`, `Task.all_targets`, … (not sqlite data).
- ✔️ **`argus-list-probe`** (`tests/list-probe.vala`) reproduces on TLS: `Agent.list` returns 2 rows; other lists → client `INVALID` empty in ~1–5 ms while server logs GObject errors.
- ✔️ **On-disk sqlite** (`/var/lib/argusrm/argus.sqlite`): agents **15–17** (two controllers, one agent `192.168.122.1`). **Wire `Agent.list`** reported **id=1,2** both `fastboy` — **mismatch** with file snapshot (live server vs disk backup / in-memory state TBD).
- ✔️ **`Registration.certificate`** — “This machine is already registered” while client cert missing or stale (allowlist / row vs keyring skew after crash and re-enroll attempts).
- ✔️ **`argusrm-agent-gtk`** — `property 'app' … LocalRegistration is not writable` → `data_dir: assertion 'self != NULL'`. **Tree fix:** `agent/linux/LocalRegistration.vala` `private construct` → `construct` (not installed on system yet).
- ✔️ Stale phone hello spam — `failed certificate 1259496e…` in server log.

---

## Root cause (open)

1. ⏳ **Primary:** server-side **ocrpc / GObject encode** for many `.list` replies (empty or non-empty arrays).
2. ⏳ **Registration state:** crash + reinstall timing, deregister/re-enroll, **sqlite on disk vs running server** agent rows.
3. ✔️ **Local Gtk enroll:** Vala `private construct` on `LocalRegistration.app` (fix in tree).

---

## Throwaway repro

```bash
ninja -C build-probe tests/argus-list-probe
build-probe/tests/argus-list-probe 192.168.0.16 817 fastboy
# parallel: tail -f /var/log/argusrm/server.log
```

```bash
sudo sqlite3 /var/lib/argusrm/argus.sqlite \
  "SELECT id, hostname, username, is_controller, status, ip FROM agent ORDER BY id;"
```

---

## Next (when resumed)

- Prove encode failure in OLLMchat throwaway (not controller product).
- Reconcile **Agent.list** ids with on-disk sqlite (backup / ocsqlite memory model).
- Install agent **LocalRegistration** construct fix; retest local enroll.

---

## Parked

- Android DebPackages disconnect — closed `docs/bugs/done/2026-11-22-CLOSED-android-debpackages-disconnect.md` (separate).