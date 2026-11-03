# Building Argus

Argus uses Meson and Ninja. A normal Linux installation is system-wide:

- Programs: `/usr/bin`
- Configuration: `/etc/argusrm`
- Runtime data: `/var/lib/argusrm`
- Service logs: `/var/log/argusrm/server.log` and `/var/log/argusrm/agent.log`
- D-Bus policy: `/usr/share/dbus-1/system.d`

## Requirements

- Meson 1.0 or newer
- Ninja
- A C compiler and the Vala compiler
- GLib, GObject, GIO, Gee, JSON-GLib, libsoup 3, GTK 4, libadwaita, Avahi, GnuTLS, and SQLite development files
- The `ocrpc` and `ocsqlite` libraries and Vala API files
- `ocsqlite.h`; the build also accepts it from a sibling `OLLMchat/build/libocsqlite` directory

## Configure and build

From the repository root:

```sh
meson setup build
meson compile -C build
```

The project defaults to the system prefix `/usr`, not `/usr/local` or
`~/.local`.

## Install

```sh
sudo meson install -C build
```

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
