# Removed agent still says it is registered

**Status:** ⏳ in progress

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 Remove the machine from the controller, then run `argusrm-agent`.
- 🔷 It prints `Argus agent is already registered.` and exits.
- 🔷 The server no longer has that machine. Registration should run again.

## Evidence

- ✔️ `argusrm-agent` root registration is `cli()` in `agent/linux/Application.cli.vala`.
- ✔️ That method returns when `client.pem` exists. It does not ask the server.
- ✔️ `Agent.remove` deletes the row, closes the app socket, and refreshes the allowlist. It does not tell the agent to drop `client.pem`.
- ✔️ An unknown certificate that still completes TLS gets `certificate not registered` from `SslConnection.allow_request` (`CERT_NOT_REGISTERED`).
- ℹ️ A connect failure is not that reply. The app port allowlist no longer contains a removed remote address, so a later probe can be rejected before the RPC. A connected agent can still be told while the socket is up.

## Root cause

- ✔️ Registration is the server row. `cli()` treats the local certificate file as that row.

## Proposed fix

- 🔷 `Agent.remove` writes `agent.removed` on that machine's connection, then closes it.
- 🔷 The agent deletes `client.pem` when it reads `agent.removed`.
- 🔷 `cli()` calls `RPC-Daemon.hello` with the stored certificate. `CERT_NOT_REGISTERED` deletes `client.pem` and registration continues. Any other result, including a server that cannot be reached, keeps the current message.

### 1. `server/Agent.vala` — `remove`

#### Remove

```vala
			foreach (var connection in this.app.ssl_listen.connections) {
				if (connection.agent_id != id) {
					continue;
				}
				connection.stop();
			}
```

#### Replace with

```vala
			foreach (var connection in this.app.ssl_listen.connections) {
				if (connection.agent_id != id) {
					continue;
				}
				connection.write(new OLLMrpc.Notification() {
					method = "agent.removed"
				});
				connection.stop();
			}
```

### 2. `agent/Application.vala` — `notification`

Handle `agent.removed` by deleting `client.pem`.

### 3. `cli()` in `agent/linux/Application.cli.vala` and `agent/linux/Application.vala`

After the certificate exists, hello the stored server. Only `CERT_NOT_REGISTERED` deletes the file and falls through.

## Attempts

- ✔️ The proposal is in the tree. `ninja` built `agent/argusrm-agent`, `agent/argusrm-agent-gtk`, and `server/argusrm-server`.
- ℹ️ `GLib.FileUtils.remove` does not throw here, so the delete is a direct call.
- ⏳ Not verified on the installed `/usr/bin` binaries.
