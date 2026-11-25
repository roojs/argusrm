# Provisional registration — remaining work

**Status:** ⏳

**Priority:** High — confirmed for next Windows office rollout.

**Background:** Full product spec archived at [`done/2026-11-24-archived-provisional-registration-broadcast.md`](done/2026-11-24-archived-provisional-registration-broadcast.md). This file is the **active** checklist only.

**Pointer:** `docs/bug-fix-process.md`, [`docs/rpc-commands.md`](../rpc-commands.md), [`server/Offering/`](../../server/Offering/)

### User decisions required

None (carry forward from archived spec).

---

## Closed in tree (2026-11-25) — do not re-litigate

| Item | ✔️ |
| --- | --- |
| **`Offering.*`** wire (`open`, `close`, `enroll`, `accept`, `reject`; **`status`** stub) | [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala), [`docs/rpc-commands.md`](../rpc-commands.md) |
| **`Offering.Network`** (registration TLS, offering nftables, PairPublish) | [`server/Offering/Network.vala`](../../server/Offering/Network.vala) |
| **`Application.offering`**; no **`register_listen`** / **`publish`** on app | [`server/Application.vala`](../../server/Application.vala) |
| Delete **`server/Agent.vala`**; fleet **`SQT.Agent`** (`list`, `remove`, **`allowlist`**) | [`server/SQT/Agent.vala`](../../server/SQT/Agent.vala) |
| Clients: **`Offering.enroll`**, controller **`Offering.open`** / **`close`** / accept / reject | [`shared/Register.vala`](../../shared/Register.vala), [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala), [`controller/cli/Pin.vala`](../../controller/cli/Pin.vala) |
| Registration TLS gate **`Offering.enroll`** / **`Offering.status`** | [`server/Net/SslConnection.vala`](../../server/Net/SslConnection.vala) |
| Integration test (stub app, no full server link) | [`server/tests/offering-test-application.vala`](../../server/tests/offering-test-application.vala), **`meson test offering-registration`** — see [`done/2026-11-25-FIXED-offering-registration-test-main-loop.md`](done/2026-11-25-FIXED-offering-registration-test-main-loop.md) |

---

## Phase 1 — server lifecycle (still open)

- **`Offering.status`** — implement pending / accepted / rejected poll (replaces app-socket `hello` loop for provisional certs); document in `rpc-commands.md`.
- **Bulk close** — stop PairPublish / new provisional enroll; **keep** `agent_pending` rows; **`polling`** keeps registration TLS up (`SslListen` + handshake without PIN).
- **Reject** — optional client-visible **`rejected`** on status poll (archived spec).
- **Accept watchdog** — ~30 min stall when client never upgrades to app socket; surface state for controller (feeds Phase 2).
- **Controller-on-agent-path** — refuse controller enroll on agent PIN / bulk window (plain `error.message`).
- **Second `PairPublish`** for provisional bulk (product decision in archived spec).
- **Done when:** field script: bulk on → two provisionals → bulk off → queue persists → accept one / reject one; registration port stays up through accept/poll per spec.

---

## Phase 2 — controller Agents page

- **Pending registration** tab (hide / default-select / emphasis); toolbar **Bulk registration**, **Agent registration**, **Controller registration** (PIN dialog only — no pending list in dialog).
- App-level banner when registrations stall after **Accept**.
- **Done when:** tab behaviour + banner verified on lab controller.

---

## Phase 3 — Windows client (unregistered)

- Auto provisional enroll from browse; registration-port status poll (~10 min); **`accepted`** → app socket; **`rejected`** → wipe cert + user message.
- **Done when:** bulk on → **Accept** on controller → Windows connected without manual PIN.

---

## Phase 4 — Linux / shared register client

- Same status poll path as Phase 1 / 3; align **`Register.try_batch`** (or successor) with registration port, not app **`hello`**.
- **Done when:** Linux **Reject** / **Accept** paths match Windows.

---

## Phase 5 — end-to-end verify

- Scenarios in archived spec **Phase 5** (stalled VM after **Accept**, controller blocked on agent PIN, etc.).

---

### LLM

- ℹ️ 2026-11-25: Active tracker split from archived 2026-11-24 feature doc; Phase 1a + integration test signed off above.