# Changelog

All notable changes to Argus Remote Management are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and release tags use [Semantic Versioning](https://semver.org/).

`CHANGELOG.md` is the source of truth for release notes and Debian/RPM
package changelogs.

## [0.1.1] - Unreleased

### Changed

- The server no longer links GTK or libadwaita. Those libraries stay with the agent and the controller.
- The server registration reply is its own record. The controller keeps the shared registration record, and the reply on the socket is unchanged.

### Added

- The server package includes a SysV init script. Setup covers systemd and SysV init, including an LXC container that is not running systemd.
- Packages install from the RooJS repository by name.

## [0.1.0] - 2026-11-08

### Added

- Argus server, Linux agent, and controller, packaged as argusrm-server, argusrm-agent, and argusrm-controller.
- A managed machine enrolls with a short-lived PIN and stores a client certificate. The agent service stays stopped until that registration finishes.
- Linux agent service files for systemd and SysV init, plus Polkit policies for agent registration and a local controller certificate.
- The server downloads osquery for the agent. The agent reports system, CPU, logged-in user, and network interface identity.
- The controller can open enrollment, list agents, and run one command on one agent. Output is streamed back and stored under the Argus log directory.
- The server keeps a script library, cloned script repositories, and a task scheduler. A one-line controller command is a task.
- The server applies an nftables allowlist on its external port and accepts enrolled agents and controllers.
- On a desktop, the controller can sign in to the local server or enroll with a remote one, then open its window.
- A machine that cannot hear the server registers with sudo argus-agent --server ADDRESS --pin PIN. While registration is open, the controller prints that command with the server's public IPv4 address.
- Setup instructions cover starting the server, registering a desktop, a local machine, and a remote machine, and signing in the controller.
