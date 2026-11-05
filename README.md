# Argus Remote Management

> **Under development:** Argus is incomplete and is not ready to install or use.

The goal is plug-and-play remote machine management. An agent runs on each
managed machine, an Argus server coordinates management, and a controller
operates the server. Installation and enrollment are intended to be simple,
rather than requiring a long manual setup process.

There is no web application. The controller will be a desktop application
and, later, a mobile application. These controller applications manage the
Argus server.

## How it works

When the Argus server first starts, it downloads the osquery installers it
will distribute to Debian, RPM-based, and Windows machines. It then listens
for registered agents and controllers.

To add a managed machine:

1. Install and start the Argus agent. Windows presents registration from the
   tray application. The Linux registration flow is awaiting approval in
   `docs/plans/2.1-registration-flow.md`.
2. On the server, run `sudo argus-controller`. It prints a six-digit PIN and
   opens registration for 60 seconds.
3. Enter that PIN on the managed machine. The server verifies it, creates a
   certificate for that machine, and sends the certificate securely to the
   agent.

The PIN only permits enrollment during that short registration window. At
all other times, the server rejects unknown machines and accepts connections
only from clients with a previously issued certificate.

The Linux agent service runs as root, and the Windows service runs as
`LocalSystem`, because management includes installing software and running
commands. The registration window itself runs as the signed-in desktop user.

## Project documentation

- [Aims](docs/plans/1.0-aims.md)
- [Implementation](docs/plans/1.1-implementation.md)
- [Installing packages](docs/install-packages.md)
- [Installing from source](docs/install-source.md)
- [Building](docs/build.md)
- [Packaging and releases](docs/packaging.md)

## Artificial intelligence usage

This project was developed with the assistance of artificial intelligence.

- Architecture and design direction are human-led
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Changes were reviewed, revised, and approved before landing
- Application code is treated as author-approved

Limited exceptions apply mainly to build scaffolding.
