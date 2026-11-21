# OLLMrpc: `tcp://127.0.0.1` skips TLS while `configure_tls` is in use

**Status:** ✅ closed 2026-11-21 — duplicate of upstream fix; Argus consumers already set `force_localhost_tls`.

**Upstream (canonical):** `OLLMchat/docs/bugs/done/2026-11-21-FIXED-loopback-tcp-tls-option.md` — `OLLMrpc.Client.force_localhost_tls` in `libocrpc/Client.vala`.

**Component:** `OLLMchat/libocrpc/Client.vala` — `OLLMrpc.Client.connect`

---

## Closure

| Item | ✔️ |
| --- | --- |
| **libocrpc** | TLS on `tcp://127.0.0.1` when `force_localhost_tls` is true (default false preserves Windows tray plain loopback) |
| **Argus** | `controller/dialog/Bootstrap.vala` — management client after local login |
| **Argus** | `server/tests/registration-local-login.vala` — same flag on probe client |

No further Argus libocrpc fork or workaround doc needed.

---

## Symptom (historical)

- Argus management is TLS-only on the app port.
- Any client that dials `tcp://127.0.0.1:<port>` with `configure_tls` connected still skipped the TLS handshake in libocrpc.
- RPC hello failed with **Client: disconnected** (plain bin RPC on a TLS listener).

## Cause (historical)

TLS was gated with `!socket_path.has_prefix("tcp://127.0.0.1")` only — correct for Windows tray `tcp://127.0.0.1:4142`, wrong when `configure_tls` is wired for management.

## Argus policy (unchanged)

| Step | Transport |
|------|-----------|
| Issue certificate (`pkexec … --give-me-a-certificate`) | Unix `argus.sock` only |
| Open main window (probe + `use`) | Prefer **`127.0.0.1`** when listed in cert addresses; TLS via **`force_localhost_tls`** on `OLLMrpc.Client` |

Plain loopback without the flag remains for Windows tray agents.