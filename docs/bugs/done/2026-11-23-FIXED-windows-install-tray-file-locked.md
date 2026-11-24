# Windows installer cannot replace argus-tray.exe

**Status:** ✅

### User reported

- 🔷 Upgrade hung: NSIS could not overwrite `argus-tray.exe` (file in use); installer stuck.

### Success scenario

- Upgrade renames in-use binaries, copies new files, completes without a file-lock error.

### Current behavior

- User confirmed installer fix on upgrade testing (shipped **0.1.38** / **0.1.39** NSIS).

### Proposed fix

- ✔️ [`packaging/windows/argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi) — `StopArgusForUpgrade`, `QuarantineInstalledExes` (rename to `.old` before `File /r`), delete `.old` with `/REBOOTOK`.

### LLM

- ℹ️ Cause: service `tick()` respawns tray ~every 5s; single `taskkill` left the file locked.
- ℹ️ Active note was 2026-11-23-windows-install-tray-file-locked.md (archived).