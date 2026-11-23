# Bootstrap local login loops (evidence on alan-office-desktop)

**Status:** ⏳ parked (2026-11-23 — registration flow still unstable; evidence captured; resume with logs in this file)

**Pointer:** [2026-11-23-ISSUE-bootstrap-already-registered-recovery.md](2026-11-23-ISSUE-bootstrap-already-registered-recovery.md), [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala), [`server/Registration.vala`](../../server/Registration.vala)

### User reported

- 🔷 Local **log in / re-register** spins; multiple pkexec steps feel broken when already root.
- 🔷 Expected: one clear re-register, then the main window.

### Success scenario

- One privileged step clears local save + server row + new cert, then connect on loopback without probing every bridge address.

### Current behavior (evidence, not theory)

- **Host:** `alan-office-desktop`, user `alan` (uid 1001, not root when Gtk runs).
- **Binaries (2026-11-23):** `/usr/bin/argusrm-controller` 15:49, `/usr/bin/argusrm-server` 15:42, both **0.1.43** in log hellos.

### Debugging

#### On-disk client state (2026-11-23 ~15:51)

- `~/.config/argusrm/server.sqlite` — rows `172.18.0.1` and two `alan-office-desktop` rows (`deleted_dt` set on id 1–2; id 3 active with `127.0.0.1` first).
- `~/.config/argusrm/connections.json` — still lists `alan-office-desktop` and `roojs.com` ( six bridge/LAN addresses + remote host).

#### `~/.cache/argusrm/controller.log` (Gtk session, same afternoon)

```text
15:49:56.341554: G_LOG_LEVEL_CRITICAL : gtk_widget_get_can_focus: assertion 'GTK_IS_WIDGET (widget)' failed
15:50:06.055166: G_LOG_LEVEL_CRITICAL : gtk_widget_get_can_focus: assertion 'GTK_IS_WIDGET (widget)' failed
15:51:00.140245: G_LOG_LEVEL_CRITICAL : gtk_widget_get_can_focus: assertion 'GTK_IS_WIDGET (widget)' failed
15:51:01.308056: G_LOG_LEVEL_CRITICAL : gtk_widget_get_can_focus: assertion 'GTK_IS_WIDGET (widget)' failed
```

#### `/var/log/argusrm/server.log` — recovery sequence (before restart; **replaced** when server restarted 15:49:44)

Captured from the same host earlier the same day; no longer in the live file after restart:

```text
15:43:16.057035: G_LOG_LEVEL_DEBUG : Daemon.vala:67: hello argusrm-server 1 0.1.43
15:43:16.058318: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=2 method=Registration.certificate
15:43:16.059147: G_LOG_LEVEL_WARNING : SslListen.vala:192: ssl handshake failed: Peer failed to perform TLS handshake: Error sending data: Broken pipe
15:43:20.395702: G_LOG_LEVEL_DEBUG : Daemon.vala:67: hello argus-controller 1 0.1.43
15:43:20.395942: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=2 method=Registration.deregister
15:43:20.396068: G_LOG_LEVEL_DEBUG : Database.vala:183: disk backup requested
15:43:22.650203: G_LOG_LEVEL_DEBUG : Daemon.vala:67: hello argusrm-server 1 0.1.43
15:43:22.650498: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=2 method=Registration.certificate
```

- ℹ️ Server log does **not** print RPC error text for refused certificates—only `recv … Registration.certificate`.

#### `/var/log/argusrm/server.log` — after restart (current file tail)

```text
15:50:20.162270: G_LOG_LEVEL_WARNING : SslListen.vala:192: ssl handshake failed: Peer failed to perform TLS handshake: Error sending data: Broken pipe
(×4 within ~1s)
15:50:20.745522: G_LOG_LEVEL_DEBUG : Daemon.vala:67: hello argus-agent 1 0.1.39
15:50:20.745531: G_LOG_LEVEL_WARNING : Daemon.vala:80: This client is 0.1.39. The server is 0.1.43.
```

### Codebase observed behavior

- ✔️ Bootstrap **TCP probe** tries every saved address (docker bridges, etc.) before TLS; matches Broken-pipe burst pattern.
- ✔️ Recovery used **two pkexec** steps (deregister + certificate) from an unprivileged Gtk process.
- ✔️ Username **deregister** on Unix socket originally skipped active rows with non-loopback `ip` (fixed in tree; needs server install).

### Proposed fix (in tree — verify on this host)

- `--local-reregister`: one root flow (deregister + `Registration.certificate` on the same Unix socket).
- Skip pkexec when `geteuid() == 0`.
- After local enroll, open via **127.0.0.1** instead of full address probe.

### Still open on this host

- ⏳ Gtk `GTK_IS_WIDGET` critical during Bootstrap (log above).
- ⏳ `connections.json` vs `server.sqlite` drift after clear (roojs.com still in JSON).
- 💩 `/var/lib/argusrm/argus.sqlite` agent rows — not readable from agent session without sudo (no pasted copy).

### LLM

- 2026-11-23: Evidence file added from live `server.log` / `controller.log` / client DB on `alan-office-desktop`; 15:43 RPC block preserved here because restart truncated `server.log`.
- 2026-11-23: User paused work — treat registration as **unstable** until re-test after full install (server + controller + polkit policy for `--local-reregister`).