# Android controller: `DebPackages.list` decode failure drops TLS; lists show Client disconnected

**Status:** ✅

## User decisions required

None.

## User reported

- 🔷 Debian package list on the phone **seems to be working now** (2026-11-23); not sure what changed.
- 🔷 Close the bug for now if it is working.
- 🔷 After the post-PIN connect fix, the Android controller opens and SystemInfo / startup lists work, but Software → Debian packages shows Could not list Debian packages / Client: disconnected, then Machines and tasks fail the same way.
- 🔷 Expected: same RPC behaviour as desktop `argusrm-controller` on the same server.
- 🔷 Reproduce: connect on phone, open aggregated Debian packages (Software).

## Success scenario

- On `SM-S9380` (or current test phone), Software → Debian packages loads rows without decode or transport errors on a single TLS session to the lab server.
- `DebPackages.list` completes without `expected object type byte` in phone `controller.log`; server log shows a normal reply without client reset mid-write for that call.
- After opening Debian packages, Machines, tasks, and other tabs keep working without cascading Client: disconnected from a broken session.
- Desktop controller on the same server still works (regression guard).

## Current behavior

- 2026-11-22 repro: `DebPackages.list` decode failure (`0x75`), disconnect, follow-on tab errors (see **Debugging**).
- 2026-11-23 phone session (`controller.log` via adb): `DebPackages.list` ids **10**, **20**, **32** each get `replied id=…`; **no** `0x75` / parse errors in the current log file.
- 2026-11-23 user: Debian package list working; issue closed without a pinned product fix.

## Codebase observed behavior

- [`controller/store/DebPackages.vala`](../../../controller/store/DebPackages.vala) calls `DebPackages.list` with `agent_id` 0 and `since` 0 on the shared Android/desktop store path; the full reply is decoded into a `Gee.ArrayList` before the grid updates.

```vala
this.app.rpc.call.begin(new OLLMrpc.Request() {
	method = "DebPackages.list",
	args = OLLMrpc.args("ii", agent_id, 0)
}, …);
```

- [`controller/tab/Asset/DebPackages.vala`](../../../controller/tab/Asset/DebPackages.vala) loads the store when the Software Debian page is mapped (`store.load(0)`).
- [`controller/android/Window.vala`](../../../controller/android/Window.vala) `check_connection()` runs every second; on drop it calls `rpc.disconnect()` then `rpc.connect.begin(hello)` with 5 s backoff — follow-on tab failures can be from a session already desynced, not only from hello logic.
- Throwaways under [`tests/`](../../../tests/) (e.g. [`list-probe.vala`](../../../tests/list-probe.vala), [`debpackages-reply-snapshot.vala`](../../../tests/debpackages-reply-snapshot.vala)) — manual probes, not product changes.
- Wire contract: [`docs/rpc-commands.md`](../../rpc-commands.md) — `DebPackages.list` args `ii`, reply is an array of `DebPackages` rows (aggregated when `agent_id` is 0).

## Debugging

### Current debug output

- Phone (2026-11-22, `controller.log` on device):
  - `DebPackages.list` id=5 → `expected object type byte, got 0x75` → disconnect.
  - Follow-on hello / `Agent.list` parse failures after session desync.
- Server (2026-11-22, `/var/log/argusrm/server.log`):
  - `DebPackages.list` id=5 on phone TLS conn; ~360 ms later client reset by peer while server still writing reply.
  - Second desktop controller session active same window.
- Host (2026-11-23):
  - `build-probe/tests/argus-list-probe 192.168.0.16 817 fastboy` — **5346** rows decoded, exit 0.
  - `build-probe/tests/argus-debpackages-reply-snapshot` — **986548** B snapshot; offline decode **5346** rows.
- Phone (2026-11-23 ~01:10 local, `pull-controller-log.sh`): `DebPackages.list` → `replied` ~1.5–2 s later (ids 10, 20, 32).

### Debug code added (remove when complete)

None.

### Investigation plan (throwaways — archived)

| Step | What | Status |
| ---- | ---- | ------ |
| 1a | `build-probe/tests/argus-list-probe` | ✔️ 2026-11-23 |
| 1b | UI repro + `pull-controller-log.sh` | ✔️ 2026-11-23 log |
| 1c | `argus-debpackages-reply-snapshot` | ✔️ 2026-11-23 |
| 1e | `argus-debpackages-snapshot-decode` | ✔️ 2026-11-23 |

## Proposed fix

None applied — closed with symptom resolved on device; reopen with a new dated ISSUE if `0x75` / disconnect returns.

## LLM

- **Archived:** 2026-11-23 user confirmed close; root cause not pinned (possible concurrent desktop controller + large reply on 2026-11-22).
- **Throwaways kept in tree** for regression: `tests/list-probe.vala`, `debpackages-reply-snapshot.vala`, `debpackages-snapshot-decode.vala`, `debpackages-android-list-probe.vala`, `scripts/android/run-debpackages-list-probe.sh`.
- **Related (still open):** [`docs/bugs/2026-11-22-android-controller-offline-reconnect.md`](../2026-11-22-android-controller-offline-reconnect.md).