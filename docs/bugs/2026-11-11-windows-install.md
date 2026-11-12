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

- ✔️ `packaging/windows/argusrm-agent.nsi` creates the service as `argus-agent`, removes a leftover `ArgusAgent` service, and names the shortcut Argus Agent.
- 🔷 Starting the service did not open the registration window. `.onInstSuccess` starts `argus-tray.exe` when the installer finishes.
- ✔️ `scripts/ci/windows-package-nsis.sh` sets the tray copy to the windows subsystem. `argus-agent.exe` stays a console program.
- ✔️ `controller/dialog/Pairing.vala` sets `selectable` on the PIN label and leaves it unfocused, so the digits are not shown selected.
- ✔️ The tray writes the window's `host:port` with the PIN. The service registers to that address.
- ✔️ From `snappr-win`, `argus-agent.exe --host 192.168.88.132 --port 819 --pin 000000` reached `Register.vala` and stopped with `os-release did not name debian or rpm` (`-32603`). TCP to port 819 succeeded. No certificate was sent. MSYS2 valac does not define `G_OS_WIN32`, so `shared/Register.vala` kept the Linux family.
- ✔️ After `-D G_OS_WIN32`, the same command gets past that check. With registration closed it stops on `Could not connect to 192.168.88.132: Socket I/O timed out`. Port 819 is firewalled until the controller opens a PIN.
- ✔️ A failed attempt writes `client.pem` before the server answers. The tray treated that file as registered and did not open the window. Startup now removes `client.pem`, `client-key.pem`, and `client.csr` when `ollmrpc-ca.pem` is absent.
- 🔷 The window came up and the PIN still failed. The server log had the offer and no registration connection. The tray closed the pipe when a peek failed, so the service never called `Register`. A broken pipe is the only peek that closes it now, and the service drops an instance that is not listening.

## Next

- 🔷 ⏳ Install `ArgusAgent-0.1.4-Setup.exe`. The registration window title ends in 0.1.4.
