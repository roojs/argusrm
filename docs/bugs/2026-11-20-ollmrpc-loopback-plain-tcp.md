# OLLMrpc: `tcp://127.0.0.1` skips TLS while `configure_tls` is in use

**Status:** open (upstream libocrpc / OLLMchat)

**Component:** `OLLMchat/libocrpc/Client.vala` — `OLLMrpc.Client.connect`

## Symptom

- Argus management is TLS-only on the app port.
- Any client that dials `tcp://127.0.0.1:<port>` with `configure_tls` connected still skips the TLS handshake in libocrpc.
- RPC hello fails with **Client: disconnected** (plain bin RPC on a TLS listener).

## Cause

After TCP connect, TLS is only enabled when the endpoint is **not** prefixed with `tcp://127.0.0.1`:

```vala
if (this.protocol == Protocol.TCP
    && !this.socket_path.has_prefix("tcp://127.0.0.1")) {
    var tls_link = GLib.TlsClientConnection.@new(this.socket, null);
    this.configure_tls(tls_link);
    …
}
```

That exception exists for plain loopback peers (e.g. Windows agent tray `tcp://127.0.0.1:4142`). It must not apply when `configure_tls` is in use.

## Expected upstream fix

Run the TLS handshake on TCP when **either** the path is not loopback **or** `configure_tls` has a handler connected.

## Argus policy (no libocrpc patch from this repo)

**Local login does not use loopback for management.**

| Step | Transport |
|------|-----------|
| Issue certificate (`pkexec … --give-me-a-certificate`) | Unix `argus.sock` only |
| Open main window (probe + `use`) | Saved **interface** addresses from `Registration.certificate`, never fabricated `127.0.0.1` |

`address_list()` skips `127.0.0.1` / `::1` for probes. Do **not** rename dial targets to `localhost` to dodge libocrpc.

## Evidence

- `libocrpc/Client.vala` lines ~417–418 (2026-11-20).
- Argus removed Bootstrap `127.0.0.1` address fallback and server-side loopback append in `Registration.certificate` (2026-11-20).