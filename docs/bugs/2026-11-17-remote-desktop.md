# Remote desktop from the machine General tab

**Status:** ⏳ critical — Phases 1–4 are implemented and not yet verified. Force and the Disconnect notice are Phase 6.5. The viewer is Phases 5 and 6. Phase 7 waits until Windows works.

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md`, archived plan [5.12-MOVED-remote-desktop.md](../plans/done/5.12-MOVED-remote-desktop.md), [2026-11-17-FIXED-windows-command-session-job.md](done/2026-11-17-FIXED-windows-command-session-job.md), [2026-11-16-FIXED-windows-uninstall-task-queue.md](done/2026-11-16-FIXED-windows-uninstall-task-queue.md), [`controller/tab/Asset/Machine/General.vala`](../../controller/tab/Asset/Machine/General.vala), [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala), [`server/Net/Download.vala`](../../server/Net/Download.vala)

---

## Problem

- 🔷 Scripted Windows uninstalls are not a reliable way to finish the job. A task can start on the signed-in desktop and still be a window nobody is there to click. The person has to be at that desktop.
- 🔷 **Expected:** on the General tab of a Windows machine, a button with a screen picture. Touch and hold starts visual remote control of that machine. Argus turns Windows Remote Desktop on, and tunnels those protocol bytes to a viewer on the controller.
- 🔷 **Actual:** no button, the agent does not enable Remote Desktop, and there is no product tunnel. The only path onto the machine is a task command.

---

## Why this left the plan

- 🔷 [5.12](../plans/done/5.12-MOVED-remote-desktop.md) was feasibility only, and it waited. It is this bug because the uninstall work still leaves machines that need a person on the desktop.
- ℹ️ [2026-11-17-FIXED-windows-command-session-job.md](done/2026-11-17-FIXED-windows-command-session-job.md) starts the command on the signed-in desktop and waits for the process tree. That does not click a wizard. The Illustrator run in that log is the case: the launcher exited, and `Set-up.exe` sat on a lock.
- ℹ️ [2026-11-16-FIXED-windows-uninstall-task-queue.md](done/2026-11-16-FIXED-windows-uninstall-task-queue.md) rewrites `msiexec /I` to a silent `/X … /qn /norestart`. An uninstaller that is not `msiexec`, or that ignores the quiet flags, still opens a window on a desktop the controller cannot see.

---

## Evidence

- ✔️ The General tab is `controller/tab/Asset/Machine/General.vala`, inside `controller/tab/Asset/Machine/Detail.vala`. General is a vertical list of expanders. It has no bar of its own. `Detail` has the tab toggles. The window header bar is the title only.
- ✔️ The controller is GTK 4 and libadwaita. `controller/meson.build`.
- ✔️ The Windows agent is the service in `agent/Win32/Service.vala`. It already holds a TLS session to the server. Nothing in the tree sets `fDenyTSConnections`, starts `TermService`, or speaks Remote Desktop.
- ℹ️ The download socket is the precedent for a second listen: the same client certificate, and a transfer there does not clog the app socket. `server/Net/Download.vala`.
- ℹ️ `Application.open_connection` keeps one `TlsClient`, and `watch` reads frames for the life of it.

---

## Root cause

- ✔️ There is no remote-desktop path. A task command cannot stand in for one when the work is a window on that machine.

---

## Phases

- ✔️ **Phase 1 — Relay proof.** Framed RPC carried a FreeRDP session. Test binaries only.
- ✔️ **Phase 2 — Second connection, same port.** No other port and no other listener. The server registers `Relay.join` and `Relay.write`. The proof still uses the test listen.
- ✔️ **Phase 3 — Enable Windows Remote Desktop.** Edition check, logged-in check, and the tray balloon are in. The button is Phase 5.
- ✔️ **Phase 4 — Start the flow.** In the tree. Not verified on a machine. The agent streams. The server tells the controller. Bytes are dropped until the controller connects, then forwarded from the start of a connection. A late controller gets a new connection from the first byte.
- 🔷 ⏳ **Phase 5 — Viewer.** A touch and hold of the screen button on General opens the RDP page in this window.
- 🔷 ⏳ **Phase 6 — Session tabs.** The selected tab is the live feed. The X on a tab disconnects it.
- 🔷 ⏳ **Phase 6.5 — Takeover edges.** Force. The tray names who has the screen and can disconnect. The stream proposal is Phase 4.
- 💩 ⏳ **Phase 7 — Linux desktops.** After Windows works. GNOME Remote Desktop and xrdp speak this protocol.

Phase 2 adds no port and no listener.

---

## Phase 1 — Relay proof

- ✔️ `meson test -C build rdp-relay` passed. The desk log contains `ACTIVATED` and the test prints `ok rdp relay activated`. Needs `freerdp3`, `freerdp-server3`, `winpr3`, and `sdl-freerdp3`.
- ✔️ The path is `Argus.Agent.Rdp.Desk` (FreeRDP listener on `127.0.0.1`) ← `Argus.Agent.Rdp.Tunnel` (dials that port, joins as `agent`) ← `Argus.Server.Rdp.Relay` (`Relay.write` chunks become `relay.data`) ← `Argus.Controller.Rdp.Viewer` (joins as `view`, accepts sdl-freerdp3 on a loopback port).
- ✔️ Those classes are compiled into `argus-rdp-desk` and `argus-rdp-relay-test` from the top-level `meson.build`. They are not linked into the agent, the server, or the controller.
- ✔️ The bytes are framed `ay` chunks on `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`. `Relay.join` and `Relay.write` exist only inside the test process. They are not in `docs/rpc-commands.md`.
- ℹ️ The stand-in desk turns NLA off and accepts any logon, so the Linux listener can finish without a Windows account. Phase 3 does not copy that. Network Level Authentication stays on for TermService.
- ℹ️ sdl-freerdp3 ran with `+auth-only`. It did not open a window. `ACTIVATED` is FreeRDP finishing the connection sequence, not a person looking at a desktop.
- ✔️ 2026-11-18: the same listen also answers `App.ping` on the first connection while the second connection streams. After `joined view` the log still has `app pong`, then `ACTIVATED`. `meson test -C build rdp-relay` prints `ok app rpc during stream`.
- 🚫 A hand-rolled C Gio TLS splice. The probe is Vala and uses the existing RPC types.
- 🚫 sdl-freerdp3 inside a GTK 4 widget. It is a separate SDL window. Phase 5 paints with `libfreerdp-client`.

---

## Phase 2 — Second connection, same port

- 🔷 The desktop is another connection to the port that is already listening. No other port. No other listener.
- 🔷 The first connection stays the app session. It is not switched to raw bytes. The desktop bytes are not `agent.run`.
- 🔷 An RPC on the second connection turns streaming on. The bytes are the Remote Desktop protocol, not a second remote-desktop product.
- ✔️ One listen, one port. The first connection calls `App.ping` and does not join the stream. The agent and the viewer open further connections to that same port and `Relay.join` turns streaming on. `App.ping` still replies after `joined view`, and the desk reaches `ACTIVATED`.
- ℹ️ The listen in the test is the same shape as `server/Net/SslListen.vala`: one `SocketService`, TLS, a client certificate, then `OLLMrpc.Transport.Connection`. The product class is not the one that accepted these connections.
- 🚫 Another listen, or any new port. The download socket stays an HTTPS GET. `server/Net/Download.vala`.
- ℹ️ The agent still dials out. The machine does not accept a new inbound port for this.
- ℹ️ Streaming off is not dropping the desktop. A tab that is not selected keeps the Windows session and drops the bytes. Phase 6.
- ℹ️ Phase 2 does not start the stream. The test opens the agent connection itself. Phase 4 is signed off. Phase 6.5 builds it.
- 🔷 A new or changed `Request.add_class` method is written into `docs/rpc-commands.md` in the same change.
- ✔️ The fences are applied. The server calls `Rdp.Relay.rpc_register()` and compiles `Relay.vala`. `listen()` stays the test's listen. The server does not call it.

---

## Phase 3 — Enable Windows Remote Desktop

- 🔷 Show the button only when `supports_rdp()` is true. If it is false, show nothing. The button is Phase 5. It is not built.
- ✔️ The agent does not change Windows when `supports_rdp()` is false.
- ℹ️ The Windows name is `os_version.name`, for example `Microsoft Windows 11 Pro`. No name yet means no.
- ✔️ After startup the Windows agent sets `fDenyTSConnections` to `0`, sets `UserAuthentication` to `1`, and starts `TermService`. The firewall group is left closed.
- 🔷 Leave the Windows password prompt on. Argus does not store the password.
- ✔️ Nobody is logged in: an active Windows session is absent, so Remote Desktop is turned on. No tray question.
- ✔️ Someone is logged in: an active session is present. The service sends `agent.desktop`.
- ✔️ The tray reads the last keyboard or mouse time. Half an hour idle allows Remote Desktop without asking. More recent input shows a balloon. A click allows it. Ignoring the balloon leaves it off.
- ℹ️ The service cannot read that time. It runs in session 0. The tray runs in the signed-in session.
- 🔷 Sign in as the person already logged in. A different account logs them off.
- ℹ️ Force, and the tray notice that names who has the screen, are Phase 6.5.
- ℹ️ A machine that is really asleep has to wake before any of this.
- 🚫 Do not patch Windows to invent a second screen, or to turn this on for Home.

---

## Phase 4 — Start the flow

- 🔷 The controller starts this when the operator touches and holds the screen button on that machine's General tab. Phase 5 draws the button.
- 🔷 The agent opens the second connection and starts streaming once Remote Desktop is on.
- 🔷 The server tells the controller that this machine's stream has started. That notification is not the desktop bytes.
- 🔷 Until that controller connects, the server drops the stream bytes.
- 🔷 When the controller connects, the server forwards both ways.
- ℹ️ Windows sends nothing until it receives the viewer's opening bytes. The controller's first bytes are the start of the connection.
- 🔷 A controller that arrives after a stream is already going does not join the middle. The agent closes that connection to Windows and opens a new one. Forwarding starts at the first byte of the new connection.
- 🚫 The server does not read Remote Desktop messages to find a cut point. The cut is a new connection.
- ℹ️ The proposal is this phase. Force and the tray notice stay in Phase 6.5.
- ℹ️ Not in `meson test -C build rdp-relay`. That test starts the agent and the viewer itself. `Relay.listen` stays the test listen.
- 🔷 Phase 5's screen button calls `MachineGeneral.start_desktop`. It does not draw the button.

### 1. `server/Rdp/Relay.vala` — `rpc_register`: `start`, `view`, `fresh`

**Why:** The controller asks on the app socket. The view joins on its own connection. `fresh` is the cut after Windows is dialed again. `join` and `write` stay the test pair.

**Where:** `rpc_register`, the `add_class` argument list.

**Depends on:** none.

#### Remove

```vala
				"join", "s",
				"write", "ay");
```

#### Replace with

```vala
				"join", "s",
				"write", "ay",
				"start", "i",
				"view", "i",
				"fresh", "");
```

### 2. `server/Rdp/Seat.vala` — one machine

**Why:** One test pair cannot carry more than one machine. Each agent id has its own stream, view, and the controller that asked. That state lives on `Seat`. `Relay` keeps the map.

**Where:** `server/Rdp/Seat.vala`. The map is inside `Relay`, after `view_conn`.

**Depends on:** none.

#### Add — `Seat`, and the map on `Relay`

`asked` is the controller app connection waiting for `relay.ready`. `holding` is a `Relay.view` that is waiting for `release`. `begun` is set when a byte has been forwarded. `ready`, `joined`, `attach`, `release`, and `forward` are the seat. The controller check and `ssl_listen.by_id` stay on `Relay`.

```vala
		private Gee.HashMap<int, Seat> seats = new Gee.HashMap<int, Seat>();
```

### 3. `server/Rdp/Relay.vala` — `seat` and `seat_of`

**Why:** `start`, `view`, `join`, `write`, and `fresh` share one lookup.

**Where:** new methods, after `rpc_register`.

**Depends on:** ### 2.

#### Add — after `rpc_register`, the two lookups

```vala
		/**
		 * The seat for one agent id, creating it on first use.
		 *
		 * @param id ''agent.id''
		 * @return that seat
		 */
		private Seat seat(int id)
		{
			if (this.seats.has_key(id)) {
				return this.seats.get(id);
			}
			var created = new Seat();
			this.seats.set(id, created);
			return created;
		}

		/**
		 * The seat whose stream or view is this connection.
		 *
		 * @param conn a stream connection
		 * @return the seat, or null for the test pair
		 */
		private Seat? seat_of(OLLMrpc.Transport.Connection conn)
		{
			foreach (var seat in this.seats.values) {
				if (seat.agent_conn == conn || seat.view_conn == conn) {
					return seat;
				}
			}
			return null;
		}
```

### 4. `server/Rdp/Relay.vala` — `start`

**Why:** The hold on General calls this. The server tells that agent, on the app connection, to open the stream. The reply is not the desktop.

**Where:** new method, after `seat_of`.

**Depends on:** ### 3.

#### Add — after `seat_of`, the controller ask

A missing agent replies `unknown agent`. An agent that has already joined gets `relay.ready` on this call. Otherwise the ask is stored and `relay.start` is written to `ssl_listen.by_id`.

```vala
		/**
		 * Ask one Windows agent to open its desktop stream.
		 *
		 * The caller is a controller. ''relay.start'' goes to that
		 * agent's app connection. ''relay.ready'' is sent here when
		 * the stream is already up, and from {@link join} when it
		 * comes up later.
		 *
		 * @param request inbound RPC
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void start(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var ssl = request.connection as Net.SslConnection;
			if (ssl == null || agent_id < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			var agent = ssl.app.ssl_listen.by_id.get(agent_id);
			if (agent == null || !agent.running) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			var seat = this.seat(agent_id);
			if (seat.agent_conn != null) {
				request.reply(new OLLMrpc.Response());
				seat.ready(request.connection, agent_id);
				return;
			}
			seat.asked = request.connection;
			agent.write(new OLLMrpc.Notification() {
				method = "relay.start"
			});
			request.reply(new OLLMrpc.Response());
		}
```

### 5. `server/Rdp/Relay.vala` — `join` for a product agent

**Why:** The second connection is the agent's certificate. The test connections are not `SslConnection`, so they keep the single pair.

**Where:** the start of `join`, before `if (role == "agent")`.

**Depends on:** ### 3.

#### Add — at the start of `join`, before the test pair

An agent `SslConnection` is stored on that id. `relay.ready` goes to the controller that called `start`. A controller `join` is not this branch.

```vala
			var ssl = request.connection as Net.SslConnection;
			if (ssl != null && ssl.user.id > 0 && !ssl.user.is_controller && role == "agent") {
				var id = (int) ssl.user.id;
				this.seat(id).joined(request, id);
				return;
			}
```

### 6. `server/Rdp/Relay.vala` — `view` and `fresh`

**Why:** The first view is forwarded from the Windows connection already waiting. A view that arrives after a byte has been forwarded does not join that middle. The server tells the agent `relay.cut` and does not answer `view` until `fresh`.

**Where:** new methods, after `start`.

**Depends on:** ### 4.

#### Add — after `start`, the view join and the cut

`view` stores this connection as the view. When `begun` is false it replies at once. When `begun` is true it keeps the request and writes `relay.cut` on the agent app connection. `fresh` clears `begun` and replies to that held request. Bytes until then are dropped by `write`.

```vala
		/**
		 * Attach this controller stream to one agent.
		 *
		 * A stream that has already forwarded a byte is cut first.
		 * The reply waits for {@link fresh}.
		 *
		 * @param request inbound RPC, the controller's second connection
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void view(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var ssl = request.connection as Net.SslConnection;
			if (ssl == null || agent_id < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			var seat = this.seat(agent_id);
			if (!seat.attach(request)) {
				return;
			}
			var agent = ssl.app.ssl_listen.by_id.get(agent_id);
			if (agent == null || !agent.running) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown agent")
				});
				return;
			}
			seat.holding = request;
			agent.write(new OLLMrpc.Notification() {
				method = "relay.cut"
			});
		}

		/**
		 * Mark the agent's new Windows connection as the start.
		 *
		 * The next forwarded byte is the first byte of that connection.
		 *
		 * @param request inbound RPC on the agent stream
		 */
		public void fresh(OLLMrpc.Request request)
		{
			var seat = this.seat_of(request.connection);
			request.reply(new OLLMrpc.Response());
			if (seat == null) {
				return;
			}
			seat.release();
		}
```

### 7. `server/Rdp/Relay.vala` — `write`

**Why:** Product bytes go to that seat's other side. Until the view exists, and while a cut is waiting, the chunk is dropped. The test pair is unchanged.

**Where:** `write`, the lines that choose `other`, and after `other.write`.

**Depends on:** ### 6.

#### Remove

```vala
			var other = this.agent_conn;
			if (request.connection == this.agent_conn) {
				other = this.view_conn;
			}
			request.reply(new OLLMrpc.Response());
			if (other == null || chunk.get_size() == 0) {
				return;
			}
```

#### Replace with

```vala
			var seat = this.seat_of(request.connection);
			var other = this.agent_conn;
			if (seat == null && request.connection == this.agent_conn) {
				other = this.view_conn;
			}
			request.reply(new OLLMrpc.Response());
			if (seat != null) {
				seat.forward(request.connection, chunk);
				return;
			}
			if (other == null || chunk.get_size() == 0) {
				return;
			}
```

`Seat.forward` writes the chunk and remembers that a byte moved. The test pair still uses `other.write(note)` below this.

### 8. `docs/rpc-commands.md` — the three calls and two notifications

**Why:** A new method and a new notification are written here in the same change.

**Where:** the Remote desktop section, after `relay.data`.

**Depends on:** ### 1.

#### Add — after `relay.data`, the start path

```markdown
### `Relay.start`

- 🔷 Socket: the app socket. The first connection.
- 🔷 Direction: controller calls the server.
- 🔷 Argument `i`: `agent.id`.
- 🔷 The server writes notification `relay.start` on that agent's app connection. No arguments. That is not the desktop.
- 🔷 Reply: empty success. An unknown or disconnected agent is `unknown agent`. A caller that is not a controller is `controller only`.
- 🔷 When that agent has already joined, the reply is followed by notification `relay.ready` on this controller connection.

### `relay.start`

- 🔷 Notification on the agent's app connection. No arguments. The agent opens the second connection once Remote Desktop is on.

### `relay.ready`

- 🔷 Notification on the controller connection that called `Relay.start`. Argument `i`: `agent.id`. The stream has started. This is not the desktop bytes.

### `Relay.view`

- 🔷 Socket: the controller's second connection to the same port.
- 🔷 Argument `i`: `agent.id`.
- 🔷 Reply: empty success, then both sides are forwarded.
- 🔷 A view that arrives after a byte has already been forwarded gets no reply until `Relay.fresh`. The server writes notification `relay.cut` on that agent's app connection.

### `relay.cut`

- 🔷 Notification on the agent's app connection. No arguments. The agent closes its connection to Windows and opens a new one, then calls `Relay.fresh`.

### `Relay.fresh`

- 🔷 Socket: the agent stream connection. No arguments.
- 🔷 Reply: empty success. The held `Relay.view` is answered. Forwarding starts at the next byte, which is the first byte of the new Windows connection.
- 🚫 The server does not read Remote Desktop messages to find this cut.
```

### 9. `agent/Application.vala` — `stream_connection` and the two notifications

**Why:** The app connection stays the first socket. The desktop is another connection to the same host and port. `relay.start` and `relay.cut` are handled on Windows only.

**Where:** `stream_connection` is a new method after `open_connection`. The two cases go in `notification`, immediately before `default:`.

**Depends on:** ### 8.

#### Add — after `open_connection`, a second socket that is not stored

```vala
		/**
		 * Open another connection to the same server.
		 *
		 * {@link connection} stays the app session. This socket
		 * is the desktop stream. The certificate files are the
		 * ones {@link open_connection} uses.
		 *
		 * @return the stream, or null when the server file or the handshake fails
		 */
		internal OLLMrpc.Transport.TlsClient? stream_connection()
		{
#if LINUX
			var dir = Argus.AGENT_DATA_DIR;
#else
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
#endif
			var text = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "server"), out text);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
			}
			text = text.strip();
			var mark = text.last_index_of(":");
			if (text == "" || mark < 1) {
				return null;
			}
			var host = text.substring(0, mark);
			var port = int.parse(text.substring(mark + 1));
			if (port <= 0 || port > 65535) {
				return null;
			}
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
			var opened = new OLLMrpc.Transport.TlsClient(host, (uint16) port) {
				accept_any = true,
				tls_certificate = tls_files.certificate
			};
			opened.timeout = 5;
			try {
				opened.open();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
			}
			return opened;
		}
```

#### Add — in `notification`, immediately before `default:`

```vala
				case "relay.start":
#if WINDOWS
					if (Service.current != null) {
						Service.current.relay_start();
					}
#endif
					return;
				case "relay.cut":
#if WINDOWS
					if (Service.current == null) {
						return;
					}
					if (Service.current.tunnel == null) {
						Service.current.relay_start();
						return;
					}
					Service.current.tunnel.reopen();
#endif
					return;
```

### 10. `agent/Win32/Service.vala` — start once Remote Desktop is on

**Why:** `relay.start` before `desktop()` waits. `relay.cut` closes Windows and dials it again. The service object has to be visible to `Application.notification`.

**Where:** `current` becomes `internal`. `desktop_on`, `start_asked`, and `tunnel` are new fields next to `ticks`. `tunnel` is `internal` because the cut notification uses it. `desktop()` sets `desktop_on` only after TermService is running. `relay_start` is the new method after `desktop`.

**Depends on:** ### 9 and ### 11.

#### Remove

```vala
		private static Service current;
```

#### Replace with

```vala
		internal static Service current;
```

#### Add — after `ticks`, the desktop gate and the one tunnel

```vala
		private bool desktop_on = false;
		private bool start_asked = false;
		internal Argus.Agent.Rdp.Tunnel? tunnel;
```

#### Remove

```vala
			if (!Win32.StartServiceW(svc, 0, null) &&
				Win32.GetLastError() != Win32.ERROR_SERVICE_ALREADY_RUNNING) {
				GLib.warning("remote desktop service start %u", Win32.GetLastError());
			}
			Win32.CloseServiceHandle(svc);
			Win32.CloseServiceHandle(scm);
		}
```

#### Replace with

```vala
			var started = Win32.StartServiceW(svc, 0, null) ||
				Win32.GetLastError() == Win32.ERROR_SERVICE_ALREADY_RUNNING;
			if (!started) {
				GLib.warning("remote desktop service start %u", Win32.GetLastError());
			}
			Win32.CloseServiceHandle(svc);
			Win32.CloseServiceHandle(scm);
			if (!started) {
				return;
			}
			this.desktop_on = true;
			if (this.start_asked) {
				this.relay_start();
			}
		}
```

#### Add — after `desktop`, open the tunnel

```vala
		/**
		 * Open the desktop stream once Remote Desktop is on.
		 *
		 * A start that arrives earlier waits for {@link desktop}.
		 * A tunnel that is already open is left as it is.
		 */
		internal void relay_start()
		{
			if (!this.desktop_on) {
				this.start_asked = true;
				return;
			}
			this.start_asked = false;
			if (this.tunnel != null) {
				return;
			}
			var rpc = this.application.stream_connection();
			if (rpc == null) {
				return;
			}
			this.tunnel = new Argus.Agent.Rdp.Tunnel();
			try {
				this.tunnel.open_windows(rpc);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.tunnel = null;
			}
		}
```

### 11. `agent/Rdp/Tunnel.vala` — `open_windows`, `handle_stream`, and `reopen`

**Why:** The product dials `127.0.0.1:3389` and the real server. `run` stays the test path and still exits the process. This path does not. The desktop thread is the `while`. `handle_stream` is one read.

**Where:** new fields and methods after `carry`.

**Depends on:** ### 9.

#### Add — after `carry`, the Windows stream

`dial` is a field because `open_windows` returns while the read thread still uses it. `buf` is a property. The desktop thread allocates it. `reopen` closes the Windows socket. `handle_stream` discards that read, dials again, and calls `Relay.fresh` before the thread reads another byte.

```vala
		private GLib.SocketClient dial;
		private uint8[] buf { get; set; }
		public GLib.SocketConnection? plain;
		public OLLMrpc.Transport.TlsClient? rpc;
		public bool again;

		/**
		 * Dial Windows on loopback and join the server as ''agent''.
		 *
		 * The app connection is not this socket. ''Relay.write''
		 * carries bytes read from port 3389. ''relay.data'' is
		 * written back to that port.
		 *
		 * @param rpc the agent's second connection
		 */
		public void open_windows(OLLMrpc.Transport.TlsClient rpc) throws GLib.Error
		{
			this.dial = new GLib.SocketClient();
			this.dial.timeout = 10;
			this.plain = this.dial.connect_to_host("127.0.0.1", 3389);
			try {
				this.plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				GLib.warning("nodelay: %s", e.message);
			}
			this.rpc = rpc;
			this.rpc.notification.connect((notif) => {
				if (notif.method != "relay.data" || notif.args.size < 1 || this.plain == null) {
					return;
				}
				var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
				unowned uint8[] data = blob.get_data();
				if (data == null) {
					return;
				}
				size_t off = 0;
				while (off < data.length) {
					try {
						off += this.plain.output_stream.write(data[off:data.length]);
					} catch (GLib.Error e) {
						GLib.warning("desktop write: %s", e.message);
						return;
					}
				}
			});
			var joined = this.rpc.call(new OLLMrpc.Request() {
				method = "Relay.join",
				args = OLLMrpc.args("s", "agent")
			});
			if (joined.error != null) {
				GLib.warning("join: %s", joined.error.message);
				return;
			}
			this.rpc.watch();
			new GLib.Thread<int>("desktop", () => {
				this.buf = new uint8[16384];
				while (this.handle_stream()) {
				}
				return 0;
			});
		}

		/**
		 * Read one chunk from Windows and write it to the server.
		 *
		 * A cut dials port 3389 again and calls ''Relay.fresh''.
		 * That chunk is not copied.
		 *
		 * @return true when the desktop thread should read again
		 */
		private bool handle_stream()
		{
			ssize_t n = 0;
			try {
				n = this.plain.input_stream.read(this.buf);
			} catch (GLib.Error e) {
				if (!this.again) {
					GLib.warning("desktop read: %s", e.message);
					return false;
				}
			}
			if (this.again) {
				this.again = false;
				try {
					this.plain = this.dial.connect_to_host("127.0.0.1", 3389);
				} catch (GLib.Error e) {
					GLib.warning("desktop: %s", e.message);
					return false;
				}
				try {
					var mark = this.rpc.call(new OLLMrpc.Request() {
						method = "Relay.fresh"
					});
					if (mark.error != null) {
						GLib.warning("fresh: %s", mark.error.message);
						return false;
					}
				} catch (GLib.Error e) {
					GLib.warning("fresh: %s", e.message);
					return false;
				}
				return true;
			}
			if (n <= 0) {
				return false;
			}
			var chunk = new uint8[n];
			GLib.Memory.copy((uint8[]) chunk, this.buf, n);
			var held = GLib.Value(typeof(GLib.Bytes));
			held.set_boxed(new GLib.Bytes(chunk));
			var request = new OLLMrpc.Request() {
				method = "Relay.write"
			};
			request.args.add(held);
			try {
				var response = this.rpc.call(request);
				if (response.error != null) {
					GLib.warning("desktop write: %s", response.error.message);
					return false;
				}
			} catch (GLib.Error e) {
				GLib.warning("desktop call: %s", e.message);
				return false;
			}
			return true;
		}

		/**
		 * Close the Windows socket so the read dials a new one.
		 */
		public void reopen()
		{
			this.again = true;
			if (this.plain == null) {
				return;
			}
			try {
				this.plain.close();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}
```

### 12. `agent/meson.build` and `docs/meson.build` — compile the tunnel into the Windows agent

**Why:** `Tunnel.vala` is only in the test binary today.

**Where:** the Windows `sources += files(` list in `agent/meson.build`, and the agent source list in `docs/meson.build`.

**Depends on:** ### 11.

#### Add — `agent/meson.build`, in the Windows `sources += files(`, after `Win32/main.vala`

The Windows agent compiles the tunnel. Linux does not.

```meson
		'Rdp/Tunnel.vala',
```

#### Add — `docs/meson.build`, after `../agent/Application.vala`

```meson
  '../agent/Rdp/Tunnel.vala',
```

### 13. `controller/store/MachineGeneral.vala` — `start_desktop`

**Why:** The hold starts the flow by this call. The store already has the app connection and the loaded agent. The button is Phase 5.

**Where:** a new method after `load_section`, before the class closing brace.

**Depends on:** ### 4.

#### Add — after `load_section`, the ask for this machine

No call when the page has not loaded a machine. `relay.ready` is the later notice that the stream is up.

```vala
		/**
		 * Ask the server to start this machine's desktop stream.
		 *
		 * Phase 5's screen button calls this on touch and hold.
		 * ''relay.ready'' is the later notice that the stream is up.
		 */
		public void start_desktop()
		{
			if (this.loaded_agent < 1) {
				return;
			}
			var agent_id = this.loaded_agent;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Relay.start",
				args = OLLMrpc.args("i", agent_id)
			}, (obj, res) => {
				try {
					this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
			});
		}
```

---

## Phase 5 — Viewer

- 🔷 FreeRDP is the viewer. It asks for the Windows password. No drive redirection.
- 🔷 Clipboard sharing can wait. It is not required to see and control the desktop.
- 🔷 Audio is not part of this bug.
- 🔷 The starter is on the General tab of one Windows machine. A button with a screen picture. Touch and hold starts the flow and switches this window to the RDP page, with that machine's tab selected. A second machine adds a tab.
- 🔷 A short press does not start it.
- 🔷 The button is shown only when that machine's `OsVersion.supports_rdp()` is true. Unknown and Home show nothing.
- 🔷 The RDP row sits under Assets on the left. It shows while a session tab exists, and it goes when the last tab is gone. `controller/TabList.vala` lists Assets above Distributables.
- 🔷 On Android the viewer is that same RDP page.
- 💩 ⏳ The button sits at the top of the General page, above the key-value list, on a bar that belongs to that page. Not in the window header. Not on the detail tab switcher.
- 🚫 A text button labeled Connect to desktop.
- 🚫 The starter on the machine list, or on Agents.
- ℹ️ A desktop inside the controller window links `libfreerdp-client` and paints into GTK. The localhost port from Phase 2 is the socket that viewer reads.
- 🚫 A separate viewer window.

```
web-03, General
+------------------------------------------------------------------+
| [ General | Users | Windows programs | Interfaces | Storage ]    |
+------------------------------------------------------------------+
|                                                          [screen]|
|  Computer                                                        |
|  hostname            web-03                                      |
|  operating system    Microsoft Windows 11 Pro                    |
+------------------------------------------------------------------+
 touch and hold [screen] starts the flow
```

```
+------------------+------------------------------------------------------+
| Argus RM         | web-03 - Argus RM                                    |
+------------------+------------------------------------------------------+
| Dashboard        |                                                      |
| Assets           |                                                      |
| RDP              |                                                      |
| Distributables   |              web-03 desktop                          |
| Tasks            |                                                      |
| Monitoring       |                                                      |
| Scripts          |                                                      |
| Repositories     |                                                      |
|                  |                                                      |
|                  +------------------------------------------------------+
|                  | [ web-03  x ] [ db-01  x ]                      [key]|
| Agents           |                                                      |
| Settings         |                                                      |
+------------------+------------------------------------------------------+
```

---

## Phase 6 — Session tabs

- 🔷 The page is the desktop of the selected tab. The bottom bar is the session tabs and a key button.
- 🔷 The selected tab is the live feed. The agent sends for that session and the server forwards it.
- 🔷 A tab that is not selected gets no live feed. The agent keeps that Windows session and drops the bytes.
- 🔷 Selecting a quiet tab starts its feed. The tab that was showing goes quiet.
- 🔷 The X on a tab disconnects that session and removes the tab. The agent lets go of that RDP session. The last X removes the RDP row.
- 🔷 The key button sends keys into the desktop that is showing.
- 🚫 A list of RDP connections.
- 🚫 A frame bar with Send keys, Close connection, and an X that leaves the desktop running. The window header stays the title.

---

## Phase 6.5 — Takeover edges

- ℹ️ The stream proposal is Phase 4. This phase does not repeat it.
- ⏳ 🔷 Force is off unless the operator turns it on.
- ⏳ 🔷 The tray names who from Argus has the screen, and offers Disconnect.
- ℹ️ While a connection is up the PC screen is locked. Signing in at the PC disconnects the remote side. Windows does that. It does not say the Argus name.

---

## Phase 7 — Linux desktops

- 💩 ⏳ After Windows works. GNOME Remote Desktop and xrdp speak this protocol, so the same stream could reach them. Nothing in Phases 2–6 turns a Linux service on.

---

## Attempts / changelog

- ✔️ 2026-11-17: First probe was a C Gio TLS splice under `/tmp`. Rejected. The proof has to be Vala and has to use `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`.
- ✔️ 2026-11-17: The probe moved into the repo test tree. `server/vapi/freerdp.vapi` replaced the C desk. `server/tests/rdp-desk.c` is gone.
- ✔️ 2026-11-17: The desk, the tunnel, the relay, and the viewer are separate classes. `server/tests/rdp-relay.vala` only starts them and waits for `ACTIVATED`. `meson test -C build rdp-relay` passed.
- ✔️ 2026-11-17: "The Android controller does not get this button" was an inference. It is removed. Android shows the viewer in the same window, with navigation back to the main page.
- ✔️ 2026-11-17: The spec is split into phases. Each phase holds the requirements for that slice.
- ✔️ 2026-11-18: A second listen was an assumption, not a result. The design is another connection to the port already listening. Phase 5 is the parked desktop: the X stops streaming, Close connection drops the session, and **RDP connections** under Assets opens it again.
- ✔️ 2026-11-18: `App.ping` on the first connection kept replying after the second connection joined the stream. The test prints `ok app rpc during stream`.
- ✔️ 2026-11-18: The controller message starts the flow. The server notifies the agent, and that notification is what makes the agent open the second connection. This is Phase 4, before the viewer. The test does not do it.
- ✔️ 2026-11-18: `SslListen.by_id` is the connection for one agent id. `Command.dispatch`, `Agent.list`, `Agent.remove`, and the task list use it. `broadcast` still walks `connections` because that send goes to every connection.
- ✔️ 2026-11-18: Phase 2 fences now include the `join()` and `write()` bodies. `write()` in that fence does not use a ternary. The fences are not applied.
- ✔️ 2026-11-18: Phase 2 fences are applied. `Application.command_line` calls `Rdp.Relay.rpc_register()`. `Relay.join` and `Relay.write` are in `docs/rpc-commands.md`. `listen()` is still only the test.
- ✔️ 2026-11-18: Phase 2 fences are removed from this bug. Phase 3 proposes `OsVersion.supports_rdp()`. Unknown and Home are not offered. A client edition has no supported second session. The service is not changed.
- ✔️ 2026-11-18: Connect when nobody is logged in, or when the screen is locked or idle, as that same user. If someone is at the PC, the tray asks first. Force is off unless the operator turns it on. A different account logs them off.
- ✔️ 2026-11-18: The tray names who has the screen and can disconnect. The person at the locked PC gets the screen back by signing in. Windows does that itself.
- ✔️ 2026-11-18: `OsVersion.supports_rdp()` is in. After startup the Windows agent turns Remote Desktop on only when that is true, and leaves the password prompt on. Home and an unknown name do nothing. The button and the tray ask are not built.
- ✔️ 2026-11-18: An active Windows session means someone is logged in. The tray asks before Remote Desktop is turned on. Allow turns it on. No leaves it off. Nobody logged in skips the question. Force, Disconnect, and the connection are not built. Lock versus a person at the keyboard is not detected.
- ✔️ 2026-11-18: The tray allows Remote Desktop without asking when the keyboard and mouse have been idle for half an hour. The service cannot see that time.
- ✔️ 2026-11-18: When the agent streams, the server tells the controller and drops the bytes until the controller connects. A late controller gets a new connection from the first byte. The server does not parse Remote Desktop.
- ✔️ 2026-11-18: The tray ask is a balloon, the same call Snappr uses. A click allows Remote Desktop. Ignoring the balloon leaves it off.
- 🔷 2026-11-18: Phase 4 rules are signed off. The stream is not built. Building it, Force, and the Disconnect notice are Phase 6.5.
- ✔️ 2026-11-18: Those rules had been marked ✅. ✅ is work verified on a machine. The stream is not built, so the rules stay 🔷. The viewer is one RDP page under Assets. Session tabs sit on the bottom bar. The selected tab is the live feed. The X on a tab disconnects it.
- 🔷 2026-11-18: The starter is a screen button on the General tab of a Windows machine. Touch and hold starts the flow. A short press does not.
- 🔷 2026-11-18: Phase 4's stream proposal is in this bug. `Relay.start` asks the agent. The agent dials Windows on `127.0.0.1:3389` once Remote Desktop is on. Bytes are dropped until `Relay.view`. A late view waits for `Relay.fresh` after `relay.cut`. The screen button is still Phase 5.
- 🔷 2026-11-18: The desktop thread is the `while`. `Tunnel.handle_stream` reads one chunk. `buf` is a property, allocated in that thread. `MachineGeneral.start_desktop` is the controller ask.
- ✔️ 2026-11-18: Phase 4 is in the tree. `Relay.start` asks the agent. The Windows agent dials `127.0.0.1:3389` once Remote Desktop is on. The screen button is still Phase 5.
- ✔️ 2026-11-18: The relay and the tunnel have one body. A connection that is not a server connection stays the single test pair. The service opens the second connection and passes it to the tunnel.
- ✔️ 2026-11-18: `Seat` is its own class. It remembers the ask, answers `relay.ready`, attaches a view, holds a late view, releases that view, and forwards one chunk. `Relay` still checks the controller and finds the agent connection.
- ✔️ 2026-11-18: `relay.cut` with no tunnel opens the stream. An open tunnel is closed so the read dials Windows again. That sits in the notification. `Service.tunnel` is visible to it.

## Next

- ⏳ 🔷 Phase 5 is the viewer: the screen button on General, and the RDP page. Phase 6 is the session tabs.
- ⏳ 🔷 Phase 6.5 is Force and the tray notice that names who has the screen. The stream proposal is Phase 4.
- ⏳ 💩 The proof listen is still `Relay.listen`. Phase 2 does not move it into `SslListen`.

## LLM notes

- 🚫 Do not patch `termsrv.dll` to add a session, or to unlock Remote Desktop on Windows Home.
- 🚫 Do not turn Network Level Authentication off.
- 🚫 Do not put the desktop bytes on `agent.run` or the command log files.
- 🚫 Do not switch `Application.connection` to raw bytes. The desktop is a second connection to the same port.
- 🚫 Do not add a listener, and do not open another port.
- 🚫 Do not add drive redirection.
- 🚫 Do not put the button in the window header bar.
- 🚫 Do not start the flow from a short press, or from a button labeled Connect to desktop.
- 🚫 Do not put the starter on the machine list or on Agents.
- 🚫 Do not hide the button on Android.
- 🚫 Do not open the viewer in another window.
- 🚫 Do not add an RDP connections list.
