# Windows remote desktop does not take over the signed-in user's session

**Status:** ⏳

### User decisions required

- 💩 **Takeover mechanism when a user is signed in at the Windows desktop:** choose which path Phase 1 should target (or combine):
  1. **Tray-coordinated RDP takeover (same-user or admin-approved):** `argus-tray.exe` handles consent/idle auto-allow, reports the signed-in account and session state to the controller, stops `argus_end_rdp_sessions()` from killing an active session, and shows who took control + a Disconnect button. Note: standard Windows 10/11 Pro RDP only attaches to the user's *existing* desktop (keeping their open windows) when signing in as that **same Windows account** (which locks the physical screen); signing in as a *different* admin account logs the user off / opens a separate desktop.
  2. **Session-1 live desktop takeover via the tray / Session-1 helper (non-RDP):** reuses the proven `tests/screenshot-poc/` path (`BitBlt` + `libjpeg-turbo` + `SendInput` over the existing `Relay` channel) so an admin can view and click directly inside the signed-in user's live session without needing the user's Windows password and without locking them out. (Elevated/UAC prompts require a SYSTEM-token helper spawned into Session 1 by `argus-agent`.)
  3. **Hybrid:** use RDP when nobody is signed in (or when the operator signs into the same account), and use Session-1 takeover (coordinated with `argus-tray.exe`) when taking over another signed-in user's active desktop.
- 💩 **Desktop window sizing mode (deferred to Phase 3 alongside takeover):** choose whether the controller viewer should (a) negotiate and dynamically resize the remote desktop to match the controller tab (`MS-RDPEDISP` for RDP), or (b) scale the remote desktop to fit the controller pane (aspect-preserving fit with optional 1:1 scroll toggle, which works identically for both RDP and native-monitor Session-1 takeover).

### User reported

- 🔷 The RDP connection stays up and performance and mouse clicks are pretty much there, so the previous TCP reset bug can be closed out.
- 🔷 We are not taking over the signed-in Windows session.
- 🔷 Taking over the session needs to involve the Windows Argus tray (`argus-tray.exe`) somehow, so we need to plan around that.
- 🔷 The window desktop size is also not correct, and should be dealt with once we sort out session takeover.

### Success scenario

- When an operator starts remote control on a Windows machine with a signed-in user, `argus-tray.exe` participates in the takeover flow: checks idle time or asks the signed-in user for consent (unless Force is enabled), informs the controller while waiting so the page is not blank, and displays who from Argus has control with a Disconnect action.
- The operator lands on the intended Windows session without unexpectedly logging off an active user or opening an unrelated empty desktop when trying to assist them.
- The remote desktop renders at the right size inside the controller tab, with accurate pointer coordinates and no awkward fixed fallback clipping.

### Current behavior

- Clicking Take control in the controller connects via FreeRDP3 over `127.0.0.1:3389` on `snappr-win` (`0.1.63`), holds cleanly with GFX RFX Progressive, and accepts mouse clicks, scrolling, and keyboard input.
- The Windows service turns Remote Desktop on during `initialize()` without asking `argus-tray.exe` and never sends the `agent.desktop` notification.
- `Tunnel.open_windows()` unconditionally calls `adapter.logoff()` (`Win32.argus_end_rdp_sessions()`), logging off any existing `RDP-*` session before dialing `127.0.0.1:3389`.
- The controller prompts for a Windows username and password with no awareness of who is currently signed into the machine. Signing in as a different user does not attach to the signed-in user's desktop.
- `Screen.begin()` reads `this.picture.get_width()` / `get_height()` before a frame is painted (`0×0`), so it falls back to `1280×720` and displays inside a `Gtk.ScrolledWindow` with `can_shrink = false`, leaving the desktop size mismatched to the controller window.

### Codebase observed behavior

- [`agent/windows/Service.vala`](../../agent/windows/Service.vala):
  - `initialize()` (lines 266–282) calls `this.desktop()` directly whenever `os_version.supports_rdp()` is true, bypassing the tray consent path.
  - `allow()` (lines 292–304) handles `AgentService.allow(bool yes)` from the tray, but nothing in `Service.vala` ever broadcasts `agent.desktop` on `this.local_listen`.
  - `relay_start()` (lines 425–501) immediately opens `Tunnel.open_windows(rpc)` without checking who is signed in, whether the user is active/idle, or notifying `argus-tray.exe`.
  - `tick()` (lines 660–716) already discovers the active session via `argus_active_session()`, queries its token via `WTSQueryUserToken`, and launches `argus-tray.exe` on `winsta0\default`.
- [`agent/windows/tray/Tray.vala`](../../agent/windows/tray/Tray.vala):
  - Already listens for `agent.desktop` on `tcp://127.0.0.1:4142` (lines 197–200) and implements `ask()` (lines 829–852): checks `GetLastInputInfo` for 30-minute idle auto-allow, otherwise displays a `Shell_NotifyIconW` balloon ("An admin wants to take over") whose click (`NIN_BALLOONUSERCLICK`, lines 411–427) calls `AgentService.allow(true)`.
  - Does not yet handle takeover-active notifications (who has control), a Disconnect control, denial/timeout reporting back to the service, or reporting the signed-in user/session metadata.
- [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala) and [`win32/register-pipe.c`](../../win32/register-pipe.c):
  - `Tunnel.open_windows()` (line 192) calls `this.adapter.logoff()` → `Win32.argus_end_rdp_sessions()`, which enumerates WTS sessions and calls `WTSLogoffSession` on every `WTSActive` / `WTSDisconnected` session whose `pWinStationName` starts with `RDP` (`win32/register-pipe.c` lines 51–73).
- [`controller/Rdp/Screen.vala`](../../controller/Rdp/Screen.vala) and [`controller/tab/Rdp.vala`](../../controller/tab/Rdp.vala):
  - `Screen` sets `can_shrink = false`, `content_fit = Gtk.ContentFit.SCALE_DOWN`, `halign = START`, `valign = START` (lines 83–90) inside a `Gtk.ScrolledWindow` (`controller/tab/Rdp.vala` lines 245–249).
  - `Screen.begin()` reads `this.picture.get_width()` and `this.picture.get_height()` (lines 355–362) before any paintable exists, falling back to `1280×720`, and never renegotiates size on window resize.
- [`docs/rpc-commands.md`](../../docs/rpc-commands.md):
  - Documents `AgentService.allow` and `agent.desktop` (lines 86–87) and `Relay.start` / `relay.start` / `relay.status` (lines 536–564). Any new or changed RPC method/notification must be recorded here in the same change.

### Debugging

#### Current debug output

- None yet for this issue. Prior RDP transport evidence is archived in [`docs/bugs/done/2026-11-26-FIXED-windows-desktop-tcp-reset.md`](done/2026-11-26-FIXED-windows-desktop-tcp-reset.md).

#### Debug code added (remove when complete)

- None.

### Proposed fix

#### Phase 1 — Define and verify the Windows session takeover path

- Confirm the target takeover mode with the user (see **User decisions required**):
  - **If RDP takeover:** test on `snappr-win` what happens with an active Console user (same account vs different account) and with an active RDP session when `argus_end_rdp_sessions()` is removed/gated; check whether Windows 10/11 Pro supports any non-destructive session attach or if same-account sign-in is the hard OS boundary.
  - **If Session-1 helper / tray takeover (or hybrid):** wire the proven `tests/screenshot-poc/` capture + input worker design into a clean Session-1 takeover flow coordinated by `argus-agent` and `argus-tray.exe` over the existing `Relay` channel (no Windows user password required, no console lockout, native monitor resolution).
- Do not edit product code until the takeover path is chosen and any Windows session-API edge cases are verified in a throwaway on `snappr-win`.

#### Phase 2 — Argus Tray consent, status, and disconnect handshake

- Extend the local RPC contract between `agent/windows/Service.vala` and `agent/windows/tray/Tray.vala` (and update `docs/rpc-commands.md` + `Argus.Rdp.State` in `shared/Rdp.vala`):
  - **Pre-takeover check:** when `relay.start` arrives and an interactive session exists (`argus_active_session() != 0xFFFFFFFF`), the service queries/notifies `argus-tray.exe` (`agent.desktop` with operator identity and `force` flag).
  - **Consent / idle gate:** if `force` is false and `GetLastInputInfo` is under 30 minutes idle, the tray asks the signed-in user (allow / deny / timeout), while the service reports a waiting-for-user state via `Relay.report` so the controller displays a clear status instead of hanging blank.
  - **Active takeover banner & disconnect:** once takeover starts, the service notifies the tray with the controller/operator name; the tray updates its tooltip/menu/dialog to show who has control and offers a **Disconnect** action (`AgentService.disconnect`) that tears down the active tunnel/session immediately.
  - **Session metadata to controller:** report whether a user is signed in (and which account / session type) so the controller UI can inform the operator before/during sign-in (or prefill/skip credentials if using Session-1 takeover).

#### Phase 3 — Desktop window sizing and scaling

- Fix initial dimension detection in [`controller/Rdp/Screen.vala`](../../controller/Rdp/Screen.vala) / [`controller/tab/Rdp.vala`](../../controller/tab/Rdp.vala): read the viewport (`Gtk.ScrolledWindow` / `pictures` stack) allocation instead of the uninitialized `0×0` `Gtk.Picture`.
- Align sizing with the chosen Phase 1 takeover mechanism:
  - For **RDP:** request the viewport size at connect time and add dynamic display resize (`MS-RDPEDISP` / `disp` virtual channel in FreeRDP3) or clean fit-to-window scaling (`can_shrink = true`, `ContentFit.CONTAIN`, with offset-aware pointer coordinate mapping so clicks stay exact when letterboxed).
  - For **Session-1 takeover:** capture the real monitor resolution and scale smoothly to fit the controller pane (with optional 1:1 scroll toggle) with exact aspect-offset pointer mapping.
- Fix mouse coordinate mapping in `Screen.vala` (`motion`, `click.pressed`, `click.released`) so any letterboxing offset from `ContentFit.CONTAIN` / `SCALE_DOWN` is subtracted before dividing by `scale`.

### LLM

- ℹ️ Closed predecessor bug: [`docs/bugs/done/2026-11-26-FIXED-windows-desktop-tcp-reset.md`](done/2026-11-26-FIXED-windows-desktop-tcp-reset.md) (`0.1.63` verified holding with GFX RFX Progressive + mouse/keyboard/scroll).
- ℹ️ Related master spec (Phase 6.5 Takeover edges): [`docs/bugs/2026-11-17-remote-desktop.md`](2026-11-17-remote-desktop.md).
- ℹ️ Related proven Session-1 capture + input PoC (65.7 s, 3-hop mTLS relay, UIPI findings): [`docs/bugs/2026-11-26-FEATURE-screenshot-stream-remote-control.md`](2026-11-26-FEATURE-screenshot-stream-remote-control.md) and archived source in `tests/screenshot-poc/`.
- ℹ️ `agent/windows/tray/Tray.vala` already has partial Phase 6.5 scaffolding (`agent.desktop` listener, 30-min `GetLastInputInfo` check, balloon prompt, `AgentService.allow`), which was disabled in `Service.vala` on 2026-11-19 because `initialize()` turned RDP on unconditionally and nothing sent `agent.desktop`.
- ℹ️ `controller/Rdp/Screen.vala` pointer math currently computes `scale = double.min(pw / gdi.width, ph / gdi.height)` and `rx = x / scale` without subtracting letterbox margins — safe only while `halign = START, valign = START` and `can_shrink = false`, and must be updated together with Phase 3 sizing.
- 🚫 Do not patch `termsrv.dll` or weaken Windows NLA (`UserAuthentication` stays `1`).
- 🚫 Do not put takeover/Disconnect/size controls in the window header bar (`.cursor/rules/no-header-bar-controls.mdc`).
- ⏳ Waiting on user direction for Phase 1 takeover mechanism and Phase 3 sizing preference before running throwaway verification on `snappr-win`.
