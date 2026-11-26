# Feasibility of live screenshot streaming and basic input over the relay channel

**Status:** ⏳

### User decisions required

- 💩 Phase 3 go/no-go: decide whether live screenshot streaming replaces the Windows RDP virtual-adapter path, runs alongside RDP as an alternative/fallback, or is parked.
- 💩 If proceeding to a product design, confirm whether elevated windows and the lock screen must be clickable (selecting a SYSTEM-token helper in Session 1 over the unprivileged tray process).

### User reported

- 🔷 Our RDP path is still having massive issues.
- 🔷 Can we do a minimal proof of concept using that channel to stream live screenshots, compressed or whatever, and see what libraries we can get to do that?
- 🔷 Create a bug report about that as a possible alternative.
- 🔷 Honestly, all that is needed is to see what is going on on the screen, be able to press a few buttons, and maybe type.
- 🔷 Check what the feasibility is like.
- 🔷 Keep this as off-code testing and documentation only, without modifying or proposing modifications to product code.
- 🔷 The tray is the key to this, using its RPC layer or a socket into the agent; it already talks to the agent, so all communications can be triple-relayed via the agent.
- 🔷 Run a throwaway Phase 1 proof of concept.
- 🔷 Go ahead and look at Phase 2.
- 🔷 Move the proof-of-concept stuff into `tests/` for archival sake, without linking it into the build.

### Success scenario

- Feasibility is documented: libraries and licenses, transport over the existing relay channel, Windows session and UAC constraints, input injection, bandwidth, and controller rendering.
- An off-tree throwaway on `snappr-win` captures the active desktop, compresses frames with an already-shipped non-GPL library, and streams them to a standalone GTK 4 viewer over the relay framing without disconnecting for at least 60 seconds.
- Mouse clicks and basic keyboard typing from the standalone viewer act on a window on the Windows desktop, including clarity on elevated/UAC windows.
- No product source file is modified during this investigation.

### Current behavior

- What you said
  - RDP continues to fail and needs an alternative feasibility check.
  - Only viewing the screen, clicking buttons, and basic typing are required.
  - This report is documentation and off-tree testing only, with no product code changes.
  - The tray already talks to the agent over local RPC, so the stream can be triple-relayed via the agent.
  - Run the Phase 1 throwaway proof of concept.
  - Run the Phase 2 end-to-end streaming proof of concept.
  - Archive the PoC source files under `tests/` without wiring them into Meson.
- Tool calls
  - Phase 1: ran `probe.c` on `snappr-win` via temporary `ArgusShotProbe` service, copied `frame-q65.jpg` back, cleaned up, and decoded it on Linux with `decode.vala`.
  - Phase 2: ran `relay.vala`, `viewer.vala`, `agent.vala`, `worker.c`, and `run-phase2.sh` for a 65.7-second 3-hop mTLS `OLLMrpc` stream (`Worker` → `Agent` → `Relay` → `Viewer`) between `snappr-win` and Linux, saved before/after composited PNGs, and removed temporary `ArgusShotP2` service and files on `snappr-win`.
  - Archival: moved the PoC source files from `/tmp/` into `tests/screenshot-poc/` (not referenced in `tests/meson.build`) and deleted the temporary `/tmp/argus-shot-*` files.
- Observable outcome
  - Phase 1 succeeded on `snappr-win` (Session 1, `Winlogon` lock screen, 1024×768): `BitBlt` averaged 29.45 ms, `libjpeg-turbo` (`JCS_EXT_BGRA`, q=65) encoded the full screen in 1.73 ms (100,659 bytes), and GTK 4 `Gdk.Texture.from_bytes` decoded it on Linux in 2.54 ms.
  - Phase 1 proved UIPI: SYSTEM `SendInput` clicked and typed into the test window, while a medium-integrity (`S-1-16-8192`) child's `SendInput` returned success (`3`, `err 0`) with `0` clicks delivered.
  - Phase 2 succeeded end-to-end across all three hops for 65.7 seconds with 0 disconnects and 0 send errors: remote clicks and Unicode typing from Linux drove the Windows window to `"Clicks: 3"` and `"Hello via Relay!"` (`ui_return=1`), visually confirmed in `/tmp/argus-shot-phase2-after.png`.
  - Total downstream traffic across 65.7 seconds was 200,704 bytes (1 full frame + 18 dirty-tile batches, 1.73 ms avg GTK 4 decode); idle traffic over 61.3 seconds was 12,342 bytes (~0.2 KB/s, dropping to 0 B/s once the edit caret stopped blinking).
  - No product source files were modified.

### Codebase observed behavior

- [`server/Rdp/Relay.vala`](../../server/Rdp/Relay.vala) and [`server/Rdp/Seat.vala`](../../server/Rdp/Seat.vala) forward opaque `GLib.Bytes` (`ay`) chunks between paired TLS connections via `Relay.join`, `Relay.view`, `Relay.write`, and `relay.data`.
  - Neither class inspects or parses RDP bytes, so the same channel can carry any custom framed stream.
- [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala) reads up to 16 KiB chunks from a local socket and sends each chunk with `Relay.write`, while writing incoming `relay.data` bytes back to that socket.
- [`controller/Rdp/Viewer.vala`](../../controller/Rdp/Viewer.vala) mirrors the tunnel on the controller side using `Relay.view`, `Relay.write`, and `relay.data`.
- [`controller/Rdp/Screen.vala`](../../controller/Rdp/Screen.vala) renders frames into a `Gtk.Picture` using `Gdk.MemoryTexture` inside [`controller/tab/Rdp.vala`](../../controller/tab/Rdp.vala).
- [`agent/windows/Service.vala`](../../agent/windows/Service.vala) runs in Windows Session 0 as a service and launches `argus-tray.exe` into the active signed-in session via `WTSQueryUserToken`, `DuplicateTokenEx`, and `CreateProcessAsUserW` on `winsta0\default`.
- [`agent/windows/tray/Tray.vala`](../../agent/windows/tray/Tray.vala) runs in the signed-in session and talks to the service over local RPC on `127.0.0.1:4142`.
- [`agent/meson.build`](../../agent/meson.build) and [`controller/meson.build`](../../controller/meson.build) both already link `gtk4` and `libadwaita-1`, and [`packaging/android/pixiewood-argus.xml`](../../packaging/android/pixiewood-argus.xml) already ships `gtk` and `libadwaita` on Android.
- [`scripts/ci/copy-windows-runtime.sh`](../../scripts/ci/copy-windows-runtime.sh) stages GTK 4 runtime DLLs from MSYS2 UCRT64 into the Windows installer, which already includes `libjpeg-8.dll`, `libpng16-16.dll`, `libwebp-7.dll`, `libzstd.dll`, `zlib1.dll`, `libgdk_pixbuf-2.0-0.dll`, and `libgtk-4-1.dll` (verified in `dist-windows/ArgusAgent-0.1.45-Setup.exe`).

### Debugging

#### Current debug output

- Throwaway `/tmp/argus-shot-probe.c` compiled and run on `snappr-win`, 2026-11-26 16:48, via temporary one-shot service `ArgusShotProbe` (deleted afterward; `sc query ArgusShotProbe` returned 1060).
  ```text
  === service.log ===
  active_console_session 1
  spawned_worker pid 15492
  worker_exit 0
  === worker.log ===
  worker_session 1
  desktop_name Winlogon
  screen 1024 768
  capture_10frames min 20.05 ms avg 29.45 ms max 37.63 ms nonzero 786378/786432
  jpeg_q60 1.72 ms bytes 94140
  jpeg_q75 1.42 ms bytes 126609
  jpeg_q85 2.02 ms bytes 182199
  jpeg_q65 1.73 ms bytes 100659
  webp_q65 57.62 ms bytes 77272
  zstd_l1_full 6.01 ms bytes 2037624
  zstd_l3_full 13.74 ms bytes 1821760
  tile_diff_idle 0.63 ms changed 0/192
  tile_diff_8dirty_jpeg65 2.11 ms dirty 8 bytes 9436
  input_sys_click sent 3 clicks 1 pos 164,141
  input_sys_type sent 26 text "Argus OK! 123" return_seen 1
  uipi_child_exit 0
  input_medium_vs_sys_clicks 0
  worker_done
  === uipi.log ===
  desktop_name Winlogon
  uipi_sendinput 3 err 0
  ```
  - `libjpeg-turbo` (`JCS_EXT_BGRA`) encoded a real 1024×768 screen in 1.4–2.0 ms (~94–182 KB); `libwebp` was ~33× slower (57.62 ms) for 23% fewer bytes, and full-frame `zstd` remained ~1.8–2.0 MB.
  - SYSTEM `SendInput` clicked the test button and typed `"Argus OK! 123"` + `VK_RETURN` cleanly; medium-integrity `SendInput` returned `3` (`err 0`) while UIPI silently dropped the click (`0` clicks received).

- Throwaway `/tmp/argus-shot-decode.vala` on Linux dev host, 2026-11-26, decoding `/tmp/argus-shot-frame-q65.jpg` copied from `snappr-win`.
  ```text
  gdk_texture_from_bytes 1024x768 avg 2.54 ms (10 runs) input 100659 bytes
  ```
  - GTK 4's built-in `Gdk.Texture.from_bytes` decoded the Windows-encoded JPEG directly in 2.54 ms with no extra image bindings; the saved JPEG visually showed the live 1024×768 Windows lock screen ("4:48 Thursday, November 26").

- Phase 2 throwaway `/tmp/argus-shot-p2-run.sh`, 2026-11-26 17:05, 65.7-second 3-hop mTLS `OLLMrpc` relay test between `snappr-win` (Session 1 `Winlogon`) and Linux (after adding `SetThreadDesktop(g_desk)` in `recv_thread`; temporary `ArgusShotP2` deleted afterward and confirmed 1060).
  ```text
  DISCOVERED: targets btn=194,163 edit=274,215
  viewer joined
  viewer saved_before seq=1 1024x768
  viewer sending_clicks_and_text btn=194,163 edit=274,215
  viewer saved_after active_bytes=185791
  viewer_summary elapsed=65.7s full=1 tile_batches=18 tiles=89 avg_decode=1.73ms active_bytes=188362 idle_sec=61.3s idle_frames=8 idle_bytes=12342 send_errors=0
  === RELAY LOG ===
  relay listening 19443
  relay tls_connected
  relay joined agent
  relay tls_connected
  relay joined view
  relay stats a2v_msgs=13 a2v_bytes=190933 v2a_msgs=35 v2a_bytes=145
  relay stats a2v_msgs=18 a2v_bytes=197372 v2a_msgs=40 v2a_bytes=170
  …
  relay stats a2v_msgs=19 a2v_bytes=200704 v2a_msgs=41 v2a_bytes=175
  === WORKER LOG ===
  desktop Winlogon
  worker screen 1024 768
  targets btn=194,163 edit=274,215
  worker local_connected
  recv_desk_attached
  sent_full seq=1 bytes=102067
  sent_tiles seq=2 dirty=28 bytes=28731
  sent_tiles seq=3 dirty=18 bytes=19188
  ui_btn_clicked 1
  ui_btn_clicked 2
  sent_tiles seq=4 dirty=21 bytes=23497
  ui_btn_clicked 3
  sent_tiles seq=5 dirty=1 bytes=1360
  …
  sent_tiles seq=19 dirty=2 bytes=3332
  worker_summary frames=19 bytes=200704 clicks_in=4 keys_in=18 ui_clicks=3 ui_text="Hello via Relay!" ui_return=1
  worker_done
  ```
  - All three hops stayed up 65.7 seconds with zero disconnects and zero send errors, moving 200,704 bytes downstream and 175 bytes upstream across the entire run (~3.0 KB/s overall, ~0.2 KB/s during the 61.3 s idle window).
  - `/tmp/argus-shot-phase2-after.png` visually confirmed `"Clicks: 3"` and `"Hello via Relay!"` composited on Linux from dirty 64×64 JPEG tiles decoded by `Gdk.Texture.from_bytes` (1.73 ms avg).
  - Important Win32 pitfall caught on the first Phase 2 run: newly created Win32 threads do not inherit `SetThreadDesktop()`, so `SendInput` from `recv_thread` was silently ignored until `recv_thread` called `SetThreadDesktop(g_desk)` itself.

#### Debug code added (remove when complete)

- None in the product tree or Meson build files.
- Archived unlinked PoC sources in `tests/screenshot-poc/` (not added to `tests/meson.build`):
  - `tests/screenshot-poc/probe.c` (Phase 1 Windows capture/codec/tile/UIPI probe)
  - `tests/screenshot-poc/decode.vala` (Phase 1 Linux GTK 4 `Gdk.Texture.from_bytes` decode probe)
  - `tests/screenshot-poc/relay.vala` (Phase 2 Linux mTLS `OLLMrpc` relay stub)
  - `tests/screenshot-poc/agent.vala` (Phase 2 Windows Session 0 `OLLMrpc` forwarder stub)
  - `tests/screenshot-poc/worker.c` (Phase 2 Windows Session 1 capture + dirty-tile + `SendInput` worker)
  - `tests/screenshot-poc/viewer.vala` (Phase 2 Linux GTK 4 tile-compositing viewer and input driver)
  - `tests/screenshot-poc/run-phase2.sh` (Phase 2 manual runner script)
- Temporary `/tmp/argus-shot-*` files and temporary `ArgusShotProbe` / `ArgusShotP2` services and directories on `snappr-win` were removed and verified absent (`sc query` returned 1060).

### Proposed fix

No product code changes are proposed or applied in this report. This section records the feasibility assessment and an off-tree throwaway proof-of-concept plan.

#### Feasibility — Libraries and licensing (zero GPL, zero new DLLs)

- Already shipped in both the Windows agent installer and the Linux controller
  - `libjpeg-turbo` (`libjpeg-8.dll` / `libjpeg.so.8`) — IJG / BSD-3-Clause / zlib license (LGPL-3 compatible). SIMD-accelerated JPEG encode and decode; encodes 1920×1080 BGRA in ~5–15 ms on CPU at ~50–150 KB per full frame (quality 60–75).
  - `libwebp` (`libwebp-7.dll` / `libwebp.so.7`) — BSD-3-Clause. Smaller files for crisp UI text than JPEG, slower CPU encode.
  - `libpng16` (`libpng16-16.dll` / `libpng16.so.16`) — libpng license. Lossless and crisp, but slow to encode and large (~200–1200 KB per full frame; the archived VNC throwaway's 1024×768 lock screen PNG was 1.17 MB vs 3.15 MB raw BMP).
  - `libzstd` (`libzstd.dll` / `libzstd.so.1`) and `zlib` (`zlib1.dll` / `libz.so.1`) — BSD-3-Clause / zlib license. Fast lossless compression if sending XOR-diffed or changed raw tiles.
  - `GTK 4` (`Gdk.Texture.from_bytes`) — LGPL-2.1+. Already available on Linux, Windows, and Android; decodes JPEG, PNG, and TIFF bytes directly into a `Gdk.Paintable` for `Gtk.Picture` with no custom decoder code.
- Windows system APIs (built into OS, no third-party library)
  - Screen capture: GDI `BitBlt` + `GetDIBits` (`gdi32.dll`, `user32.dll`) works on all Windows editions including VMs, basic display adapters, and the lock screen; already proven on `snappr-win` in `2026-11-26-archived-vnc-desktop-share.md`.
  - Faster optional capture: DXGI Desktop Duplication (`IDXGIOutputDuplication` in `dxgi.dll` + `d3d11.dll`, Windows 8+) gives hardware-accelerated dirty rectangles and cursor updates with near-zero idle CPU, but fails across secure desktop switches and on some headless/basic adapters, so `BitBlt` remains the simplest PoC and fallback.
  - Optional OS encoder: Windows Imaging Component (`windowscodecs.dll`) encodes JPEG/PNG natively, though `libjpeg-turbo` is already bundled and faster.
  - Input injection: `SendInput` (`user32.dll`) handles absolute mouse positioning (`MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK` in 0..65535 coordinates), clicks, scroll wheel, and keyboard input.
- Licensing verdict
  - Every candidate library is BSD / zlib / IJG / libpng / LGPL-2.1+ or a Windows OS DLL, so there is no GPL conflict with Argus's LGPL-3.0-or-later license.

#### Feasibility — Channel, triple relay via agent, framing, and bandwidth

- Triple relay via the agent (three hops, one RPC framing layer)
  - Hop 1 (Session capture ↔ Agent service): the tray (`argus-tray.exe`) already runs in the active desktop session and already speaks `OLLMrpc` to `argus-agent.exe` on `127.0.0.1:4142`.
  - Hop 2 (Agent service ↔ Management server): the service already holds the TLS client certificate and opens a second `OLLMrpc` connection (`Relay.join` / `Relay.write` / `relay.data`).
  - Hop 3 (Management server ↔ Controller): the controller already joins that seat with `Relay.view` / `Relay.write` / `relay.data`.
  - The agent service stays a dumb byte/chunk forwarder between the local session connection and the server `Relay` connection, with no image decoding or encoding in Session 0 and no TLS credentials exposed to the interactive session.
  - Using a second local connection on `127.0.0.1:4142` (or a dedicated loopback socket, mirroring how [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala) bridges a local `SocketConnection` into `Relay.write`) keeps image frames from blocking `AgentService.status` and `AgentService.register` calls.
  - Local loopback latency on Hop 1 is sub-millisecond, so triple relaying adds negligible overhead compared to JPEG encode (~5–15 ms) and LAN/WAN RTT.
  - Local security note: because `127.0.0.1:4142` is loopback TCP reachable by any local user, a real implementation should gate the stream join with a per-session random token (handed out on the authenticated control channel) or an ACL-restricted named pipe.
- Message boundaries and `OLLMrpc` `ay` framing
  - `OLLMrpc` serializes `GLib.Bytes` (`ay`) with a `uint32` length prefix on the wire, so an entire compressed frame (~60–150 KB JPEG) fits in a single `Relay.write` / `relay.data` message without splitting into 16 KiB chunks or manual stream reassembly.
  - Sending one whole compressed frame per `ay` avoids multiplying WAN round-trip time across many synchronous 16 KiB `Relay.write` replies.
  - Each `ay` payload only needs a small header (e.g. `[msg_type: uint8][flags: uint8]` + type-specific fields) because `OLLMrpc` already preserves message boundaries.
  - Agent → Controller message types: `FRAME_FULL` (width, height, format, encoded bytes), optional `FRAME_TILE` (x, y, w, h, encoded bytes), optional `CURSOR`.
  - Controller → Agent message types: `FRAME_ACK` (backpressure so slow links never queue stale frames), `MOUSE_MOVE`, `MOUSE_BUTTON`, `MOUSE_WHEEL`, `KEY_EVENT`, `TEXT_UNICODE`.
- Bandwidth and frame rate
  - Clicking dialogs and reading installer screens does not need 60 fps video; 2–5 fps (or 0 fps when unchanged, bursting to ~5 fps right after input) is responsive enough.
  - Full-frame JPEG (q=65) at 1920×1080 is ~60–120 KB (~180–360 KB/s at 3 fps); simple 64×64 or 128×128 tile hashing drops idle traffic to 0 bytes/sec and typical UI click updates to ~5–30 KB.
- Advantages over Windows RDP
  - Works on Windows Home as well as Pro/Enterprise.
  - Shows the active signed-in desktop directly without creating a second session, logging the user off, or prompting for Windows NLA credentials.
  - Eliminates Wintun, userspace TCP, TermService session resets, and FreeRDP client dependencies on the controller (including Android).

#### Feasibility — Windows session, UAC, and input constraints

- Session 0 isolation
  - The Windows service in Session 0 cannot capture the desktop or inject input into the interactive user session (`WinSta0\Default`).
  - Capture and `SendInput` must run in a process inside the active console session.
- Privilege choice (UIPI and UAC — critical constraint)
  - The same triple-relay-via-agent design works regardless of which interactive-session process connects to `127.0.0.1:4142`.
  - Unprivileged `argus-tray.exe` can capture the whole `WinSta0\Default` desktop (including seeing elevated windows) and click/type in normal user windows, but Windows UIPI silently drops `SendInput` to elevated windows (admin installers like `Set-up.exe`, Task Manager) and blocks capture/input on the secure desktop (UAC prompt and lock screen).
  - If elevated windows or the lock screen must be clickable, a short-lived helper launched by the service into the active console session with the service's own `NT AUTHORITY\SYSTEM` token (`WTSGetActiveConsoleSessionId` + `DuplicateTokenEx` + `SetTokenInformation(TokenSessionId)` + `CreateProcessAsUserW`) speaks the exact same local RPC/socket into the agent while bypassing UIPI and following `OpenInputDesktop()` across `Default` and `Winlogon`.
- Mouse and keyboard details
  - Controller maps `Gtk.Picture` pointer coordinates (accounting for `Gtk.ContentFit` scale/offset) via `Gtk.GestureClick`, `Gtk.EventControllerMotion`, and `Gtk.EventControllerScroll` into normalized 0..65535 virtual-desktop coordinates for `SendInput`.
  - Printable characters can use `SendInput` with `KEYEVENTF_UNICODE` (UTF-16 code units), avoiding keyboard-layout mismatch bugs between controller and Windows target.
  - Non-printable keys (Enter, Tab, Escape, Backspace, Delete, arrows, Ctrl/Alt/Shift modifiers) map GDK keyvals from `Gtk.EventControllerKey` to Windows `VK_*` codes.
  - `Ctrl+Alt+Del` cannot be sent via `SendInput`; if ever needed, Windows requires `SendSAS(FALSE)` from `sas.dll` as SYSTEM with `SoftwareSASGeneration` enabled.
- Known limitations vs RDP
  - Headless machines with no active display/monitor may report a black screen or small fallback resolution unless a virtual display driver exists.
  - No audio, drive redirection, or multi-user concurrent sessions (not required for the stated goal).
  - Clipboard sync is not included in the minimal scope, though a small UTF-8 clipboard message is trivial later.

### ✔️ Phase 1 — Off-tree Windows capture, encode, and input throwaway

- Scope
  - Standalone C probe in `/tmp/argus-shot-probe.c` compiled on `snappr-win` with MSYS2 UCRT64 `gcc` (`-lgdi32 -luser32 -ladvapi32 -lwtsapi32 -ljpeg -lwebp -lzstd`), launched as SYSTEM in the active console session; zero edits to the Argus repo.
- Result
  - `BitBlt` + `GetDIBits` captured 1024×768 (`Winlogon`) in 29.45 ms avg (20.05–37.63 ms).
  - `libjpeg-turbo` (`JCS_EXT_BGRA`) beat both `libwebp` and full-frame `zstd`: q=65 took 1.73 ms for 100,659 bytes vs `libwebp` q=65 at 57.62 ms (77,272 bytes) and `zstd` level 1 at 6.01 ms (2,037,624 bytes).
  - 64×64 tile diff cost 0.63 ms when idle (0/192 tiles changed) and 2.11 ms total for 8 dirty tiles encoded as JPEG q=65 (9,436 bytes).
  - SYSTEM `SendInput` clicked a Win32 button (`clicks 1`) and typed `"Argus OK! 123"` + `VK_RETURN` via `KEYEVENTF_UNICODE` + `VK_RETURN`; medium-integrity `SendInput` was silently blocked by UIPI (`0` clicks).
  - Linux GTK 4 `Gdk.Texture.from_bytes` decoded the captured JPEG in 2.54 ms avg.
  - Note: nobody was signed in at the console, so this run exercised `Winlogon` rather than an interactive user `Default` desktop.

### ✔️ Phase 2 — Off-tree end-to-end stream over relay framing

- Scope
  - Standalone 3-hop mTLS `OLLMrpc` proof of concept in `/tmp/`: Session 1 SYSTEM worker (`worker.exe`) ↔ local TCP ↔ Windows agent stub (`agent.exe`, `OLLMrpc.Transport.TlsClient`) ↔ Linux relay (`argus-shot-relay`, `Relay.join` / `Relay.write` / `relay.data`) ↔ Linux GTK 4 viewer (`argus-shot-viewer`), with zero product edits.
- Result
  - Held continuously for 65.7 seconds with 0 disconnects and 0 send errors.
  - Remote mouse clicks (3 button clicks + 1 edit focus click) and Unicode typing (`"Hello via Relay!"` + `VK_RETURN`) drove the Windows window across all three hops (`ui_clicks=3`, `ui_text="Hello via Relay!"`, `ui_return=1`), visually confirmed in `/tmp/argus-shot-phase2-after.png`.
  - Downstream traffic: 1 full JPEG frame (102,067 bytes) + 18 dirty 64×64 tile batches (98,637 bytes total) = 200,704 bytes across 65.7 seconds (~3.0 KB/s average; ~0.2 KB/s during the 61.3 s idle period, dropping to 0 B/s once the caret stopped blinking).
  - Upstream traffic: 41 `ay` messages (`FRAME_ACK` + clicks + keys) = 175 bytes total.
  - GTK 4 `Gdk.Texture.from_bytes` + `Gdk.MemoryTexture` tile compositing averaged 1.73 ms per update on Linux.
  - Win32 threading requirement proved: every thread that calls `SendInput` (not only the capture thread) must call `SetThreadDesktop()` to attach to the active input desktop.

### Phase 3 — Go / no-go decision (still before any product code)

- Scope
  - Review Phase 1 and Phase 2 evidence to decide whether screenshot streaming replaces RDP, runs as a fallback alongside RDP, or is parked.
- Done when
  - User chooses a direction; any product implementation plan would be authored separately only after approval.

### LLM

- ℹ️ Related active reports (plain names only): `2026-11-26-ISSUE-windows-desktop-tcp-reset.md`, `2026-11-26-FEATURE-windows-rdp-virtual-adapter.md`, `2026-11-17-remote-desktop.md`.
- ℹ️ Related archived feasibility report (plain name only): `docs/bugs/done/2026-11-26-archived-vnc-desktop-share.md` (already proved `BitBlt` + `OpenInputDesktop` on `snappr-win` and verified non-GPL libraries in MSYS2).
- ℹ️ Process and product references: `docs/bug-fix-process.md`, `docs/guide-to-writing-bug-reports.md`, `docs/rpc-commands.md`, `server/Rdp/Relay.vala`, `server/Rdp/Seat.vala`, `agent/Rdp/Tunnel.vala`, `controller/Rdp/Viewer.vala`, `controller/Rdp/Screen.vala`, `agent/windows/Service.vala`, `agent/windows/tray/Tray.vala`, `scripts/ci/copy-windows-runtime.sh`, `packaging/android/pixiewood-argus.xml`.
- ℹ️ Verified library versions on Linux dev host (2026-11-26): `gtk4` 4.18.5, `gdk-pixbuf-2.0` 2.42.12, `libjpeg` 2.1.5, `libpng` 1.6.47, `libwebp` 1.5.0, `libzstd` 1.5.6, `zlib` 1.3.1, `liblz4` 1.10.0.
- ℹ️ Verified DLLs already bundled in `dist-windows/ArgusAgent-0.1.45-Setup.exe`: `libgtk-4-1.dll`, `libgdk_pixbuf-2.0-0.dll`, `libcairo-2.dll`, `libjpeg-8.dll`, `libpng16-16.dll`, `libwebp-7.dll`, `libzstd.dll`, `zlib1.dll`.
- ℹ️ Verified `Gdk.Texture.from_bytes` exists in `/usr/share/vala-0.56/vapi/gtk4.vapi` (line 5362, cname `gdk_texture_new_from_bytes`), so the controller needs no extra image-decoding bindings.
- ℹ️ Verified in `OLLMchat/libocrpc/Bin/StreamValue.vala` (lines 139–149) that `GLib.Bytes` (`ay`) writes a `uint32` length followed by raw bytes, so single-message frames (~60–150 KB) need no 16 KiB chunk reassembly.
- ✔️ 2026-11-26: Phase 1 throwaway ran cleanly on `snappr-win` (`Winlogon` Session 1, 1024×768) and Linux (`Gdk.Texture.from_bytes`). Clear codec winner is `libjpeg-turbo` (`JCS_EXT_BGRA`, 1.73 ms, 100 KB full / 9.4 KB for 8 dirty 64×64 tiles). UIPI confirmed: medium-integrity `SendInput` silently dropped (`0` clicks), while SYSTEM `SendInput` clicked and typed `"Argus OK! 123"` + `VK_RETURN`.
- ✔️ 2026-11-26: Phase 2 3-hop mTLS `OLLMrpc` throwaway passed on `snappr-win` ↔ Linux: 65.7 s with 0 disconnects, 200 KB total downstream (~3 KB/s overall, ~0.2 KB/s idle), 175 B upstream, 1.73 ms avg GTK 4 decode, and verified remote button clicks (`Clicks: 3`) + Unicode typing (`"Hello via Relay!"`) + `VK_RETURN`. Caught Win32 `SetThreadDesktop()` per-thread requirement for `SendInput`.
- ✔️ 2026-11-26: Moved PoC sources from `/tmp/` into `tests/screenshot-poc/` (unlinked from `tests/meson.build`) and deleted temporary `/tmp/argus-shot-*` artifacts.
- 🚫 Do not modify any product source file for this report.
- 🚫 Do not link GPL libraries (e.g., LibVNCServer).
- 🚫 Do not run capture or `SendInput` from the Session 0 service process directly.
- ⏳ Waiting on Phase 3 go/no-go decision from user.
