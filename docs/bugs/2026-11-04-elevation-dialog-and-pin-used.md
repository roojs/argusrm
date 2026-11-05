# Standard-user elevation dialog, hide PIN, stop controller when used

**Status:** ✔️ applied in tree; await device verify

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala must follow `docs/coding-standards.md`.

ℹ️ Related: `docs/plans/2.1-registration-flow.md`, `docs/plans/2.1.1-linux-startup-polkit.md`, `docs/plans/3.0-server.md` Phase 2.

---

## Problem

- 🔷 A desktop `argus-agent` running as a standard user must show a dialog first:
  - Heading `This application needs to run as admin`.
  - Body `You will be prompted to escalate privileges.`
  - One button `OK`.
  - Only after OK does the Polkit popup appear.
  - Then hide that dialog and close the unprivileged process.
- 🔷 After that login, if the machine is already registered, do not exit silently.
  - Show that the agent is running.
  - Buttons `Close` and `Restart`.
  - `Close` quits.
  - `Restart` restarts the background service, then quits.
- 🔷 After the correct PIN is accepted:
  - The PIN number disappears.
  - Hide the PIN input and the `Enter registration PIN` title.
  - The registration window can then show status and close as it does now.
- 🔷 `argus-controller` must get a response that the PIN has been used, and that must stop it.
- 🔷 There is a transport / live-handle problem after osquery is downloaded.
  - Check whether the RPC layer is constructed with `live_handles = true`.

---

## Evidence

- ℹ️ Unprivileged desktop `argus-agent` calls `pkexec` at once.
  - `agent/linux/Application.vala` `command_line`.
  - No GTK dialog.
  - No `Gtk.init`.
  - The process returns `0` as soon as `pkexec` is spawned.
- ℹ️ Root desktop registration already uses `Adw` / `RegisterWindow`.
  - Same file, `registration`.
  - Already registered prints `Argus agent is already registered.` and returns `0`.
  - No dialog. No restart.
  - `agent/Application.vala` already shows `Adw.AlertDialog` + `OK` for “already registered” on Android.
- ℹ️ `RegisterWindow.registration_succeeded` updates `listen_label` and starts the 10s close.
  - It does not hide `pin_box`.
  - `pin_box` holds the title and the entry.
  - The typed number stays on screen.
- ℹ️ `ClientCert.pair` replies `ok` as soon as the window is opened.
  - `server/Agent.vala` `pair`.
  - The controller prints the PIN only after that reply.
  - It then waits 60s and sends an empty PIN.
  - It never waits for the PIN to be consumed.
- ℹ️ When registration succeeds, the server already broadcasts `event.pair` / `done`.
  - `request_registration` and the TLS `pair` path.
  - The controller never connects `rpc.notification`.
- ℹ️ Unix listen already sets live handles.
  - `server/Application.vala` `SocketListen` `{ live_handles = true }`.
  - `server/SslListen.vala` each `SslConnection` `{ live_handles = true }`.
- ℹ️ Controller client does not.
  - `controller/Application.vala` `new OLLMrpc.Client(...)`.
  - `OLLMrpc.Client.live_handles` defaults to `false`.
- ℹ️ Agent app socket is a one-shot `TlsClient`.
  - `agent/Application.vala` `open_link`.
  - No `live_handles`.
  - `agent/Listen.vala` `start` does not read notifications.
  - Comment: `TlsClient.call` only returns a `Response`.
- ℹ️ Server startup fetches osquery before the sockets bind.
  - `server/Application.vala` `Initialize.fetch_osquery`.
  - That can succeed while the controller / agent live path is still wrong.

---

## Root cause

- ✔️ Standard-user startup has no elevation dialog. It jumps straight to `pkexec`.
- ✔️ An already-registered elevated run prints one line and exits.
  - `setup()` may have started the service.
  - The user never sees that it is running, and cannot restart it.
- ✔️ Success leaves `pin_box` visible, so the number and title stay up.
- ✔️ `pair` answers “window open”, not “PIN used”.
  - The controller’s wait is a local 60s timer.
  - `event.pair` / `done` is sent, and nobody on the controller reads it.
- 💩 The live-handle gap is the controller `Client` (and the agent `TlsClient`), not the server Unix listen.
  - Delayed `request.reply` on the held `pair` call does not need live handles.
  - Notifications and live objects on that client do.
  - 🔷 Still turn `live_handles` on for the controller client so that path can stay live.

---

## Proposed fix

- 🔷 Unprivileged desktop: `Argus.Shared.Notice` heading `This application needs to run as admin`, body `You will be prompted to escalate privileges.`, button `OK`.
  - Same 480×280 layout as `RegisterWindow`.
  - OK starts `pkexec` with the session display variables and waits for that process.
  - The unprivileged window closes. It does not quit until `pkexec` exits.
- 🔷 Already-registered desktop: `Argus.Shared.Notice` heading `Argus agent is running`, buttons `Close` and `Restart`.
  - Headless root keeps the print line.
- 🚫 No `Reset` button.
- 🔷 `registration_succeeded`: hide `pin_box` so the title and the number go away.
- 🔷 Hold the controller’s `ClientCert.pair` request until the PIN is used, closed, or the controller drops.
  - Reply `msg = "used"` when `request_registration` consumes the PIN.
  - Reply `msg = "ok"` when the empty PIN closes the window.
- 🔷 Controller: set `live_handles = true`.
  - Print the PIN as soon as the hello connects (it already has the number).
  - Start `pair` and the 60s empty-PIN timer together.
  - Quit when `pair` returns `used` or the empty-PIN close finishes.
- 🚫 Do not treat `event.pair` as the controller stop.
  - The user asked for a **response** on the pair call.
- 🚫 Do not add a helper for the pending pair reply.
- 💩 Agent `TlsClient` live listen stays out of this log.
  - `Listen.start` is still a stub.
- ℹ️ Osquery rows not reaching the server is a different bug.
  - `docs/bugs/done/2026-11-04-FIXED-osquery-not-sent.md`.
  - Registration writes `AGENT_DATA_DIR`. The service reads the root user data dir.

### `agent/linux/Application.vala` — `command_line`: elevation dialog before Polkit

**Why:** The unprivileged process must explain the switch and wait for OK before `pkexec`.

**Where:** desktop, non-root path, after the `pkexec` / executable lookups, replacing the immediate spawn and `return 0`.

**Depends on:** none.

#### Remove

```vala
			try {
				new GLib.Subprocess.newv({pkexec, executable}, GLib.SubprocessFlags.NONE);
			} catch (GLib.Error e) {
				command_line.printerr("Could not request administrator access: %s\n", e.message);
				return 1;
			}
			return 0;
```

#### Replace with

```vala
			Gtk.init();
			var alert = new Adw.AlertDialog(
				"This application needs to run as admin",
				"You will be prompted to escalate privileges.");
			alert.add_response("ok", "OK");
			alert.response.connect((response) => {
				if (response == "ok") {
					try {
						new GLib.Subprocess.newv(
							{pkexec, executable}, GLib.SubprocessFlags.NONE);
					} catch (GLib.Error e) {
						command_line.printerr(
							"Could not request administrator access: %s\n",
							e.message);
					}
				}
				this.quit();
			});
			alert.present(null);
			this.hold();
			return 0;
```

### `agent/linux/Application.vala` — `registration`: already-registered Close / Restart

**Why:** After Polkit, the user must see that the service is running and be able to restart it.

**Where:** `registration`, the `client.pem` exists branch.

**Depends on:** none.

#### Remove

```vala
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				command_line.print("Argus agent is already registered.\n");
				return 0;
			}
```

#### Replace with

```vala
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				var have_display = GLib.Environment.get_variable("DISPLAY");
				var have_wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				if ((have_display == null || have_display == "") &&
					(have_wayland == null || have_wayland == "")) {
					command_line.print("Argus agent is already registered.\n");
					return 0;
				}
				Gtk.init();
				var alert = new Adw.AlertDialog("Argus agent is running", "");
				alert.add_response("close", "Close");
				alert.add_response("restart", "Restart");
				alert.response.connect((response) => {
					if (response == "restart") {
						try {
							service.restart();
						} catch (GLib.Error e) {
							command_line.printerr("%s\n", e.message);
						}
					}
					this.quit();
				});
				alert.present(null);
				this.hold();
				return 0;
			}
```

### `shared/RegisterWindow.vala` — `registration_succeeded`: hide PIN title and entry

**Why:** The correct number must disappear. `pin_box` is the title and the entry.

**Where:** start of `registration_succeeded`, before `certificate_received`.

**Depends on:** none.

#### Add — hide `pin_box` as soon as registration succeeds

```vala
			this.pin_box.visible = false;
```

### `server/Agent.vala` — hold `pair` until the PIN is used

**Why:** The controller’s `ClientCert.pair` call is the response that the PIN was used.

**Where:** field on `Agent`. `pair` for the Unix-socket path. `request_registration` after `listen.pin = ""`.

**Depends on:** none.

#### Add — pending pair request next to the other `Agent` fields

```vala
		private OLLMrpc.Request? pending_pair = null;
```

#### Remove

```vala
			if (!(request.connection is SslConnection)) {
				listen.pin = pin;
				if (pin == "") {
					this.app.publish.stop();
					request.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
					return;
				}
```

#### Replace with

```vala
			if (!(request.connection is SslConnection)) {
				listen.pin = pin;
				if (pin == "") {
					this.app.publish.stop();
					if (this.pending_pair != null) {
						this.pending_pair.reply(new OLLMrpc.Response() {
							msg = "ok"
						});
						this.pending_pair = null;
					}
					request.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
					return;
				}
```

#### Remove

```vala
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				var owner = request.connection;
				GLib.Timeout.add(250, () => {
					if (listen.pin != pin) {
						return false;
					}
					if (owner.running) {
						return true;
					}
					listen.pin = "";
					this.app.publish.stop();
					GLib.debug(
						"registration closed after controller disconnected");
					return false;
				});
				return;
```

#### Replace with

```vala
				if (this.pending_pair != null) {
					this.pending_pair.reply(new OLLMrpc.Response() {
						msg = "ok"
					});
				}
				this.pending_pair = request;
				var owner = request.connection;
				GLib.Timeout.add(250, () => {
					if (listen.pin != pin) {
						return false;
					}
					if (owner.running) {
						return true;
					}
					listen.pin = "";
					this.app.publish.stop();
					if (this.pending_pair != null) {
						this.pending_pair.reply(new OLLMrpc.Response() {
							msg = "ok"
						});
						this.pending_pair = null;
					}
					GLib.debug(
						"registration closed after controller disconnected");
					return false;
				});
				return;
```

#### Add — after `listen.pin = ""` in `request_registration`, before packing the certificate reply

```vala
			if (this.pending_pair != null) {
				this.pending_pair.reply(new OLLMrpc.Response() {
					msg = "used"
				});
				this.pending_pair = null;
			}
```

### `controller/Application.vala` — `command_line`: live client, print PIN, stop on `used`

**Why:** The pair call now stays open until the PIN is used. The number is local, so print it after hello. The 60s empty PIN is only the unused-window close.

**Where:** `command_line` after `OLLMrpc.rpc_register()`, through `loop.run()`.

**Depends on:** `server/Agent.vala` held `pair`.

#### Remove

```vala
			var rpc = new OLLMrpc.Client("", "",
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock"));
			rpc.debug = false;
			var loop = new GLib.MainLoop();
			var code = 1;
			command_line.print("Connecting to the local Argus server...\n");
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				var opened = rpc.connect.end(res);
				if (!opened) {
					command_line.printerr("%s\n", rpc.connect_error);
					loop.quit();
					return;
				}
				rpc.call.begin(new OLLMrpc.Request() {
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				}, (obj, res) => {
					try {
						var response = rpc.call.end(res);
						if (response.error != null) {
							command_line.printerr("%s\n", response.error.message);
							loop.quit();
							return;
						}
					} catch (GLib.Error e) {
						command_line.printerr("%s\n", e.message);
						loop.quit();
						return;
					}
					command_line.print(
						"Registration PIN: %s\n" +
						"Registration is open for 60 seconds. Press Ctrl+C to close it early.\n",
						pin);
					GLib.Timeout.add_seconds(60, () => {
						rpc.call.begin(new OLLMrpc.Request() {
							method = "ClientCert.pair",
							args = OLLMrpc.args("s", "")
						}, (obj, res) => {
							try {
								rpc.call.end(res);
							} catch (GLib.Error e) {
								GLib.warning("%s", e.message);
							}
							code = 0;
							loop.quit();
						});
						return false;
					});
				});
			});
```

#### Replace with

```vala
			var rpc = new OLLMrpc.Client("", "",
				GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock")) {
				live_handles = true
			};
			rpc.debug = false;
			var loop = new GLib.MainLoop();
			var code = 1;
			command_line.print("Connecting to the local Argus server...\n");
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				var opened = rpc.connect.end(res);
				if (!opened) {
					command_line.printerr("%s\n", rpc.connect_error);
					loop.quit();
					return;
				}
				command_line.print(
					"Registration PIN: %s\n" +
					"Registration is open for 60 seconds. Press Ctrl+C to close it early.\n",
					pin);
				rpc.call.begin(new OLLMrpc.Request() {
					method = "ClientCert.pair",
					args = OLLMrpc.args("s", pin)
				}, (obj, res) => {
					try {
						var response = rpc.call.end(res);
						if (response.error != null) {
							command_line.printerr("%s\n", response.error.message);
							loop.quit();
							return;
						}
						if (response.msg == "used") {
							command_line.print("Registration PIN has been used.\n");
						}
					} catch (GLib.Error e) {
						command_line.printerr("%s\n", e.message);
						loop.quit();
						return;
					}
					code = 0;
					loop.quit();
				});
				GLib.Timeout.add_seconds(60, () => {
					rpc.call.begin(new OLLMrpc.Request() {
						method = "ClientCert.pair",
						args = OLLMrpc.args("s", "")
					}, (obj, res) => {
						try {
							rpc.call.end(res);
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
						}
					});
					return false;
				});
			});
```

---

## Attempts / changelog

- 🔷 Dialog copy is the admin heading plus the escalate-privileges body. Not `Switching to admin`.
- 🔷 Already-registered desktop shows `Argus agent is running` with `Close` and `Restart`.
- ✔️ Fences applied. `meson compile -C build` succeeded.
- 🔷 After Polkit the elevated process went silent. The parent quit as soon as `pkexec` started, and `pkexec` dropped the session display variables, so the root process treated itself as headless.
- ✔️ `Argus.Shared.Notice` is the standard 480×280 dialog. `pkexec` now keeps `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `XAUTHORITY`, and `DBUS_SESSION_BUS_ADDRESS`, and the parent waits for that process.
- 🔷 Desktop errors must not go to `printerr`. Show them on `Notice`. Headless and `--service` still print.

---

## Next

- 🔷 `✔️` Fences applied in `agent/linux/Application.vala`, `shared/RegisterWindow.vala`, `server/Agent.vala`, `controller/Application.vala`.
- 🔷 `⏳` Desktop: standard-user `argus-agent` shows the admin / escalate-privileges dialog / `OK`, then Polkit, then the root PIN window or the running dialog.
- 🔷 `⏳` Already registered: `Close` quits. `Restart` restarts the service, then quits.
- 🔷 `⏳` Correct PIN hides the input and the title. Controller prints that the PIN was used and exits.
- ℹ️ Osquery send is `docs/bugs/done/2026-11-04-FIXED-osquery-not-sent.md`.
