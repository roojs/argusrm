# Remote desktop from the machine General tab

**Status:** ⏳ critical — nothing is written. Feasibility is already settled. Enabling the service and the byte tunnel are a design, API, and security change, so they wait for approval before any code.

**Pointer:** `docs/bug-fix-process.md`, archived plan [5.12-MOVED-remote-desktop.md](../plans/done/5.12-MOVED-remote-desktop.md), [2026-11-17-FIXED-windows-command-session-job.md](done/2026-11-17-FIXED-windows-command-session-job.md), [2026-11-16-FIXED-windows-uninstall-task-queue.md](done/2026-11-16-FIXED-windows-uninstall-task-queue.md), [`controller/tab/Asset/Machine/General.vala`](../../controller/tab/Asset/Machine/General.vala), [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala), [`server/Net/Download.vala`](../../server/Net/Download.vala)

---

## Problem

- 🔷 Scripted Windows uninstalls are not a reliable way to finish the job. A task can start on the signed-in desktop and still be a window nobody is there to click. The person has to be at that desktop.
- 🔷 **Expected:** a **Connect to desktop** button on the machine General tab. It opens another window that is visual remote control of that machine. Argus turns Windows Remote Desktop on, and tunnels those protocol bytes to a Linux viewer on the controller.
- 🔷 **Actual:** no button, the agent does not enable Remote Desktop, and there is no tunnel. The only path onto the machine is a task command.

---

## Why this left the plan

- 🔷 [5.12](../plans/done/5.12-MOVED-remote-desktop.md) was feasibility only, and it waited. It is this bug because the uninstall work still leaves machines that need a person on the desktop.
- ℹ️ [2026-11-17-FIXED-windows-command-session-job.md](done/2026-11-17-FIXED-windows-command-session-job.md) starts the command on the signed-in desktop and waits for the process tree. That does not click a wizard. The Illustrator run in that log is the case: the launcher exited, and `Set-up.exe` sat on a lock.
- ℹ️ [2026-11-16-FIXED-windows-uninstall-task-queue.md](done/2026-11-16-FIXED-windows-uninstall-task-queue.md) rewrites `msiexec /I` to a silent `/X … /qn /norestart`. An uninstaller that is not `msiexec`, or that ignores the quiet flags, still opens a window on a desktop the controller cannot see.

---

## Evidence

- ✔️ The General tab is `controller/tab/Asset/Machine/General.vala`, inside `controller/tab/Asset/Machine/Detail.vala`. General is a vertical list of expanders. It has no bar of its own. `Detail` has the tab toggles. The window header bar is the title only.
- ✔️ The controller is GTK 4 and libadwaita. `controller/meson.build`.
- ✔️ The Windows agent is the service in `agent/Win32/Service.vala`. It already holds a TLS session to the server. Nothing in the tree sets `fDenyTSConnections`, starts `TermService`, or speaks Remote Desktop.
- ℹ️ Enabling is feasible on Windows Pro, Enterprise, Education, and Server. The service account can set `fDenyTSConnections` to `0` under `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server`, start Remote Desktop Services, and open the firewall group.
- ℹ️ Enabling is not feasible on Windows Home. That edition has no supported way to accept an incoming Remote Desktop session.
- ℹ️ Remote Desktop is a two-way TCP byte stream on port 3389. The agent can open `127.0.0.1:3389` and carry those bytes on a second connection. The app socket stays the RPC session. `Application.open_connection` keeps one `TlsClient`, and `watch` reads frames for the life of it.
- ℹ️ The download socket is the precedent: a separate listen, the same client certificate, and a transfer there does not clog the app socket. `server/Net/Download.vala`.
- ℹ️ The person at the controller still signs in as a Windows user. Network Level Authentication stays on. Argus does not store the password. One interactive session on a client Windows edition takes the console, and the person sitting at the machine is signed out of it.

---

## Root cause

- ✔️ There is no remote-desktop path. A task command cannot stand in for one when the work is a window on that machine.

---

## What Argus enables

- 🔷 Turn incoming Remote Desktop on for that machine.
- ℹ️ The switch Windows already has: `fDenyTSConnections` = `0`, `TermService` set to start and started, and the firewall group "Remote Desktop" (TCP 3389 to the LAN).
- 💩 ⏳ Leave Network Level Authentication on.
- 💩 ⏳ The tunnel only needs the service listening on localhost. Opening 3389 on the LAN is a separate choice. Default is leave the LAN rule closed, so the only client is the Argus tunnel.

---

## What Argus tunnels

- 🔷 The Remote Desktop protocol bytes, not a second remote-desktop product.
- 🔷 The relay has its own listen socket. It is not the app socket, the download socket, or the registration socket.
- 🔷 The agent opens a second connection to that socket, with the client certificate it already has. The app connection stays up.
- 🔷 After the server has matched that certificate, the new connection is switched to raw bytes and stays the transport until the window closes.
- 🔷 The controller opens a second connection to the same socket. The server splices the two. FreeRDP talks to a localhost port on the controller, and that port is the controller's end of the splice.
- ℹ️ The agent dials out, the same way it dials the app socket, so the machine does not accept a new inbound port.
- ℹ️ A short notification on the app socket tells the agent to open the second connection. The desktop bytes do not travel on that notification.
- ℹ️ The session ends when the window closes, and when either relay connection drops.
- ℹ️ The new port sits on the same allowlist as the app socket, or the agent cannot dial it.
- 🔷 FreeRDP is the viewer. It asks for the Windows password.
- 🔷 No drive redirection.
- 🔷 Clipboard sharing can wait. It is not required to see and control the desktop.
- 🔷 Audio is not part of this bug.

---

## Where the button sits

- 🔷 On the General tab of one machine. Not on the machine list. Not on Agents.
- 🔷 Label: Connect to desktop.
- 🔷 It opens another window. It does not replace the General tab.
- 💩 ⏳ The button sits on a bar that belongs to the General page, above the key-value list.
- 💩 ⏳ The button is shown when `os_version.platform` is `windows` and the edition can host Remote Desktop. Home gets a notice.

---

## Open before any code

- 🔷 ⏳ Approve enabling the service and adding the byte tunnel. Both are feasible. Neither is written.
- 💩 ⏳ LAN firewall stays closed. Only the tunnel connects.
- 💩 ⏳ The Android controller does not get this button.
- 💩 ⏳ Linux machines wait. GNOME Remote Desktop and xrdp speak this protocol, so the same tunnel could reach them after Windows works.

---

## LLM notes

- 🚫 Do not patch `termsrv.dll` or otherwise unlock Remote Desktop on Windows Home.
- 🚫 Do not turn Network Level Authentication off.
- 🚫 Do not put the desktop bytes on `agent.run` or the command log files.
- 🚫 Do not switch `Application.connection` to raw bytes. The relay is a second `TlsClient` to the relay socket.
- 🚫 Do not add drive redirection.
- 🚫 Do not put the button in the window header bar.
