# Changelog

All notable changes to Argus Remote Manager are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release tags use [Semantic Versioning](https://semver.org/).

`CHANGELOG.md` is the source of truth for release notes and Debian/RPM
package changelogs.

## [0.1.45] - Unreleased

### Fixed

- The Windows tray asked the service for status before the management session was up, then kept **Disconnected**. The service now tells the tray when that session connects and when it drops.

## [0.1.44] - Unreleased

### Added

- Windows program rows include the PE file SHA-256 and Authenticode signer when a path resolves: status, certificate thumbprint, subject key id, publisher, issuer, and serial. The agent caches that per path and refreshes it when the file size or modification time changes. Registry publisher is unchanged. The server stores the fields on ``programs``.

### Changed

- The controller PIN command lists each network the registration broadcast is published on. ``Agent.offer`` returns those addresses after the six digits and the public IPv4 address.

## [0.1.43] - Unreleased

### Fixed

- After **log in to local machine**, the controller opens on **127.0.0.1** instead of probing every saved bridge address.
- Controller startup offers **Clear registration and log in** when local enrollment reports *already registered*; it clears saved logins, deregisters the controller row, and issues a new certificate in one flow.
- `Registration.deregister` on the Unix socket with a username removes every controller row for that user on this hostname (not only loopback `ip`), so recovery works after a controller has connected with a routable address.

- Windows in-place upgrades keep ``server.sqlite`` when the service shuts down. The installer ships **OLLMchat** ``v1.4.17`` ``libocsqlite`` (copy-over-delete promote instead of ``rename``), so registration survives NSIS upgrade.

## [0.1.42] - Unreleased

### Fixed

- Windows program inventory uses the osquery ``programs`` table only. The snapshot no longer unions the non-existent ``appx_packages`` table; MSIX rows use ``source`` ``appx`` when ``package_family_name`` is set.

## [0.1.41] - Unreleased

### Fixed

- After enrollment, the agent connects using host names only in the saved address list. ``address_list()`` had stored ``host:port`` lines; Windows ``getaddrinfo`` then failed on strings like ``192.168.88.132:817``.

## [0.1.40] - Unreleased

### Fixed

- Windows tray registration sends ``family`` ``windows``. ``Register.vala`` is built with ``G_OS_WIN32`` on the client library args, not only the server shared args.
- The Windows agent opens ``server.sqlite`` at service startup, same as the Linux agent, so enrollment and the connection loop do not run with a null client database.

## [0.1.39] - Unreleased

### Fixed

- The Windows installer stops the service once, kills tray and agent once, and renames in-use executables instead of retrying ``taskkill`` many times.
- The Windows tray status dialog matches ``Argus.Shared.Notice`` elsewhere: no duplicate Close action; Register appears when the machine is not connected.

## [0.1.38] - Unreleased

### Fixed

- The Windows installer stops the agent and tray in a loop and renames in-use executables before it replaces them, so upgrades no longer hang on a locked ``argus-tray.exe``.

## [0.1.37] - Unreleased

### Changed

- Release bump for Windows install and remote desktop testing.

## [0.1.36] - 2026-11-23

### Added

- Agents report the operating system, Debian packages, RPM packages, and Windows programs from osquery.
- The Assets page has Machines and Software. Machines is a grid of the one-row columns and has no rows. Hidden columns start off. Software is the word Software.
- The controller has a Linux desktop icon from the logo in argusrm.svg.
- Touch and hold the screen button on a Windows machine's General tab to open that desktop.
- The desktop is a page in this window, with an RDP row under Assets and a tab per machine.
- FreeRDP asks for the Windows password. Drives, the clipboard, and audio stay on the machine.
- The Windows agent turns Remote Desktop on when that edition allows it, and asks at the tray when someone is at the keyboard.
- The desktop bytes travel on a second connection. A late join starts from the first byte.
- The Windows agent reports each step while it opens the desktop.
- Meson test `registration-local-login` (root): temp server, real `argusrm-controller --give-me-a-certificate`, Bootstrap JSON, TCP probe, and TLS hello. Unit tests `registration-*` support it but are not a substitute.

### Changed

- A tag release no longer builds or publishes the controller AppImage. That build stays on its manual workflow.
- Window titles include the release version.
- Replace the Windows tray named-pipe protocol with `OLLMrpc` over loopback TCP (`127.0.0.1:4142`) using `OLLMchat` `v1.4.12`.
- The Windows agent turns Remote Desktop on without asking at the tray.
- The Windows agent sends its version when it connects, and it disconnects when the server is older.
- Pin `OLLMchat` to `v1.4.15` for Android CI (`x-android.yml`) and Windows MSYS packages (`OLLMCHAT_RELEASE` in `x-windows.yml`).
- Android builds link `ocrpc` and `ocsqlite` from Pixie only (`check-pixie-only.sh` blocks from-source native libs and non-Pixie jniLibs).
- `scripts/android/fetch-pixie-deps.sh` merges `ocrpc` and `ocsqlite` from OLLMchat `release.pins` with the pixiewood-pkgs sysroot.
- `packaging/android/stage-ollmchat-android-pins.sh` copies GTK IME and webkit Pixie pins from the pinned OLLMchat checkout before each APK build.
- Local controller registration uses the saved server row JSON shape end to end (`SQT.Server` wire, pkexec, and Bootstrap).
- Revamp registration and server connection configuration across agent, controller, and bootstrap flows.

### Fixed

- Debian packages depend on libocrpc1 and libocsqlite1, and RPM packages depend on libocrpc and libocsqlite. Shared-library detection skips both libraries because their SONAMEs have no version.
- Removing a machine from the controller no longer leaves argusrm-agent saying it is already registered. A connected agent drops its certificate when it is removed. A later run asks the server, and a rejected certificate is deleted so registration can continue.
- argusrm-agent --debug shows browse progress. argusrm-server --debug shows when a firewall port is opened or enforced, and when the allowlist changes.
- Windows discovery asks again every two seconds until the management server is advertising. The sixth PIN digit is drawn before registration starts.
- Windows discovery keeps a browse result that arrives after an earlier name whose address never comes back.
- Windows registration sends the certificate request. The variadic argument packer repeated the PIN in every string.
- The Windows service loads the GnuTLS module shipped beside the agent. Without it, registration aborts.
- The Windows installer waits until the service is gone before it creates the service again.
- Registration stores the host it connected to and the download port. The reply does not send the bind address.
- The registration window stays open until the agent is connected to the management server.
- The Windows registration window waits for the Windows service before it looks for the management server.
- The Windows installer creates the service. The previous command line was rejected, so the install removed the service and left it missing.
- The Windows installer kills the running agent and tray before it replaces the service.
- A stored registration the server does not accept is cleared, and the registration window is offered again.
- Start osquery initialization, startup sync, and package monitor on Windows immediately after pairing.
- Fix package snapshot sync instantiating abstract `Package` instead of the concrete `DebPackages`, `RpmPackages`, or `Programs` row type.
- Embed the approved Argus bird icon in Windows executables, tray icon, desktop windows, Start Menu shortcut, and NSIS installer.
- Stop the Windows tray from hanging on "Waiting for the Windows service…" after upgrades by accepting tray RPC connections before background `OSQuery` startup, enforcing single-instance tray execution, and querying service-side registration state.
- Add right-click menu, left-click status dialog, and UAC-elevated service restart to the Windows tray icon.
- Ship GLib's `gspawn-win64-helper.exe` and `gspawn-win64-helper-console.exe` in the Windows installer so `GLib.Subprocess` can launch `msiexec.exe`, `osqueryi.exe`, and remote commands.
- Query and serialize agent package snapshots (`Programs`, `DebPackages`, `RpmPackages`) using the wire-registered `GType` instead of the agent subclass type.
- Send the command line as stdin once a task process has started, so the Tasks pane shows what was run.
- End a Windows task with exit 127 when the process fails to start, instead of leaving it Running.
- Draw the Connected tick again when a machine reconnects.
- After startup sync, end tasks this agent process is not running, so a restarted machine is not left occupied by a task whose child never started.
- Run a Windows task command through GLib's command-line parser and report the process exit code. A quoted path such as the Adobe uninstaller was being escaped and then shown as exit 0.
- A silent Windows task reports `running` every five seconds while its process is alive, and the task ends when that process exits.
- A silent Windows task shows the executable name and its CPU time. A task whose agent connection closes before the command starts is marked failed.
- A Windows task starts on the signed-in desktop and stays running until every process that command started has exited. The exit code is the last of those processes.
- The Windows agent window shows the same version as the installer.
- The Windows agent is built against the RPC library that sends an integer array followed by its length, so a task reaches the machine.
- The Windows agent opens a fresh server connection after a restart, so a desktop request is understood.
- The Windows agent dials the server again as soon as the connection drops, then every two seconds until it is back.
- The Windows agent sends `RPC-Daemon.hello` on every reconnect, not only at startup.
- The tray shows a five-second countdown while it retries after a drop.
- The Windows tray no longer sticks on Connecting; each attempt is capped at eight seconds, then the five-second retry countdown runs again.
- The Windows agent dials the server off the main loop so the connect countdown ticks and times out instead of freezing.
- Initialize `opt_data_dir` before the server opens its database so the in-memory store loads agents from `/var/lib/argusrm/argus.sqlite`.
- The Android controller tears down RPC before reconnecting, retries every five seconds, shows Reconnecting…, and accepts a tap on the offline title to retry immediately.
- The desktop controller uses the same reconnect behaviour as Android.

## [0.1.2] - 2026-11-10

### Changed

- Linux commands are argusrm-server, argusrm-agent, argusrm-agent-gtk, argusrm-controller, and argusrm-controller-cli. The command-line agent package is argusrm-agent. On a desktop, argusrm-agent starts argusrm-agent-gtk and exits. Login starts that window from /etc/xdg/autostart/argusrm-agent-gtk.desktop.
- The server package includes argusrm-controller-cli. That command opens registration and does not use GTK. On a machine without a desktop, argusrm-controller no longer opens registration.
- Registration listens on its own port. The connect window shows the command to run on the server. It can take an IP address or a domain when this machine cannot hear the broadcast. Connect checks that address every twenty seconds and asks for the PIN when registration is open.

### Added

- The agent is packaged as argusrm-agent and argusrm-agent-gtk. Servers install the command-line agent, argusrm-agent, which does not link GTK. argusrm-agent-gtk is the registration window.
- The controller lists agents and saved servers.

## [0.1.1] - 2026-11-08

### Changed

- The server no longer links GTK or libadwaita. Those libraries stay with the agent and the controller.
- The server registration reply is its own record. The controller keeps the shared registration record, and the reply on the socket is unchanged.

### Added

- The server package includes a SysV init script. Setup covers systemd and SysV init, including an LXC container that is not running systemd.
- Packages install from the RooJS repository by name.

## [0.1.0] - 2026-11-08

### Added

- Argus Remote Manager server, Linux agent, and controller, packaged as argusrm-server, argusrm-agent, and argusrm-controller.
- A managed machine enrolls with a short-lived PIN and stores a client certificate. The agent service stays stopped until that registration finishes.
- Linux agent service files for systemd and SysV init, plus Polkit policies for agent registration and a local controller certificate.
- The server downloads osquery for the agent. The agent reports system, CPU, logged-in user, and network interface identity.
- The controller can open enrollment, list agents, and run one command on one agent. Output is streamed back and stored under the Argus Remote Manager log directory.
- The server keeps a script library, cloned script repositories, and a task scheduler. A one-line controller command is a task.
- The server applies an nftables allowlist on its external port and accepts enrolled agents and controllers.
- On a desktop, the controller can sign in to the local server or enroll with a remote one, then open its window.
- A machine that cannot hear the server registers with sudo argus-agent --server ADDRESS --pin PIN. While registration is open, the controller prints that command with the server's public IPv4 address.
- Setup instructions cover starting the server, registering a desktop, a local machine, and a remote machine, and signing in the controller.