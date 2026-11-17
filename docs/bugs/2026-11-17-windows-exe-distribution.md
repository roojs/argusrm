# Distributables: NSIS installers

**Status:** ⏳ opened — one grid, Distribute picks machines and creates a task

**Pointer:** `docs/bug-fix-process.md`, [2.0-agent.md](../plans/2.0-agent.md), [7.0-tasks.md](../plans/7.0-tasks.md), [2026-11-17-remote-repository-checkouts.md](2026-11-17-remote-repository-checkouts.md), [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-windows-uninstall-task-queue.md), [`controller/TabList.vala`](../../controller/TabList.vala), [`shared/SQT/Task.vala`](../../shared/SQT/Task.vala), [`shared/OSQuery/Programs.vala`](../../shared/OSQuery/Programs.vala), [`packaging/windows/argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi)

---

## Problem

- 🔷 There is no way to hand a Windows installer to a machine. The download socket only serves the fixed osquery installer. Repository checkouts already exist in MTrack. [2026-11-17-remote-repository-checkouts.md](2026-11-17-remote-repository-checkouts.md).
- 🔷 **Expected:** a sidebar page, **Distributables**. One grid: the distributable name, its platform, the version, and a **Distribute** button. Distribute opens a dialog of the machines for that platform. The list is searchable. Each row shows the version already installed on that machine, when `programs` has this name. Machines that already have it start ticked, so the default run is an update. The user can tick a machine that does not have it, or clear one. **Select all** ticks every machine in the list. Confirming creates a task whose command is that installer, on the ticked machines, and the task references the stored distributable file the agent has to download.
- 🔷 The file is an NSIS installer. Other files wait. Several versions of one name are stored, with their files. A screen that lists those versions is not part of this bug.
- 🔷 **Actual:** no Distributables page, no stored installer, and `task` has no reference to a file the agent must fetch.

---

## Evidence

### 1. The controller has no page for this

- ✔️ `controller/TabList.vala` sidebar keys are `dashboard`, `agents`, `assets`, `tasks`, `monitoring`, `scripts`, `repositories`. `controller/Window.vala` builds a page for each of those keys.
- 🚫 There is no `distributables` key and no grid of uploaded installers.

### 2. A download exists for one installer, and a task cannot name a file

- ✔️ The package store is `packages/` under `Argus.SERVER_DATA_DIR`. The default is `/var/lib/argusrm/packages`. `server/Net/Download.vala` answers `GET /{relative}` from that directory and refuses `..`. Osquery is already `packages/osquery/osquery.msi`. The handler returns 405 for every method other than GET.
- ✔️ `Argus.Agent.Download.fetch` is a TLS HTTP GET on that socket. [2.0](../plans/2.0-agent.md). The controller talks to the Unix socket (`controller/Application.vala`), not this download socket.
- ✔️ `shared/SQT/Task.vala` is `is_script`, `command`, and `script_id`. A command task runs `command` on each `task_target`. Nothing on the row points at a stored installer.
- ℹ️ [7.0](../plans/7.0-tasks.md) already says an install downloads a file from Argus and then runs the installer. That download command is not built.
- 🚫 Nothing stores an uploaded installer, a version, or a hash.

### 3. What an NSIS installer exposes, and how it is run

- ✔️ An NSIS installer is a PE with an overlay. The overlay first-header contains signature `0xDEADBEEF` (`EF BE AD DE`) followed by the three little-endian ints that spell `NullsoftInst`. Finding that byte string is enough to accept the file as NSIS.
- ✔️ The product name and version are in the PE version resource only when the `.nsi` sets them:

```nsis
VIProductVersion "1.2.3.0"
VIAddVersionKey /LANG=1033 "ProductName" "Argus RM Agent"
VIAddVersionKey /LANG=1033 "FileVersion" "1.2.3"
```

  `ProductName`, `ProductVersion`, and `FileVersion` are then readable from the uploaded bytes on the Linux server.
- ✔️ [`packaging/windows/argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi) does not set `VIProductVersion` or `VIAddVersionKey`. `Name` is `"Argus RM Agent"` and `DisplayVersion` is written into the uninstall registry key at install time. Both strings sit in the compressed NSIS header, so a direct read of `ArgusAgent-Setup.exe` does not yield a name or a version.
- ℹ️ Decompressing that header (LZMA, the block 7-Zip opens) can recover those strings. That parser is not required for the grid.
- ✔️ Silent install is `Setup.exe /S` (`/S` is case-sensitive). Session 0 can run that. The MUI pages in our `.nsi` are skipped.

### 4. Installed copies already live on `programs`

- ✔️ `programs` (`shared/OSQuery/Programs.vala`) is one installed Windows program per agent: `agent_id`, `name`, `version`. `name` is the uninstall registry `DisplayName`. Our `.nsi` writes that as `"Argus RM Agent"`, the same string as `Name`.
- ✔️ `os_version.platform` is `windows` for a Windows agent. `Programs.machines` already returns the live rows for one `programs.name`.
- 🚫 Nothing on `distributable` stores a platform, and nothing ties a distributable to `programs.name`. A second table of "where we sent it" is not how this is tracked. `programs` is that list, once the name matches.

---

## Root cause

- ✔️ Installers were never a catalog, and a task cannot say "fetch this file, then run it".

---

## Phases

- ⏳ **Phase 1 — Store the installer and show it.** Upload keeps the file and the version. The grid is one row per distributable: name, platform, latest version, Distribute.
- ⏳ **Phase 2 — Distribute.** The dialog reads `programs` for the installed version, ticks machines that already have this name, and creates a task that references the file.

A version-history screen is deferred. The rows and the files from Phase 1 stay.

---

## Phase 1 — Store the installer and show it

- ✔️ Sidebar page `distributables`, title **Distributables**. The grid columns are name, platform, latest version, file size, and **Archive**. Search matches those three text columns. **Upload** (suggested action) sits on the right of the bar. Download is not on the bar yet.
- ✔️ **Archive** is a hold, the same gesture as the rubbish bin. It sets `deleted_dt` on that distributable and the row leaves the list. There is no view of archived rows. The file stays in the package store. Osquery under `packages/osquery/` is not a row on this grid.
- 🔷 **Distribute** on a row is still Phase 2.
- 🚫 No second grid of older versions. No running the installer on the server to discover its name. The bytes do not go in SQLite.

### Tables

`added_dt`, `updated_dt`, and `deleted_dt` are on both, as in [4.0](../plans/4.0-data-types.md).

`distributable` is the product. One live row per platform and name.

```
id                      INTEGER
name                    TEXT      programs.name match. Windows DisplayName
platform                TEXT      windows for this bug
```

- 🔷 `name` is the string `programs.name` shows after install. The grid label is that same string. Upload of an NSIS installer sets `platform` to `windows`. A later platform uses the same table. The match for "already installed" is `platform` plus `name`.

`distributable_version` is one uploaded file. A newer upload of the same name inserts another row and leaves the previous file in place.

```
id                      INTEGER
distributable_id        INTEGER   distributable.id
version                 TEXT      ProductVersion, or the version the user typed
sha256                  TEXT      hash of the bytes
filename                TEXT      original file name
path                    TEXT      relative to packages/. distributables/{sha256}.exe
size                    INTEGER   bytes
uploaded_by             INTEGER   agent.id of the controller that uploaded it. 0 is the Unix socket
```

- 🔷 The file itself is `packages/distributables/{sha256}.exe` inside the package store. The download URL for that file is `/distributables/{sha256}.exe`. Phase 2 GETs that path. The same bytes uploaded twice share one file. Two version rows may point at the same `path`.
- 🔷 `Distributable.list` returns one row per live distributable: `id`, `name`, `platform`, and the latest live version (`version`, `distributable_version.id`). Latest is the greatest `distributable_version.id` for that distributable. The grid binds to that.

### Upload

The controller is on the Unix socket, so the send is an RPC there. The file is not one RPC body. The download socket stays GET-only.

- ✔️ **Upload** opens a file dialog, then a progress dialog: the file name, a bar, bytes sent of the file size, an estimate of the time left, and **Cancel**.
- ✔️ The file is split into 256 KiB chunks. `Distributable.begin` sends the file name and size and returns an id held in memory on the server. Each `Distributable.chunk` sends the id, the offset, and the bytes. The server appends them to `packages/distributables/incoming/{id}`. The offset has to match the bytes already stored.
- ✔️ `uploaded_by` on `distributable_version` is the agent that sent the file. `begin` records that from the calling controller. `0` is the Unix socket. The column is on the version row. The finished upload keeps it in memory until processing inserts the row.
- ✔️ **Cancel** calls `Distributable.cancel`, which deletes the partial file.
- ✔️ The last call is `Distributable.complete`. The stored length must equal the size from `begin`. The server reads the file with `Installer.from_file`. The NSIS signature has to be present. `ProductName` and `ProductVersion` (or `FileVersion`) come from the PE version resource. The file moves to `packages/distributables/{sha256}.exe`. A new name inserts `distributable` (`platform = windows`) and `distributable_version`, including `uploaded_by`. A live row with that platform and name gets another version. The same bytes on that row return the version already stored. The reply is the product, and the grid reloads. A file that is not NSIS, or that has no product name and version, is deleted and the upload dialog shows that error.
- 💩 Add `VIProductVersion` and `VIAddVersionKey` (`ProductName`, `FileVersion`) to `packaging/windows/argusrm-agent.nsi` so our own installer takes the match path. Confirm before editing the installer.
- 🚫 Do not put the installer bytes on the agent app socket. Do not add PUT on the download socket for this. The controller upload is the Unix-socket RPC above.

---

## Phase 2 — Distribute

- 🔷 Where a distributable is installed is a live `programs` row whose `name` equals `distributable.name`, on an agent whose `os_version.platform` equals `distributable.platform`. There is no placement table. The next `Programs` sync is what moves the version the dialog shows.
- 🔷 **Distribute** on a row opens a dialog. The dialog lists agents of that platform. For `windows`, each row is a Windows agent plus the `programs.version` for this `name` when one exists. No `programs` row means it is not installed, and the version cell is empty. A search box filters the list by machine name.
- 🔷 Machines that already have this `name` start ticked. That is the update. A machine with no copy starts clear, and the user can tick it to install. **Select all** ticks every machine currently listed. The user can clear a ticked machine.
- 🔷 The version cell is the installed `programs.version` next to the version this dialog will send (the latest on the grid), so a machine already on that version is visible before the task is created.
- 🔷 Confirm creates one task. The targets are the ticked machines. The command is that installer run with `/S`. The task stores a reference to the distributable version file, so the agent downloads that file on the download socket and then runs it.
- 🔷 `task` gains that reference. `script_id` stays for library scripts. `command` stays the line that runs after the file is on the machine.
- 💩 The column name on `task` (`distributable_version.id`). The agent needs the file id.
- 💩 Empty selection. Confirm stays disabled until one machine is ticked.
- 🚫 The dialog does not offer a pick-list of older versions. It sends the version the grid is showing. Do not write a "distributed to" row when the task is queued. `programs` is the record after the install.
