# Windows tray stays disconnected after the service connects

**Status:** ✔️

### User decisions required

- None.

### User reported

- 🔷 After installing the Windows agent, the machine shows the agent disconnected.

### Success scenario

- The tray tip becomes **Connected to management server** once the service TLS session is up, including when the tray asked for status before that session existed.

### Current behavior

- `snappr-win` after the **0.1.44** install: `argus-agent.exe` is running and `192.168.88.244:64763` is established to `192.168.88.132:817`.
- The service log records `AgentService.status` at `16:20:36.954` and `watching the server connection` at `16:20:38.222`.
- The tray tip is set from that status reply and from `agent.status` notifications. No later notification was sent.

### Codebase observed behavior

- [`agent/windows/tray/Tray.vala`](../../agent/windows/tray/Tray.vala) `connect_service` calls `AgentService.status` once after hello. Later updates come only from notification `agent.status`.
- [`agent/windows/Service.vala`](../../agent/windows/Service.vala) broadcasts `agent.status` only from `Application.state_changed`.
- [`agent/Application.vala`](../../agent/Application.vala) emits `state_changed` only for `agent.removed`.
- [`agent/Connection.vala`](../../agent/Connection.vala) sets `connection_down` in `on_connected`, `on_disconnected_will_retry`, and `on_disconnected_dead` and does not emit `state_changed`. `status` therefore still reports disconnected if the tray asked during `CHECKING_CONFIG` or `CONNECTING`.

### Debugging

#### Current debug output

```text
16:20:36.840049: G_LOG_LEVEL_DEBUG : Service.vala:102: local hello argus-tray 1
16:20:36.954138: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=6 method=AgentService.status conn=000001737b407c00
16:20:38.222186: G_LOG_LEVEL_DEBUG : Connection.vala:384: watching the server connection
```

`snappr-win` service `agent.log`, 2026-11-24, after the 0.1.44 installer. Server `server.log` shows `hello argus-agent 1 0.1.44` and `Task.agent_boot` on the same session.

#### Debug code added (remove when complete)

None.

### Proposed fix

#### `agent/Connection.vala` — emit `state_changed` when the link state the tray reads changes

**Why:** `AgentService.status` and the tray broadcast both read `connection` and `connection_down`. Those change in the three handlers below. The signal is already what the Windows service uses to push `agent.status`.

#### Replace with — `on_disconnected_will_retry`

```vala
			this.connect_attempt_until = 0;
			this.failure_detail = "";
			this.app.state_changed();
```

#### Replace with — `on_connected`

```vala
			this.reconnect_at = 0;
			this.connect_attempt_until = 0;
			this.app.state_changed();
```

#### Replace with — `on_disconnected_dead`

```vala
			this.reconnect_at = 0;
			this.connect_attempt_until = 0;
			this.app.status_notice = this.failure_detail;
			this.app.state_changed();
```

### LLM

- ✔️ Applied in `agent/Connection.vala`. Installer is **0.1.45** so it is not the already-installed **0.1.44**.
- ℹ️ Programs snapshot logged `osqueryi exited 1` in the same startup. The TLS session stayed up through `Task.agent_boot`. That query failure is separate from the tray tip.
