# Gtk **Connect locally** — nested pkexec + wrong loopback probe

**Status:** ✅ closed in tree 2026-11-21 — device re-check on install host still recommended

**Supersedes:** active logs `2026-11-21-agent-local-enroll-double-pkexec.md`, 2026-11-21-FIXED-agent-connect-locally-missing.md

**Pointer:** `docs/bug-fix-process.md`, [`agent/linux/LocalRegistration.vala`](../../../agent/linux/LocalRegistration.vala), [`agent/linux/Application.vala`](../../../agent/linux/Application.vala), [`shared/Register.vala`](../../../shared/Register.vala), [`agent/Connection.vala`](../../../agent/Connection.vala), [`tests/registration-wire.vala`](../../../tests/registration-wire.vala)


---

## Problem

- Gtk **Connect locally** after admin pkexec: long wait, **Registration failed** / empty cert output.
- Unconfigured notice: **Connect locally** hidden when daemon was up but registration port 819 was not.

---

## Root cause

| # | Cause | Symptom |
|---|--------|---------|
| R1 | Nested `pkexec … --give-me-a-certificate` while Gtk already runs as root | Second polkit, empty stdout |
| R2 | `Register.probe_local()` probed `REGISTER_PORT` (819) | No **Connect locally** when only management port is listening |

---

## What shipped

- ✔️ **R1:** [`LocalRegistration.enroll_certificate`](../../../agent/linux/LocalRegistration.vala) runs `argusrm-server --give-me-a-certificate agent` directly when `geteuid() == 0` (no second pkexec).
- ✔️ **R2:** [`Register.probe_local`](../../../shared/Register.vala) probes loopback {@link Argus.SOCKET_PORT} and `SERVER_EXECUTABLE` presence.
- ✔️ Gtk elevation: `on_start_admin` uses `SubprocessLauncher.setenv` for session display vars (polkit matches gtk binary, not `/usr/bin/env`).
- ✔️ Post-enroll: `Register.save` + `backupDB`; `service.restart(false)` after local enroll (do not wait for CONNECTED).
- ✔️ `Registration.deregister` `"agent"` on Unix socket before **Remove on server** retry; `RegistrationError.ALREADY_REGISTERED` for conflict UI.
- ✔️ `Connection.stand_down()` during gtk registration; RPC types registered early on gtk command line.
- ✔️ Empty on-disk client store: libocsqlite `SQ.Database` open discards zero-byte files (no duplicate logic in agent/controller `Application`).

---

## Ruled out

- JSON / kebab key mismatch (`tests/registration-wire`).
- New shared JSON parsers or `store_file_on_disk_ready` helper.

---

## Still separate

- `g_file_test: filename != NULL` on server `--give-me-a-certificate` (stderr noise).
- End-to-end confirm on target host after `argusrm-agent-gtk` install.
- Controller/agent enroll dedup — refactor bug above.

---

## Verify

```bash
ninja -C build tests/argus-registration-wire build/tests/argus-registration-wire
# Desktop: argusrm-agent-gtk → administrator → Connect locally → save + service restart
# Second run: configured or connected notice, not nested polkit
```