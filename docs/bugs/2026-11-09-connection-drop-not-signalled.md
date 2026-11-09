# Server connection drop is not reported

**Status:** ✔️ `attach_connection` sets `connection_down` from `closed`. Not device-verified.

**Pointer:** `docs/bug-fix-process.md`

ℹ️ Library report: `/home/alan/gitlive/OLLMchat/docs/bugs/2026-11-09-tlsclient-watch-drop-not-signalled.md`.
ℹ️ `OLLMrpc.Transport.TlsClient` is `/home/alan/gitlive/OLLMchat/libocrpc/Transport/TlsClient.vala`. This tree does not edit that project.

---

## Problem

- 🔷 The agent must notice when the server connection drops, then try again 30 seconds later.
- 🔷 Reading the log text for `TlsClient.vala:` is not how that is detected.
- ℹ️ That check was in `agent/Application.vala` `debug_log`. It is removed.

## Ruled out

- 🚫 Sniffing `GLib.warning` text.
- 🚫 Editing OLLMchat from this tree.
- 🚫 Calling `TlsClient.call` on a timer to see if the connection is dead. `call` restarts `watch` while `watching` is still true.

## Evidence

- ✔️ Installed `/usr/share/vala/vapi/ocrpc.vapi` `TlsClient` exposes `open`, `call`, `watch`, and `notification`.
  - No `closed` signal.
  - `connected` is not in the vapi.
- ✔️ `TlsClient.watch` treats `WOULD_BLOCK` and `TIMED_OUT` as idle.
  - Any other read error calls `GLib.warning`, sets `watch_id` to 0, and returns false.
  - `connected` stays true.
  - `open` returns immediately while `connected` is true, so the same object cannot handshake again.
- ✔️ `agent/Application.vala` `attach_connection` retries when `connection` is null or `connection_down` is true.
  - `connection_down` is set only when `open_connection` returns null.
  - After a successful open, a later drop leaves `connection` set and `connection_down` false, so the 30-second timer does not try again.

## Root cause

- ✔️ The idle read stops inside `TlsClient` and the only public trace is a warning. The agent has no signal to set `connection_down`.

## Proposed fix

### 1. OLLMchat `TlsClient` — emit `closed`

- ℹ️ The library proposal is `/home/alan/gitlive/OLLMchat/docs/bugs/2026-11-09-tlsclient-watch-drop-not-signalled.md`.
- 🔷 Apply that report and install `libocrpc` before the agent change below.
- 🚫 Do not edit `TlsClient.vala` from this tree.

### 2. `agent/Application.vala` — set `connection_down` from `closed`

**Why:** The 30-second retry already runs when `connection_down` is true. Open the same `TlsClient` again. A new object would leave the old socket up.

**Where:** `attach_connection`, after section 1 is installed.

**Depends on:** the OLLMchat report in section 1

#### Remove

```vala
			this.connecting = true;
			this.connection = null;
			Application.connection_down = false;
			var opened = this.open_connection();
			if (opened == null) {
				Application.connection_down = true;
				this.connecting = false;
				return;
			}
			opened.notification.connect(this.notification);
			opened.watch();
			GLib.debug("watching the server connection");
			this.connecting = false;
```

#### Replace with

```vala
			this.connecting = true;
			var opened = this.connection;
			if (opened == null) {
				opened = this.open_connection();
				if (opened != null) {
					opened.closed.connect(() => {
						Application.connection_down = true;
					});
					opened.notification.connect(this.notification);
				}
			} else {
				try {
					opened.open();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					Application.connection_down = true;
					this.connecting = false;
					return;
				}
			}
			if (opened == null) {
				Application.connection_down = true;
				this.connecting = false;
				return;
			}
			opened.watch();
			Application.connection_down = false;
			GLib.debug("watching the server connection");
			this.connecting = false;
```

### 3. `agent/OSQuery/Initialize.vala` — no separate connection

**Why:** OSQuery sends on `Application.connection` when it syncs. It does not keep a client, and it does not call `watch`.

**Where:** already applied. Nothing in the library report changes this file.

## Attempts

- ✔️ Removed the `TlsClient.vala:` test from `debug_log`.
- ✔️ Renamed the agent server connection off the name `link`.
  - `connection`, `open_connection`, `attach_connection`, `connection_down`, `connection_check_id`.
- ✔️ Installed vapi now has `TlsClient.closed` and `TlsClient.connected`.
- ✔️ Applied the `agent/Application.vala` `attach_connection` replacement.
  - `connection_down` doc now includes the `closed` path.
- ✔️ `ninja -C build agent/argus-agent agent/argus-agent-cli` exited 0.

## Next

- ⏳ Drop a live server connection and confirm the agent opens it again about 30 seconds later.
