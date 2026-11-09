# Installing packages

Argus Remote Manager packages are published in the
[roojs package repositories](https://roojs.github.io/repos/). Add that
repository, then install by package name.

- `argusrm-server` — installs, enables, and starts the server service. It includes `argusrm-controller-cli`, which opens registration and does not use GTK
- `argusrm-agent` — installs the managed-machine service without starting it. The command is `argusrm-agent`
- `argusrm-agent-gtk` — adds the `argusrm-agent-gtk` registration window and starts it at login. It depends on the command-line agent
- `argusrm-controller` — installs the desktop controller; no service

Install the server on the server machine. Install the desktop controller
on a machine with a desktop. Install the command-line agent on each
managed machine. Install the GTK agent as well when that machine should
show the registration window.

## Debian and Ubuntu

On the server:

```sh
sudo apt install argusrm-server
```

On a desktop:

```sh
sudo apt install argusrm-controller
```

On a managed machine:

```sh
sudo apt install argusrm-agent
```

## Fedora

On the server:

```sh
sudo dnf install argusrm-server
```

On a desktop:

```sh
sudo dnf install argusrm-controller
```

On a managed machine:

```sh
sudo dnf install argusrm-agent
```

The server package enables and starts the server. Starting registration and
connecting a managed machine are in [Setup](setup.md).
