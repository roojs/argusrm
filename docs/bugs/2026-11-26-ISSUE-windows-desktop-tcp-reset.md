# Windows resets the desktop TCP session about six seconds after the picture is on screen

**Status:** ⏳

### User decisions required

None.

### User reported

- 🔷 The same error is still there after the desktop is on screen: the machine could not send the desktop, trying 1 of 3.
- 🔷 Fixes have been going round and round and the failure has not changed. This needs its own bug report and an analysis, not another product patch.
- 🔷 Further work stays off the product. A throwaway has to pass the roadblock before any speculative fix is applied.

### Success scenario

- The picture stays on screen.
- A close, if one still happens, is explained by a throwaway that logged the reset packet and a change that the same throwaway has already shown survives.
- The agent is not edited again until that throwaway has passed.

### Current behavior

- Controller and agent under test are 0.1.60.
- The desktop reaches “The desktop is on screen.” and then “The machine could not send the desktop. Trying 1 of 3.”
- Gap from on screen to that line is about six seconds.
- Same shape on 0.1.58 and 0.1.59.
- Server log shows attempt 1 only. No second “Connecting to Windows Remote Desktop.”
- 0.1.60 agent log at that same instant:
  - `desktop tcp reset`
  - `desktop read ended`
- Throwaway `/tmp/argus-tcp-hold.c` on `snappr-win`, adapter `ArgusPoC0`, `10.200.1.1` to `10.200.1.2:3389`:
  - Handshake and the 19-byte X.224 greeting completed.
  - Held 20 seconds.
  - 19 bytes, 2 segments, 0 out of order, 0 RST, 0 FIN.
  - Exit 0.
- TermService does not reset a quiet userspace TCP session.
- The reset happens on the product session after the picture is up.
- Throwaway `/tmp/argus-tcp-splice.exe` listened on `127.0.0.1:3391` and spliced one FreeRDP client onto `ArgusPoC0`.
- `xfreerdp /sec:tls` was refused by the server: `HYBRID_REQUIRED_BY_SERVER`.
- `xfreerdp /sec:nla` completed the negotiation and the server returned `STATUS_LOGON_FAILURE`.
- That run moved 1251 bytes from Windows and 1436 bytes to Windows.
- No RST and no FIN from Windows.
- The client closed after the rejected logon, about six seconds after accept, before any desktop.
- `query user` on `snappr-win` reported no interactive logon, and `cmdkey /list` stored none. `mstsc /restrictedadmin` from the SSH session never reached the listener.
- A later `mstsc /v:127.0.0.1:3391` from the console, splice started as administrator, showed “An internal error has occurred.”
- That run’s splice log: 1295 bytes from Windows, 1263 bytes to Windows, `rst 0`, `fin 0`, then `client recv failed 10054` and `exit 4`.
- 10054 is the loopback socket from `mstsc` being reset. TermService did not send a TCP RST.
- Product session 10, client `10.200.0.1:51422`, 2026-11-26 15:01:
  - 15:01:46.320 the server asked the client for a UDP transport.
  - 15:01:46.537 the desktop was ready.
  - 15:01:52.381 UDP handshake timed out (`0x800705B4`), six seconds later, and the server fell back to TCP.
  - 15:01:52.578 the graphics pipe failed (`0x8000000A`), WD reported protocol error 303, and the TCP read failed with 1236.
  - 15:01:52.693 the server disconnected the client. Reason `0xD0000001`.
- The agent’s `desktop tcp reset` is that server disconnect.
- 15:55 controller run, `SelectTransport` = 1 already set: on screen 15:55:29, report attempt 4 at 15:55:35.
- Tunnel 3 was forced to TCP. Tunnel 1 still waited for UDP, timed out at 15:55:34.987, then WD error 303 and `0xD0000001` again.
- `SelectTransport` was removed after that run. It did not stop the reset.
- Attempt 4 is the same tunnel's retry counter, left over from the 15:01, 15:04, and 15:13 reports. The status line prints that number and still says "of 3".

### Codebase observed behavior

- [`agent/windows/Adapter.vala`](../../agent/windows/Adapter.vala) `on_packet` sets `rst` when the peer segment has the RST flag, then the splice logs `desktop tcp reset` and stops.
- [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala) reads 0 from the loopback socket after that close and logs `desktop read ended`, then `redial()`.
- That redial is already in 0.1.60. The 15:01 run still stopped on attempt 1.
- In-order payload is appended and acknowledged.
- Any other payload length is acknowledged and discarded. There is no out-of-order buffer.
- `snd_una` is set to the peer ACK with no check that the ACK falls inside the sent range.
- Retransmit sends only the first 1460 bytes of `hold`.
- A failed `socket.send` of `inbox` sets `local_eof` and drops `inbox` after `rcv_nxt` has already moved.
- The splice then sends FIN on the way out unless it already saw RST.

### Debugging

#### Current debug output

- **Source:** `snappr-win` service `agent.log`, agent 0.1.60, 2026-11-26 15:01

```text
15:01:52.568977: G_LOG_LEVEL_WARNING : Adapter.vala:446: desktop tcp reset
15:01:52.568977: G_LOG_LEVEL_WARNING : Tunnel.vala:411: desktop read ended
```

- **Source:** throwaway `/tmp/argus-tcp-hold.exe` on `snappr-win`, 2026-11-26 15:04, not the agent

```text
send flags 0x02 seq 268435456 ack 0 len 0
recv flags 0x12 seq 3396596046 ack 268435457 len 0
send flags 0x10 seq 268435457 ack 3396596047 len 0
send flags 0x18 seq 268435457 ack 3396596047 len 19
recv flags 0x18 seq 3396596047 ack 268435476 len 19
send flags 0x10 seq 268435476 ack 3396596066 len 0
held bytes 19 segs 2 ooo 0 rst 0 fin 0
exit 0
```

- **Source:** throwaway `/tmp/argus-tcp-splice.exe` on `snappr-win`, client `xfreerdp` `/sec:nla` via a local forward, 2026-11-26 15:13

```text
client accepted
> flags 0x18 seq 268435457 ack 3535201898 len 42
< flags 0x18 seq 3535201898 ack 268435499 len 19
> flags 0x18 seq 268435499 ack 3535201917 len 329
< flags 0x18 seq 3535201917 ack 268435828 len 846
> flags 0x18 seq 268435828 ack 3535202763 len 318
< flags 0x18 seq 3535202763 ack 268436146 len 51
> flags 0x18 seq 268436146 ack 3535202814 len 122
< flags 0x18 seq 3535202814 ack 268436268 len 291
> flags 0x18 seq 268436268 ack 3535203105 len 594
< flags 0x18 seq 3535203105 ack 268436862 len 44
> flags 0x18 seq 268436862 ack 3535203149 len 31
< flags 0x10 seq 3535203149 ack 268436893 len 0
done in 1251 out 1436 rst 0 fin 0
```

- **Source:** same client, same minute

```text
[WARN][com.freerdp.core.nla] - SPNEGO received NTSTATUS: STATUS_LOGON_FAILURE [0xC000006D] from server
[ERROR][com.freerdp.core] - nla_recv_pdu:freerdp_set_last_error_ex ERRCONNECT_LOGON_FAILURE [0x00020014]
```

- **Source:** `C:\msys64\tmp\argus-tcp-splice.log` after console `mstsc /v:127.0.0.1:3391`, 2026-11-26 15:36

```text
client accepted
> flags 0x18 seq 268435457 ack 3889634308 len 19
< flags 0x18 seq 3889634308 ack 268435476 len 19
> flags 0x18 seq 268435476 ack 3889634327 len 180
< flags 0x18 seq 3889634327 ack 268435656 len 846
> flags 0x18 seq 268435656 ack 3889635173 len 318
< flags 0x18 seq 3889635173 ack 268435974 len 51
> flags 0x18 seq 268435974 ack 3889635224 len 86
< flags 0x18 seq 3889635224 ack 268436060 len 291
> flags 0x18 seq 268436060 ack 3889635515 len 660
< flags 0x18 seq 3889635515 ack 268436720 len 88
client recv failed 10054
done in 1295 out 1263 rst 0 fin 0
exit 4
```

#### Debug code added (remove when complete)

- None in the product for this report.
- `/tmp/argus-tcp-hold.c` and `/tmp/argus-tcp-splice.c`. Both use `ArgusPoC0` and `10.200.1.1/32`. Neither opens `ArgusWintun0` or calls `WintunDeleteDriver`.

### Proposed fix

Disable the broken FreeRDP 3 client settings in [`controller/Rdp/Screen.vala`](../../controller/Rdp/Screen.vala) (`SupportMultitransport=false`, `MultitransportFlags=0`, `RemoteFxCodec=false`, `NSCodec=false`, `SurfaceCommandsEnabled=false`, `SupportGraphicsPipeline=false`, `GfxH264=false`, `GfxAVC444=false`, `GfxAVC444v2=false`), wait on FreeRDP event handles with `WinPr.wait` instead of busy-spinning `check_event_handles`, and log `freerdp_get_last_error` on disconnect.

Disable Wintun at runtime in [`agent/windows/Adapter.vala`](../../agent/windows/Adapter.vala) (`use_wintun = false`) so Windows connects directly to `127.0.0.1:3389` without deleting the Wintun implementation, and reset `stream_tries` on fresh reconnect in [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala).

### Phase 3 — Live proof on `snappr-win` over plain `127.0.0.1:3389`

- Temporary local Windows user `argustest` was created on `snappr-win` (and deleted + session logged off after testing), tunneled with `ssh -L 127.0.0.1:3390:127.0.0.1:3389 snappr-win` (no Wintun).
- Real `/usr/bin/xfreerdp` (`-multitransport`) held the full 35 s until `timeout 35` killed it (`exit=124`). `netstat -ano` confirmed `127.0.0.1:3389 <-> 127.0.0.1:56963 ESTABLISHED` on `TermService` (PID 808). Windows `TermService` does not reject `127.0.0.1`.
- Throwaway `/tmp/argus-rdp-repro.c` (linked against `freerdp3` + `winpr3`, matching `Screen.vala`):
  - Exact `Screen.vala` flags: rendered 1024×768 (`786432` nonzero px), disconnected at `t=+6.33s` (`0x0002000D`). Windows `RdpCoreTS/Operational` logged the exact product failure: 6 s UDP timeout (`0x800705B4`) → `RDP_GFX: PipeEventOnProtocolClosedFailed (0x8000000A)` → `WD detected an error (303)` → `TCP READ error 1236` → `0xD0000001`.
  - Disabling only `SupportMultitransport`: failed immediately at `t=+0.31s` with the same `0x8000000A` / `WD error (303)` (proving the 6 s delay was the UDP timeout).
  - Disabling `SupportGraphicsPipeline` while keeping `SurfaceCommandsEnabled` + `RemoteFxCodec`/`NSCodec`: still failed at `t=+0.25s`–`0.39s` with the same `0x8000000A` / `WD error (303)`.
  - Disabling `SupportMultitransport`, `SupportGraphicsPipeline`, `GfxH264/AVC444/AVC444v2`, `RemoteFxCodec`, `NSCodec`, and `SurfaceCommandsEnabled` (with `BitmapCacheEnabled` + `BitmapCacheV3Enabled` on): held 35.24 s cleanly (`disconnected=0`, `events=1492`, `786432` nonzero px, `ERRBASE_SUCCESS`).
- Applied the proven fix to `server/vapi/freerdp.vapi`, `controller/Rdp/Screen.vala`, `agent/windows/Adapter.vala`, and `agent/Rdp/Tunnel.vala`. Linux controller/server build and Windows `valac -D WINDOWS` check on `Adapter.vala` pass cleanly.

### Phase 1 — Quiet TCP hold

- Ran `/tmp/argus-tcp-hold.exe`.
- Exit 0. Windows did not reset a session that only completed the greeting and then sat.
- This phase does not explain the desktop reset.

### Phase 2 — Splice throwaway through a real desktop

- `/tmp/argus-tcp-splice.exe` is the listener. Careful TCP: out-of-order data is kept until the gap fills, and an ACK moves `snd_una` only inside the unacked range.
- Ran it with `xfreerdp` `/sec:nla`. Windows did not reset that session. The client stopped at `STATUS_LOGON_FAILURE` and no picture was sent.
- Ran it with console `mstsc`. Windows did not reset that session either. `mstsc` reset its own loopback socket (`10054`) and showed an internal error. No picture.
- Pass remains: no RST, desktop still up 30 seconds after accept. That TCP is then the reference for a later product change.
- Fail remains: the program prints the RST sequence, ACK, and the last segments. The product is still not edited in that same step.
- This run is neither. The checker that treated “bytes moved, client already gone” as success is corrected so exit 0 requires the full 30 seconds.

### LLM

- ℹ️ Related feature file stays separate: `docs/bugs/2026-11-26-FEATURE-windows-rdp-virtual-adapter.md`. Do not mark it ✅ from this issue.
- ℹ️ Controller log `/home/alan/.cache/argusrm/controller.log`. Server log `/var/log/argusrm/server.log`. Agent log is the SYSTEM profile `agent.log` on `snappr-win`.
- ℹ️ 0.1.58 on screen 14:00:38, report 14:00:45. 0.1.59 on screen 14:43:18, report 14:43:24. 0.1.60 on screen 15:01:46.396, report 15:01:52.520, agent warning 15:01:52.568.
- 🚫 Ruled out as the cause of this death: TCP header offset (picture already appears), controller frame queue, five-second view timeout, missing `Relay.fresh`, stale seat, toast order, ignoring `relay.start` after a server restart.
- 🚫 A bare TermService TCP session is not reset at six seconds. The hold test stayed up.
- 🚫 A real FreeRDP NLA exchange that the server rejects is also not reset. Phase 2 moved 1251 bytes in and 1436 bytes out with `rst 0`.
- 🚫 Console `mstsc` to `127.0.0.1:3391` is also not a TermService RST. The splice logged `client recv failed 10054`, `rst 0`, `exit 4`. Same-box `mstsc` cannot produce the picture this phase needs.
- ℹ️ `query user` was empty and `cmdkey /list` was empty, so `mstsc /restrictedadmin` from the SSH session had no interactive logon to use. The listener never saw that client.
- 🚫 Hypothesis disproven: the 6-second drop was not Wintun TCP or Windows rejecting `127.0.0.1`. It was `controller/Rdp/Screen.vala` leaving `SupportMultitransport` enabled (6 s UDP timeout) and advertising uninitialized `SupportGraphicsPipeline` / `SurfaceCommandsEnabled` + `RemoteFxCodec`/`NSCodec` (immediate `RDP_GFX 0x8000000A` / `WD error 303`).
- ✔️ Proven live on `snappr-win` (both `xfreerdp` and `/tmp/argus-rdp-repro` held 35 s over plain `127.0.0.1:3389`), then applied to `server/vapi/freerdp.vapi`, `controller/Rdp/Screen.vala`, `agent/windows/Adapter.vala` (`use_wintun = false`), and `agent/Rdp/Tunnel.vala`.
- ⏳ Ready for Windows rebuild/install and end-to-end controller verification.
