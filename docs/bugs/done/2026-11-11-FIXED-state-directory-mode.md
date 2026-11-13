# Server state directory is world-readable

**Status:** ✅ closed 2026-11-13. All directory mode changes are applied in `server/Application.vala`, `server/Initialize.vala`, `packaging/systemd/argusrm-server.service`, and `packaging/sysvinit/argusrm-server.in`.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 `/var/lib/argusrm` should be readable by root only.
- 🔷 The database, the Unix socket, and the package store live in that directory.

## Evidence

- ✔️ On 2026-11-11 the directory is mode `755`, owner `root:root`. `argus.sqlite` is mode `644`.
- ✔️ `argusrm-server` runs as root. A normal login could open the database.
- ✔️ `tls/` is already mode `700`. The state directory was created at `0755` and never tightened.
- ✔️ systemd `StateDirectory=` resets that directory to `StateDirectoryMode=` on each start. The default is `0755`.
- ✔️ The controller opens `argus.sock` only after `geteuid()` is 0. Registration on that socket also requires root.

## Root cause

- ✔️ Startup created the state directory world-accessible and left it that way.

## Proposed fix

- 🔷 On startup, `Application` sets `/var/lib/argusrm` to mode `0700`, including when the directory already exists.
- 🔷 New `git/`, `scripts/`, and `packages/` directories are created at `0700`.
- 🔷 The systemd unit sets `StateDirectoryMode=0700`. The sysv script chmods the data directory before the daemon starts.

## Attempts

- ✔️ The change is in `server/Application.vala`, `server/Initialize.vala`, `packaging/systemd/argusrm-server.service`, and `packaging/sysvinit/argusrm-server.in`.

## Next

- ✅ Closed. State directory mode `0700` is in `server/` and packaging units.
