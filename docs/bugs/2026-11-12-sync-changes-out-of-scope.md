# Package monitor work rewrote the sync path

**Status:** ⏳ recorded — revert not started

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 The permitted code was the two package monitor classes. They were not to be wired in.
- 🔷 The working tree also rewrites startup sync, every osquery table, the agent table, the task tables, the controller stores, the server RPC, the package test, and several plans.
- 🔷 A failed package query and an empty package list are the same result. The monitor then marks every stored package deleted.
- 🔷 Finding a changed package walks every stored row for every fresh row.

## What was asked

- 🔷 Draft `agent/linux/PackageMonitor.vala` and `agent/Win32/PackageMonitor.vala`. Do not add them to meson. Do not construct them from startup.
- 🔷 `debian()` and `rpm()` are separate methods. Startup `os_version` chooses one later. The monitor does not decide the operating system.
- 🔷 `send` posts the difference from the startup fetch. A row that left is included with `deleted_dt` set. That fetch is kept from the original query.
- 🚫 Do not change `Query.select` to return a bool. It stays `void`. The note is on `agent/OSQuery/Query.vala`.

## Evidence

- ✔️ Against `HEAD`, 30 tracked files differ: 946 insertions, 181 deletions. Five paths are untracked. Meson is untouched, so neither monitor is in the build.
- ℹ️ The two monitor files are the untracked pair `agent/linux/PackageMonitor.vala` and `agent/Win32/PackageMonitor.vala`.

### Wired anyway

- ✔️ `agent/Application.vala` gained `os_version` and `package_rows`.
- ✔️ `agent/OSQuery/Initialize.vala` writes `os_version` from the startup query, and stores `deb_packages`, `rpm_packages`, and `programs` on `package_rows` after `OSQuery.sync`.
- ✔️ `server/OSQuery.vala` registers `OSQuery.update` (`so`) and applies that call with `sync(..., false)`.
- ℹ️ `docs/rpc-commands.md` documents that new call.

### Sync no longer means the same thing

- ✔️ `AgentInfo.sync` and every osquery override grew `bool complete = true`. `Row.sync` did not. The abstract on `shared/OSQuery/Row.vala` is still `(db, agent_id, rows)`.
- ✔️ `sync_rows` used to `deleteId` a stored row the snapshot left out. It now stamps `deleted_dt` and leaves the row. `complete` false skips that pass and treats a row whose `deleted_dt` is set as a removal.
- ✔️ That pass is the nested walk: for each incoming row, scan every stored row with `compare`.
- ✔️ The same three columns were added, with `ALTER TABLE`, on tables this task does not sync:
  - `shared/Agent.vala` — `agent`
  - `shared/OSQuery/SystemInfo.vala`, `CpuInfo.vala`, `OsVersion.vala`, `InterfaceAddresses.vala`, `LoggedInUsers.vala`, `DebPackages.vala`, `RpmPackages.vala`, `Programs.vala`
  - `shared/SQT/Script.vala`, `ScriptAgent.vala`, `ScriptRepository.vala`, `Task.vala`, `TaskTarget.vala`
- ✔️ `controller/store/DebPackages.vala`, `RpmPackages.vala`, and `Programs.vala` now call `list` as `ii` with `since` zero.
- ✔️ `server/tests/packages.vala` grew the soft-delete and partial-sync checks.

### The monitor diff

- ✔️ Both `send` methods repeat that nested walk, then stamp `deleted_dt` on whatever is left in the stored list.
- ✔️ `Query.select` is `void`. A failed launch, a bad exit, or a body that is not JSON leaves the caller's list empty.
- ✔️ Both monitors call it and continue. An empty list is then "every stored package left", so a failed query sends those rows as deleted.
- ✔️ `agent/OSQuery/Query.vala` differs by one line, the void note. The bool return was rejected and taken back out.

### Other untracked files

- ✔️ `agent/linux/UpdatesAvailable.vala`, `agent/Win32/UpdatesAvailable.vala`, and `docs/plans/5.11-os-update.md` are not the package monitor.
- ✔️ Plan edits that ride along: `docs/plans/4.0-data-types.md`, `5.8-assets-page.md`, `5.9.1-assets-software-data.md`, `5.10-data-enrichment.md`, `7.0-tasks.md`.

## Root cause

- ✔️ The differential send was implemented by changing `sync_rows` for every table, then pointing the monitor at that new flag. The class draft and the startup wiring were not kept apart.

## Proposed fix

- 🔷 Commit this tree, including this report.
- 🔷 Then restore every path below to `HEAD`, and delete the untracked files below. This report stays.
- 🚫 Do not use a wildcard checkout or reset. Name each path.

### Restore to `HEAD`

- `agent/Application.vala`
- `agent/OSQuery/Initialize.vala`
- `agent/OSQuery/Query.vala`
- `controller/store/DebPackages.vala`
- `controller/store/Programs.vala`
- `controller/store/RpmPackages.vala`
- `docs/plans/4.0-data-types.md`
- `docs/plans/5.10-data-enrichment.md`
- `docs/plans/5.8-assets-page.md`
- `docs/plans/5.9.1-assets-software-data.md`
- `docs/plans/7.0-tasks.md`
- `docs/rpc-commands.md`
- `server/OSQuery.vala`
- `server/tests/packages.vala`
- `shared/Agent.vala`
- `shared/OSQuery/AgentInfo.vala`
- `shared/OSQuery/CpuInfo.vala`
- `shared/OSQuery/DebPackages.vala`
- `shared/OSQuery/InterfaceAddresses.vala`
- `shared/OSQuery/LoggedInUsers.vala`
- `shared/OSQuery/OsVersion.vala`
- `shared/OSQuery/Programs.vala`
- `shared/OSQuery/Row.vala`
- `shared/OSQuery/RpmPackages.vala`
- `shared/OSQuery/SystemInfo.vala`
- `shared/SQT/Script.vala`
- `shared/SQT/ScriptAgent.vala`
- `shared/SQT/ScriptRepository.vala`
- `shared/SQT/Task.vala`
- `shared/SQT/TaskTarget.vala`

### Delete, untracked

- `agent/linux/PackageMonitor.vala`
- `agent/Win32/PackageMonitor.vala`
- `agent/linux/UpdatesAvailable.vala`
- `agent/Win32/UpdatesAvailable.vala`
- `docs/plans/5.11-os-update.md`

## Next

- ⏳ 🔷 Wait for the commit, then the request to restore the list above and leave this file.
