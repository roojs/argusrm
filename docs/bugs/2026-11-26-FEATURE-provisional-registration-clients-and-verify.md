# Provisional registration — controller, clients, verify

**Status:** ⏳

### User decisions required

- 💩 **Second `PairPublish` on bulk open** — separate mDNS publish from the six-digit PIN window, or keep one `pair_publish` for both until lab needs split.

### User reported

- 🔷 Continue provisional bulk registration after server Phase 1: controller Agents UI, Windows/Linux clients on registration-port status poll, then field verify for office rollout.

### Success scenario

- Phase 2 — Pending registration tab (hide / default-select / emphasis); toolbar **Agent**, **Controller**, **Bulk registration** (agents). Bulk hides that button and shows Pending, where **Stop bulk registration** lives. App banner when `event.pair` `stalled` after Accept.
- Phase 3 — Windows: auto provisional enroll from browse; `Offering.status` poll (~10 min); `accepted` → app socket; `rejected` → wipe cert + message.
- Phase 4 — Linux/shared: `Register.try_batch` (or successor) polls registration port with `Offering.status`, not app `RPC-Daemon.hello`.
- Phase 5 — End-to-end: bulk on → two provisionals → bulk off → queue → accept/reject; stalled VM after Accept; controller blocked on agent PIN paths; office rollout script.

### Current behavior

- Server Phase 1 is in the tree (`Offering.status`, polling enroll guard, reject tombstones, accept stall notification, bulk ARM → POLLING when queue non-empty).
- ✔️ Sidebar **Agent / Controller registration** → [`controller/tab/Register/Agent.vala`](../../controller/tab/Register/Agent.vala) with **Current** ([`Current.vala`](../../controller/tab/Register/Current.vala), was fleet grid) and **Pending** ([`Pending.vala`](../../controller/tab/Register/Pending.vala) + `Store.Pairing` / `Tab.Pairing`); Pending subtab hidden when empty; auto-select on `event.pair` `pending`.
- Toolbar is **Agent**, **Controller**, and **Bulk registration**. Bulk calls `Offering.open` `pending` true, hides that button, and selects Pending. **Stop bulk registration** on Pending calls `Offering.close` `pending` true. Stall banner and dialog queue removal not built yet.
- [`shared/Register.vala`](../../shared/Register.vala) `try_batch` still polls the app socket with `RPC-Daemon.hello` after provisional enroll.
- Windows unregistered tray path has no auto provisional enroll + registration status poll.
- Accept stall timer is not cancelled when the agent connects on the app socket (Phase 2).

### Codebase observed behavior

- [`controller/tab/Agent.vala`](../../controller/tab/Agent.vala) — fleet grid; pairing not split into pending tab.
- [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala) — PIN / bulk close; pending list not on Agents page toolbar.
- [`shared/Register.vala`](../../shared/Register.vala) — `try_batch` status wait uses app TLS + `hello` (~665+).
- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) — `event.pair` `stalled` broadcast; no controller consumer yet.
- Phase 1 server lifecycle is closed in `docs/bugs/done/2026-11-26-CLOSED-provisional-registration-phase-1-server.md` (plain path; not a product file).

### Debugging

#### Current debug output

- None yet.

#### Debug code added (remove when complete)

- None.

### Proposed fix

- Not written yet — open phases 2–5 in order when each is next. Spec detail in archived `2026-11-24-archived-provisional-registration-broadcast.md` under `docs/bugs/done/`.

### Phase 2 — controller Agents page

- ✔️ **Pending registration** tab (hide / default-select / `needs_attention` when non-empty); Accept/Reject on the page tab.
- ✔️ Toolbar **Agent**, **Controller** (PIN dialog), **Bulk registration** (agents). Bulk hides the button and shows Pending. **Stop bulk registration** is on that tab.
- ⏳ Consume **`event.pair`** `stalled`; cancel accept watchdog when app socket connects; app-level stall banner.
- **Done when:** tab behaviour + banner verified on lab controller.

### Phase 3 — Windows client (unregistered)

- Auto provisional enroll from browse; registration-port **`Offering.status`** poll (~10 min).
- **Done when:** bulk on → **Accept** on controller → Windows connected without manual PIN.

### Phase 4 — Linux / shared register client

- Same status poll as Phase 1 server wire; align **`Register.try_batch`** with registration port.
- **Done when:** Linux **Reject** / **Accept** paths match Windows.

### Phase 5 — end-to-end verify

- Scenarios from archived spec (stall after Accept, controller on agent PIN, bulk queue script).

### LLM

- ℹ️ Priority: high — next Windows office rollout.
- ℹ️ Continues from closed `2026-11-26-CLOSED-provisional-registration-phase-1-server.md` and archived `2026-11-24-archived-provisional-registration-broadcast.md`.
- ℹ️ Process: `docs/bug-fix-process.md`, `docs/rpc-commands.md`, `server/Offering/`.
- ℹ️ 2026-11-26: Phase 2 — namespace `Tab.Register`; container `Register.Agent`; `TabList.select_registration` when pending opens.
- ℹ️ 2026-11-26: Bulk active does not retitle the sidebar. Pending appears, Bulk registration hides, stop is on Pending. Agent and Controller stay insensitive while bulk is open so a PIN does not replace the provisional publish.