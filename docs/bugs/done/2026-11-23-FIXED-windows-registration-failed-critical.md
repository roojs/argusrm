# Windows tray registration fails after PIN

**Status:** ✅

### User reported

- 🔷 Windows registration failed; agent log showed a critical-level line.

### Success scenario

- Tray PIN enrolls the machine (`registration 0`, PEMs + `server.sqlite` under systemprofile `argus`).

### Current behavior

- User confirmed tray registration succeeded on **0.1.40** (`snappr-win`, 2026-11-23).

### Proposed fix

- ✔️ **`shared/meson.build`** — `shared_client_vala_args += ['-D', 'G_OS_WIN32']`.
- ✔️ **`agent/Application.vala`** — `ensure_client_db()` on Windows service startup.

### LLM

- ℹ️ Pre-fix failure log: `Register.vala:525: os-release did not name debian or rpm` — 2026-11-23-ISSUE-windows-registration-failed-critical.md (archived content merged here).
- ℹ️ Post-enroll “Disconnected” / no controller tick → 2026-11-23-ISSUE-windows-agent-disconnected-after-register.md.