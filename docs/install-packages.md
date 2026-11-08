# Installing packages

Argus packages are published in the
[roojs package repositories](https://roojs.github.io/repos/). Add that
repository, then install by package name.

- `argusrm-server` — installs, enables, and starts the server service
- `argusrm-agent` — installs the managed-machine service without starting it
- `argusrm-controller` — installs the command-line controller; no service

Install the server and controller on the server machine. Install only the
agent on each managed machine.

## Debian and Ubuntu

On the server:

```sh
sudo apt install argusrm-server argusrm-controller
```

On a managed machine:

```sh
sudo apt install argusrm-agent
```

## Fedora

On the server:

```sh
sudo dnf install argusrm-server argusrm-controller
```

On a managed machine:

```sh
sudo dnf install argusrm-agent
```

The server package enables and starts the server. Starting registration and
connecting a managed machine are in [Setup](setup.md).
