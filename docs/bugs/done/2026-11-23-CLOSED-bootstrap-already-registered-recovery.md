# Local login “already registered” must offer one-click recovery

**Status:** ✅ closed 2026-11-24 — parked with broader registration backlog (2026-11-21-CLOSED-local-enroll-register-session-refactor.md).

**Pointer:** `docs/bug-fix-process.md`, [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) (`exe_root`, `deregister_local`)

### User reported

- 🔷 Linux controller spins on startup (saved servers, failed TLS) and **Log in to local machine** returns *This machine is already registered.*
- 🔷 Copy tells the user to remove the machine **in Remote Manager**, but the controller window **is** the only registration tool — no recovery without CLI.

### Success scenario

- On *already registered*, one **primary** action clears local saved login **and** drops the server’s loopback controller row (`Registration.deregister` via pkexec), then **continues local enrollment** without a manual terminal step.

### Current behavior

- ✔️ [`Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) already shows **Deregister locally** beside **Retry** on that error (~543–550).
- 🚫 Body text still says *Delete it from the agent list in Remote Manager* — wrong for this lockout.
- 🚫 **Retry** runs `--give-me-a-certificate` again → same error loop.
- 🚫 **Deregister locally** ends on the empty home page; user must discover **Log in to local machine** a second time (`deregister_local` → `exe_root --deregister` only).

### Proposed fix

**Copy + one chained button** (minor UX; logic already exists).

1. **Replace body** on the already-registered page — remove Remote Manager; say local certs or server row block a new certificate and that the button clears both sides.
2. **Primary button** — e.g. **Clear registration and log in** (response id `recover`):
   - Same steps as `deregister_local()` (drop saved rows + keyring).
   - On successful `--deregister`, call `exe_root("--give-me-a-certificate", "controller", …)` instead of returning to the home page.
   - On deregister failure, stay on the error page with **Retry** only.
3. **Secondary** — keep **Deregister locally** (clear only, return home) or drop it if redundant.
4. **Remove or demote Retry** on this page — it must not re-issue a cert without deregister first.

#### `controller/dialog/Bootstrap.vala` — `exe_root` callback, already-registered branch

**Why:** Users hit the error from **Log in to local machine**; recovery should finish that flow, not send them back to the menu.

**Where:** `message == "This machine is already registered."` page + new `recover` handler in `add_button` (chain after successful `--deregister`).

**Depends on:** none (server username deregister on `argus.sock` already shipped in 2026-11-10).

### Root cause (2026-11-23 follow-up)

- ✔️ Deregister returned success but left **status = 1** rows with a routable `ip` — recovery re-issued the cert and hit *already registered* in a loop.
- ✔️ **Fix:** [`server/Registration.vala`](../../server/Registration.vala) username deregister deletes all controller rows for `username` + server hostname (any `ip` / `status`).

### LLM

- User (2026-11-24): close — whole registration UX/refactor is known backlog; reopen with a new ISSUE when resuming.

### Next

- ✔️ Parked; UX proposal above remains for a future pass.