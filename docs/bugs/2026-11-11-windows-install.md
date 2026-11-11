# Windows install does not open the agent

**Status:** ⏳ install and PIN copy are in the tree — discovery and registration are still open

**Pointer:** `docs/bug-fix-process.md`

**Seen:** `ArgusAgent-0.1.3-Setup.exe` on a Windows machine, 2026-11-11.

---

## Problem

- 🔷 The installer finishes and nothing happens.
- 🔷 The agent is not in the Start menu under Argus Agent. The entry there is named Register this machine.
- 🔷 Starting that entry opens a console, then the registration window.
- 🔷 Registration did not finish. The window did not find the server. The two machines were on different networks.
- 🔷 Discovery sat there for a long time.
- 🔷 The number shown on the controller cannot be copied.

## Evidence

- ✔️ `packaging/windows/argusrm-agent.nsi` creates the service, then a shortcut. It never starts `argus-tray.exe`.
- ✔️ The shortcut target is `argus-tray.exe`. The link name is `Register this machine.lnk`.
- ✔️ `sc create` uses the service name `ArgusAgent`. `agent/Win32/Service.vala` registers `argus-agent` with `StartServiceCtrlDispatcherW`. Those names do not match, so the service does not enter `service_main` and does not start the tray.
- ✔️ `argus-tray.exe` is a copy of `argus-agent.exe`. `agent/meson.build` links that executable with the console subsystem. Windows opens a console for it.
- ✔️ `shared/windows/Browse.vala` sets `none` only when `DnsServiceBrowse` fails. A quiet network leaves the result empty, so `RegisterWindow` stays on “Looking for a management server…”.
- ✔️ A typed address is checked again every 20 seconds (`RegisterWindow.on_wait`). The pipe to the service carries the six digits and not that address. The service then waits on its own browse.
- ✔️ `controller/dialog/Pairing.vala` shows the six digits on a `Gtk.Label` with class `pairing-pin`. `selectable` is not set. The server command on the agent window is a label with `selectable = true`.

## Root cause

- ✔️ The installer leaves startup to a service whose registered name is not the name it created, and it points the Start menu at a console build named Register this machine.

## Proposed fix

- 🔷 `sc create` uses `argus-agent`, the name `Service` registers.
- 🔷 The shortcut is `Argus Agent.lnk`. The finish step starts `argus-tray.exe` in the signed-in session.
- 🔷 `argus-tray.exe` is linked with the windows subsystem. `argus-agent.exe` stays a console program so a command-line launch still has a console.
- 🔷 The controller PIN label is selectable, the same way the agent window’s server command is.
- 💩 ⏳ Discovery and the failed registration stay open. The broadcast does not cross networks, and the window does not give up while browse stays empty.

## Attempts

- ✔️ `packaging/windows/argusrm-agent.nsi` creates the service as `argus-agent`, removes a leftover `ArgusAgent` service, and names the shortcut Argus Agent. `sc start` is what opens the window: the service starts `argus-tray.exe` in the signed-in session.
- ✔️ `scripts/ci/windows-package-nsis.sh` sets the tray copy to the windows subsystem. `argus-agent.exe` stays a console program.
- ✔️ `controller/dialog/Pairing.vala` sets `selectable` on the PIN label.

## Next

- 🔷 ⏳ Install `ArgusAgent-0.1.3-Setup.exe` again. The registration window is open when the installer closes. Start → Argus Agent opens that window with no console.
