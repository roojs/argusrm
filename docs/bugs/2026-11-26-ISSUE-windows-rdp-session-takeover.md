# Windows remote desktop does not take over the signed-in user's session

**Status:** ⏳

### User decisions required

- ✅ **Takeover mechanism chosen (2026-11-27):** **`IRDPSRAPISharingSession` (`RdpEncom.dll`) + existing FreeRDP3 viewer** when a user is signed in (passwordless live takeover of the active desktop, coordinated with `argus-tray.exe`), with **standard `TermService` (`127.0.0.1:3389`)** as fallback when nobody is signed in.
- 💩 **Desktop window sizing mode (deferred to Phase 3 alongside takeover):** choose whether the controller viewer should (a) negotiate and dynamically resize the remote desktop to match the controller tab (`MS-RDPEDISP` for `TermService` RDP), or (b) scale the remote desktop to fit the controller pane (aspect-preserving fit with optional 1:1 scroll toggle, which works identically for both `IRDPSRAPISharingSession` and `TermService`).

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

- Prior RDP transport evidence is archived in `2026-11-26-FIXED-windows-desktop-tcp-reset.md`.
- **2026-11-27 passwordless takeover investigation & live throwaway proof on `snappr-win` (`Windows 10 Pro 10.0.19045.6466`, `alan` active in Session 16 `RDP-Tcp#46`):**
  - Confirmed OS boundary for standard `TermService` (port 3389): attaching to an active user's desktop requires that user's exact Windows credentials; `SYSTEM` cannot extract/replay passwords (especially Microsoft Account / Azure AD / Windows Hello PIN); logging in as a different account disconnects/replaces the session with a separate desktop; FreeRDP3 client does not support remote `mstsc /shadow` (`RpcShadow2` over SMB/DCE-RPC).
  - Tested built-in **Windows Desktop Sharing API (`IRDPSRAPISharingSession` in `RdpEncom.dll`)** — the same local engine `RdpSa.exe` / `RpcShadow2` uses — in a throwaway C probe (`ArgusWdsProbe`, spawned as `NT AUTHORITY\SYSTEM` into active Session 16) connected by a throwaway Linux **FreeRDP 3** (`3.14.0`) client over an SSH tunnel (`127.0.0.1:13399 -> 192.168.88.244:3399`) using **zero Windows user credentials** (only the one-time invitation string + random one-time password):
    ```text
    parse_file_buffer rc=1
    populate_settings=1
    orig TargetNetAddressCount=1
    Calling freerdp_connect (NO Windows username/password)...
    PreConnect: mode=1 host=127.0.0.1 port=13399
    PostConnect OK: gdi 1024x768
    freerdp_connect SUCCEEDED!
    RESULT: elapsed=5s gdi=1024x768 paints=106 nonzero=520726/786432 last_err=0x00000000 (ERRBASE_SUCCESS)
    ```
    Windows worker log (running as `SYSTEM` inside Session 16):
    ```text
    worker_start pid=14736 session=16 user=SYSTEM
    Open hr=0x00000000
    CreateInvitation hr=0x00000000
    rdp_event dispid=301 cArgs=1
    event connected: put_ControlLevel(3) hr=0x00000000
    rdp_event dispid=302 cArgs=1
    worker_done
    ```
    `query user` afterward confirmed `alan` remained `Active` in Session 16 (`rdp-tcp#46`) throughout — no logoff, no lockout.
  - **2026-11-27 follow-up throwaway (`wds-test2.exe` + `argus-wds-client2` on `snappr-win`, Session 16):** verified interactive mouse clicks, keyboard input on a `SYSTEM`-owned (UIPI-protected) test window, exact `controller/Rdp/Screen.vala` GFX settings, and ephemeral certificate handling:
    - Caught a real FreeRDP3 cert-caching failure on the first run (`ERRCONNECT_TLS_CONNECT_FAILED`): each `IRDPSRAPISharingSession` generates a fresh ephemeral self-signed certificate; returning `1` (`ACCEPT_PERMANENT`) in `VerifyCertificateEx` wrote `~/.config/freerdp/server/127.0.0.1_<port>.pem` and broke the next connection. Setting `FreeRDP_IgnoreCertificate = TRUE`, `FreeRDP_NlaSecurity = FALSE`, and returning `2` (`ACCEPT_TEMPORARY`) in both `VerifyCertificateEx` and `VerifyChangedCertificateEx` fixed it cleanly.
    - Verified with exact `Screen.vala` GFX settings (`SupportDynamicChannels=true`, `SupportGraphicsPipeline=true`, `GfxProgressive=true`, `GfxProgressiveV2=true`):
      ```text
      PostConnect OK: gdi 1024x768
      connect SUCCEEDED! auth_called=1 gfx_connected=0
      sending 2 clicks at (203,186), focus edit (273,242), typing 'ok'+Enter
      RESULT: auth_called=1 gfx=0 paints=154 err=0x00000000 (ERRBASE_SUCCESS)
      ```
      Windows `SYSTEM` worker log:
      ```text
      event connected: put_ControlLevel(3) hr=0x00000000
      ui_btn_clicked 1
      ui_btn_clicked 2
      ui_return_seen 1
      ui_summary clicks=2 text="" return_seen=1
      worker_done
      ```
    - Verified `Authenticate` returning `FALSE` (without prompting) still connects cleanly in Remote Assistance mode because `RemoteAssistancePassword` is already populated.
    - Temporary `ArgusWdsProbe` service (`sc query` returned `1060`), `C:\Users\Alan\argus-wds-probe`, and local `/tmp/argus-wds-*` files were deleted after the test.

#### Debug code added (remove when complete)

- None.

### Proposed fix

#### Phase 1 — Passwordless live desktop sharing (`IRDPSRAPISharingSession` + FreeRDP3)

- **Windows C COM module (`win32/desktop-share.c`, `win32/desktop-share.h`, `win32/win32.vapi`, `win32/meson.build`, `agent/meson.build`):**
  - Implement `argus_desktop_share_run(uint16_t port, const char *password, const char *invite_file, const char *stop_event)` in `win32/desktop-share.c` (linking `ole32`, `oleaut32`, `uuid`):
    - Opens `IRDPSRAPISharingSession` (`PortId`, `PortProtocol = AF_INET`, `EnabledTransports = 1` TCP-only, `DefaultAttendeeControlLevel = CTRL_LEVEL_VIEW`), creates a single-attendee invitation with the random one-time password, writes the RACS2 `ConnectionString` to the given file/pipe, grants `CTRL_LEVEL_INTERACTIVE` on `OnAttendeeConnected` / `OnControlLevelChangeRequest`, pumps Win32 messages until attendee disconnects or the stop event is signaled, and calls `Close()`.
  - Implement `argus_spawn_session_system(uint32_t session_id, const wchar_t *cmdline)` in `win32/register-pipe.c` (or `desktop-share.c`): duplicates the service's own `SYSTEM` token with `SetTokenInformation(TokenSessionId)` and calls `CreateProcessAsUserW` on `winsta0\default` so the share worker runs as `SYSTEM` inside the signed-in user's session (handling elevated windows).
  - Add `--share <port> <password> <invite_path> <stop_event>` CLI entry in `agent/windows/main.vala` before `Service.start()` so no extra `.exe` needs to be packaged.
- **Agent tunnel & service (`agent/windows/Service.vala`, `agent/windows/Adapter.vala`, `agent/Rdp/Tunnel.vala`):**
  - When `relay.start` arrives and `argus_active_session() != 0xFFFFFFFF`:
    - Do **not** call `argus_end_rdp_sessions()`.
    - Generate a random one-time password + ephemeral local port + stop event name, spawn `argus-agent.exe --share ...` into the active session, read the generated `ConnectionString` (parsing its `<L P="..." N="..."/>` local IP and port), send `Relay.ticket(invite, password)` to the server, and have `Adapter.connect()` dial that local `<ip>:<port>` instead of `127.0.0.1:3389`.
    - When the tunnel retires/disconnects, signal the stop event so the share worker closes `IRDPSRAPISharingSession` cleanly.
  - When `argus_active_session() == 0xFFFFFFFF` (nobody signed in):
    - Fall back to standard `TermService` on `127.0.0.1:3389` (sending empty ticket so the controller uses normal NLA sign-in).
- **Server relay (`server/Rdp/Relay.vala`, `server/Rdp/Seat.vala`, `docs/rpc-commands.md`):**
  - Add `Relay.ticket` (`"ss"`, agent stream/app connection) storing `seat.invite` and `seat.password` on the `Seat`, and emit `relay.ticket` (`"iss"`, `(agent_id, invite, password)`) to the requesting controller right before `relay.ready` (`"i"`) — keeping existing `relay.ready` callers and unit tests unbroken.
  - Document `Relay.ticket` and `relay.ticket` in `docs/rpc-commands.md` in the same change.
- **Controller FreeRDP3 viewer (`server/vapi/freerdp.vapi`, `controller/tab/Rdp.vala`, `controller/Rdp/Screen.vala`):**
  - Bind `FreeRDP.AssistanceFile` (`freerdp_assistance_file_new`, `parse_file_buffer`, `populate_settings_from_assistance_file`, `free`), `TargetNetAddressCount`, `RemoteAssistanceRequestControl`, `IgnoreCertificate`, `NlaSecurity`, and `VerifyChangedCertificateEx` in `server/vapi/freerdp.vapi`.
  - In `controller/tab/Rdp.vala`, handle `relay.ticket` and store `(invite, password)` on the target `Screen`.
  - In `controller/Rdp/Screen.vala`:
    - Return `2` (`ACCEPT_TEMPORARY`) from both `VerifyCertificateEx` and `VerifyChangedCertificateEx` and set `IgnoreCertificate = true`.
    - When `this.invite != ""`, populate FreeRDP3 settings from `AssistanceFile`, set `TargetNetAddressCount = 0`, `ServerHostname = "127.0.0.1"`, `ServerPort = port`, `RemoteAssistanceRequestControl = true`, `NlaSecurity = false`, and return `false` immediately in `Authenticate` without showing the Windows sign-in dialog.
    - When `this.invite == ""`, keep the existing NLA sign-in dialog for unattended `TermService` sessions.

#### Phase 2 — Argus Tray consent, status, and disconnect handshake

- Extend the local RPC contract between `agent/windows/Service.vala` and `agent/windows/tray/Tray.vala` (and update `docs/rpc-commands.md` + `Argus.Rdp.State` in `shared/Rdp.vala`):
  - **Pre-takeover consent / idle gate:** when `relay.start` arrives and an interactive session exists (`argus_active_session() != 0xFFFFFFFF`), `Service.vala` sends `agent.desktop` (operator name, `force` flag) to `argus-tray.exe` and reports a waiting-for-user state via `Relay.report` so the controller displays a clear status instead of hanging blank. If `force` is false and `GetLastInputInfo` is under 30 minutes idle, the tray asks the signed-in user (allow / deny / timeout); if idle ≥30 min or `force` is true, it auto-allows and calls `AgentService.allow(true)`.
  - **Active takeover notice & disconnect:** once the share worker is live, the service notifies the tray (`agent.desktop_active` with operator name); the tray updates its tooltip/menu to show who has control and offers a **Disconnect** action (`AgentService.disconnect`) that signals the share worker stop event and tears down the tunnel immediately.
  - **Home edition support:** because `IRDPSRAPISharingSession` (`RdpEncom.dll`) works on Windows Home as well as Pro, review `OsVersion.supports_rdp()` so Windows Home machines can still offer live session takeover when a user is signed in.

#### Phase 3 — Desktop window sizing and scaling

- Fix initial dimension detection in [`controller/Rdp/Screen.vala`](../../controller/Rdp/Screen.vala) / [`controller/tab/Rdp.vala`](../../controller/tab/Rdp.vala): read the viewport (`Gtk.ScrolledWindow` / `pictures` stack) allocation instead of the uninitialized `0×0` `Gtk.Picture`.
- Add clean fit-to-window scaling (`can_shrink = true`, `ContentFit.CONTAIN`, with optional 1:1 scroll toggle) and update mouse coordinate mapping in `Screen.vala` (`motion`, `click.pressed`, `click.released`) to subtract letterbox offsets before dividing by `scale` so clicks stay exact at any window size.

### LLM

- ℹ️ Closed predecessor bug: `2026-11-26-FIXED-windows-desktop-tcp-reset.md` (`0.1.63` verified holding with GFX RFX Progressive + mouse/keyboard/scroll).
- ℹ️ Related master spec (Phase 6.5 Takeover edges): `2026-11-17-remote-desktop.md`.
- ℹ️ Related proven Session-1 capture + input PoC (65.7 s, 3-hop mTLS relay, UIPI findings): `2026-11-26-FEATURE-screenshot-stream-remote-control.md` and archived source in `tests/screenshot-poc/`.
- ℹ️ 2026-11-27 live proof on `snappr-win`: `IRDPSRAPISharingSession` (`RdpEncom.dll`, COM in MinGW `<rdpencomapi.h>`) running as `SYSTEM` in Session 16 + FreeRDP 3 (`freerdp_assistance_parse_file_buffer` + `freerdp_assistance_populate_settings_from_assistance_file` + `TargetNetAddressCount = 0`) connected over a tunnel with zero Windows user credentials, rendered 1024×768 (`106` paints, `ERRBASE_SUCCESS`), granted `CTRL_LEVEL_INTERACTIVE` (`hr=0x00000000`), and left `alan` active without logoff.
- ℹ️ `agent/windows/tray/Tray.vala` already has partial Phase 6.5 scaffolding (`agent.desktop` listener, 30-min `GetLastInputInfo` check, balloon prompt, `AgentService.allow`), which was disabled in `Service.vala` on 2026-11-19 because `initialize()` turned RDP on unconditionally and nothing sent `agent.desktop`.
- ℹ️ `controller/Rdp/Screen.vala` pointer math currently computes `scale = double.min(pw / gdi.width, ph / gdi.height)` and `rx = x / scale` without subtracting letterbox margins — safe only while `halign = START, valign = START` and `can_shrink = false`, and must be updated together with Phase 3 sizing.
- 🚫 Do not patch `termsrv.dll` or weaken Windows NLA (`UserAuthentication` stays `1`).
- 🚫 Do not put takeover/Disconnect/size controls in the window header bar (`.cursor/rules/no-header-bar-controls.mdc`).
- ℹ️ 2026-11-27 follow-up proof on `snappr-win`: verified mouse clicks + keyboard Enter landing on a `SYSTEM`-owned (UIPI-protected) window (`ui_btn_clicked 1`, `ui_btn_clicked 2`, `ui_return_seen 1`), verified exact `Screen.vala` GFX settings negotiate cleanly (`paints=154`, `ERRBASE_SUCCESS`), caught FreeRDP3 permanent cert caching (`1`) failing on fresh ephemeral WDS certs (fixed with `IgnoreCertificate=true` + `VerifyCertificateEx`/`VerifyChangedCertificateEx` returning `2`), and verified `Authenticate` returning `false` skips password prompting in Remote Assistance mode.
- ⏳ Ready for user approval on the Phase 1–3 implementation plan in this file (remember: Phase 1 changes RPC commands, so update `docs/rpc-commands.md` in the same change, and bump version in `CHANGELOG.md` + `meson.build` before packaging a Windows installer).
