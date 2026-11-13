# Agent debug is silent, and the firewall open is not logged

**Status:** ✅ closed 2026-11-13. Verified all proposed changes are applied in the tree.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 `argusrm-agent --debug` prints `Looking for a management server…` and then nothing.
- 🔷 With a registration PIN open, that agent still does not show browse or connect lines.
- 🔷 `--debug` on the server should show the registration firewall opening and closing, and the allowlist commands.

## Evidence

- ✔️ `argusrm-agent` is `agent/linux/Application.cli.vala`. Root with no `--service` returns from `cli()` and never calls `Argus.Agent.Application.command_line`.
- ✔️ `debug_on` is set only in that base `command_line`. It is `private`, so the Linux process parses `--debug` into `opt_debug` and then leaves the log handler quiet.
- ✔️ `GLib.debug` in `shared/Browse.vala` runs only after a TXT `id` is resolved. A wait with no service has no line.
- ✔️ `server/Net/NFTables.vala` logs nftables failures. `enable`, `disable`, and a successful `apply` do not log.
- ℹ️ The firewall lives in `argusrm-server`. `argusrm-controller-cli --debug` cannot print it. Server lines go to stderr when that process was started with `--debug`, and always to `ARGUS_LOG_DIR` (`/var/log/argusrm/server.log` from the unit).

## Root cause

- ✔️ The command-line agent replaces the log handler and then never sets `debug_on`.
- ✔️ Firewall transitions are silent even when the server debug handler is on.

## Proposed fix

- 🔷 `debug_on` and `debug_critical_enabled` are `protected`, and both Linux entry points set them after option parsing.
- 🔷 Browse logs the client state, each service, and the resolved address.
- 🔷 `NFTables` logs an unchanged allowlist, the nft commands that were applied, `firewall enforced`, and `firewall open`.
- 🔷 `Agent.offer` logs the addresses it publishes. `Register.try_connection` logs the host and port.

### 1. `agent/Application.vala` — log flags visible to Linux

#### Remove

```vala
		private static bool debug_on;
		private static bool debug_critical_enabled;
```

#### Replace with

```vala
		protected static bool debug_on;
		protected static bool debug_critical_enabled;
```

### 2. Linux `command_line` — turn `--debug` on

`agent/linux/Application.cli.vala` and `agent/linux/Application.vala`, immediately after a successful parse.

#### Add

```vala
			debug_on = opt_debug;
			debug_critical_enabled = opt_debug_critical;
```

### 3. `cli()` — one line before browse

Same two files, in the `host == ""` branch.

#### Add

```vala
				GLib.debug("browsing");
```

### 4. `shared/Browse.vala`, `shared/Register.vala`, `server/Agent.vala`, `server/Net/NFTables.vala`

Log the browse phases, the registration attempt, the published addresses, and each firewall transition. No new methods.

## Attempts

- ✔️ The proposal above is in the tree. `ninja` built `agent/argusrm-agent`, `agent/argusrm-agent-gtk`, and `server/argusrm-server`.
- ℹ️ `Avahi.ClientState.to_string()` does not compile (`GA_TYPE_CLIENT_STATE` is missing). The state log names each enum value instead.

## Next

- ✅ Closed. Debug logging and firewall transition logging are in the tree.
