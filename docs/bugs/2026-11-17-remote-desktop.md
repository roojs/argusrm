# Remote desktop from the machine General tab

**Status:** ⏳ critical — Phases 1–4 are signed off. The Windows agent can turn Remote Desktop on and ask at the tray. Phase 4's stream rules are signed off. Building that stream, Force, and the Disconnect notice are Phase 6.5. The viewer is Phase 5. Phase 7 waits until Windows works.

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

- ✔️ **Phase 1 — Relay proof.** Framed RPC carried a FreeRDP session. Test binaries only.
- ✔️ **Phase 2 — Second connection, same port.** No other port and no other listener. The server registers `Relay.join` and `Relay.write`. The proof still uses the test listen.
- ✔️ **Phase 3 — Enable Windows Remote Desktop.** Edition check, logged-in check, and the tray balloon are in. The button is Phase 5.
- ✅ **Phase 4 — Start the flow.** Signed off. The agent streams. The server tells the controller. Bytes are dropped until the controller connects, then forwarded from the start of a connection. A late controller gets a new connection from the first byte.
- 🔷 ⏳ **Phase 5 — Viewer.** The General-tab button and the desktop window.
- 🔷 ⏳ **Phase 6 — Parked connections.** The X leaves the desktop running. **RDP connections** under Assets opens it again.
- 🔷 ⏳ **Phase 6.5 — Takeover edges.** Build the Phase 4 stream. Force. The tray names who has the screen and can disconnect.
- 💩 ⏳ **Phase 7 — Linux desktops.** After Windows works. GNOME Remote Desktop and xrdp speak this protocol.

Phase 2 adds no port and no listener.

---

## Phase 1 — Relay proof

- ✔️ `meson test -C build rdp-relay` passed. The desk log contains `ACTIVATED` and the test prints `ok rdp relay activated`. Needs `freerdp3`, `freerdp-server3`, `winpr3`, and `sdl-freerdp3`.
- ✔️ The path is `Argus.Agent.Rdp.Desk` (FreeRDP listener on `127.0.0.1`) ← `Argus.Agent.Rdp.Tunnel` (dials that port, joins as `agent`) ← `Argus.Server.Rdp.Relay` (`Relay.write` chunks become `relay.data`) ← `Argus.Controller.Rdp.Viewer` (joins as `view`, accepts sdl-freerdp3 on a loopback port).
- ✔️ Those classes are compiled into `argus-rdp-desk` and `argus-rdp-relay-test` from the top-level `meson.build`. They are not linked into the agent, the server, or the controller.
- ✔️ The bytes are framed `ay` chunks on `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`. `Relay.join` and `Relay.write` exist only inside the test process. They are not in `docs/rpc-commands.md`.
- ℹ️ The stand-in desk turns NLA off and accepts any logon, so the Linux listener can finish without a Windows account. Phase 3 does not copy that. Network Level Authentication stays on for TermService.
- ℹ️ sdl-freerdp3 ran with `+auth-only`. It did not open a window. `ACTIVATED` is FreeRDP finishing the connection sequence, not a person looking at a desktop.
- ✔️ 2026-11-18: the same listen also answers `App.ping` on the first connection while the second connection streams. After `joined view` the log still has `app pong`, then `ACTIVATED`. `meson test -C build rdp-relay` prints `ok app rpc during stream`.
- 🚫 A hand-rolled C Gio TLS splice. The probe is Vala and uses the existing RPC types.
- 🚫 sdl-freerdp3 inside a GTK 4 widget. It is a separate SDL window. Phase 5 paints with `libfreerdp-client`.

---

## Phase 2 — Second connection, same port

- 🔷 The desktop is another connection to the port that is already listening. No other port. No other listener.
- 🔷 The first connection stays the app session. It is not switched to raw bytes. The desktop bytes are not `agent.run`.
- 🔷 An RPC on the second connection turns streaming on. The bytes are the Remote Desktop protocol, not a second remote-desktop product.
- ✔️ One listen, one port. The first connection calls `App.ping` and does not join the stream. The agent and the viewer open further connections to that same port and `Relay.join` turns streaming on. `App.ping` still replies after `joined view`, and the desk reaches `ACTIVATED`.
- ℹ️ The listen in the test is the same shape as `server/Net/SslListen.vala`: one `SocketService`, TLS, a client certificate, then `OLLMrpc.Transport.Connection`. The product class is not the one that accepted these connections.
- 🚫 Another listen, or any new port. The download socket stays an HTTPS GET. `server/Net/Download.vala`.
- ℹ️ The agent still dials out. The machine does not accept a new inbound port for this.
- ℹ️ Streaming off is not dropping the desktop. Phase 6 parks the session on the agent and stops the bytes toward the server.
- ℹ️ Phase 2 does not start the stream. The test opens the agent connection itself. Phase 4 is signed off. Phase 6.5 builds it.
- 🔷 A new or changed `Request.add_class` method is written into `docs/rpc-commands.md` in the same change.
- ✔️ The fences are applied. The server calls `Rdp.Relay.rpc_register()` and compiles `Relay.vala`. `listen()` stays the test's listen. The server does not call it.

---

## Phase 3 — Enable Windows Remote Desktop

- 🔷 Show the button only when `supports_rdp()` is true. If it is false, show nothing. The button is Phase 5. It is not built.
- ✔️ The agent does not change Windows when `supports_rdp()` is false.
- ℹ️ The Windows name is `os_version.name`, for example `Microsoft Windows 11 Pro`. No name yet means no.
- ✔️ After startup the Windows agent sets `fDenyTSConnections` to `0`, sets `UserAuthentication` to `1`, and starts `TermService`. The firewall group is left closed.
- 🔷 Leave the Windows password prompt on. Argus does not store the password.
- ✔️ Nobody is logged in: an active Windows session is absent, so Remote Desktop is turned on. No tray question.
- ✔️ Someone is logged in: an active session is present. The service sends `agent.desktop`.
- ✔️ The tray reads the last keyboard or mouse time. Half an hour idle allows Remote Desktop without asking. More recent input shows a balloon. A click allows it. Ignoring the balloon leaves it off.
- ℹ️ The service cannot read that time. It runs in session 0. The tray runs in the signed-in session.
- 🔷 Sign in as the person already logged in. A different account logs them off.
- ℹ️ Force, and the tray notice that names who has the screen, are Phase 6.5.
- ℹ️ A machine that is really asleep has to wake before any of this.
- 🚫 Do not patch Windows to invent a second screen, or to turn this on for Home.

---

## Phase 4 — Start the flow

- ✅ The agent opens the second connection and starts streaming once Remote Desktop is on.
- ✅ The server tells the controller that this machine's stream has started. That notification is not the desktop bytes.
- ✅ Until that controller connects, the server drops the stream bytes.
- ✅ When the controller connects, the server forwards both ways.
- ℹ️ Windows sends nothing until it receives the viewer's opening bytes. The controller's first bytes are the start of the connection.
- ✅ A controller that arrives after a stream is already going does not join the middle. The agent closes that connection to Windows and opens a new one. Forwarding starts at the first byte of the new connection.
- 🚫 The server does not read Remote Desktop messages to find a cut point. The cut is a new connection.
- ℹ️ The build of this, including the notification in `docs/rpc-commands.md`, is Phase 6.5.

---

## Phase 5 — Viewer

- 🔷 FreeRDP is the viewer. It asks for the Windows password. No drive redirection.
- 🔷 Clipboard sharing can wait. It is not required to see and control the desktop.
- 🔷 Audio is not part of this bug.
- 🔷 The button is on the General tab of one machine. Not on the machine list. Not on Agents. Label: Connect to desktop.
- 🔷 On the desktop controller it opens another window. It does not replace the General tab.
- 🔷 On Android the viewer is a page in the same window. Navigation back to the main page parks the session, the same as the X in Phase 6. It does not drop the desktop.
- 💩 ⏳ The button sits on a bar that belongs to the General page, above the key-value list. Not in the window header bar.
- 🔷 The button is shown only when that machine's `OsVersion.supports_rdp()` is true. Unknown and Home show nothing.
- ℹ️ A desktop inside the controller window links `libfreerdp-client` and paints into GTK. The localhost port from Phase 2 is the socket that viewer reads.

---

## Phase 6 — Parked connections

- 🔷 Under Assets on the left bar, a row **RDP connections** shows while any remote desktop is running. The row is hidden when none are. `controller/TabList.vala` lists Assets above Distributables.
- 🔷 The RDP frame has its own bar, the same kind as the terminal emulator: Send keys, Close connection, and an X on the right. That bar belongs to the frame. It is not the application header.
- 🔷 The X does not close the desktop. The agent keeps the RDP session open and keeps talking to it. Streaming to the server is turned off.
- 🔷 Opening that desktop again from **RDP connections** starts the flow again, the same message and notification as Phase 4. The same session carries on. The desktop can keep running while the viewer is away.
- 🔷 Close connection is what drops it. The agent then lets go of the RDP session. The sidebar row hides when the last one is gone.

---

## Phase 6.5 — Takeover edges

- ⏳ 🔷 Build the Phase 4 stream. The agent opens the second connection once Remote Desktop is on. The server tells the controller. Bytes are dropped until the controller connects, then forwarded. A late controller gets a new connection from the first byte.
- ⏳ 🔷 That notification is written into `docs/rpc-commands.md` in the same change.
- ⏳ Not in `meson test -C build rdp-relay`. That test starts the agent and the viewer itself.
- ⏳ 🔷 Force is off unless the operator turns it on.
- ⏳ 🔷 The tray names who from Argus has the screen, and offers Disconnect.
- ℹ️ While a connection is up the PC screen is locked. Signing in at the PC disconnects the remote side. Windows does that. It does not say the Argus name.

---

## Phase 7 — Linux desktops

- 💩 ⏳ After Windows works. GNOME Remote Desktop and xrdp speak this protocol, so the same stream could reach them. Nothing in Phases 2–6 turns a Linux service on.

---

## Attempts / changelog

- ✔️ 2026-11-17: First probe was a C Gio TLS splice under `/tmp`. Rejected. The proof has to be Vala and has to use `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`.
- ✔️ 2026-11-17: The probe moved into the repo test tree. `server/vapi/freerdp.vapi` replaced the C desk. `server/tests/rdp-desk.c` is gone.
- ✔️ 2026-11-17: The desk, the tunnel, the relay, and the viewer are separate classes. `server/tests/rdp-relay.vala` only starts them and waits for `ACTIVATED`. `meson test -C build rdp-relay` passed.
- ✔️ 2026-11-17: "The Android controller does not get this button" was an inference. It is removed. Android shows the viewer in the same window, with navigation back to the main page.
- ✔️ 2026-11-17: The spec is split into phases. Each phase holds the requirements for that slice.
- ✔️ 2026-11-18: A second listen was an assumption, not a result. The design is another connection to the port already listening. Phase 5 is the parked desktop: the X stops streaming, Close connection drops the session, and **RDP connections** under Assets opens it again.
- ✔️ 2026-11-18: `App.ping` on the first connection kept replying after the second connection joined the stream. The test prints `ok app rpc during stream`.
- ✔️ 2026-11-18: The controller message starts the flow. The server notifies the agent, and that notification is what makes the agent open the second connection. This is Phase 4, before the viewer. The test does not do it.
- ✔️ 2026-11-18: `SslListen.by_id` is the connection for one agent id. `Command.dispatch`, `Agent.list`, `Agent.remove`, and the task list use it. `broadcast` still walks `connections` because that send goes to every connection.
- ✔️ 2026-11-18: Phase 2 fences now include the `join()` and `write()` bodies. `write()` in that fence does not use a ternary. The fences are not applied.
- ✔️ 2026-11-18: Phase 2 fences are applied. `Application.command_line` calls `Rdp.Relay.rpc_register()`. `Relay.join` and `Relay.write` are in `docs/rpc-commands.md`. `listen()` is still only the test.
- ✔️ 2026-11-18: Phase 2 fences are removed from this bug. Phase 3 proposes `OsVersion.supports_rdp()`. Unknown and Home are not offered. A client edition has no supported second session. The service is not changed.
- ✔️ 2026-11-18: Connect when nobody is logged in, or when the screen is locked or idle, as that same user. If someone is at the PC, the tray asks first. Force is off unless the operator turns it on. A different account logs them off.
- ✔️ 2026-11-18: The tray names who has the screen and can disconnect. The person at the locked PC gets the screen back by signing in. Windows does that itself.
- ✔️ 2026-11-18: `OsVersion.supports_rdp()` is in. After startup the Windows agent turns Remote Desktop on only when that is true, and leaves the password prompt on. Home and an unknown name do nothing. The button and the tray ask are not built.
- ✔️ 2026-11-18: An active Windows session means someone is logged in. The tray asks before Remote Desktop is turned on. Allow turns it on. No leaves it off. Nobody logged in skips the question. Force, Disconnect, and the connection are not built. Lock versus a person at the keyboard is not detected.
- ✔️ 2026-11-18: The tray allows Remote Desktop without asking when the keyboard and mouse have been idle for half an hour. The service cannot see that time.
- ✔️ 2026-11-18: When the agent streams, the server tells the controller and drops the bytes until the controller connects. A late controller gets a new connection from the first byte. The server does not parse Remote Desktop.
- ✔️ 2026-11-18: The tray ask is a balloon, the same call Snappr uses. A click allows Remote Desktop. Ignoring the balloon leaves it off.
- ✅ 2026-11-18: Phase 4 is signed off. The agent streams, the server tells the controller, and bytes are dropped until the controller connects. A late controller gets a new connection from the first byte. Building that, Force, and the Disconnect notice are Phase 6.5.

## Next

- ⏳ 🔷 Phase 5 is the viewer: the General-tab button and the desktop window.
- ⏳ 🔷 Phase 6.5 builds the stream, Force, and the tray notice that names who has the screen.
- ⏳ 💩 The proof listen is still `Relay.listen`. Phase 2 does not move it into `SslListen`.

## LLM notes

- 🚫 Do not patch `termsrv.dll` to add a session, or to unlock Remote Desktop on Windows Home.
- 🚫 Do not turn Network Level Authentication off.
- 🚫 Do not put the desktop bytes on `agent.run` or the command log files.
- 🚫 Do not switch `Application.connection` to raw bytes. The desktop is a second connection to the same port.
- 🚫 Do not add a listener, and do not open another port.
- 🚫 Do not add drive redirection.
- 🚫 Do not put the button in the window header bar.
- 🚫 Do not hide the button on Android.
