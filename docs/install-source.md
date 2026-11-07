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

A source install does not enable or start the services. Starting the server
and registering a managed machine are in [Setup](setup.md).
