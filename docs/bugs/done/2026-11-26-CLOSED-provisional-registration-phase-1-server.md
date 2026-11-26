# Provisional registration — Phase 1 server lifecycle

**Status:** ✅

### User decisions required

- None.

### User reported

- 🔷 Ship provisional bulk registration for the next Windows office rollout: server must expose registration-port status and desk lifecycle before controller and client work.

### Success scenario

- `meson test offering-registration` passes status and polling-enroll checks.
- Field script: bulk on → two provisionals → bulk off → queue persists → accept one / reject one; registration port stays up through accept/poll.

### Current behavior

- Phase 1 shipped 2026-11-26; follow-on work is active tracker `2026-11-26-FEATURE-provisional-registration-clients-and-verify.md`.

### Codebase observed behavior (at close)

- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) — `Offering.status` (`pending` / `accepted` / `rejected`), `rejected_provisional`, enroll bulk guard, controller-on-agent-path, batch accept/reject load, accept stall broadcast.
- [`server/Offering/Network.vala`](../../server/Offering/Network.vala) — bulk ARM supervisor drop → `POLLING` when `agent_pending` non-empty.
- [`server/Net/SslListen.vala`](../../server/Net/SslListen.vala) — registration listener does not run app-socket known-agent task connect path.
- [`docs/rpc-commands.md`](../../docs/rpc-commands.md) — `Offering.status` documented.
- [`server/tests/offering-registration.vala`](../../server/tests/offering-registration.vala) — status with provisional client certs; no enroll while polling.

### Debugging

#### Current debug output

- None.

#### Debug code added (remove when complete)

- None.

### Proposed fix

- Applied as documented in this file’s LLM (2026-11-25 … 2026-11-26 proposal passes). Historical Remove/Replace fences removed on archive — see git history and product files above.

### LLM

- ℹ️ 2026-11-25: Phase 1a wire + `offering-registration` test (see `2026-11-25-FIXED-offering-registration-test-main-loop.md` in this folder).
- ✔️ 2026-11-26: Phase 1 server lifecycle landed; `meson test offering-registration` OK.
- ℹ️ Optional second `PairPublish` — moved to `2026-11-26-FEATURE-provisional-registration-clients-and-verify.md` (user decision).
- ℹ️ Split 2026-11-26: phases 2–5 continue in that active tracker; remainder tracker deleted.

**Closed in tree with Phase 1 (2026-11-25 … 2026-11-26)**

| Item | ✔️ |
| --- | --- |
| **`Offering.*`** wire including **`status`** | [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala), [`docs/rpc-commands.md`](../../docs/rpc-commands.md) |
| **`Offering.Network`** registration desk | [`server/Offering/Network.vala`](../../server/Offering/Network.vala) |
| **`Application.offering`** | [`server/Application.vala`](../../server/Application.vala) |
| Fleet **`SQT.Agent`** | [`server/SQT/Agent.vala`](../../server/SQT/Agent.vala) |
| Registration TLS allowlist | [`server/Net/SslConnection.vala`](../../server/Net/SslConnection.vala) |
| Integration test | `meson test offering-registration` |