# Setup

Install the packages first. [Installing packages](install-packages.md) covers that. A source install is [Installing from source](install-source.md). This page is what you do after the programs are on the machines.

The **server** coordinates. The **agent** runs on each managed machine, receives a certificate, and then connects to the server. The **controller** primarily runs on a desktop, where it signs in and manages that server. It can also run on the server to perform basic registration.

## 1. Start the server

A package install enables and starts the server. After a source install, do that yourself:

```sh
sudo systemctl enable --now argusrm-server.service
```

On the server machine:

```sh
systemctl status argusrm-server.service
```

## 2. Open registration

On the server:

```sh
sudo argus-controller
```

It prints:

```
Connecting to the local Argus server...
Registration PIN: 123456
Registration is open for 60 seconds. Press Ctrl+C to close it early.
On a remote terminal you can use:
sudo argus-agent --server 203.0.113.10 --pin 123456
```

On this server, `argus-controller` is a local administration command. It uses `/var/lib/argusrm/argus.sock` and does not enroll itself. The address in that command is the server's public IPv4 address. Public registration uses IPv4 only. IPv6 is not supported.

## 3. Register a managed machine

### 3.1 Register a desktop

On the same network, where the machine can hear the server, run:

```sh
argus-agent
```

Polkit requests administrator access, then the registration window asks for the PIN.

### 3.2 Register a local server

Without a desktop, on a machine that can hear the server, run:

```sh
sudo argus-agent
```

It prints:

```
Looking for a management server…
Enter registration PIN: 123456
Registration succeeded. The Argus agent is running and connected.
```

### 3.3 Register a remote server

When the machine cannot hear the server, run the command printed in step 2, as root:

```sh
sudo argus-agent --server 203.0.113.10 --pin 123456
```

It prints:

```
Registration succeeded. The Argus agent is running and connected.
```

`--server` is that IPv4 address. `--pin` is the six digits from the server. Registration enables and starts the agent service. The agent stores its certificate and then connects to the server.

Logs are in `/var/log/argusrm/server.log` and `/var/log/argusrm/agent.log`.

## 4. Set up the controller on the desktop

On the desktop:

```sh
argus-controller
```

The window offers "Log in to local machine" and "Connect a remote machine".

On the machine running the server, choose "Log in to local machine". Polkit requests administrator access. The controller stores a certificate for the signed-in user and opens its window. That login does not use the PIN.

On another desktop that can hear the server, choose "Connect a remote machine". Open registration again, as in step 2. The window finds the server and asks for that PIN. The controller stores its certificate and opens its window.

The window then shows that it is connected to the Argus server.
