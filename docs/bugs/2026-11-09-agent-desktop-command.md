# Desktop launch from `argusrm-agent`

**Status:** ✔️ implemented — not user-verified

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 The command is `argusrm-agent`. There is no `argus-agent` and no `argus-agent-cli`.
- 🔷 `argusrm-agent` is the CLI binary. It does not link GTK.
- 🔷 A normal user on a desktop starts `argusrm-agent-gtk` when that program is installed, then this process exits.
- 🔷 Without a desktop, or without `argusrm-agent-gtk`, a non-root run says to run `argusrm-agent` as root.
- 🔷 `argusrm-agent-gtk`, still as that user, runs the existing admin flow and starts itself as root. That root process keeps the registration window.

## How it will work

- 🔷 `argusrm-agent` knows the other program is `argusrm-agent-gtk`. It looks that name up on `PATH`.
- 🔷 Not root, no `--service`, `DISPLAY` or `WAYLAND_DISPLAY` is set, and `argusrm-agent-gtk` is on `PATH`: start that program as this user, then exit.
- 🔷 `--service` does not start the GTK program. The unit runs `/usr/bin/argusrm-agent --service`.
- 🔷 Not root, and the GTK program was not started: `Run argusrm-agent as root.`
- 🔷 Root, without `--service`: terminal registration. It does not start the GTK program.
- 🔷 `argusrm-agent-gtk` as a normal user runs itself through Polkit, the same admin flow as now.
- 🔷 `argusrm-agent-gtk` as root keeps the registration window in `agent/linux/Application.vala`.
- 🔷 The GTK package ships a `.desktop` file that starts `argusrm-agent-gtk`. It does not start `argusrm-agent`.

## Packaging

- 🔷 Installed commands take the `argusrm-` prefix, the same token as the packages.
  - `argus` becomes `argusrm-server`.
  - `argus-controller` becomes `argusrm-controller`.
  - The agent CLI becomes `argusrm-agent`.
  - The registration window becomes `argusrm-agent-gtk`.
- 🔷 Package `argusrm-agent` replaces `argusrm-agent-cli`.
  It installs `/usr/bin/argusrm-agent`, the systemd unit, and the SysV script.
  It does not depend on GTK.
- 🔷 Package `argusrm-server` installs `/usr/bin/argusrm-server`.
- 🔷 Package `argusrm-controller` installs `/usr/bin/argusrm-controller`.
- 🔷 Package `argusrm-agent-gtk` depends on `argusrm-agent`.
  It installs `/usr/bin/argusrm-agent-gtk`, the Polkit policy, and `/etc/xdg/autostart/argusrm-agent-gtk.desktop`.
  That `.desktop` file runs `argusrm-agent-gtk`.
  It does not install `/usr/bin/argusrm-agent`.
- 🔷 Package `argusrm-agent` does not install a `.desktop` file.
- 🔷 The agent service `ExecStart` is `/usr/bin/argusrm-agent --service`.
- 🔷 The server service runs `/usr/bin/argusrm-server`.
- ℹ️ Debian: `debian/control`, `debian/argusrm-agent-cli.install` renamed to `debian/argusrm-agent.install`, `debian/argusrm-agent-gtk.install`, `debian/argusrm-server.install`, `debian/argusrm-controller.install`.
- ℹ️ RPM: `packaging/rpm/argusrm.spec`.
- ℹ️ Units: `packaging/systemd/argusrm-agent.service`, `packaging/systemd/argusrm-server.service`.

## Not this

- 🚫 No binary or package name with `-cli`.
- 🚫 No installed command named `argus`, `argus-agent`, or `argus-controller`.
- 🚫 `argusrm-agent` does not discover the GTK program from its own path.
- 🚫 `argusrm-agent` does not stay running after it has started `argusrm-agent-gtk`.
- 🚫 A root `argusrm-agent` does not start the GTK program.
- 🚫 `--service` does not start the GTK program.
- 🚫 The CLI package does not install a `.desktop` file.
- 🚫 The service does not link GTK.

## Built

- ✔️ `ninja -C build agent/argusrm-agent agent/argusrm-agent-gtk server/argusrm-server controller/argusrm-controller` exited 0.
- ✔️ `argusrm-agent` does not link GTK. `argusrm-agent-gtk` links GTK and libadwaita.
- ✔️ Polkit `exec.path` is `/usr/bin/argusrm-agent-gtk`. SysV `DAEMON` is `/usr/bin/argusrm-agent` and `/usr/bin/argusrm-server`.
