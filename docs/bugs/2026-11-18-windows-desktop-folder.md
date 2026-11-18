# Desktop folder whose files live on the server

**Status:** ⏳ feasibility only. Phase 1 is a Windows test that creates the folder and its backing folder from a pretend tree. No connection in that test. Login, sync, and the change store come after.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [2026-11-17-remote-desktop.md](2026-11-17-remote-desktop.md), [`tests/`](../../tests/), [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala), [`agent/Win32/tray/Tray.vala`](../../agent/Win32/tray/Tray.vala)

---

## Problem

- 🔷 While the agent is running, the signed-in desktop has a folder named `Argus RM`.
- 🔷 The person uses it like any other folder. Explorer lists it. A double-click on a Word document opens Word.
- 🔷 Whichever way the folder is faked, we keep a backing folder on the desktop. Word and the other programs do their day-to-day read and write there.
- 🔷 That backing folder syncs up to the server out of band, within a few seconds of a change. The write does not wait for the sync. There is no lag on the write.
- 🔷 The share is not the agent's app socket. It listens on its own port. That port carries two connections. One is RPC for ordinary calls. The other is file access. File bytes do not travel as RPC on the first connection.
- 🔷 The person logs in before the folder can be used. The server checks that login. The first check is PAM, on the server. The check it grows into is a Samba server on that same machine.
- 🔷 The person cannot delete the folder. The person can rename it. After a rename it is still our folder.
- 🔷 **Actual:** there is no folder, and nothing in the tree serves a directory over RPC.

---

## What this bug is for

- 🔷 The first half is whether that folder can exist, and what it takes. A filesystem driver is one possibility. It is not assumed.
- 🔷 The work is phased. Phase 1 is the folder. The connection and the sync are later phases.
- 🔷 Every phase stays out of band. The code lives in the top-level `tests/` directory. It is not an agent test, and it is not linked into the installed agent or the installed server.
- 🔷 This may leave the agent later and become its own piece. This bug does not do that split.
- 🔷 A design that sends each write to the server before the write returns does not meet the backing folder. The write has to finish locally.

---

## Phases

- 🔷 ⏳ **Phase 1 — The folder.** A Windows test. It creates the fake folder and the backing folder. The folders inside come from a pretend server tree. No connection. No data sent.
- 🔷 ⏳ **Phase 2 — The share.** Its own port. Two connections. A login. PAM first, Samba later. Not Phase 1.
- 🔷 ⏳ **Phase 3 — Sync.** On connect, resync the backing-folder placeholders. SQLite stores the data and the changes. A connect sends down the files that changed. It does not send the whole tree. A local write syncs up within a few seconds, and that send is not part of the write.

---

## Evidence

- ✔️ The Windows agent is the service in `agent/Win32/Service.vala`. It already holds a TLS session to the server. It runs in session 0. It has no desktop.
- ✔️ The tray in `agent/Win32/tray/Tray.vala` runs in the signed-in session. The service starts it at sign-in. That is the process that can see the desktop.
- ✔️ Test programs stay uninstalled. The agent ones live in top-level `tests/`. `agent/` is the program. `tests/meson.build` builds them. The top-level `meson.build` only includes that directory. The remote-desktop proof is the same shape: `server/tests/rdp-relay.vala` and the classes it compiles, registered only inside that process, not in `docs/rpc-commands.md`.
- ℹ️ A new product `Request.add_class` method is written into `docs/rpc-commands.md` in the same change. A method that exists only inside a phase test is not a product call.
- ℹ️ Phase 1 runs on Windows. `agent/meson.build` builds the agent when `host_machine.system() == 'windows'`. This Linux tree does not create the folder.
- ℹ️ The server already stores rows in SQLite through `libocsqlite`. `server/Application.vala` opens `argus.sqlite`. Nothing in that file records a share's file changes.
- ✔️ The server already listens on three ports: `Argus.SOCKET_PORT` (the app socket), `Argus.DOWNLOAD_PORT` (HTTPS GET), and `Argus.REGISTER_PORT`. `server/Application.vala` binds those three. None of them is a place a person logs in with a PAM or Samba account.
- ℹ️ Remote desktop refused a new port on purpose. That refusal stays in [2026-11-17-remote-desktop.md](2026-11-17-remote-desktop.md). It does not apply to this share.
- 🚫 No call in `docs/rpc-commands.md` lists or reads a file. Nothing in the tree calls PAM or Samba.

---

## Root cause

- ✔️ Nothing projects a server directory into a Windows folder. There is no defect in an existing path to repair.

---

## Phase 1 — The folder

- 🔷 A test that runs on Windows. It creates the fake folder and the backing folder.
- 🔷 The folders it creates come from a pretend server tree. That tree stands in for the server. The test does not connect, and it does not send file data.
- 🔷 The pass mark is that those pretend folders show up, with the backing folder in place.
- 💩 The pretend tree is a directory on that Windows machine. The test is given the path. It is not a listen.
- 🔷 The proof's code and its build stay in top-level `tests/`. The agent build does not see it, and it is not installed.
- 🚫 A server process, a port, PAM, Samba, SQLite, or a sync, in this phase.
- 🚫 Linking the test into `argus-agent.exe` to find out if the folder works.

---

## Phase 2 — The share

- 🔷 The share is not the agent's app socket. It listens on its own port. That port carries two connections. One is RPC for ordinary calls. The other is file access. File bytes do not travel as RPC on the first connection.
- 🔷 The person logs in before the folder can be used. The server checks that login. The first check is PAM, on the server. The check it grows into is a Samba server on that same machine.
- 🔷 The proof may use the existing RPC library. It does not dial the app socket, the download socket, or the registration socket.
- 💩 The login call is on the RPC connection. The file connection is refused until that login has succeeded. The password is not sent on the file connection.
- 💩 The Windows program runs in the signed-in session, next to the tray, because session 0 has no desktop.
- 🚫 Phase 1 does not dial this port.

---

## Phase 3 — Sync

- 🔷 On connect, resync the placeholders in the backing folder.
- 🔷 SQLite stores the data and the changes. A connect sends down the files that changed. It does not send the whole tree every time.
- 🔷 After a local change, the backing folder syncs up on the file connection, within a few seconds. That send is not part of the write.
- 🚫 A full dump of every file on each connect.
- 💩 The change database is a new file on the server. It is not `argus.sqlite`.
- 💩 What starts the few seconds. A quiet gap after the last write is the stand-in. Close, and Word letting go of the file, are not ruled in.

---

## Ways the folder can be fake

How the folder is faked is still open. The constraint on that choice is the backing folder.

- 🔷 We keep a backing folder on the desktop. Day-to-day read and write go there. The server is not on that path.
- 🔷 After a change, the backing folder syncs up on the share's file connection, within a few seconds. That send is not part of the write.
- 🚫 A filesystem that holds the write until the server has the bytes.
- 💩 A normal directory we create, watch, and sync. It still has to refuse a delete and keep owning the folder after a rename.
- 💩 **Cloud Files API** (`cfapi`, the filter Windows already ships for OneDrive). Placeholders can stand for files that are not in the backing folder yet. A write still lands in the backing folder, and the upload is the later sync. We do not ship a driver.
- 💩 **Projected File System** (`ProjFS`, also shipped with Windows). Enumeration can be a callback. A write still has to finish in the backing folder. Some editions leave the feature turned off until it is enabled.
- 💩 **A shell namespace extension.** Explorer can show a folder that is not itself the backing folder. Word still has to read and write the backing folder.
- 💩 **A user-mode filesystem** (WinFsp or Dokan). Only if the write finishes in the backing folder and the server sync stays the later step. This is a driver we would have to install.
- ℹ️ Renaming a directory on NTFS uses the same permission as deleting it. An access mask that denies delete also denies rename. "Cannot delete, can rename" will not be a single deny ACE. The proof has to show which mechanism holds the folder (a callback that refuses the delete, the folder coming back, or something else) while a rename sticks.

---

## Left open

- 🔷 ⏳ Deleting a file inside the folder, and what happens when the share is not connected. Not Phase 1.
- 🔷 ⏳ The port number. It is a new listen. It is not `SOCKET_PORT`, `DOWNLOAD_PORT`, or `REGISTER_PORT`. Phase 2.
- 🔷 ⏳ What the RPC connection carries besides the login and the calls that are not file bytes. Phase 2.
- 🔷 ⏳ The columns in the change store. Phase 3 says it is SQLite and that it records data and changes. The rows are not chosen.
- 💩 ⏳ How the person is asked for the username and password. Phase 2 needs a login. A product dialog is not part of that phase.
- 💩 ⏳ Which desktop, when more than one person is signed in. Each person logs in as themselves.
- 💩 ⏳ The name `Argus RM` is the name we create. Where we store the name after the person renames it.
- 💩 ⏳ When the Samba check replaces PAM, and whether a Samba login is the same username and password Phase 2 already sent.
