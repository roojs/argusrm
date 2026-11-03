# Installing from source

Argus is under development. A source install builds and installs all three
Linux programs:

- `argus` — server
- `argus-agent` — managed-machine agent
- `argus-controller` — local server controller

It also installs the server and agent systemd units, but it does not enable
or start either service automatically.

## Requirements

Install Meson, Ninja, a C compiler, Vala, and the development dependencies
listed in [Building](build.md). The RooJS `libocrpc-dev` and
`libocsqlite-dev` packages must be installed, including `ocsqlite.h`.

## Build and install

From the repository root:

```sh
meson setup build \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var
meson compile -C build
sudo meson install -C build
sudo systemctl daemon-reload
```

## 1. Start the Argus server

On the server machine, enable and start the server:

```sh
sudo systemctl enable --now argusrm-server.service
systemctl status argusrm-server.service
```

The installed `argus-controller` is currently a local administration
command. It talks to `/var/lib/argusrm/argus.sock` on this server and does
not enroll itself. Remote desktop and mobile controller enrollment comes
later.

## 2. Start the agent on the managed machine

On a different machine, enable and start the agent:

```sh
sudo systemctl enable --now argusrm-agent.service
```

Windows opens its registration window from the tray. On a Linux desktop,
open the registration window as the signed-in user:

```sh
argus-agent --register
```

The window waits for the server registration PIN. It does not need root
privileges; it passes the PIN to the root agent service.

## 3. Issue and enter the PIN

Back on the server, run:

```sh
sudo argus-controller
```

It reports that it is connecting, prints a six-digit PIN, and keeps
registration open for 60 seconds. Press Ctrl+C to close it early. Enter that
PIN in the waiting agent window. The root agent service performs registration
and stores the certificate.

Service logs are written to `/var/log/argusrm/server.log` and
`/var/log/argusrm/agent.log`.
