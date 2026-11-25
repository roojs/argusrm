# offering-registration test: main-loop stall on registration TLS

**Status:** ✅ closed 2026-11-25

**Pointer:** [`server/tests/offering-registration.vala`](../../server/tests/offering-registration.vala), [`server/tests/offering-test-application.vala`](../../server/tests/offering-test-application.vala), [`docs/bugs/2026-11-25-FEATURE-provisional-registration-remainder.md`](../2026-11-25-FEATURE-provisional-registration-remainder.md)

### Observed

- `meson test offering-registration` timed out at 60s.
- Each `Offering.enroll` from the test logged `Socket I/O timed out` ~10s apart.
- Unix `Offering.open` succeeded; failures were only on `TlsClient.call` to the registration port.

### Cause

The test `run()` async method drives the server on the default `MainContext`. Synchronous `TlsClient.call` on the same thread blocked that context, so `SslListen` could not finish `handshake_async` and accept RPC.

### Fix

- `server/tests/offering-registration.vala`: **`RegistrationTlsJob`** runs each registration `TlsClient.call` on a worker thread while the test pumps `MainContext.default().iteration(false)` until the job completes.
- CSR material: per-label subdirs under `agent-tls/` with `client.pem` / `client-key.pem` / `client.csr` (same as [`shared/Register.vala`](../../shared/Register.vala)).
- **`argus-offering-registration`** links a test-only [`Application`](../../server/tests/offering-test-application.vala) stub instead of production [`server/Application.vala`](../../server/Application.vala) — see remainder bug for harness scope.

### Verification

```bash
meson test -C build offering-registration --print-errorlogs
```

- ✔️ 2026-11-25: pass ~1.2s as unprivileged user (nftables setup warnings only; `NFTables.ready` stays false).

### Closure

No product code change. Do not reopen — new registration-test issues get a new bug under `docs/bugs/`.