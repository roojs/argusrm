# Windows tray hangs on "Waiting for the Windows service…" after update

**Status:** ✅ fixed (`0.1.17`–`0.1.19`); verified on `snappr-win` (`OLLMrpc` + `TcpListen` over `127.0.0.1:4142`)

**Pointer:** `docs/bug-fix-process.md`. Prior Windows install bug: [2026-11-11-FIXED-windows-install.md](2026-11-11-FIXED-windows-install.md). Related design: [2.0-agent.md](../../plans/2.0-agent.md) (Phase 2.5).

---

## How the desktop and service talk

- ℹ️ `argus-agent.exe` (Session 0 `LocalSystem` service) and `argus-tray.exe` (desktop session tray UI) do **not** use `OLLMrpc` (`libocrpc`) to talk to each other.
- ℹ️ Instead, they use a custom plain-text protocol over a raw Win32 named pipe (`\\.\pipe\Argus.Register`):
  - `agent/Win32/register-pipe.c` creates `\\.\pipe\Argus.Register` with `PIPE_NOWAIT`, `PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE`, and **`nMaxInstances = 1`**.
  - `agent/Win32/Service.vala` (`tick()`) polls it once a second with raw `ConnectNamedPipe`, `PeekNamedPipe`, `ReadFile`, and `WriteFile`.
  - `agent/Win32/tray/Tray.vala` opens it with raw `CreateFileW` and polls `PeekNamedPipe` / `ReadFile` in `Tray.run()`.
  - Messages are ad-hoc text lines: `"tip <text>"` and `"<rpc_code>"` from the service; `"<pin>\n<host:port>"` from the tray.
- ℹ️ `OLLMchat/libocrpc` already has `OLLMrpc.Transport.TcpListen` (`127.0.0.1:<port>`) and `OLLMrpc.Client` (`tcp://127.0.0.1:<port>`, no TLS on loopback), though `Client.vala` and `Connection.vala` still call `GLib.IOChannel.unix_new(fd)` (needs `GLib.IOChannel.win32_socket(fd)` on `G_OS_WIN32` for Winsock handles).

---

## Problem

- 🔷 After installing an update on the Windows machine, the tray / registration window has repeatedly sat hanging with the spinner on **"Waiting for the Windows service…"**.
- 🔷 Replace the custom named-pipe protocol with `OLLMrpc` (`libocrpc`) over `OLLMrpc.Transport.TcpListen` on `127.0.0.1`.

---

## Evidence

- ✔️ **`RegisterWindow` shows "Waiting for the Windows service…" whenever `this.pipe == -1` at startup (`shared/RegisterWindow.vala:442`, `agent/Win32/tray/Tray.vala:209-233`, `609-619`, `699-728`):**
  - `Tray.present()` checks `GLib.Environment.get_user_data_dir()/argus/ollmrpc-ca.pem`. On Windows, the `LocalSystem` service stores certificates under `C:\Windows\System32\config\systemprofile\AppData\Local\argus\`, whereas `argus-tray.exe` runs in the signed-in user's profile (`C:\Users\<user>\AppData\Local\argus\`). `ollmrpc-ca.pem` is never in the user's directory, so `Tray.present()` does not return early unless `this.known` was already set from the pipe.
  - In `Tray.run()`, if `CreateFileW("\\\\.\\pipe\\Argus.Register", ...)` returns `-1` on the first attempt, the 6-tick wait (`if (!this.started && (intptr) this.pipe != -1 && !this.known && this.waits < 6)`) is skipped, `this.present()` runs immediately, and `RegisterWindow.show_add()` displays `"Waiting for the Windows service…"` with a spinner until `Tray.present()`'s 200 ms `GLib.Timeout` manages to open the pipe.
- ✔️ **The service delays creating `\\.\pipe\Argus.Register` until all blocking startup work finishes (`agent/Win32/Service.vala:142-143`, `agent/Application.vala:428-475`):**
  - `Service.service_main()` registers `GLib.Timeout.add_seconds(1, this.tick)` and then calls `this.application.run({ "argus-agent" })`.
  - On an updated (already registered) machine, `Application.command_line()` runs synchronously **before** the GLib main loop dispatches `this.tick()`:
    - `attach_connection()` -> TCP + TLS connect (5 s timeout).
    - `connection.call("RPC-Daemon.hello")` (up to 10 s timeout).
    - `new OSQuery.Initialize(this).start()` — runs synchronously on the main thread despite the docblock (`agent/OSQuery/Initialize.vala:64-73`), potentially downloading and installing `osquery`.
    - `this.osquery.send_startup()` — runs 6 synchronous `osqueryi --json` subprocesses and 6 synchronous `OSQuery.sync` calls (`agent/OSQuery/Execute.vala:155-169`).
  - Until `command_line()` finishes and `tick()` runs at least once, `\\.\pipe\Argus.Register` does not exist (`ERROR_FILE_NOT_FOUND` = 2).
- ✔️ **Single-instance `nMaxInstances = 1` pipe lockout on update/re-launch (`agent/Win32/register-pipe.c:28`, `packaging/windows/argusrm-agent.nsi:84-86`, `agent/Win32/Service.vala:389-478`, `agent/Win32/tray/Tray.vala`):**
  - `argus_create_registration_pipe()` allows only **1** pipe instance (`nMaxInstances = 1`).
  - `Tray.vala` has no single-instance check (`other_copy()` from Snappr was not ported).
  - The installer finishes with `Exec '"$INSTDIR\argus-tray.exe"'` (running under the installer's elevated token) right after `sc start argus-agent`, while `Service.tick()` also scans `EnumProcesses` every 5 seconds and spawns `argus-tray.exe` via `CreateProcessAsUserW` if not seen yet. If two `argus-tray.exe` instances exist (or a prior tray kept the handle), the second tray gets `ERROR_PIPE_BUSY` (231) indefinitely and sits on `"Waiting for the Windows service…"` forever.
- ✔️ **Main-loop stall in `Tray.run()` once the registration window is up (`agent/Win32/tray/Tray.vala:234-237`, `704-727`):**
  - When `this.window_up` is true, `Tray.run()` executes `GLib.MainContext.@default().iteration(true); continue;`.
  - There is no `GLib.IOChannel` / `GLib.Timeout` watch on `this.pipe` after `CreateFileW` succeeds (the 200 ms `GLib.Timeout` in `present()` returns `false` as soon as the pipe opens). If `this.pipe` is open when the window is visible, `PeekNamedPipe` at the top of `Tray.run()` only runs when an unrelated GTK event wakes `iteration(true)`.
- ✔️ **Already-registered updates start with `"Disconnected"` tip (`agent/Win32/Service.vala:214-221`, `agent/Application.vala:428-475`):**
  - `Application.command_line()` only sets `ARGUS_AGENT_TIP` on failure (`line 465`), leaving `this.tip == ""` on a healthy update. When the pipe connects, `Service.tick()` hits `if (became && this.tip == "" && GLib.FileUtils.test(cert, ...))` and sends `"tip Disconnected"` until the download-socket probe fires (`ticks % 120 == 1`), so `this.known` stays `false` and the tray opens `RegisterWindow` even on a connected machine.

---

## Root cause

- ✔️ The Windows tray hangs on **"Waiting for the Windows service…"** because desktop–service IPC uses a bespoke, single-instance (`nMaxInstances = 1`), polled Win32 named pipe (`\\.\pipe\Argus.Register`) combined with three bugs:
  1. `Service.tick()` (which creates the pipe) cannot execute until `Application.command_line()` finishes synchronous TLS connect, `hello`, `OSQuery.Initialize`, and `OSQuery.send_startup()`, leaving the pipe absent during startup after an update.
  2. `nMaxInstances = 1` plus missing single-instance enforcement in `Tray` (and concurrent launch from `.onInstSuccess` and `Service.tick()`) lets a second `argus-tray.exe` get `ERROR_PIPE_BUSY` indefinitely.
  3. `Tray` has no unified event-driven RPC channel (so it guesses registered state from the wrong user profile's `ollmrpc-ca.pem`, stalls `PeekNamedPipe` inside blocking `GLib.MainContext.iteration(true)`, and receives `"tip Disconnected"` on healthy restarts).

---

## Proposed fix

- 🔷 Replace `\\.\pipe\Argus.Register` and the custom pipe loop with `OLLMrpc.Transport.TcpListen` (`127.0.0.1:4142`) in `agent/Win32/Service.vala` and `OLLMrpc.Client` (`tcp://127.0.0.1:4142`) in `agent/Win32/tray/Tray.vala`.
- 🔷 Expose `AgentService.hello`, `AgentService.status`, and `AgentService.register` via `OLLMrpc.Request.add_class` on `Argus.Agent.Win32.Service`, and broadcast `agent.status` notifications when registration or management-server connection state changes.
- 🔷 Defer the Windows existing-certificate startup check (`attach_connection`, `RPC-Daemon.hello`, `OSQuery.Initialize`, `osquery.send_startup`) out of synchronous `Application.command_line()` onto `GLib.Idle.add` (and run `OSQuery.Initialize` on a `GLib.Thread`), so `TcpListen` accepts `argus-tray.exe` connections immediately after service start.
- 🔷 Port Snappr's `other_copy()` into `Tray` and drain `GLib.MainContext.@default()` alongside the Win32 message loop.
- 💩 Prerequisite in `OLLMchat` (`libocrpc`): use `GLib.IOChannel.win32_socket(fd)` under `#if G_OS_WIN32` in `libocrpc/Transport/Connection.vala` and `libocrpc/Client.vala` so `TcpListen` and `Client` work with Winsock sockets on Windows.
- 💩 Loopback TCP port choice: `4142` (adjacent to `libocrpc`'s `4141` default) used at both `TcpListen` and `Client` sites, with `AgentService.register` refusing once `ollmrpc-ca.pem` exists.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding lines before applying.

### 1. `OLLMchat` (`libocrpc`) — Winsock `IOChannel` under `#if G_OS_WIN32`

**Why:** `libocrpc` passes `socket.get_fd()` to `GLib.IOChannel.unix_new(fd)`, which fails on Windows Winsock `SOCKET` handles; `GLib.IOChannel.win32_socket(fd)` is required on `G_OS_WIN32`.

**Where:** `OLLMchat/libocrpc/Transport/Connection.vala` (`start`) and `OLLMchat/libocrpc/Client.vala` (`connect`).

**Depends on:** none (see [OLLMchat windows-tcp-iochannel](../../../OLLMchat/docs/bugs/2026-11-13-windows-tcp-iochannel.md); rebuilt/packaged in `OLLMchat` release consumed by `.github/workflows/x-windows.yml`).

#### `libocrpc/Transport/Connection.vala` — Remove

```vala
				var fd = this.stream.get_socket().get_fd();
				this.channel = new GLib.IOChannel.unix_new(fd);
```

#### `libocrpc/Transport/Connection.vala` — Replace with

```vala
				var fd = this.stream.get_socket().get_fd();
#if G_OS_WIN32
				this.channel = new GLib.IOChannel.win32_socket(fd);
#else
				this.channel = new GLib.IOChannel.unix_new(fd);
#endif
```

#### `libocrpc/Client.vala` — Remove

```vala
			var fd = this.socket.get_socket().get_fd();
			this.read_channel = new GLib.IOChannel.unix_new(fd);
```

#### `libocrpc/Client.vala` — Replace with

```vala
			var fd = this.socket.get_socket().get_fd();
#if G_OS_WIN32
			this.read_channel = new GLib.IOChannel.win32_socket(fd);
#else
			this.read_channel = new GLib.IOChannel.unix_new(fd);
#endif
```

### 2. `agent/meson.build`, `agent/Win32/win32.h`, `agent/Win32/win32.vapi`, and `agent/Win32/register-pipe.c` — export FFI symbols and drop the registration pipe

**Why:** `OLLMrpc.Request.add_class` resolves `Service` methods via `GLib.Module.open(null)` (`GetProcAddress` on the Windows PE executable), which requires `export_dynamic: true` in `agent/meson.build`. `argus_create_registration_pipe` is replaced by `TcpListen`, leaving only `argus_active_session` in the C helper.

**Where:** `agent/meson.build` (`executable(installed_name, ...)`), `agent/Win32/win32.h`, `agent/Win32/win32.vapi`, and `agent/Win32/register-pipe.c`.

**Depends on:** none.

#### `agent/meson.build` — Remove

```meson
	executable(
		installed_name,
		sources,
		dependencies: deps,
		vala_args: vala_args,
		c_args: c_args,
		install: true,
	)
```

#### `agent/meson.build` — Replace with

```meson
	executable(
		installed_name,
		sources,
		dependencies: deps,
		export_dynamic: true,
		vala_args: vala_args,
		c_args: c_args,
		install: true,
	)
```

#### `agent/Win32/win32.h` — Remove

```c
HANDLE argus_create_registration_pipe(void);
DWORD argus_active_session(void);
```

#### `agent/Win32/win32.h` — Replace with

```c
DWORD argus_active_session(void);
```

#### `agent/Win32/win32.vapi` — Remove

```vala
	[CCode (cname = "argus_create_registration_pipe", cheader_filename = "win32.h")]
	public void* create_registration_pipe ();
	[CCode (cheader_filename = "win32.h")]
	public uint32 argus_active_session ();
```

#### `agent/Win32/win32.vapi` — Replace with

```vala
	[CCode (cheader_filename = "win32.h")]
	public uint32 argus_active_session ();
```

#### `agent/Win32/win32.vapi` — Add `GetCurrentProcessId` after `OpenProcess` for `Tray.other_copy()`

```vala
	[CCode (cname = "GetCurrentProcessId", cheader_filename = "win32.h")]
	public uint32 GetCurrentProcessId ();
```

#### `agent/Win32/register-pipe.c` — Remove

```c
#include "win32.h"
#include <sddl.h>

HANDLE
argus_create_registration_pipe(void)
{
	PSECURITY_DESCRIPTOR descriptor = NULL;
	SECURITY_ATTRIBUTES security = {
		sizeof(SECURITY_ATTRIBUTES),
		NULL,
		FALSE
	};
	HANDLE pipe;

	if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
		L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)",
		SDDL_REVISION_1,
		&descriptor,
		NULL)) {
		return INVALID_HANDLE_VALUE;
	}
	security.lpSecurityDescriptor = descriptor;
	pipe = CreateNamedPipeW(
		L"\\\\.\\pipe\\Argus.Register",
		PIPE_ACCESS_DUPLEX,
		PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT |
			PIPE_REJECT_REMOTE_CLIENTS,
		1,
		4096,
		4096,
		0,
		&security);
	LocalFree(descriptor);
	return pipe;
}
```

#### `agent/Win32/register-pipe.c` — Replace with

```c
#include "win32.h"
```

### 3. `agent/Application.vala` — `state_changed` signal and non-blocking Windows startup

**Why:** running `attach_connection()`, `RPC-Daemon.hello`, `OSQuery.Initialize`, and `osquery.send_startup()` synchronously inside `command_line()` blocks the GLib main loop so `TcpListen` cannot accept tray connections after an update. Deferring Windows startup via `GLib.Idle.add` (with `OSQuery.Initialize` in a `GLib.Thread`) and emitting `state_changed` lets `Service` serve status immediately and push live updates.

**Where:** `agent/Application.vala` (`connection_down`, `attach_connection()`, `command_line()`, and `notification()`).

**Depends on:** none.

##### Part 1 — `state_changed` signal and `attach_connection()`

#### Add — after `connection_down`, signal service when registration or connection state changes

```vala
		/**
		 * Emitted when the stored registration or server connection state changes.
		 */
		internal signal void state_changed();

		/**
		 * Last startup or rejection notice for the Windows tray.
		 */
		internal string status_notice = "";
```

#### Remove

```vala
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

#### Replace with

```vala
				if (opened != null) {
					opened.closed.connect(() => {
						Application.connection_down = true;
						this.state_changed();
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
					this.state_changed();
					return;
				}
			}
			if (opened == null) {
				Application.connection_down = true;
				this.connecting = false;
				this.state_changed();
				return;
			}
			opened.watch();
			Application.connection_down = false;
			GLib.debug("watching the server connection");
			this.connecting = false;
			this.state_changed();
```

##### Part 2 — defer Windows `#else` startup check out of `command_line()`

#### Remove

```vala
#else
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.attach_connection();
				var rejected = this.connection == null;
				var notice = "Could not reach the management server.";
				if (this.connection != null) {
					try {
						var response = this.connection.call(new OLLMrpc.Request() {
							method = "RPC-Daemon.hello",
							args = OLLMrpc.args("is", 1, "argus-agent")
						});
						if (response.error != null) {
							rejected = true;
							if (response.error.code ==
								(int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED) {
								notice = "Not registered with the management server.";
							}
						}
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						rejected = true;
					}
				}
				if (rejected) {
					if (this.connection_check_id != 0) {
						GLib.Source.remove(this.connection_check_id);
						this.connection_check_id = 0;
					}
					this.connection = null;
					Application.connection_down = true;
					var dir = GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus");
					GLib.FileUtils.remove(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"));
					GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
					GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
					GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
					GLib.Environment.set_variable("ARGUS_AGENT_TIP", notice, true);
					GLib.debug("registration cleared");
				}
				if (!rejected && this.connection != null) {
					new OSQuery.Initialize(this).start();
					this.osquery.send_startup();
					this.monitor = new PackageMonitor(this);
					this.monitor.start();
				}
			}
#endif
```

#### Replace with

```vala
#else
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				GLib.Idle.add(() => {
					this.attach_connection();
					var rejected = this.connection == null;
					var notice = "Could not reach the management server.";
					if (this.connection != null) {
						try {
							var response = this.connection.call(new OLLMrpc.Request() {
								method = "RPC-Daemon.hello",
								args = OLLMrpc.args("is", 1, "argus-agent")
							});
							if (response.error != null) {
								rejected = true;
								if (response.error.code ==
									(int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED) {
									notice = "Not registered with the management server.";
								}
							}
						} catch (GLib.Error e) {
							GLib.warning("%s", e.message);
							rejected = true;
						}
					}
					if (rejected) {
						if (this.connection_check_id != 0) {
							GLib.Source.remove(this.connection_check_id);
							this.connection_check_id = 0;
						}
						this.connection = null;
						Application.connection_down = true;
						var dir = GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "argus");
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"));
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
						GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
						this.status_notice = notice;
						GLib.debug("registration cleared");
						this.state_changed();
						return false;
					}
					this.status_notice = "";
					this.state_changed();
					new GLib.Thread<int>("osquery-init", () => {
						var code = new OSQuery.Initialize(this).run();
						GLib.Idle.add(() => {
							if (code == 0 && this.connection != null) {
								this.osquery.send_startup();
								this.monitor = new PackageMonitor(this);
								this.monitor.start();
							}
							return false;
						});
						return 0;
					});
					return false;
				});
			}
#endif
```

##### Part 3 — `agent.removed` emits `state_changed()`

#### Remove

```vala
					GLib.FileUtils.remove(removed);
					GLib.debug("registration removed");
					return;
```

#### Replace with

```vala
					GLib.FileUtils.remove(removed);
					GLib.debug("registration removed");
					this.state_changed();
					return;
```

### 4. `agent/Win32/Service.vala` — `TcpListen` + `AgentService` RPC and `agent.status` notifications

**Why:** replace the single-instance polled `\\.\pipe\Argus.Register` pipe with `OLLMrpc.Transport.TcpListen` (`127.0.0.1:4142`) and `AgentService` RPC handlers (`hello`, `status`, `register`), broadcasting `agent.status` whenever `Application.state_changed` or registration fires.

**Where:** `agent/Win32/Service.vala` (fields, `rpc_register`, `hello`, `status`, `register`, `service_main`, `tick`).

**Depends on:** ### 1, ### 2, ### 3.

##### Part 1 — fields, `rpc_register`, and `AgentService` RPC handlers

#### Remove

```vala
		private Argus.Agent.Application application;
		private void* pipe = (void*) (intptr) (-1);
		private bool pipe_up = false;
		private bool pipe_warned = false;
		private string number = "";
		private string directed = "";
		private string tip = "";
		private string reply_line = "";
		private bool tip_due = false;
		private int ticks = 0;
		private bool probe_open = false;
		private int probe_id = 0;
```

#### Replace with

```vala
		private Argus.Agent.Application application;
		private OLLMrpc.Transport.TcpListen local_listen;
		private int ticks = 0;

		/**
		 * Register ''AgentService'' RPC methods on {@link OLLMrpc.Request}.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"AgentService", typeof(Service),
				"hello", "is",
				"status", "",
				"register", "ss"
			);
		}

		/**
		 * Answer the tray client's initial handshake.
		 *
		 * @param request inbound RPC from the tray
		 * @param protocol client protocol version
		 * @param client client name
		 */
		public void hello(OLLMrpc.Request request, int protocol, string client)
		{
			GLib.debug("local hello %s %d", client, protocol);
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Return registered flag, server connection flag, and tray tip.
		 *
		 * @param request inbound RPC from the tray
		 */
		public void status(OLLMrpc.Request request)
		{
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var registered =
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
					GLib.FileTest.EXISTS) &&
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"),
					GLib.FileTest.EXISTS);
			var connected = registered &&
				this.application.connection != null &&
				!Argus.Agent.Application.connection_down;
			var tip = "Not registered";
			if (!registered && this.application.status_notice != "") {
				tip = this.application.status_notice;
			}
			if (registered && connected) {
				tip = "Connected to management server";
			}
			if (registered && !connected) {
				tip = "Disconnected";
			}
			string[] reply = {
				registered ? "1" : "0",
				connected ? "1" : "0",
				tip
			};
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", reply),
				msg = "ok"
			});
		}

		/**
		 * Register this machine using a PIN and optional ''host:port''.
		 *
		 * @param request inbound RPC from the tray
		 * @param pin six-digit registration PIN
		 * @param hostport management server address, or empty to browse
		 */
		public void register(OLLMrpc.Request request, string pin, string hostport)
		{
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var registered =
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
					GLib.FileTest.EXISTS) &&
				GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"),
					GLib.FileTest.EXISTS);
			if (registered) {
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("i", (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR),
					msg = "ok"
				});
				return;
			}
			var target = hostport.strip();
			if (target == "") {
				var line = this.application.browse.poll();
				var split = line.index_of("\n");
				if (split >= 1) {
					target = line.substring(split + 1);
				}
			}
			var colon = target.last_index_of(":");
			var host = colon >= 1 ? target.substring(0, colon) : "";
			var port = colon >= 1 ? int.parse(target.substring(colon + 1)) : 0;
			var code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			if (host != "" && port > 0) {
				var registration = new Argus.Shared.Register();
				code = registration.try_connection(host, (uint16) port,
					pin.strip(), GLib.Environment.get_host_name());
				GLib.debug("registration %d", code);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("i", code),
				msg = "ok"
			});
			if (code != 0) {
				return;
			}
			this.application.status_notice = "";
			GLib.Idle.add(() => {
				this.application.attach_connection();
				if (this.application.connection != null) {
					new GLib.Thread<int>("osquery-init", () => {
						var init_code = new Argus.Agent.OSQuery.Initialize(this.application).run();
						GLib.Idle.add(() => {
							if (init_code == 0 && this.application.connection != null) {
								this.application.osquery.send_startup();
								this.application.monitor = new Argus.Agent.PackageMonitor(this.application);
								this.application.monitor.start();
							}
							return false;
						});
						return 0;
					});
				}
				return false;
			});
		}
```

##### Part 2 — `service_main`: start `TcpListen` before `application.run` and broadcast `agent.status`

#### Remove

```vala
			this.state = SERVICE_RUNNING;
			var running = SERVICE_STATUS();
			running.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			running.dwCurrentState = this.state;
			running.dwControlsAccepted = SERVICE_ACCEPT_STOP;
			SetServiceStatus(this.handle, ref running);
			GLib.Timeout.add_seconds(1, this.tick);
			this.application.run({ "argus-agent" });
			this.state = SERVICE_STOPPED;
```

#### Replace with

```vala
			OLLMrpc.rpc_register();
			Service.rpc_register();
			OLLMrpc.Request.register("AgentService", this);
			this.local_listen = new OLLMrpc.Transport.TcpListen("127.0.0.1", 4142);
			if (!this.local_listen.start()) {
				GLib.warning("local RPC listener did not bind");
			}
			this.application.state_changed.connect(() => {
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argus");
				var registered =
					GLib.FileUtils.test(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"),
						GLib.FileTest.EXISTS) &&
					GLib.FileUtils.test(GLib.Path.build_filename(dir, "client.pem"),
						GLib.FileTest.EXISTS);
				var connected = registered &&
					this.application.connection != null &&
					!Argus.Agent.Application.connection_down;
				var tip = "Not registered";
				if (!registered && this.application.status_notice != "") {
					tip = this.application.status_notice;
				}
				if (registered && connected) {
					tip = "Connected to management server";
				}
				if (registered && !connected) {
					tip = "Disconnected";
				}
				this.local_listen.broadcast(new OLLMrpc.Notification() {
					method = "agent.status",
					args = OLLMrpc.args("bbs", registered, connected, tip)
				});
			});
			this.state = SERVICE_RUNNING;
			var running = SERVICE_STATUS();
			running.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
			running.dwCurrentState = this.state;
			running.dwControlsAccepted = SERVICE_ACCEPT_STOP;
			SetServiceStatus(this.handle, ref running);
			GLib.Timeout.add_seconds(1, this.tick);
			this.application.run({ "argus-agent" });
			this.local_listen.stop();
			this.state = SERVICE_STOPPED;
```

##### Part 3 — `tick`: keep only the 5-second `argus-tray.exe` session launch

#### Remove

```vala
		private bool tick()
		{
			this.ticks++;
			var notice = GLib.Environment.get_variable("ARGUS_AGENT_TIP") != null ?
				GLib.Environment.get_variable("ARGUS_AGENT_TIP") : "";
			if (this.tip == "" && notice != "") {
				this.tip = notice;
				GLib.Environment.unset_variable("ARGUS_AGENT_TIP");
				GLib.debug("tip %s", this.tip);
			}
			if ((intptr) this.pipe == -1) {
				this.pipe = create_registration_pipe();
				this.pipe_up = false;
			}
			if (this.pipe == null) {
				this.pipe = (void*) (intptr) (-1);
			}
			if ((intptr) this.pipe == -1 && !this.pipe_warned) {
				GLib.warning("pipe: %u", GetLastError());
				this.pipe_warned = true;
			}
			if ((intptr) this.pipe != -1) {
				this.pipe_warned = false;
			}
			// FIXME? == stored publically?
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var cert = GLib.Path.build_filename(dir, "ollmrpc-ca.pem");
			if (this.number == "" && !GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
			}
			var became = false;
			if ((intptr) this.pipe != -1 && !this.pipe_up) {
				var joined = ConnectNamedPipe(this.pipe, null);
				var pipe_err = GetLastError();
				if (joined || pipe_err == ERROR_PIPE_CONNECTED) {
					became = true;
					this.pipe_up = true;
					GLib.debug("registration pipe open");
				}
				if (!joined && pipe_err != ERROR_PIPE_CONNECTED &&
					pipe_err != ERROR_PIPE_LISTENING) {
					GLib.warning("registration pipe %u", pipe_err);
					DisconnectNamedPipe(this.pipe);
					CloseHandle(this.pipe);
					this.pipe = (void*) (intptr) (-1);
					this.pipe_up = false;
				}
			}
			if (became && this.tip != "") {
				this.tip_due = true;
			}
			if (became && this.tip == "" &&
				GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.tip = "Disconnected";
				GLib.debug("tip %s", this.tip);
				this.tip_due = true;
			}
			uint32 avail = 0;
			if (this.pipe_up && this.number == "" &&
				!PeekNamedPipe(this.pipe, null, 0, null, out avail, null)) {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
			}
			uint32 got = 0;
			var buf = new uint8[256];
			if (this.pipe_up && this.number == "" && avail > 0 &&
				!ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
			}
			if (this.pipe_up && this.number == "" && got >= 6) {
				var msg = ((string) buf[0:got]).strip();
				var nl = msg.index_of("\n");
				if (nl == 6) {
					this.number = msg.substring(0, 6);
					this.directed = msg.substring(7);
					GLib.debug("registration pin for %s", this.directed);
				}
				if (nl < 0 && msg.length == 6) {
					this.number = msg;
					this.directed = "";
				}
			}
			var line = "";
			if (this.number != "" &&
				GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				this.reply_line = "%d".printf(
					(int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR);
				this.number = "";
				this.directed = "";
			}
			if (this.number != "" && this.directed != "") {
				line = "address\n" + this.directed;
			}
			if (this.number != "" && this.directed == "") {
				line = this.application.browse.poll();
			}
			if (line == "none") {
				this.reply_line = "%d".printf((int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR);
				this.number = "";
				this.directed = "";
			}
			var host = "";
			var port = 0;
			var split = line.index_of("\n");
			var hostport = "";
			if (split >= 1) {
				hostport = line.substring(split + 1);
			}
			var colon = hostport.last_index_of(":");
			if (line != "" && line != "none" && colon >= 1) {
				host = hostport.substring(0, colon);
				port = int.parse(hostport.substring(colon + 1));
			}
			var code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			if (host != "" && port > 0) {
				var registration = new Argus.Shared.Register();
				code = registration.try_connection(host, (uint16) port,
					this.number, GLib.Environment.get_host_name());
				GLib.debug("registration %d", code);
			}
			var attach = line != "" && line != "none" && code == 0;
			if (attach) {
				this.probe_id++;
				this.probe_open = false;
				this.tip = "Connected to management server";
				GLib.debug("tip %s", this.tip);
				this.tip_due = true;
			}
			if (line != "" && line != "none") {
				this.reply_line = "%d".printf(code);
				this.number = "";
				this.directed = "";
			}
			var probing = this.ticks % 120 == 1 && !this.probe_open &&
				GLib.FileUtils.test(cert, GLib.FileTest.EXISTS);
			var text = "";
			if (probing) {
				try {
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "download"), out text);
				} catch (GLib.Error e) {
					text = "";
				}
				text = text.strip();
			}
			var mark = text.last_index_of(":");
			if (probing && (text == "" || mark < 1) && this.tip != "Disconnected") {
				this.tip = "Disconnected";
				GLib.debug("tip %s", this.tip);
				this.tip_due = true;
			}
			var reach_port = 0;
			if (probing && text != "" && mark >= 1) {
				reach_port = int.parse(text.substring(mark + 1));
			}
			if (reach_port > 0) {
				this.probe_open = true;
				this.probe_id++;
				var id = this.probe_id;
				var client = new GLib.SocketClient() {
					timeout = 10
				};
				client.connect_to_host_async.begin(text.substring(0, mark),
					(uint16) reach_port, null, (obj, res) => {
						if (id != this.probe_id) {
							return;
						}
						this.probe_open = false;
						var next = "Disconnected";
						try {
							var conn = client.connect_to_host_async.end(res);
							next = "Connected to management server";
							conn.close();
						} catch (GLib.Error e) {
							if (next == "Connected to management server") {
								GLib.debug("download socket: %s", e.message);
							}
						}
						if (next == this.tip) {
							return;
						}
						this.tip = next;
						GLib.debug("tip %s", this.tip);
						this.tip_due = true;
				});
			}
			uint32 wrote = 0;
			var reply = this.reply_line.data;
			if (this.reply_line != "" && this.pipe_up && (intptr) this.pipe != -1 &&
				WriteFile(this.pipe, reply, (uint32) reply.length, out wrote, null)) {
				this.reply_line = "";
			}
			if (this.reply_line != "" && this.pipe_up && (intptr) this.pipe != -1) {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
				this.reply_line = "";
			}
			var tip_bytes = ("tip " + this.tip).data;
			if (this.tip_due && this.pipe_up && (intptr) this.pipe != -1 && this.tip != "" &&
				WriteFile(this.pipe, tip_bytes, (uint32) tip_bytes.length, out wrote, null)) {
				this.tip_due = false;
			}
			if (this.tip_due && this.pipe_up && (intptr) this.pipe != -1 && this.tip != "") {
				DisconnectNamedPipe(this.pipe);
				CloseHandle(this.pipe);
				this.pipe = (void*) (intptr) (-1);
				this.pipe_up = false;
			}
			if (attach) {
				this.application.attach_connection();
			}
			if (attach && this.application.connection != null) {
				new Argus.Agent.OSQuery.Initialize(this.application).start();
				this.application.osquery.send_startup();
				this.application.monitor = new Argus.Agent.PackageMonitor(this.application);
				this.application.monitor.start();
			}
			if (this.ticks % 5 != 1) {
				return true;
			}
```

#### Replace with

```vala
		private bool tick()
		{
			this.ticks++;
			if (this.ticks % 5 != 1) {
				return true;
			}
```

### 5. `agent/Win32/tray/Tray.vala` — `OLLMrpc.Client` instead of raw pipe, plus `other_copy()`

**Why:** use `OLLMrpc.Client("","","tcp://127.0.0.1:4142")` for status queries, `agent.status` notifications, and `AgentService.register`; keep `GLib.MainContext.@default()` running alongside Win32 messages so RPC watches never stall; and exit if another `argus-tray.exe` is already running.

**Where:** `agent/Win32/tray/Tray.vala` (fields, `other_copy`, `connect_service`, `run`, `on_message` menu/click, `present`).

**Depends on:** ### 1, ### 2, ### 3, ### 4.

##### Part 1 — fields, `other_copy`, and `connect_service`

#### Remove

```vala
		private void* pipe = (void*) (intptr) (-1);
		private bool known = false;
		private bool started = false;
		private bool submitted = false;
		private int waits = 0;
		private string tip_text = "";
		private void* restart_proc = null;
		private bool restarting = false;
```

#### Replace with

```vala
		private OLLMrpc.Client rpc;
		private bool registered = false;
		private bool started = false;
		private bool submitted = false;
		private int waits = 0;
		private bool connecting = false;
		private bool waiting_service = false;
		private string tip_text = "";
		private void* restart_proc = null;
		private bool restarting = false;

		/**
		 * Return true when another ''argus-tray.exe'' process is running.
		 *
		 * @return true if another tray process already exists
		 */
		private bool other_copy()
		{
			var ids = new uint32[4096];
			var needed = (uint32) 0;
			if (!EnumProcesses(ids, (uint32) (ids.length * 4), out needed)) {
				return false;
			}
			var count = int.min((int) (needed / 4), ids.length);
			var self = GetCurrentProcessId();
			for (var i = 0; i < count; i++) {
				if (ids[i] == 0 || ids[i] == self) {
					continue;
				}
				var proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, ids[i]);
				if (proc == null) {
					continue;
				}
				var image = g_utf8_to_utf16(string.nfill(259, ' '));
				var size = (uint32) 260;
				if (!QueryFullProcessImageNameW(proc, 0, image, ref size)) {
					CloseHandle(proc);
					continue;
				}
				CloseHandle(proc);
				try {
					if (image.to_utf8().down().has_suffix("\\argus-tray.exe")) {
						return true;
					}
				} catch (GLib.ConvertError e) {
					continue;
				}
			}
			return false;
		}

		/**
		 * Connect to the local Windows service and query its initial status.
		 */
		private async void connect_service()
		{
			if (this.connecting || this.rpc.connected) {
				return;
			}
			this.connecting = true;
			var ok = yield this.rpc.connect(new OLLMrpc.Request() {
				method = "AgentService.hello",
				args = OLLMrpc.args("is", 1, "argus-tray")
			});
			if (!ok) {
				this.connecting = false;
				this.waits++;
				if (!this.started && this.waits >= 10) {
					this.started = true;
					this.present();
				}
				return;
			}
			try {
				var resp = yield this.rpc.call(new OLLMrpc.Request() {
					method = "AgentService.status"
				});
				var info = (string[]) resp.retval;
				if (info.length >= 3) {
					this.registered = info[0] == "1";
					this.tip_text = info[2];
					this.set_tip(this.tip_text);
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			this.connecting = false;
			if (!this.started) {
				this.started = true;
				if (!this.registered) {
					this.present();
				}
			}
			if (this.window_up && this.registered && !this.submitted) {
				this.registration.close();
			}
			if (this.window_up && !this.registered && this.waiting_service) {
				this.waiting_service = false;
				this.registration.show_add();
			}
		}
```

##### Part 2 — `run()`: connect `OLLMrpc.Client` and pump `GLib.MainContext`

#### Remove

```vala
		public int run()
		{
			Tray.app = this;
			Tray.proc_slot = Tray.proc;
			if (!this.install()) {
				return 1;
			}
			try {
				this.pipe = CreateFileW(
					"\\\\.\\pipe\\Argus.Register".to_utf16(),
					GENERIC_READ | GENERIC_WRITE,
					0, null, OPEN_EXISTING, 0, null);
			} catch (GLib.ConvertError e) {
				this.pipe = (void*) (intptr) (-1);
			}
			if (this.pipe == null) {
				this.pipe = (void*) (intptr) (-1);
			}
			var mode = PIPE_READMODE_MESSAGE;
			if ((intptr) this.pipe != -1) {
				SetNamedPipeHandleState(this.pipe, ref mode, null, null);
			}
			var hs = new void*[1];
			while (true) {
				if (this.restart_proc != null &&
					WaitForSingleObject(this.restart_proc, 0) == WAIT_OBJECT_0) {
					var code = (uint32) 1;
					GetExitCodeProcess(this.restart_proc, (void*) (&code));
					CloseHandle(this.restart_proc);
					this.restart_proc = null;
					this.restarting = false;
					if (code == 0) {
						if ((intptr) this.pipe != -1) {
							CloseHandle(this.pipe);
							this.pipe = (void*) (intptr) (-1);
						}
						this.set_tip("Argus RM Agent");
						var info = NotifyIcon() {
							cb_size = (uint32) sizeof(NotifyIcon),
							hwnd = this.hwnd,
							id = 1,
							flags = NIF_INFO,
							info_flags = NIIF_INFO,
						};
						copy_wide(&info.info_title[0], g_utf8_to_utf16("Argus RM Agent"), 63);
						info.info_title[63] = 0;
						copy_wide(&info.info[0],
							g_utf8_to_utf16("The agent service has been restarted."), 255);
						info.info[255] = 0;
						Shell_NotifyIconW(NIM_MODIFY, &info);
					}
					if (code != 0) {
						this.set_tip(this.tip_text != "" ? this.tip_text : "Disconnected");
						if (!this.gtk_up) {
							Adw.init();
							this.gtk_up = true;
						}
						if (!this.notice_up) {
							var detail = "Restart exited with code %u.".printf(code);
							switch (code) {
								case 5:
									detail = "Administrator access was not granted.";
									break;

								case 1060:
									detail = "The Argus agent service is not installed.";
									break;

								default:
									break;
							}
							this.status_notice = new Argus.Shared.Notice(
								"Could not restart the Argus agent service", detail);
							this.status_notice.title =
								"Argus Remote Management Agent " + Argus.VERSION;
							this.status_notice.add_response("ok", "OK");
							this.notice_up = true;
							this.status_notice.closed.connect(() => {
								this.notice_up = false;
							});
							this.status_notice.present(null);
						}
					}
				}
				if (this.started && !this.window_up && (intptr) this.pipe == -1 &&
					!this.restarting) {
					try {
						this.pipe = CreateFileW(
							"\\\\.\\pipe\\Argus.Register".to_utf16(),
							GENERIC_READ | GENERIC_WRITE,
							0, null, OPEN_EXISTING, 0, null);
					} catch (GLib.ConvertError e) {
						this.pipe = (void*) (intptr) (-1);
					}
					if (this.pipe == null) {
						this.pipe = (void*) (intptr) (-1);
					}
					if ((intptr) this.pipe != -1) {
						var pipe_mode = PIPE_READMODE_MESSAGE;
						SetNamedPipeHandleState(this.pipe, ref pipe_mode, null, null);
					}
				}
				uint32 avail = 0;
				if ((intptr) this.pipe != -1 &&
					!PeekNamedPipe(this.pipe, null, 0, null, out avail, null)) {
					switch (GetLastError()) {
						case ERROR_BROKEN_PIPE:
						case 233:
							CloseHandle(this.pipe);
							this.pipe = (void*) (intptr) (-1);
							break;
						default:
							break;
					}
				}
				var msg = "";
				if ((intptr) this.pipe != -1 && avail > 0) {
					uint32 got = 0;
					var buf = new uint8[256];
					if (ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
						msg = (string) buf[0:int.min((int) got, buf.length)];
					}
				}
				if (msg.has_prefix("tip ")) {
					var text = msg.substring(4).strip();
					this.tip_text = text;
					this.set_tip(text);
					this.known = text == "Connected to management server";
					if (!this.started) {
						this.started = true;
						this.present();
					}
					if (this.window_up && !this.known) {
						this.registration.listen_label.label = text;
					}
				}
				if (this.known && this.window_up && !this.submitted) {
					this.registration.close();
				}
				if (!this.started && (intptr) this.pipe != -1 && !this.known && this.waits < 6) {
					this.waits++;
					Sleep(200);
					continue;
				}
				if (!this.started) {
					this.started = true;
					this.present();
				}
				if (this.window_up || this.notice_up) {
					GLib.MainContext.@default().iteration(true);
					continue;
				}
				var count = (uint32) 0;
				if (this.restart_proc != null) {
					hs[0] = this.restart_proc;
					count = 1;
				}
				var wr = MsgWaitForMultipleObjects(count, hs, false, 1000, QS_ALLINPUT);
				if (wr == WAIT_OBJECT_0 + count && !this.pump()) {
					break;
				}
				if (wr == WAIT_OBJECT_0 && count == 1) {
					continue;
				}
				if (wr == WAIT_OBJECT_0 + count || wr == WAIT_TIMEOUT) {
					continue;
				}
				OutputDebugStringW(g_utf8_to_utf16(
					"argus-tray: %s (%u)\n".printf("MsgWait", GetLastError())));
				Sleep(200);
			}
```

#### Replace with

```vala
		public int run()
		{
			if (this.other_copy()) {
				return 0;
			}
			Tray.app = this;
			Tray.proc_slot = Tray.proc;
			if (!this.install()) {
				return 1;
			}
			OLLMrpc.rpc_register();
			this.rpc = new OLLMrpc.Client("", "", "tcp://127.0.0.1:4142");
			this.rpc.notification.connect((notif) => {
				if (notif.method != "agent.status" || notif.args.size < 3) {
					return;
				}
				this.registered = notif.args.get(0).get_boolean();
				this.tip_text = notif.args.get(2).get_string();
				this.set_tip(this.tip_text);
				if (!this.started) {
					this.started = true;
					if (!this.registered) {
						this.present();
					}
				}
				if (this.window_up && this.registered && !this.submitted) {
					this.registration.close();
				}
				if (this.window_up && !this.registered) {
					this.registration.listen_label.label = this.tip_text;
				}
			});
			GLib.Timeout.add(500, () => {
				if (!this.rpc.connected && !this.connecting) {
					this.connect_service.begin();
				}
				return true;
			});
			this.connect_service.begin();
			var hs = new void*[1];
			while (true) {
				while (GLib.MainContext.@default().iteration(false)) {
				}
				if (this.window_up || this.notice_up) {
					GLib.MainContext.@default().iteration(true);
					continue;
				}
				var wr = MsgWaitForMultipleObjects(0, hs, false, 100, QS_ALLINPUT);
				if (wr == WAIT_OBJECT_0 && !this.pump()) {
					break;
				}
				if (wr == WAIT_OBJECT_0 || wr == WAIT_TIMEOUT) {
					continue;
				}
				OutputDebugStringW(g_utf8_to_utf16(
					"argus-tray: %s (%u)\n".printf("MsgWait", GetLastError())));
				Sleep(200);
			}
```

##### Part 3 — `on_message` menu & click: use `this.registered` instead of user-profile `ollmrpc-ca.pem`

#### Remove

```vala
						var dir = GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "argus");
						var registered = GLib.FileUtils.test(
							GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS);
						if (!this.known && !registered) {
							AppendMenuW(menu, MF_STRING, 1002, g_utf8_to_utf16("Register…"));
						}
```

#### Replace with

```vala
						if (!this.registered) {
							AppendMenuW(menu, MF_STRING, 1002, g_utf8_to_utf16("Register…"));
						}
```

#### Remove

```vala
					case 1:
						KillTimer(hwnd, 1);
						var dir = GLib.Path.build_filename(
							GLib.Environment.get_user_data_dir(), "argus");
						var registered = GLib.FileUtils.test(
							GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), GLib.FileTest.EXISTS);
						if (!this.known && !registered) {
							this.present();
							return 0;
						}
```

#### Replace with

```vala
					case 1:
						KillTimer(hwnd, 1);
						if (!this.registered) {
							this.present();
							return 0;
						}
```

#### `on_message` (`WM_COMMAND` `case 1001`) — Remove

```vala
						this.restart_proc = sei.hProcess;
						if (this.gtk_up) {
							GLib.Timeout.add(250, () => {
								return this.restart_proc != null;
							});
						}
```

#### `on_message` (`WM_COMMAND` `case 1001`) — Replace with

```vala
						this.restart_proc = sei.hProcess;
						GLib.Timeout.add(200, () => {
							if (this.restart_proc == null) {
								return false;
							}
							if (WaitForSingleObject(this.restart_proc, 0) != WAIT_OBJECT_0) {
								return true;
							}
							var code = (uint32) 1;
							GetExitCodeProcess(this.restart_proc, (void*) (&code));
							CloseHandle(this.restart_proc);
							this.restart_proc = null;
							this.restarting = false;
							if (code == 0) {
								this.set_tip("Argus RM Agent");
								var info = NotifyIcon() {
									cb_size = (uint32) sizeof(NotifyIcon),
									hwnd = this.hwnd,
									id = 1,
									flags = NIF_INFO,
									info_flags = NIIF_INFO,
								};
								copy_wide(&info.info_title[0], g_utf8_to_utf16("Argus RM Agent"), 63);
								info.info_title[63] = 0;
								copy_wide(&info.info[0],
									g_utf8_to_utf16("The agent service has been restarted."), 255);
								info.info[255] = 0;
								Shell_NotifyIconW(NIM_MODIFY, &info);
								return false;
							}
							this.set_tip(this.tip_text != "" ? this.tip_text : "Disconnected");
							if (!this.gtk_up) {
								Adw.init();
								this.gtk_up = true;
							}
							if (this.notice_up) {
								return false;
							}
							var detail = "Restart exited with code %u.".printf(code);
							switch (code) {
								case 5:
									detail = "Administrator access was not granted.";
									break;

								case 1060:
									detail = "The Argus agent service is not installed.";
									break;

								default:
									break;
							}
							this.status_notice = new Argus.Shared.Notice(
								"Could not restart the Argus agent service", detail);
							this.status_notice.title =
								"Argus Remote Management Agent " + Argus.VERSION;
							this.status_notice.add_response("ok", "OK");
							this.notice_up = true;
							this.status_notice.closed.connect(() => {
								this.notice_up = false;
							});
							this.status_notice.present(null);
							return false;
						});
```

##### Part 4 — `present()`: use `this.rpc.call_sync` for `AgentService.register`

#### Remove

```vala
		private void present()
		{
			if (this.known) {
				return;
			}
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var registered = GLib.Path.build_filename(dir, "ollmrpc-ca.pem");
			if (GLib.FileUtils.test(registered, GLib.FileTest.EXISTS)) {
				return;
			}
			GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
			GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
			GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
			if (!this.gtk_up) {
				Adw.init();
				this.gtk_up = true;
			}
			if (this.window_up) {
				this.registration.present(null);
				return;
			}
			this.registration = new Argus.Shared.RegisterWindow();
			this.registration.use_pipe = true;
			this.registration.send_pin.connect((pin, hostport) => {
				this.submitted = true;
				var bytes = (pin + "\n" + hostport).data;
				var wrote = (uint32) 0;
				for (var attempt = 0; attempt < 15; attempt++) {
					if ((intptr) this.pipe == -1) {
						try {
							this.pipe = CreateFileW(
								"\\\\.\\pipe\\Argus.Register".to_utf16(),
								GENERIC_READ | GENERIC_WRITE,
								0, null, OPEN_EXISTING, 0, null);
						} catch (GLib.ConvertError e) {
							this.pipe = (void*) (intptr) (-1);
						}
						if (this.pipe == null || (intptr) this.pipe == -1) {
							this.pipe = (void*) (intptr) (-1);
						}
						if ((intptr) this.pipe != -1) {
							var mode = PIPE_READMODE_MESSAGE;
							SetNamedPipeHandleState(this.pipe, ref mode, null, null);
						}
					}
					if ((intptr) this.pipe != -1 &&
						WriteFile(this.pipe, bytes, (uint32) bytes.length, out wrote, null)) {
						break;
					}
					if ((intptr) this.pipe != -1) {
						CloseHandle(this.pipe);
						this.pipe = (void*) (intptr) (-1);
					}
					Sleep(200);
				}
				if ((intptr) this.pipe == -1) {
					this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					return;
				}
				while (true) {
					uint32 got = 0;
					var buf = new uint8[256];
					if (!ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
						this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
						return;
					}
					var n = int.min((int) got, buf.length);
					var msg = (string) buf[0:n];
					if (msg.has_prefix("tip ")) {
						this.tip_text = msg.substring(4).strip();
						this.set_tip(this.tip_text);
						continue;
					}
					var code = 0;
					if (!int.try_parse(msg.strip(), out code)) {
						this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
						return;
					}
					if (code == 0) {
						this.known = true;
					}
					this.registration.pipe_code = code;
					return;
				}
			});
			this.window_up = true;
			this.registration.closed.connect(() => {
				this.window_up = false;
			});
			this.registration.show_add();
			if ((intptr) this.pipe != -1) {
				this.registration.show_add();
			} else {
				var window = this.registration;
				GLib.Timeout.add(200, () => {
					if (!this.window_up || this.registration != window) {
						return false;
					}
					if ((intptr) this.pipe == -1) {
						try {
							this.pipe = CreateFileW(
								"\\\\.\\pipe\\Argus.Register".to_utf16(),
								GENERIC_READ | GENERIC_WRITE,
								0, null, OPEN_EXISTING, 0, null);
						} catch (GLib.ConvertError e) {
							this.pipe = (void*) (intptr) (-1);
						}
						if (this.pipe == null || (intptr) this.pipe == -1) {
							this.pipe = (void*) (intptr) (-1);
							return true;
						}
						var mode = PIPE_READMODE_MESSAGE;
						SetNamedPipeHandleState(this.pipe, ref mode, null, null);
					}
					this.registration.show_add();
					return false;
				});
			}
			this.registration.present(null);
		}
```

#### Replace with

```vala
		private void present()
		{
			if (this.registered) {
				return;
			}
			if (!this.gtk_up) {
				Adw.init();
				this.gtk_up = true;
			}
			if (this.window_up) {
				this.registration.present(null);
				return;
			}
			this.registration = new Argus.Shared.RegisterWindow();
			this.registration.use_pipe = true;
			this.registration.send_pin.connect((pin, hostport) => {
				this.submitted = true;
				if (!this.rpc.connected) {
					this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					return;
				}
				try {
					var resp = this.rpc.call_sync(new OLLMrpc.Request() {
						method = "AgentService.register",
						args = OLLMrpc.args("ss", pin, hostport)
					});
					if (resp.error != null) {
						this.registration.pipe_code = resp.error.code;
						return;
					}
					var code = resp.retval.get_int();
					if (code == 0) {
						this.registered = true;
					}
					this.registration.pipe_code = code;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
			});
			this.window_up = true;
			this.registration.closed.connect(() => {
				this.window_up = false;
			});
			this.waiting_service = true;
			this.registration.show_add();
			if (this.rpc.connected) {
				this.waiting_service = false;
				this.registration.show_add();
			}
			this.registration.present(null);
		}
```

### 6. `docs/rpc-commands.md` — document `AgentService` calls and `agent.status`

**Why:** `.cursor/rules/rpc-commands.mdc` requires documenting new `Request.add_class` methods and `Notification` methods in the same change.

**Where:** `docs/rpc-commands.md` after `Agent.request_registration` (and in Notifications).

**Depends on:** ### 4.

#### Add — after `Agent.offer` and `agent.send` in `docs/rpc-commands.md`

```markdown
### `AgentService.hello` / `AgentService.status` / `AgentService.register`

- Socket: loopback `tcp://127.0.0.1:4142` (`OLLMrpc.Transport.TcpListen` inside the Windows service).
- Direction: `argus-tray.exe` calls `argus-agent.exe`.
- `AgentService.hello` `is`: protocol version, client name. Reply `msg`: `ok`.
- `AgentService.status`: no arguments. Reply `retval` `as`: `["1"|"0" registered, "1"|"0" connected, tip]`.
- `AgentService.register` `ss`: six-digit PIN, `host:port` (or empty to use browse). Reply `retval` `i`: `0` on success or `OLLMrpc.RpcErrorCode`.
- ℹ️ The handlers are in `agent/Win32/Service.vala`, called from `agent/Win32/tray/Tray.vala`.
```

and under `## Notifications`:

```markdown
### `agent.status`

- 🔷 Broadcast from `AgentService` over loopback TCP (`127.0.0.1:4142`) to connected `argus-tray.exe` clients.
- 💩 Arguments `bbs`: `registered`, `connected`, `tip`.
```

---

## Attempts / changelog

- ℹ️ 2026-11-13: Diagnosed from `agent/Win32/register-pipe.c`, `agent/Win32/Service.vala`, `agent/Win32/tray/Tray.vala`, `agent/Application.vala`, `agent/OSQuery/Initialize.vala`, `agent/OSQuery/Execute.vala`, `shared/RegisterWindow.vala`, `packaging/windows/argusrm-agent.nsi`, and `OLLMchat/libocrpc`.
- ℹ️ 2026-11-13: User approved moving Windows desktop–service IPC to `OLLMrpc` over `TcpListen` (`127.0.0.1`) with the `AgentService` RPC surface; drafted verbatim code proposals (`### 1`–`### 6`).
- ✔️ 2026-11-13: Filed `OLLMchat/docs/bugs/2026-11-13-windows-tcp-iochannel.md` for `### 1` (no `OLLMchat` code edited).
- ✔️ 2026-11-13: Applied `### 2`–`### 6` in `argusrm` (`agent/meson.build`, `agent/Win32/win32.h`, `agent/Win32/win32.vapi`, `agent/Win32/register-pipe.c`, `agent/Application.vala`, `agent/Win32/Service.vala`, `agent/Win32/tray/Tray.vala`, `docs/rpc-commands.md`). Verified Windows Vala compile (`valac -C -D WINDOWS -D G_OS_WIN32`) and Linux `meson compile -C build` + `meson test -C build` (6/6 passed).
- ✅ 2026-11-13: `OLLMchat` `v1.4.12` landed (`2026-11-13-FIXED-windows-tcp-iochannel.md`); updated `.github/workflows/x-windows.yml` to `v1.4.12` and verified `0.1.17`–`0.1.19` on `snappr-win` (`agent.log` shows `AgentService.hello` / `AgentService.status` connecting immediately over `127.0.0.1:4142` while `OSQuery` runs in background).

## Next

- ✅ Closed.
