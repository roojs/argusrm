# Installing packages

Argus Remote Manager packages are published in the
[roojs package repositories](https://roojs.github.io/repos/). Add that
repository, then install by package name.

- `argusrm-server` — installs, enables, and starts the server service
- `argusrm-agent-cli` — installs the managed-machine service without starting it. The command is `argus-agent-cli`
- `argusrm-agent-gtk` — adds the `argus-agent` registration window. It depends on the command-line agent
- `argusrm-controller` — installs the command-line controller; no service

Install the server and controller on the server machine. Install the
command-line agent on each managed machine. Install the GTK agent as well
when that machine should show the registration window.

## Debian and Ubuntu

On the server:

```sh
sudo apt install argusrm-server argusrm-controller
```

On a managed machine:

```sh
sudo apt install argusrm-agent-cli
```

## Fedora

On the server:

```sh
sudo dnf install argusrm-server argusrm-controller
```

On a managed machine:

```sh
sudo dnf install argusrm-agent-cli
```

The server package enables and starts the server. Starting registration and
connecting a managed machine are in [Setup](setup.md).
