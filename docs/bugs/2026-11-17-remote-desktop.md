# Remote desktop from the machine General tab

**Status:** ⏳ critical — Phase 1 proved a framed relay to `ACTIVATED`. Phases 2–4 still wait for approval. Phase 5 waits until Windows works.

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md`, archived plan [5.12-MOVED-remote-desktop.md](../plans/done/5.12-MOVED-remote-desktop.md), [2026-11-17-FIXED-windows-command-session-job.md](done/2026-11-17-FIXED-windows-command-session-job.md), [2026-11-16-FIXED-windows-uninstall-task-queue.md](done/2026-11-16-FIXED-windows-uninstall-task-queue.md), [`controller/tab/Asset/Machine/General.vala`](../../controller/tab/Asset/Machine/General.vala), [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala), [`server/Net/Download.vala`](../../server/Net/Download.vala)

---

## Problem

- 🔷 Scripted Windows uninstalls are not a reliable way to finish the job. A task can start on the signed-in desktop and still be a window nobody is there to click. The person has to be at that desktop.
- 🔷 **Expected:** a **Connect to desktop** button on the machine General tab. It opens visual remote control of that machine. Argus turns Windows Remote Desktop on, and tunnels those protocol bytes to a viewer on the controller.
- 🔷 **Actual:** no button, the agent does not enable Remote Desktop, and there is no product tunnel. The only path onto the machine is a task command.

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
- ℹ️ The download socket is the precedent for a second listen: the same client certificate, and a transfer there does not clog the app socket. `server/Net/Download.vala`.
- ℹ️ `Application.open_connection` keeps one `TlsClient`, and `watch` reads frames for the life of it.

---

## Root cause

- ✔️ There is no remote-desktop path. A task command cannot stand in for one when the work is a window on that machine.

---

## Phases

- ✔️ **Phase 1 — Relay proof.** A FreeRDP session crosses the existing RPC stack. Test binaries only.
- 🔷 ⏳ **Phase 2 — Product relay.** The server listen, the agent tunnel, and the controller tunnel. Not the app socket.
- 🔷 ⏳ **Phase 3 — Enable Windows Remote Desktop.** The agent turns the service on for that machine. Pro, Enterprise, Education, and Server. Not Home.
- 🔷 ⏳ **Phase 4 — Viewer.** The General-tab button, the desktop window, and on Android a page with navigation back to the main page.
- 💩 ⏳ **Phase 5 — Linux desktops.** After Windows works. GNOME Remote Desktop and xrdp speak this protocol.

Phase 2 needs an approval before code, because a new listen and a second connection are an API and security change. Phase 3 needs the same approval before the agent changes the Windows service.

---

## Phase 1 — Relay proof

- ✔️ `meson test -C build rdp-relay` passed. The desk log contains `ACTIVATED` and the test prints `ok rdp relay activated`. Needs `freerdp3`, `freerdp-server3`, `winpr3`, and `sdl-freerdp3`.
- ✔️ The path is `Argus.Agent.Rdp.Desk` (FreeRDP listener on `127.0.0.1`) ← `Argus.Agent.Rdp.Tunnel` (dials that port, joins as `agent`) ← `Argus.Server.Rdp.Relay` (`Relay.write` chunks become `relay.data`) ← `Argus.Controller.Rdp.Viewer` (joins as `view`, accepts sdl-freerdp3 on a loopback port).
- ✔️ Those classes are compiled into `argus-rdp-desk` and `argus-rdp-relay-test` from the top-level `meson.build`. They are not linked into the agent, the server, or the controller.
- ✔️ The bytes are framed `ay` chunks on `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`. `Relay.join` and `Relay.write` exist only inside the test process. They are not in `docs/rpc-commands.md`.
- ℹ️ The stand-in desk turns NLA off and accepts any logon, so the Linux listener can finish without a Windows account. Phase 3 does not copy that. Network Level Authentication stays on for TermService.
- ℹ️ sdl-freerdp3 ran with `+auth-only`. It did not open a window. `ACTIVATED` is FreeRDP finishing the connection sequence, not a person looking at a desktop.
- ℹ️ Raw bytes after the certificate match are not proved. `TlsClient` keeps the TLS stream private. The connection sequence, including RDP's own TLS, finished on the framed path. Phase 2 still has to choose.
- 🚫 A hand-rolled C Gio TLS splice. The probe is Vala and uses the existing RPC types.
- 🚫 sdl-freerdp3 inside a GTK 4 widget. It is a separate SDL window. Phase 4 paints with `libfreerdp-client`.

---

## Phase 2 — Product relay

- 🔷 The Remote Desktop protocol bytes, not a second remote-desktop product.
- 🔷 The relay has its own listen socket. It is not the app socket, the download socket, or the registration socket.
- 🔷 The agent opens a second connection to that socket, with the client certificate it already has. The app connection stays up.
- 🔷 The controller opens a second connection to the same socket. The server splices the two.
- 🔷 After the server has matched that certificate, the new connection is switched to raw bytes and stays the transport until the session ends.
- 💩 ⏳ The test proved framed `Relay.write` / `relay.data`, not raw bytes. `TlsClient` does not expose the stream. Keep the framed path, or add a way to hand the stream over after the certificate match.
- ℹ️ The agent dials out, the same way it dials the app socket, so the machine does not accept a new inbound port.
- ℹ️ A short notification on the app socket tells the agent to open the second connection. The desktop bytes do not travel on that notification.
- ℹ️ The session ends when the viewer closes, and when either relay connection drops. Phase 4 is what closes the viewer.
- ℹ️ The new port sits on the same allowlist as the app socket, or the agent cannot dial it.
- 🔷 A new or changed `Request.add_class` method is written into `docs/rpc-commands.md` in the same change.

---

## Phase 3 — Enable Windows Remote Desktop

- 🔷 Turn incoming Remote Desktop on for that machine.
- ℹ️ The switch Windows already has: `fDenyTSConnections` = `0` under `HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server`, `TermService` set to start and started.
- ℹ️ Feasible on Windows Pro, Enterprise, Education, and Server. The service account can make that change.
- ℹ️ Not feasible on Windows Home. That edition has no supported way to accept an incoming Remote Desktop session.
- 🔷 Leave Network Level Authentication on. Argus does not store the Windows password.
- ℹ️ One interactive session on a client Windows edition takes the console. The person sitting at the machine is signed out of it.
- 💩 ⏳ The tunnel only needs the service listening on localhost. Opening 3389 on the LAN is a separate choice. Default is leave the firewall group "Remote Desktop" closed, so the only client is the Argus tunnel.
- 🚫 Do not patch `termsrv.dll` or otherwise unlock Remote Desktop on Windows Home.

---

## Phase 4 — Viewer

- 🔷 FreeRDP is the viewer. It asks for the Windows password. No drive redirection.
- 🔷 Clipboard sharing can wait. It is not required to see and control the desktop.
- 🔷 Audio is not part of this bug.
- 🔷 The button is on the General tab of one machine. Not on the machine list. Not on Agents. Label: Connect to desktop.
- 🔷 On the desktop controller it opens another window. It does not replace the General tab.
- 🔷 On Android the viewer is a page in the same window. Navigation on that page goes back to the main page, and that leaves the desktop session.
- 💩 ⏳ The button sits on a bar that belongs to the General page, above the key-value list. Not in the window header bar.
- 💩 ⏳ The button is shown when `os_version.platform` is `windows` and the edition can host Remote Desktop. Home gets a notice.
- ℹ️ A desktop inside the controller window links `libfreerdp-client` and paints into GTK. The localhost port from Phase 2 is the socket that viewer reads.

---

## Phase 5 — Linux desktops

- 💩 ⏳ After Windows works. GNOME Remote Desktop and xrdp speak this protocol, so the same tunnel could reach them. Nothing in Phases 2–4 turns a Linux service on.

---

## Attempts / changelog

- ✔️ 2026-11-17: First probe was a C Gio TLS splice under `/tmp`. Rejected. The proof has to be Vala and has to use `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`.
- ✔️ 2026-11-17: The probe moved into the repo test tree. `server/vapi/freerdp.vapi` replaced the C desk. `server/tests/rdp-desk.c` is gone.
- ✔️ 2026-11-17: The desk, the tunnel, the relay, and the viewer are separate classes. `server/tests/rdp-relay.vala` only starts them and waits for `ACTIVATED`. `meson test -C build rdp-relay` passed.
- ✔️ 2026-11-17: "The Android controller does not get this button" was an inference. It is removed. Android shows the viewer in the same window, with navigation back to the main page.
- ✔️ 2026-11-17: The spec is split into the five phases above. Each phase holds the requirements for that slice.

## Next

- ⏳ 🔷 Approve Phase 2 and Phase 3 before product code. Phase 4 follows those two.
- ⏳ 💩 Phase 2 still needs the framed-or-raw choice.

## LLM notes

- 🚫 Do not patch `termsrv.dll` or otherwise unlock Remote Desktop on Windows Home.
- 🚫 Do not turn Network Level Authentication off.
- 🚫 Do not put the desktop bytes on `agent.run` or the command log files.
- 🚫 Do not switch `Application.connection` to raw bytes. The relay is a second `TlsClient` to the relay socket.
- 🚫 Do not add drive redirection.
- 🚫 Do not put the button in the window header bar.
- 🚫 Do not hide the button on Android.
