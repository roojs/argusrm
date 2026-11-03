# Installing packages

Argus is under development. Release builds provide three packages:

- `argusrm-server` — installs, enables, and starts the server service
- `argusrm-agent` — installs, enables, and starts the managed-machine service
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
can differ.

## Complete the setup

### 1. Check the server

The server package enables and starts Argus. On the server machine:

```sh
systemctl status argusrm-server.service
```

The controller is currently a local administration command. It uses
`/var/lib/argusrm/argus.sock` on this server and does not enroll itself.
Remote desktop and mobile controller enrollment comes later.

### 2. Open registration on the managed machine

The agent package enables and starts the agent service. On the managed
machine:

```sh
systemctl status argusrm-agent.service
```

Windows opens registration from the tray. On Linux, open the window as the
signed-in desktop user:

```sh
argus-agent --register
```

The window waits for a PIN and does not need root privileges.

### 3. Issue and enter the PIN

Back on the server:

```sh
sudo argus-controller
```

It reports that it is connecting, prints a six-digit PIN, and keeps
registration open for 60 seconds. Press Ctrl+C to close it early. Enter that
PIN in the waiting agent window. The privileged agent service obtains and
stores the machine certificate.

Logs are in `/var/log/argusrm/server.log` and
`/var/log/argusrm/agent.log`.
