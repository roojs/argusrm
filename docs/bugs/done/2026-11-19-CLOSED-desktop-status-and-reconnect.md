# Desktop status never reaches the Waiting page

**Status:** ✅ closed 2026-11-24 — stale investigation; superseded by current tree and 2026-11-17-remote-desktop.md for RDP work.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [`server/Rdp/Relay.vala`](../../server/Rdp/Relay.vala), [`server/Rdp/Seat.vala`](../../server/Rdp/Seat.vala), [`controller/tab/Rdp.vala`](../../controller/tab/Rdp.vala), [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala), [`agent/Application.vala`](../../agent/Application.vala), [`server/Net/SslListen.vala`](../../server/Net/SslListen.vala)

---

## Problem

- 🔷 Take control opens the remote desktop page and leaves it on Waiting.
- 🔷 The Connected tick can be on. The agent can have logged `relay.start`. The page still sits there with no step and no failure.
- 🔷 Expected: after `Relay.start` succeeds, every later step or failure comes back through the normal RPC notification path onto that Waiting label.
- 🔷 Expected: a dropped server or agent connection is dialed again at once. A temporary failure does not unregister the machine.
- 🔷 Actual: the only controller notifications on this path are `relay.ready` and FreeRDP `problem`. Everything between `relay.start` and join is silent. A server abort then wiped the Windows certificate and left Take control answering "The machine is not connected."

---

## The flow, and whether each failure is handled

Each step tells the controller when it succeeds and when it fails. The notification carries a state from the enum below, not a sentence. The toast is `state.to_string()`. A retry appends " Trying N of 3" from the attempt number. Both appear as a toast, one after another, while the connection is built. ✔️ means that news already reaches the person. ❗ means it does not. 🔁 means another attempt belongs on this failure. The toast counts them: "Trying 1 of 3", then "Trying 2 of 3", then "Trying 3 of 3", and past the plan "Trying 4 of 3". Where the sentence says it stops, that attempt is missing. No 🔁 means trying again cannot help. A blank step cell continues the step above. The remote desktop screen has no toast today. Other pages use `Adw.Toast`.

| Step | State |
| --- | --- |
| Press Take control | ❗ `SUCCESS_TAKE_CONTROL`. The Remote Desktop page is not opened yet. |
| | ❗ `FAIL_NO_MACHINE`. |
| Controller tells the server | ❗ `SUCCESS_START_DESKTOP`. |
| | ✔️🔁 `RETRY_SERVER_UNREACHABLE`. A dialog appears today, and this attempt stops. |
| | ✔️ `FAIL_SERVER_REFUSED`. Same dialog. |
| Server checks the machine | ❗ `SUCCESS_MACHINE_CONNECTED`. |
| | ✔️ `FAIL_BAD_SOCKET`. |
| | ✔️🔁 `RETRY_MACHINE_DOWN`. The dialog appears, and this attempt stops. |
| | ❗ `SUCCESS_DESKTOP_ALREADY_OPEN`. |
| Ask the machine | ❗ `SUCCESS_ASKED_MACHINE`. |
| | ❗🔁 `RETRY_ASK_MACHINE`. The controller is still told it worked, and the page opens on Waiting. |
| Machine turns Remote Desktop on | ❗ `SUCCESS_REMOTE_DESKTOP_ENABLED`. |
| | ❗🔁 `RETRY_REMOTE_DESKTOP_DISABLED`. It tries once more only if Remote Desktop is turned on later. |
| Machine starts the RDP connection | The machine connects to Windows Remote Desktop on itself. |
| | ❗ `SUCCESS_LOCAL_RDP_CONNECTED`. |
| | ❗🔁 `RETRY_LOCAL_RDP_REFUSED`. Only a log line is written, and it stops. |
| Machine joins the server | The machine opens a second connection and joins as the desktop side. |
| | ❗ `SUCCESS_MACHINE_JOINED_RELAY`. |
| | ❗🔁 `RETRY_SECOND_CONNECTION`. Only a log line is written, and it stops. |
| | ❗🔁 `RETRY_MACHINE_JOIN_REFUSED`. The machine treats this as success and stops. |
| Machine starts sending data | The bytes are not the screen yet. |
| | ❗ `SUCCESS_MACHINE_STREAMING`. |
| | ❗🔁 `RETRY_MACHINE_STREAM`. Only a log line is written, and it stops. |
| | ❗ `FAIL_READY_EARLY`. The notice is thrown away. |
| Server holds the data | A late join asks the machine to start Windows again from the first byte. |
| | ❗ `SUCCESS_SERVER_AWAITING_VIEW`. |
| | ❗🔁 `RETRY_STREAM_FRESH_CUT`. It stops. |
| Controller joins the server | This controller opens its own second connection. |
| | ❗ `SUCCESS_CONTROLLER_JOINED_RELAY`. |
| | ❗🔁 `RETRY_CONTROLLER_JOIN_RELAY`. The error is hidden because Waiting was already removed, and it stops. |
| Server passes the data through | ❗ `SUCCESS_RELAY_FORWARDING`. |
| | ❗🔁 `RETRY_RELAY_FORWARDING_DROPPED`. It stops. |
| Draw the desktop in this window | The Remote Desktop page is in this same window. |
| | ❗ `SUCCESS_DESKTOP_RENDERED`. |
| | ✔️ `FAIL_PREPARE_RENDER`. Waiting on that page is replaced with the error. |
| | ✔️🔁 `RETRY_RENDER_CONNECT`. It stops. |
| | ❗🔁 `RETRY_DESKTOP_DISCONNECTED`. The page is left blank, and it stops. |
| Stay connected | ❗ `SUCCESS_SERVER_RECONNECTED`. Today the title changes back from Offline, with no toast. |
| | ✔️🔁 `RETRY_SERVER_DISCONNECTED`. The title changes to Offline and it tries again at once. |
| | ❗🔁 `RETRY_SERVER_CONNECT_REFUSED`. The controller waits thirty seconds. The machine tries every two seconds. |
| | ❗ The running server crashes while telling every connection that one connection closed. This happened at 13:15. There is no state for the crash. The fixed copy is built and not installed. |
| | ❗🔁 `RETRY_CERTIFICATE_RESTORE`. The installed agent deletes the certificate, so it cannot try again. This happened at 13:15. |

---

## Evidence

### Silent wait with the machine connected

- ✔️ 12:36:03 agent log has `relay.start`. Server log has `Relay.start` for that click. No `Relay.join` follows. Controller stayed on Waiting.
- ✔️ Connected tick and `Relay.start` use the same `by_id.get && running` check. Tick on plus agent `relay.start` means the request was delivered.
- ✔️ `controller/tab/Rdp.vala` notification handler only acts on `relay.ready`. There is no `relay.status` (or any other progress method).
- ✔️ `server/Rdp/Relay.start` writes `relay.start` and replies empty. It does not write a status notification to the controller that asked.
- ✔️ `agent/Win32/Service.relay_start` returns with no RPC when:
  - Remote Desktop is not on yet (`start_asked` only)
  - a tunnel is already held
  - `stream_connection()` returns null
  - `open_windows` throws (3389 dial) — warning only, tunnel cleared
- ✔️ `Tunnel.open_windows` join error is a `GLib.warning` and return. It does not throw, so `relay_start` treats it as success.
- ℹ️ The 12:14 gap (agent down three seconds before reconnect) is a real "not connected" case. It is not the explanation of the tick-on blank page. See the earlier note in 2026-11-17-remote-desktop.md; that note must not be read as the general blank-screen cause.

### Server abort while clients were reconnecting

- ✔️ 13:15:22 journal: `ERROR:arraylist.c:745:gee_array_list_real_get: assertion failed: (index < _size)`, then `code=dumped, status=6/ABRT`.
- ✔️ Stack: `SslListen.broadcast` → `SslConnection.stop` → `broadcast` again, nested many times.
- ✔️ Cause: `broadcast` walks `this.connections`. A failed `write` calls `stop`, which `remove`s that connection from the same list. libgee then reads past the end.
- ✔️ Throwaway `/tmp/argus-broadcast-reenter`: remove inside `foreach` aborts with the same assertion. A copied list does not.
- ✔️ Controller log: socket closed at 13:15:22 with 82 pending calls; immediate reconnect got connection refused; `RPC-Daemon.hello` succeeded at 13:16:10 / 13:16:15. Window title stayed `Argus RM 0.1.30` (not Offline forever).

### Windows agent wiped itself after the abort

- ✔️ Agent log 13:15:22: TLS handshake reset by the dying server → `registration cleared`.
- ✔️ Service-profile `...\AppData\Local\argus` then held only `download`, `download-path`, `server`. Certificate files gone.
- ✔️ Controller `Relay.start` at 13:16:23 replied `The machine is not connected.`
- ✔️ Startup on Windows treated "could not open / handshake failed" the same as "certificate not registered" and deleted the files. That path is what left the machine unable to dial again.

### What already changed in the tree (not all running)

- ✔️ `SslListen.broadcast` and `stop` copy the connection list before walking. Compiled into `build/server/argusrm-server`. Running `/usr/bin/argusrm-server` is still the old binary unless reinstalled/restarted from that build.
- ✔️ Windows startup only deletes the certificate when hello returns `CERT_NOT_REGISTERED`. A failed dial keeps the files and leaves the two-second retry. The installed agent is still 0.1.30 without that change, and this machine already lost its files.
- ✔️ Agent reconnect on drop is immediate (0.1.30). Controller reconnect still waits thirty seconds after a failed open.

---

## Root cause

- ✔️ The product path has one success notification (`relay.ready`) and almost no failure or progress notifications. The Waiting page is mute by design of the current RPC surface.
- ✔️ The agent knows the real reasons (desktop off, second socket failed, 3389 refused, join error). The server invents none of those. Without an agent→server report, the controller cannot show them.
- ✔️ A disconnect broadcast that mutates the connection list aborts the server process. That is a separate defect that then cascades into agent unregister and "machine not connected."
- ✔️ Treating a transient TLS failure as "not registered" deletes the only credentials that would reconnect.

---

## Proposed fix

### 1. Status notifications (product path)

- 🔷 Each step sends one state when it succeeds and one state when it fails. The desktop page toasts `state.to_string()`. It does not switch on the state to pick a sentence. A state that arrives before the screen is open is kept and shown when the screen opens. The page uses the same `Adw.Toast` overlay the package pages already use.
- 🔷 The state is `Argus.Rdp.State`. Every name starts with `REQUEST_`, `SUCCESS_`, `FAIL_`, or `RETRY_`. The names sit in the order the connection reaches them: the request, then the success or the failure of that step. The sentence is not on the wire. `REQUEST_` is the step being asked for. `SUCCESS_` is that step finished. `FAIL_` stops, because trying again will not help. `RETRY_` is the same failure sent again with the next attempt number.
- 💩 `Relay.report` args `ii` — state, then attempt. Attempt `0` is the first time. `1` is "Trying 1 of 3". Agent app socket, or the server itself for a step it knows. Reply empty. The server writes `relay.status` args `iii` (agent id, state, attempt) on the one controller connection that called `Relay.start`. That is not `Application.broadcast`. Pairing, agent connect and disconnect, and task events are the calls that still go to every connection.
- 💩 `controller/tab/Rdp.vala` handles `relay.status`, keeps the latest state per agent id, and toasts `state.to_string()`. When the attempt is above zero it appends " Trying N of 3". There is no second list of sentences.
- 💩 Prove on the wire in `server/tests/rdp-start.vala`: `report` of a state, and the controller receives that same state, not a string.
- ℹ️ A state the server already knows can ship without a Windows rebuild. A state only the machine knows needs a Windows agent newer than 0.1.30.

#### Add `shared/Rdp.vala`

```vala
namespace Argus.Rdp {
	public enum State {
		REQUEST_TAKE_CONTROL,
		SUCCESS_TAKE_CONTROL,
		FAIL_NO_MACHINE,

		REQUEST_START_DESKTOP,
		SUCCESS_START_DESKTOP,
		RETRY_SERVER_UNREACHABLE,
		FAIL_SERVER_REFUSED,

		REQUEST_CHECK_MACHINE_CONNECTED,
		SUCCESS_MACHINE_CONNECTED,
		FAIL_BAD_SOCKET,
		RETRY_MACHINE_DOWN,
		SUCCESS_DESKTOP_ALREADY_OPEN,

		REQUEST_ASK_MACHINE,
		SUCCESS_ASKED_MACHINE,
		RETRY_ASK_MACHINE,

		REQUEST_ENABLE_REMOTE_DESKTOP,
		SUCCESS_REMOTE_DESKTOP_ENABLED,
		RETRY_REMOTE_DESKTOP_DISABLED,

		REQUEST_CONNECT_LOCAL_RDP,
		SUCCESS_LOCAL_RDP_CONNECTED,
		RETRY_LOCAL_RDP_REFUSED,

		REQUEST_MACHINE_JOIN_RELAY,
		SUCCESS_MACHINE_JOINED_RELAY,
		RETRY_SECOND_CONNECTION,
		RETRY_MACHINE_JOIN_REFUSED,

		REQUEST_MACHINE_STREAM_DATA,
		SUCCESS_MACHINE_STREAMING,
		RETRY_MACHINE_STREAM,
		FAIL_READY_EARLY,

		REQUEST_SERVER_AWAIT_VIEW,
		SUCCESS_SERVER_AWAITING_VIEW,
		RETRY_STREAM_FRESH_CUT,

		REQUEST_CONTROLLER_JOIN_RELAY,
		SUCCESS_CONTROLLER_JOINED_RELAY,
		RETRY_CONTROLLER_JOIN_RELAY,

		SUCCESS_RELAY_FORWARDING,
		RETRY_RELAY_FORWARDING_DROPPED,

		REQUEST_RENDER_DESKTOP,
		SUCCESS_DESKTOP_RENDERED,
		FAIL_PREPARE_RENDER,
		RETRY_RENDER_CONNECT,
		RETRY_DESKTOP_DISCONNECTED,

		SUCCESS_SERVER_RECONNECTED,
		RETRY_SERVER_DISCONNECTED,
		RETRY_SERVER_CONNECT_REFUSED,
		RETRY_CERTIFICATE_RESTORE;

		public string to_string() {
			switch (this) {
			case REQUEST_TAKE_CONTROL:
				return "Take control.";
			case SUCCESS_TAKE_CONTROL:
				return "Take control.";
			case FAIL_NO_MACHINE:
				return "No machine is selected.";
			case REQUEST_START_DESKTOP:
				return "Telling the server to open the desktop.";
			case SUCCESS_START_DESKTOP:
				return "Told the server this controller wants to take control.";
			case RETRY_SERVER_UNREACHABLE:
				return "The server cannot be reached.";
			case FAIL_SERVER_REFUSED:
				return "The server refused.";
			case REQUEST_CHECK_MACHINE_CONNECTED:
				return "Checking that the machine is connected.";
			case SUCCESS_MACHINE_CONNECTED:
				return "The machine is connected.";
			case FAIL_BAD_SOCKET:
				return "The desktop request did not arrive on the server's machine socket.";
			case RETRY_MACHINE_DOWN:
				return "The machine is not connected.";
			case SUCCESS_DESKTOP_ALREADY_OPEN:
				return "The desktop is already open.";
			case REQUEST_ASK_MACHINE:
				return "Asking the machine to open Remote Desktop.";
			case SUCCESS_ASKED_MACHINE:
				return "Asked the machine to open Remote Desktop.";
			case RETRY_ASK_MACHINE:
				return "Could not tell the machine.";
			case REQUEST_ENABLE_REMOTE_DESKTOP:
				return "Turning Remote Desktop on.";
			case SUCCESS_REMOTE_DESKTOP_ENABLED:
				return "Remote Desktop is on.";
			case RETRY_REMOTE_DESKTOP_DISABLED:
				return "Waiting for Remote Desktop to be turned on.";
			case REQUEST_CONNECT_LOCAL_RDP:
				return "Connecting to Windows Remote Desktop on the machine.";
			case SUCCESS_LOCAL_RDP_CONNECTED:
				return "The machine started the Remote Desktop connection.";
			case RETRY_LOCAL_RDP_REFUSED:
				return "Windows Remote Desktop refused the connection.";
			case REQUEST_MACHINE_JOIN_RELAY:
				return "The machine is joining the server.";
			case SUCCESS_MACHINE_JOINED_RELAY:
				return "The machine joined the server.";
			case RETRY_SECOND_CONNECTION:
				return "The machine could not open its second connection.";
			case RETRY_MACHINE_JOIN_REFUSED:
				return "The server did not accept the machine.";
			case REQUEST_MACHINE_STREAM_DATA:
				return "The machine is about to send the desktop.";
			case SUCCESS_MACHINE_STREAMING:
				return "The machine is sending the desktop to the server.";
			case RETRY_MACHINE_STREAM:
				return "The machine could not send the desktop.";
			case FAIL_READY_EARLY:
				return "The machine was ready before the screen was open.";
			case REQUEST_SERVER_AWAIT_VIEW:
				return "The server is waiting for this controller.";
			case SUCCESS_SERVER_AWAITING_VIEW:
				return "The server is holding the desktop until this controller joins.";
			case RETRY_STREAM_FRESH_CUT:
				return "Starting the desktop again from the first byte failed.";
			case REQUEST_CONTROLLER_JOIN_RELAY:
				return "This controller is joining the desktop.";
			case SUCCESS_CONTROLLER_JOINED_RELAY:
				return "This controller joined the desktop.";
			case RETRY_CONTROLLER_JOIN_RELAY:
				return "This controller could not join the desktop.";
			case SUCCESS_RELAY_FORWARDING:
				return "The desktop data is coming through.";
			case RETRY_RELAY_FORWARDING_DROPPED:
				return "The desktop connection dropped.";
			case REQUEST_RENDER_DESKTOP:
				return "Drawing the desktop in this window.";
			case SUCCESS_DESKTOP_RENDERED:
				return "The desktop is on screen.";
			case FAIL_PREPARE_RENDER:
				return "The desktop could not be prepared.";
			case RETRY_RENDER_CONNECT:
				return "FreeRDP could not open the desktop.";
			case RETRY_DESKTOP_DISCONNECTED:
				return "The desktop stopped.";
			case SUCCESS_SERVER_RECONNECTED:
				return "Connected to the server again.";
			case RETRY_SERVER_DISCONNECTED:
				return "Disconnected from the server.";
			case RETRY_SERVER_CONNECT_REFUSED:
				return "Could not reach the server.";
			case RETRY_CERTIFICATE_RESTORE:
				return "The machine certificate is missing.";
			default:
				return "";
			}
		}
	}
}
```

### 2. Server broadcast abort

- ✔️ Proposal already applied in tree: copy `connections` before `broadcast` and before `stop` walks them. Skip `!running` in the broadcast copy.
- ⏳ Install/restart the built server so the running process has it.

### 3. Windows certificate wipe

- ✔️ Proposal already applied in tree: only `CERT_NOT_REGISTERED` clears the files.
- ⏳ Ship that agent (version bump past 0.1.30). This machine must be registered again because the files are already gone.

### 4. Out of scope for the silent Waiting page, still related

- 💩 Controller 30-second reconnect after a failed open (agent is already immediate). Same class of "sit there" problem for Offline.
- 🚫 Do not invent Windows/desktop failures on the server. The agent must report them.
- 🚫 Do not put status chrome in the window header bar.

---

## Attempts / changelog

- ✔️ 2026-11-19: Confirmed 12:36 silent wait with agent `relay.start` and no join.
- ✔️ 2026-11-19: Confirmed 13:15:22 server ABRT from `broadcast` / list remove; throwaway reproduced the assertion.
- ✔️ 2026-11-19: Confirmed Windows agent deleted certificates after the reset handshake; Take control then got "The machine is not connected."
- ✔️ 2026-11-19: `SslListen` snapshot walk applied. Windows hello-only cert wipe applied. Neither is what the user is running yet for the agent; server binary built but not necessarily installed.

## Next

- ✔️ User (2026-11-24): close — log is older/relevant only as historical evidence.
- ⏳ Any live RDP/status gaps: track in 2026-11-17-remote-desktop.md or a new dated ISSUE.

## LLM notes

- User (2026-11-24): parked entire file; do not treat as active backlog.
- 🚫 Do not treat "agent was not connected" as the explanation when the Connected tick is on and the agent logged `relay.start`.
- 🚫 Do not open the desktop page on a `Relay.start` error reply. That path already returns false.
- 🚫 Do not add window-wrapper methods for `rdp` / `tabs`. Those fields are public.
- ℹ️ Feature construction phases stay in 2026-11-17-remote-desktop.md. This file owns the failure/status path and the reconnect cascade that made the machine disappear.
