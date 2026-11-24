# Provisional registration broadcast for office Windows bulk enroll

**Status:** ⏳

**Priority:** High — confirmed for next Windows office rollout.

### User decisions required

None.

### User reported

- 🔷 Bundle provisional broadcast, controller Agents UI, Windows desk enroll, and Linux bulk into one feature (prior chat).
- 🔷 **Reject / status poll** on registration port (~10 min client poll); **Accept** keeps registration port open until the machine finishes full registration on the app socket; ~30 min without upgrade → warn; app-level banner when some registrations failed to complete.
- 🔷 **Pending registration** tab: hide when empty; select by default when pending exist; emphasize (e.g. red) when the queue is non-empty.
- 🔷 **[`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala)** — PIN + countdown only for **Agent registration** and **Controller registration**; no pending list and no bulk inside the dialog.
- 🔷 Product spec in **Proposed fix** phases only.

### Success scenario

- Field verify: each phase’s **Done when** bullets pass on a lab controller, Linux agent, and Windows install.

### Current behavior

- [`controller/tab/Agent.vala`](../../controller/tab/Agent.vala) — one **Agent or Controller** button → [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala).
- [`server/Agent.vala`](../../server/Agent.vala) — **`Agent.stop`** deletes all **`agent_pending`**; batch queue only via pin **`0000`** + batch flag.
- [`agent/Win32/tray/Tray.vala`](../../agent/Win32/tray/Tray.vala) + [`shared/Register.vala`](../../shared/Register.vala) — unregistered tray opens dialog and browses **`_rpc._tcp`**, but user must type PIN manually; no provisional vs instant on the wire.
- [`shared/Register.vala`](../../shared/Register.vala) **`try_batch`** — polls the **app** socket with **`RPC-Daemon.hello`** (not registration port).
- [`server/Agent.vala`](../../server/Agent.vala) **`reject`** — deletes **`agent_pending`** only; client not informed.

### Codebase observed behavior

- [`controller/tab/Assets.vala`](../../controller/tab/Assets.vala) — **ViewSwitcher** + **ViewStack** (**Machines** / **Software**).
- [`controller/tab/Pairing.vala`](../../controller/tab/Pairing.vala) — tick list (today inside Register dialog).
- [`shared/Browse.vala`](../../shared/Browse.vala), [`shared/windows/Browse.vala`](../../shared/windows/Browse.vala) — mDNS browse.
- [`docs/rpc-commands.md`](../../docs/rpc-commands.md) — **`Agent.offer`**, **`accept`**, **`reject`**, **`stop`**.

### Debugging

#### Current debug output

None yet.

#### Debug code added (remove when complete)

None.

### Proposed fix

#### Phase 1 — Server: second Avahi publish + registration lifecycle

- **Broadcast**
  - **Second Avahi publish** for provisional bulk (separate from instant **agent** offer on existing **`_rpc._tcp`**).
- **Provisional enroll**
  - Bulk listener open → enrollments → **`agent_pending`** only, reply **`pending`**, **`event.pair` `pending`**.
  - **Close bulk listener:** stop publish and new provisional enroll; **do not** delete **`agent_pending`** rows.
- **Instant agent enroll**
  - **Agent registration** dialog path: issued PIN → active **`agent`** immediately (unchanged intent).
- **Controller vs agent paths**
  - A **controller** must not register using an **agent** registration PIN or the **provisional bulk** listener.
  - Server refuses with a short plain **`error.message`** (e.g. “This registration is for agents only.”) — no controller row created.
- **Registration port stays open**
  - After an operator ticks a row and **Accept**, keep the **registration** TLS listener up until that client has **completed full registration** (status poll returns **`accepted`**, then client connects on the **app** socket and is **active** / connected).
  - Same port serves **pending** / **rejected** status polls for rows still in **`agent_pending`** or waiting after **Accept**.
  - Close bulk broadcast does **not** mean closing registration TLS while any pending row or any **Accept** awaiting client upgrade remains.
- **Pending status poll + reject** (replaces **`try_batch`** app **`hello`** loop)
  - Clients poll **registration** host/port (~**ten minutes**; poll soon after enroll).
  - Registration handshake accepts **provisional client certificates** for the status RPC.
  - New registration-socket RPC (document in [`docs/rpc-commands.md`](../../docs/rpc-commands.md) with the change):
    - **`pending`** — still in **`agent_pending`**.
    - **`accepted`** — promoted to **`agent`**; client should move to app socket.
    - **`rejected`** — row removed; client wipes cert and shows “last registration was rejected”.
- **Stalled after Accept**
  - When **Accept** runs, start a **~30 minute** watchdog per machine.
  - If the agent has not status-polled, upgraded, and shown **connected** on the app socket within that window → mark **failed to complete registration** (stalled).
  - Controller: row state or badge on **Pending registration** tab; drive app-level warning (Phase 2).
- **Done when**
  - **Accept** then inactive client for 30+ minutes surfaces stalled state; active client clears watchdog; **Reject** returns **`rejected`** on next poll.

#### Phase 2 — Controller Agents page

- **Tabs** ([`controller/tab/Assets.vala`](../../controller/tab/Assets.vala) pattern)
  - **Agents** — registered grid.
  - **Pending registration**
    - **Hidden** when **`agent_pending`** is empty and no stalled **Accept** awaiting client upgrade (exact visibility rule in implementation).
    - **Selected by default** when the tab becomes visible because new pending rows exist.
    - **Visible emphasis** when the queue is non-empty (e.g. red tab label or indicator).
    - Embed [`controller/tab/Pairing.vala`](../../controller/tab/Pairing.vala): tick, **Accept**, **Reject** on the page bar.
- **Page toolbar**
  - **Bulk registration** — start/stop provisional broadcast + banner on page (“close when finished”).
  - **Agent registration** — opens [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala) (**PIN + countdown** only).
  - **Controller registration** — same dialog pattern, controller PIN only; server blocks agent/bulk paths (Phase 1).
  - No pending list inside the dialog.
- **Application warning**
  - Banner at top of controller window when **any** registration **failed to complete** (stalled after **Accept**, or operator-facing summary of stalled set).
  - Copy along the lines of: some registrations did not finish — check **Pending registration**.
- **Done when**
  - Tab hide/show/select/red behavior; banner appears when a stalled **Accept** is present.

#### Phase 3 — Windows client (unregistered)

- **Install** → tray → immediate **Register** dialog + background browse (provisional + instant agent publish).
- **Auto-register** on broadcast hit (PIN from TXT) where applicable.
- **Provisional** → **`pending`** cert → registration-port status poll (~10 min) → **`accepted`** → app socket + connected; **`rejected`** → wipe cert, show **last registration was rejected**, hunt again.
- If browse sees both offers, use **first resolved** offer (simultaneous dual offer is out of scope).
- **Done when**
  - Bulk on → auto provisional enroll → **Accept** on controller → Windows client reaches connected without manual PIN entry.

#### Phase 4 — Linux and shared register client

- Provisional broadcast + registration-port status poll (same as Phase 1 / 3).
- **`rejected`** / stall behavior matches Windows.
- **Done when**
  - Linux host **Reject** → next poll clears cert; **Accept** → full agent within 30 min or controller shows stall warning.

#### Phase 5 — End-to-end verify

- Bulk on → two provisionals → bulk off → queue remains → **Accept** one / **Reject** one.
- **Accept** then power off VM → within ~30 min controller shows stalled registration + app banner.
- **Agent registration** dialog: PIN only, instant one agent.
- Controller cannot enroll via agent PIN or bulk listener (plain error on server).

### LLM

- ℹ️ 2026-11-24: user decisions closed — high priority; second Avahi publish; tab **Pending registration**; Pairing PIN-only; registration port until client active; 30 min stall + app banner.
- ℹ️ Removed opaque “CSR” wording; controller-on-agent-path = plain **error.message**.
- ℹ️ `docs/bug-fix-process.md`, `docs/guide-to-writing-bug-reports.md`.