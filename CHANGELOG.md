# Changelog

All notable changes to Argus Remote Manager are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release tags use [Semantic Versioning](https://semver.org/).

`CHANGELOG.md` is the source of truth for release notes and Debian/RPM
package changelogs.

## [0.1.3] - Unreleased

### Added

- Agents report the operating system, Debian packages, RPM packages, and Windows programs from osquery.
- The Assets page has Machines and Software. Machines is a grid of the one-row columns and has no rows. Hidden columns start off. Software is the word Software.

### Fixed

- Debian packages depend on libocrpc1 and libocsqlite1, and RPM packages depend on libocrpc and libocsqlite. Shared-library detection skips both libraries because their SONAMEs have no version.
- Removing a machine from the controller no longer leaves argusrm-agent saying it is already registered. A connected agent drops its certificate when it is removed. A later run asks the server, and a rejected certificate is deleted so registration can continue.
- argusrm-agent --debug shows browse progress. argusrm-server --debug shows when a firewall port is opened or enforced, and when the allowlist changes.

### Changed

- A tag release no longer builds or publishes the controller AppImage. That build stays on its manual workflow.

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
