# Agent CLI `--request` fails with `Could not reach the management server.` when `client.pem` exists

**Status:** ✅ fixed

### User reported

- 🔷 On container `nginx`, `argusrm-agent --request --server 192.168.254.88` immediately printed `Could not reach the management server.` with no traffic reaching the server (port 819 offering open).

### Root cause

1. `agent/linux/Application.cli.vala` (line 227) and `agent/linux/Application.vala` (line 600) checked `FileUtils.test(client.pem, EXISTS)` before calling `ensure_client_db()`, then called `this.open_connection()`.
2. `agent/Application.vala` `open_connection()` only returned `this.server.client()`, which is non-null only when the daemon link state machine is `CONNECTED`. In CLI mode the link never runs, so `open_connection()` unconditionally returned `null` whenever `client.pem` existed on disk (including an orphaned self-signed `client.pem` created by `Cert.ensure()` during a failed or cancelled registration when `server.sqlite` has no active `server` row).

### Fix applied

- [`agent/Application.vala`](../agent/Application.vala): when `this.server.client()` is `null`, `open_connection()` dials a one-off `OLLMrpc.Transport.TlsClient` to the active `Argus.Agent.SQT.Server` row in `this.client_db` using `this.data_dir` credentials.
- [`agent/linux/Application.cli.vala`](../agent/linux/Application.cli.vala) and [`agent/linux/Application.vala`](../agent/linux/Application.vala): call `ensure_client_db()` before the already-registered check, only run the `RPC-Daemon.hello` check when an active `server` row exists and `row.has_certificate` is true, and on `CERT_NOT_REGISTERED` remove the saved row via `saved_server.remove(this.client_db)` + `this.client_db.backup_real()`.
- [`controller/Agents.vala`](../controller/Agents.vala): guard `response.retval.type().is_a(typeof(Gee.ArrayList))` before iterating `Agent.list` results.

### Verify

- `ninja -C build agent/argusrm-agent agent/argusrm-agent-gtk` — OK.
- `meson test -C build registration-wire registration-enroll registration-bootstrap` — 3/3 OK.

### LLM

- `agent/Application.vala`
- `agent/linux/Application.cli.vala`
- `agent/linux/Application.vala`
- `controller/Agents.vala`
