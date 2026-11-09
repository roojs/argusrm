# Building Argus Remote Manager

Argus Remote Manager uses Meson and Ninja. A source build installs all three Linux programs:

- `argus` — server
- `argus-agent` — desktop registration window
- `argus-agent-cli` — command-line agent, and the program the service runs
- `argus-controller` — local server controller

It also installs the server and agent systemd units and SysV init scripts.
It does not enable or start either service.

A normal installation is system-wide:

- Programs: `/usr/bin`
- Configuration: `/etc/argusrm`
- Runtime data: `/var/lib/argusrm`
- Service logs: `/var/log/argusrm/server.log` and `/var/log/argusrm/agent.log`

The project defaults to the system prefix `/usr`, not `/usr/local` or
`~/.local`.

## Dependencies

`libocrpc` and `libocsqlite` come from the
[roojs package repositories](https://roojs.github.io/repos/). Add that
repository before installing the packages below. Meson also accepts
`ocsqlite.h` from a sibling `OLLMchat/build/libocsqlite` directory when
the header is not installed.

### Debian and Ubuntu

```sh
sudo apt install \
  build-essential \
  meson \
  ninja-build \
  pkg-config \
  valac \
  libglib2.0-dev \
  libgee-0.8-dev \
  libjson-glib-dev \
  libsoup-3.0-dev \
  libgnutls28-dev \
  libsqlite3-dev \
  libgtk-4-dev \
  libadwaita-1-dev \
  libavahi-gobject-dev \
  libavahi-client-dev \
  libsecret-1-dev \
  libgit2-glib-1.0-dev \
  libnftables-dev \
  libnl-3-dev \
  libnl-route-3-dev \
  libocrpc-dev \
  libocsqlite-dev
```

### Fedora

```sh
sudo dnf install --setopt=install_weak_deps=False \
  meson ninja-build gcc vala \
  libocrpc-devel libocsqlite-devel \
  'pkgconfig(glib-2.0)' 'pkgconfig(gio-unix-2.0)' \
  'pkgconfig(gee-0.8)' 'pkgconfig(json-glib-1.0)' \
  'pkgconfig(libsoup-3.0)' 'pkgconfig(gnutls)' \
  'pkgconfig(sqlite3)' 'pkgconfig(gtk4)' \
  'pkgconfig(libadwaita-1)' 'pkgconfig(libsecret-1)' \
  'pkgconfig(avahi-gobject)' 'pkgconfig(avahi-client)' \
  'pkgconfig(libgit2-glib-1.0)' 'pkgconfig(libnftables)' \
  'pkgconfig(libnl-3.0)'
```

## Configure and build

From the repository root:

```sh
meson setup build
meson compile -C build
```

## Install

```sh
sudo meson install -C build
```

On systemd, reload the unit files:

```sh
sudo systemctl daemon-reload
```

On SysV init the scripts are `/etc/init.d/argusrm-server` and
`/etc/init.d/argusrm-agent`. Starting the server and registering a managed
machine are in [Setup](setup.md).

## Uninstall

Meson records each installed file in `build/meson-logs/install-log.txt`.
Use the generated Ninja target to remove those files:

```sh
sudo ninja -C build uninstall
```

Run this before deleting or replacing the build directory.

## Reset an existing build configuration

An existing build directory retains the paths with which it was first
configured. Reset it to the project system paths with:

```sh
meson configure build \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var
meson compile -C build
```

To wipe and regenerate the build directory while explicitly resetting those
paths:

```sh
meson setup --wipe build \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var
```
