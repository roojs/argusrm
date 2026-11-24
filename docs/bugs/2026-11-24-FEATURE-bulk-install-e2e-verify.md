# Bulk install (Agents paste loop) never verified end-to-end

**Status:** ⏳

### User decisions required

- 💩 Run the manual E2E below on at least one Debian host (optional: one LXC) and record results under **Debugging**.

### User reported

- 🔷 Bulk install flow was planned and may be implemented, but it has never been exercised on real hosts.
- 🔷 Wants a bug log for tracking that verification, not the plan doc sitting open as proposed work.
- 🔷 Until the controller **Bulk** paste loop exists, exercise the same outcome with **RooTerm** on the targets and the existing **batch registration** UI on the controller.

### Success scenario

Manual batch path (no controller Bulk UI required):

1. **Controller — open registration.** Agents page → **Agent or Controller**. The Register dialog opens (six-digit offer and countdown). Leave it open. Order vs the agents does not matter: targets can run **Register** before or after this step; `argusrm-agent --request` retries while the window is closed.
2. **Each target — via RooTerm**, as root (or `sudo -i` the same way bulk install would):
   - Add the roojs APT repo and install `argusrm-agent` (same steps as `scripts/ci/enable-roojs-apt.sh`, then `apt-get install -y argusrm-agent`). Service stays stopped until registration succeeds.
   - Run `argusrm-agent --request --server SERVER` where `SERVER` is the controller’s registration address (not `--pin`).
3. **Controller — approve.** The first `--request` flips the dialog from PIN mode to the pending queue (`Tab.Pairing` inside the same dialog). Further hosts append. Tick the machines to keep → **Accept** (or **Reject** the rest). The registration socket stays open for more requests while the dialog is up.
4. **Pass:** each accepted host appears on the Agents grid with the expected hostname and reaches connected (✔️) after the agent’s normal-port poll succeeds.

Optional later (same report, different phase): controller **Bulk** paste runs Install + Register over SSH per `docs/plans/done/2.2-MOVED-bulk-install.md`, using `--request` on each target instead of per-host PINs.

### Current behavior

- No end-to-end test has been recorded for either the manual RooTerm path or a future Bulk UI.
- The moved plan `docs/plans/done/2.2-MOVED-bulk-install.md` still described controller paste/SSH as unbuilt when archived.

### Codebase observed behavior

- Batch registration (agent `--request`, `agent_pending`, pairing queue, Accept/Reject) is in the tree; see `docs/bugs/done/2026-11-18-FIXED-batch-agent-registration.md` — **not field-tested** on a multi-host batch.
- Repo search (2026-11-24) finds no `rooterm`, `lxc-attach`, or Bulk UI strings under [`controller/`](../../controller/).
- [`controller/tab/Agent.vala`](../../controller/tab/Agent.vala) is the Agents grid plus **Agent or Controller**; no paste or SSH loop.
- Bulk paste specification: [`docs/plans/done/2.2-MOVED-bulk-install.md`](../plans/done/2.2-MOVED-bulk-install.md).

### Debugging

#### Current debug output

None yet.

#### Debug code added (remove when complete)

None.

### Proposed fix

#### Phase 1 — Manual E2E (RooTerm + Register dialog)

- Pick one VM without `argusrm-agent` (and optionally one LXC line on a host).
- Run the **Success scenario** steps in order or with controller Register opened first; both orders should work.
- Note controller build/version, agent package version, dates, and short log excerpts (agent wait line, dialog queue rows, Agents grid).
- For LXC: install and `--request` inside `lxc-attach`, not `lxc-console`.

#### Phase 2 — Controller Bulk UI (when built)

- Re-run with exported RooTerm lines and Bulk **Install** then **Register**, still using `--request` per target unless the product explicitly chooses PIN-per-host.
- Record the same evidence under **Debugging**.

### LLM

- ℹ️ `docs/bug-fix-process.md`, `docs/guide-to-writing-bug-reports.md`.
- ℹ️ Batch approval UI: `controller/dialog/Pairing.vala`, `controller/tab/Pairing.vala`; server `agent_pending`.
- ℹ️ Parent packaging: `docs/plans/done/2.1.5-DONE-installation-packaging.md`; registration: `docs/plans/done/2.1-DONE-registration-flow.md`.
- ℹ️ Moved bulk paste plan archived 2026-11-24; E2E Phase 1 does not wait on it.