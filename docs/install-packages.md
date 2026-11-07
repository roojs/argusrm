# Installing packages

Argus is under development. Release builds provide three packages:

- `argusrm-server` — installs, enables, and starts the server service
- `argusrm-agent` — installs the managed-machine service without starting it
- `argusrm-controller` — installs the command-line controller; no service

Install the server and controller on the server machine. Install only the
agent on each managed machine.

## Debian and Ubuntu

On the server:

```sh
sudo apt install \
  ./argusrm-server_0.1.0-1_amd64.deb \
  ./argusrm-controller_0.1.0-1_amd64.deb
```

On a managed machine:

```sh
sudo apt install ./argusrm-agent_0.1.0-1_amd64.deb
```

## Fedora

On the server:

```sh
sudo dnf install \
  ./argusrm-server-0.1.0-1.fc44.x86_64.rpm \
  ./argusrm-controller-0.1.0-1.fc44.x86_64.rpm
```

On a managed machine:

```sh
sudo dnf install ./argusrm-agent-0.1.0-1.fc44.x86_64.rpm
```

The exact version, release, distribution, and architecture in each filename
can differ. After the package repository is configured, the same packages
install by name.

The server package enables and starts the server. Starting registration and
connecting a managed machine are in [Setup](setup.md).
