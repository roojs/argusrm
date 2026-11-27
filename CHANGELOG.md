# Changelog

All notable changes to Argus Remote Manager are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release tags use [Semantic Versioning](https://semver.org/).

`CHANGELOG.md` is the source of truth for release notes and Debian/RPM
package changelogs.

## [0.1.69] - Unreleased

### Changed

- Registration dialog (`RegisterWindow` / `Register`) now shows the target management server address during connection, PIN entry (`Enter registration PIN for <host>`), and enrollment, and displays transport or reply errors instead of a generic failure message.

### Fixed

- `Offering.enroll` no longer rejects controller PIN registrations (`is_controller = true`) while the six-digit PIN window is open; only batch, pending, and polling registrations remain agents-only.

## [0.1.68] - Unreleased

### Changed

- Removed the Windows tray permission prompt (`agent.desktop` / `AgentService.allow`) so live desktop sharing attaches immediately without interrupting the signed-in user; the passive tray active indicator and Disconnect action remain.

### Fixed

- Controller remote desktop now handles FreeRDP `DesktopResize` callbacks (`gdi_resize`), scales the desktop to fit the window (`Gtk.ContentFit.CONTAIN`) with letterbox-aware pointer mapping, and uses opaque `BGRX32` (`Gdk.MemoryFormat.B8G8R8X8`).

## [0.1.67] - Unreleased

### Fixed

- Windows service startup no longer enters `GLib.Application.run()` on the main thread before `StartServiceCtrlDispatcherW`, avoiding the cross-thread default `GMainContext` acquisition failure in `Service.service_main()`.

## [0.1.66] - Unreleased

### Added

- Windows live desktop takeover via `IRDPSRAPISharingSession` (`RdpEncom.dll`) with zero user credentials, tray consent dialog/balloon, active remote-control indicator and Disconnect, Windows Home support, and unattended `TermService` fallback.
- Split Windows tray IPC and process supervision out of `Service` into `TrayServer`, and moved Windows CLI dispatch to `GLib.OptionContext` in `agent/windows/Application.vala`.

## [0.1.65] - Unreleased

### Fixed

- Agent downloads now parse HTTP `\r\n` response headers with `CR_LF` line endings, use full `write_all` writes, and close the output file explicitly so binary package downloads no longer eat the body as headers.
- Server download listener now logs incoming requests, client certificate checks, status codes, and served byte counts, and honors `--data-dir`.
- Linux agent startup runs osquery initialization off the main loop via `send_inventory()`, and an automated `download` Meson test exercises agent-to-server mTLS downloads end-to-end.

## [0.1.64] - Unreleased

### Fixed

- The agent download socket no longer uses libsoup on the osquery worker thread (which could hang after proxy resolution while openssl to the same URL succeeded). Downloads use a timed Gio TLS GET, with debug logging through `dpkg -i` / `rpm -U` / `msiexec` install success or failure.

## [0.1.63] - Unreleased

### Fixed

- Wired mouse motion, clicks, wheel scroll, keyboard input, and focus events into the controller RDP viewer.
- Enabled FreeRDP3 GFX RFX Progressive pipeline, EndPaint-driven redraws, single-copy frame publishing, and 64 KiB relay chunks in both the agent and controller.

## [0.1.62] - Unreleased

### Fixed

- Registering a fresh agent now writes `server.sqlite` to disk immediately before restarting the service, so `argusrm-agent --request` and `--pin` no longer time out waiting for the service to connect.
- Disabled Wintun virtual-adapter routing on Windows so the agent dials Remote Desktop directly on 127.0.0.1:3389, and reset the reconnect retry counter on fresh desktop cuts.
- Disabled uninitialized FreeRDP graphics pipeline, surface codecs, and UDP multi-transport in the controller viewer and waited on FreeRDP event handles instead of busy-spinning.

## [0.1.61] - Unreleased

### Fixed

- Hello uses the library compare of the first two numbers. 0.1.60 and 0.1.59 connect. A different middle number, such as 0.2, is still refused.

## [0.1.60] - Unreleased

### Fixed

- The machine reported "The machine could not send the desktop. Trying 1 of 3" when Windows closed the desktop, and then stopped. That close now starts the desktop again, up to three times.

## [0.1.59] - Unreleased

### Fixed

- Could not connect puts the address in the title. The server name and the reason are underneath.
- Opening the desktop again, after the machine had stopped sending, left the join waiting. The window then reported that FreeRDP could not open the desktop, trying 3 of 3. A later open starts the Windows connection again.
- A new desktop from the machine left the controller on "The machine is about to send the desktop." The server was still holding the join from the previous desktop. That join is released when the machine connects again.
- After the server restarted, the machine kept its old desktop connection and ignored the new request. The window then showed "Told the server this controller wants to take control" on top of the later step. A dead desktop connection is replaced, and that earlier sentence is no longer painted last.

## [0.1.58] - Unreleased

### Fixed

- The connect dialog keeps the VPN notice, with this machine's tunnel address, while it looks for a server. The PIN step names the address it found.
- A client and a server on the same middle version connect. 0.1.55 and 0.1.58 are the same API. A newer client on a different middle number, such as 0.2, is still refused.
- When that refusal happens, the window names the server and offers Retry and Select another server.
- The Windows desktop connection kept the handshake and then sent the screen bytes over the TCP header. Remote Desktop never answered, so the window stayed on "The desktop data is coming through."
- The controller kept a full copy of the desktop for every update. The picture now keeps one copy and paints that.

## [0.1.57] - Unreleased

### Fixed

- The Windows agent opens Remote Desktop through a virtual adapter. Windows sees that connection from 10.200.0.1, not from this PC. The installer places wintun.dll next to the agent.

## [0.1.56] - Unreleased

### Added

- While the connect dialog is open over a VPN, the client scans the tunnel /24 for the registration port every twenty seconds and moves to the PIN step when a server answers. Browse continues until then.

## [0.1.55] - Unreleased

### Fixed

- Registration over the VPN finishes after the number. The server was closing that port before the controller received the certificate, so the window waited and then said registration failed.

## [0.1.54] - Unreleased

### Fixed

- The Windows agent opens Remote Desktop on the machine's own network address. Windows was closing the session when it came from this PC itself.
- Debian and Fedora builds install libxlsxwriter. Debian also installs minizip and OpenSSL, which that library's pkg-config file requires. The controller uses it to write spreadsheets.

## [0.1.53] - Unreleased

### Fixed

- Before the Windows agent opens the desktop, it logs off an existing Remote Desktop session. Disconnecting left that session logged on, and Windows then closed the new one.
- When the machine cannot send the desktop, it connects again, up to three times.

## [0.1.52] - Unreleased

### Fixed

- Before the Windows agent opens the desktop, it disconnects an active Remote Desktop session. Windows was keeping that session and closing this one.

## [0.1.51] - Unreleased

### Fixed

- The Windows agent opens a second connection to the server for the desktop, instead of stopping on "The machine could not open its second connection."
- Categorize on the Software page reaches the server. The rows are System, Keep, and Bad, then a separator, then Unknown. Each row shows its mark. The Scope column starts hidden.

## [0.1.50] - Unreleased

### Fixed

- Retry on the version window stays open, shows whether the agent connected, and closes a few seconds later.

## [0.1.49] - Unreleased

### Fixed

- When this controller asks for the desktop, the Windows agent starts Remote Desktop. If that start fails, it tries again, up to three times.

## [0.1.48] - Unreleased

### Fixed

- The Windows agent no longer locks up when this controller asks it to open the desktop. It answers after it has finished receiving that request.
- When the agent and the server versions do not match, the Windows agent offers Retry, then Restart. It does not offer Register.

## [0.1.47] - Unreleased

### Added

- The Windows programs bar on a machine has a save icon on the right. It writes that machine's program list to a spreadsheet and opens the file in the registered spreadsheet application. The spreadsheet includes the file hash, the signing result, and the certificate fields.
- The Software page leads with a category mark and a listing mark. Programs and Store packages use a display. A service uses a wireless mark. Several rows can be selected. Right-click, Categorize, and choose System, Installed, Unknown, or Bad. That choice is stored as a number for the source and the name, and the category mark shows it on the next list.

### Fixed

- A matching registration number replaces a controller already saved for that login and machine name. The desktop receives the new certificate instead of being told it is already registered.

## [0.1.46] - Unreleased

### Fixed

- Closing a registration connection no longer uses the connection after it has already been freed. The close keeps its own reference until it has finished, and a second close while that is in progress is ignored. The server log names the connection id being closed.
- A refused registration now shows the server's own reason on the controller. The server log names that same reason when the number is rejected, the controller is already registered, or the certificate cannot be signed.
- The Windows programs snapshot no longer unions ``appx_packages``. That table is not in osquery, so the whole query failed and the agent posted an empty inventory. Store packages stay in the snapshot as ``source`` ``appx`` when ``programs.package_family_name`` is set.
- Windows program file hashes now follow an executable path that contains spaces, such as ``C:\Program Files\...\Uninstall.exe``.
- The Windows software list hides an MSI piece whose uninstall key sets SystemComponent. Visual Studio and the Windows SDK stay as their own entries. The hidden rows remain stored.
- The Windows software list hides a service whose signing certificate hash is one of the Windows certificates recorded in ``Programs``. Catalog-signed drivers now store that certificate. Another certificate stays visible, including Microsoft Code Signing and the hardware-compatibility publisher.
- One further Microsoft Windows certificate is left out for every source. On this machine that is Windows Setup Remediations, three Store packages, and 43 services.
- Five signing certificates are left out for every source. They cover the Windows shell packages, Print Dialog, Windows Setup Remediations, Photos, the Windows App Runtime package, and both Visual C++ 2015-2022 redistributables.
- On one machine, installed programs that share a certificate, a version, and a file hash are one row. The name joins those program names.
- Two more Microsoft Windows certificates are left out for services. One was already left out for every source. The other covers 17 services.
- A Microsoft Corporation certificate is left out for every source. On this machine it signs App Installer, Outlook, Terminal, Game Bar, Phone Link, and two Windows App Runtime packages.
- On one machine, services that share a file hash are one row. The name joins those service names.
- A Windows Store package shows the uninstall button. The command is ``Remove-AppxPackage`` for every user, using the package folder name.
- A Windows Store package is hashed from the executable named by Application in its AppxManifest.xml. Other files in the package folder are left alone. A package whose manifest names no executable is stored and left out of the list.
- Startup items stay stored and are left out of the software list.
- The one-machine software list is one row per source and name, the same grouping as the all-machines list. The reply keeps that machine's id and the highest version in the group.

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