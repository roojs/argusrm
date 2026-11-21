# Local enroll duplicated — logic in Gtk/Bootstrap instead of Register

**Status:** ⏳ refactor proposed — logic → `Register`; flow → shared session; UI → thin glue per app (not server)

**Pointer:** [`shared/Register.vala`](../../shared/Register.vala), [`agent/linux/LocalRegistration.vala`](../../agent/linux/LocalRegistration.vala), [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala), [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala), [done/2026-11-21-FIXED-agent-local-enroll-double-pkexec.md](done/2026-11-21-FIXED-agent-local-enroll-double-pkexec.md), `docs/bug-fix-process.md`

---

## Problem

- 🔷 **Agent** Gtk **Connect locally** and **controller** Bootstrap **Log in to local machine** both run `argusrm-server --give-me-a-certificate`, parse the same `Argus.Shared.SQT.Server` JSON, handle **already registered**, then save through `Register.save` (agent restarts service; controller runs `finish_registration`).
- 🔷 **Expected:** one shared registration implementation; agent and controller only differ in elevation (pkexec vs already-root), post-success hooks, and which Gtk shell paints the steps.
- ✔️ **Actual:** subprocess + JSON + error mapping live in [`agent/linux/LocalRegistration.vala`](../../agent/linux/LocalRegistration.vala) `enroll_certificate`; parallel spawn/parse/string-match logic lives in [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) `exe_root`. Step machine and notices are agent-only; Bootstrap uses `page()` buttons.

---

## Evidence

- ✔️ Agent after pkexec runs `SERVER_EXECUTABLE --give-me-a-certificate agent` directly (no nested pkexec) — see current `LocalRegistration.enroll_certificate`.
- ✔️ Controller runs `pkexec` + `SERVER_EXECUTABLE --give-me-a-certificate controller` — `Bootstrap.exe_root`.
- ✔️ Agent conflict path uses `RegistrationError.ALREADY_REGISTERED` + Unix `Registration.deregister` `"agent"` before retry.
- ✔️ Controller conflict still branches on `message == "This machine is already registered."` inside `exe_root` (~537).
- ✔️ Shared already: `Register.probe_local`, `RegistrationError`, `Register.save`, remote flow via `RegisterWindow`.
- 🚫 **Not in scope:** server `Registration.certificate` or daemon `--give-me-a-certificate` handler (stay in server package).

---

## Root cause

- ✔️ Local enroll was wired per-product (Gtk notice refactor, then `LocalRegistration`) instead of extending [`Register`](../../shared/Register.vala) the way remote PIN registration does.
- ✔️ No shared **session** object: Gtk state machine and Bootstrap pages each re-encode ENROLL → success | conflict | failed and retry/remove loops.

---

## Proposed fix

### Layering

| Layer | File (new or extend) | Owns |
| ----- | -------------------- | ---- |
| Logic | [`shared/Register.vala`](../../shared/Register.vala) | Spawn helper, parse JSON, set `server_row`, `RegistrationError`, agent Unix deregister `"agent"` |
| Flow | **Add** [`shared/LocalEnrollSession.vala`](../../shared/LocalEnrollSession.vala) | Step enum, single `advance()`, signals for UI; **no** Gtk, **no** `ServiceManager`, **no** `finish_registration` |
| Agent UI | [`agent/linux/LocalRegistration.vala`](../../agent/linux/LocalRegistration.vala) | Connect session → `Notice`; on success → `reg.save(Agent.SQT.Server)` + `service.restart(false)` |
| Controller UI | [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) | Connect session → `page()`; on success → `finish_registration` |
| Optional | **Add** [`shared/LocalEnrollNotice.vala`](../../shared/LocalEnrollNotice.vala) | Notice presenter for session signals (agent; controller may keep Bootstrap adapter) |

Elevation (document once on `Register`):

| Client | Elevation |
| ------ | --------- |
| Agent Gtk after pkexec | Run server binary **direct** (`geteuid() == 0`) |
| Controller user session | **Pkexec** on `Argus.SERVER_EXECUTABLE` |

### Add — `shared/Register.vala`

#### Add — local certificate API (conceptual)

- `public async void issue_local_certificate(string role, bool use_pkexec) throws GLib.Error`
  - `role` is `"agent"` or `"controller"`.
  - Builds argv for `--give-me-a-certificate`; on success sets `server_row`; maps server `error` → `RegistrationError.ALREADY_REGISTERED` when appropriate.
- `public async void deregister_managed_agent_on_server() throws GLib.Error` (Linux agent only)
  - Unix socket `Registration.deregister` with `"agent"` (moved from `LocalRegistration.enroll_certificate`).

Post-success **save** and platform hooks remain **callers** (agent row + restart; controller `finish_registration` + CA policy).

### Add — `shared/LocalEnrollSession.vala`

#### Add — session + signals

```vala
public enum LocalEnrollClient {
	AGENT,
	CONTROLLER
}

public class LocalEnrollSession : GLib.Object {
	public Register reg { construct; }
	public LocalEnrollClient client { construct; }

	public signal void present_busy(string heading);
	public signal void present_success(string heading, string body);
	public signal void present_failure(string detail);
	public signal void present_conflict(string detail);

	public void start();
	public void user_retry();
	public void user_remove_on_server();
	public void user_dismiss();
}
```

- 🔷 **ENROLL:** optional deregister when `replace` (agent: `Register.deregister_managed_agent_on_server`), then `Register.issue_local_certificate` with client-appropriate pkexec flag.
- 🔷 **CONFLICT / FAILED / SUCCEEDED:** emit one `present_*` signal; **do not** call `save` inside session.
- 🔷 UI glue calls `user_retry()` / `user_remove_on_server()` from buttons → session sets step and `advance()` again.

### Replace — [`agent/linux/LocalRegistration.vala`](../../agent/linux/LocalRegistration.vala)

- **Remove** `enroll_certificate` body (subprocess, JSON, deregister RPC).
- **Remove** local `LocalEnrollStep` enum if moved to session.
- **Replace with:** construct `LocalEnrollSession`, wire `present_*` to `Notice`, forward user actions to session; on `present_success` (or dedicated `enroll_complete` if added), `reg.save` + `service.restart(false)`.

### Replace — [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) `exe_root` (certificate path)

- **Remove** duplicate spawn/parse and string match for already registered when `option == "--give-me-a-certificate"`.
- **Replace with:** `LocalEnrollSession` + `present_*` → existing `page()` patterns; keep `--deregister` on controller executable until a second `Register` method exists for controller local deregister.

### Build

#### Add — [`agent/meson.build`](../../agent/meson.build), [`shared/meson.build`](../../shared/meson.build), [`docs/meson.build`](../../docs/meson.build)

- List `shared/LocalEnrollSession.vala` (and optional `LocalEnrollNotice.vala`) beside existing shared sources.

---

## Test plan

- ⏳ Existing `tests/registration-wire`, `tests/registration-enroll`, `tests/registration-bootstrap` keep passing.
- ⏳ **Add** or extend test calling `Register.issue_local_certificate` against temp server JSON (no Gtk).
- ⏳ Manual: agent **Connect locally**; controller **Log in to local machine** + conflict **Deregister locally** / **Retry**.

---

## Implementation order

1. ⏳ **`Register.issue_local_certificate`** + agent `LocalRegistration` delegates (no behaviour change).
2. ⏳ **`LocalEnrollSession`**; agent uses session signals.
3. ⏳ Bootstrap certificate path through session; drop message string match for conflict.
4. 💩 Optional `LocalEnrollNotice` if agent glue is still thick.

---

## Attempts / changelog

- ✔️ 2026-11-21: Agent **Connect locally** split to [`LocalRegistration.vala`](../../agent/linux/LocalRegistration.vala) with step machine + `RegistrationError` (interim; not the target architecture).
- ⏳ This log — target architecture for shared logic + shared session + per-app UI glue.

---

## Next

- ⏳ User approval to implement in the order above (design/API change across agent + controller; not a one-line fix).
- ℹ️ Gtk subprocess policy is documented in [done/2026-11-21-FIXED-agent-local-enroll-double-pkexec.md](done/2026-11-21-FIXED-agent-local-enroll-double-pkexec.md); move implementation into `Register` under this refactor.