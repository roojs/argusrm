# Windows registration

**Status:** 🔴 Registration did not finish. The window stayed up, the download path is an address, and the agent then timed out.

**Pointer:** `docs/bug-fix-process.md`

**Seen:** 0.1.14 on the Windows machine, 2026-11-12. Second install.

---

## Problem

- 🔴 The first install did not see the broadcast.
- ℹ️ After a reinstall the window saw the broadcast, the number was sent, and the controller's countdown disappeared.
- 🔴 The registration window then stayed where it was.
- 🔴 The download path came back as an IP address.

## 1. Windows service and tray

The installer starts `argus-agent`. The tray opens `\\.\pipe\Argus.Register` and shows a spinner until that pipe exists. Then the window looks for the broadcast.

- ℹ️ Second start, the pipe opened and the service was already browsing. This step is not the failure.

```
17:45:25.579  Application.vala:372  browsing
17:45:27.952  Service.vala:195      registration pipe open
```

## 2. Broadcast

The controller calls `Agent.offer`. The server publishes `_rpc._tcp` and opens port 819 for 60 seconds. The window's browse reads that. The tray does not register yet.

- 🔴 First install: the window did not see a broadcast.
- ℹ️ Offers at 17:43:25 and 17:44:23 got no `Agent.request_registration`. The 17:44 offer closed itself at 17:45:23. That service's log was replaced by the reinstall.
- ℹ️ Second start: the browse saw the server eight seconds after the process came up.

```
17:43:25.354  Agent.offer
17:43:57.643  registration closed after controller disconnected

17:44:23.424  Agent.offer
17:45:23.735  firewall enforced on port 819

17:45:28.847  Agent.offer
17:45:33.585  Browse.vala:188  broadcast 8d368d09-40aa-4d3c-a5a2-1ef5aee015a7 192.168.88.132:819
```

## 3. The number

The window writes six digits and `host:port` to the pipe. The service calls `Agent.request_registration`.

- ℹ️ The call reached the server. The server allowed `192.168.88.244` onto port 817 and closed port 819. The controller countdown closed.
- 🔴 The window did not finish.

```
17:45:39.958  Service.vala:238  registration pin for 192.168.88.132:819
17:45:39.863  Agent.request_registration
17:45:39.871  firewall add 192.168.88.244 on 817
17:45:39.871  firewall enforced on port 819
17:45:40.041  Service.vala:281  registration 0
17:45:40.041  Service.vala:287  tip Connected to management server
```

## 4. What got stored

The download path is a URL path. This reply put an address there.

- 🔴 `download-path` is `0.0.0.0:818`. That is the listen address, not a path.
- 🔴 `server` is `192.168.88.132:819`. That is the registration port. The app port is 817.
- ℹ️ `download` is `192.168.88.132:818`, the host the agent connected to.
- ℹ️ The process that answered started at 14:38. The binary on disk was replaced at 17:44 and is not the process that answered. That old reply puts the listen address in the field this agent stores as the path.

```
download        192.168.88.132:818
download-path   0.0.0.0:818
server          192.168.88.132:819
```

## 5. The window stays up

The service logs the connected tip and then calls `attach_connection` before it writes the reply on the pipe. The tray is blocked in that read, so the window cannot move on.

`attach_connection` opens `192.168.88.132:819`. Port 819 is already closed. The open times out. The pipe reply is written after that returns.

- 🔴 The window stayed up. The timeout is three minutes after the server had already taken the number.

```
17:48:49.975  Application.vala:193  Could not connect to 192.168.88.132: Socket I/O timed out
```

The tray closes the window on `Connected to management server` only when the number has not been sent. This number had been sent, so that tip does not close it. The success line and the ten-second close run only after the pipe reply arrives.

## Root cause

- 🔴 The window waits on the pipe reply. The service writes that reply only after `attach_connection`. That call opens port 819 from the old reply and blocks until the socket times out.
- 🔴 The download path is an address because the 14:38 server process is still the one answering.

## Next

- 🔴 Restart `argusrm-server`. The 14:38 process has to stop answering before another number is used.
- ✔️ The pipe reply is written before `attach_connection`.
- ✔️ The installer kills `argus-agent.exe` and `argus-tray.exe` before it stops and deletes the service. `sc stop` does not return while the process is blocked in a socket open.
- ✔️ A stored certificate is checked with a five-second open and `RPC-Daemon.hello`. If the open fails, or the server does not accept the certificate, the local registration files are removed and the window offers registration again. The label is `Could not reach the management server.` or `Not registered with the management server.`

---

## LLM log

The record below is the running log from this investigation. It is not the status.

# Windows install does not open the agent

**Status:** ⏳ ✔️ Proposal applied in the tree. Not verified on the Windows machine.

**Pointer:** `docs/bug-fix-process.md`

**Seen:** `ArgusAgent-0.1.3-Setup.exe` on a Windows machine, 2026-11-11.

---

## Problem

- 🔷 The installer finishes and nothing happens.
- 🔷 The agent is not in the Start menu under Argus Agent. The entry there is named Register this machine.
- 🔷 Starting that entry opens a console, then the registration window.
- 🔷 Registration did not finish. The window did not find the server. The two machines were on different networks.
- 🔷 Discovery sat there for a long time.
- 🔷 The number shown on the controller cannot be copied.

## Evidence

- ✔️ `packaging/windows/argusrm-agent.nsi` creates the service, then a shortcut. It never starts `argus-tray.exe`.
- ✔️ The shortcut target is `argus-tray.exe`. The link name is `Register this machine.lnk`.
- ✔️ `sc create` uses the service name `ArgusAgent`. `agent/Win32/Service.vala` registers `argus-agent` with `StartServiceCtrlDispatcherW`. Those names do not match, so the service does not enter `service_main` and does not start the tray.
- ✔️ `argus-tray.exe` is a copy of `argus-agent.exe`. `agent/meson.build` links that executable with the console subsystem. Windows opens a console for it.
- ✔️ `shared/windows/Browse.vala` sets `none` only when `DnsServiceBrowse` fails. A quiet network leaves the result empty, so `RegisterWindow` stays on “Looking for a management server…”.
- ✔️ A typed address is checked again every 20 seconds (`RegisterWindow.on_wait`). The pipe to the service carries the six digits and not that address. The service then waits on its own browse.
- ✔️ `controller/dialog/Pairing.vala` shows the six digits on a `Gtk.Label` with class `pairing-pin`. `selectable` is not set. The server command on the agent window is a label with `selectable = true`.

## Root cause

- ✔️ The installer leaves startup to a service whose registered name is not the name it created, and it points the Start menu at a console build named Register this machine.

## Proposed fix

- 🔷 `sc create` uses `argus-agent`, the name `Service` registers.
- 🔷 The shortcut is `Argus Agent.lnk`. The finish step starts `argus-tray.exe` in the signed-in session.
- 🔷 `argus-tray.exe` is linked with the windows subsystem. `argus-agent.exe` stays a console program so a command-line launch still has a console.
- 🔷 The controller PIN label is selectable, the same way the agent window’s server command is.
- 💩 ⏳ Discovery and the failed registration stay open. The broadcast does not cross networks, and the window does not give up while browse stays empty.

## Attempts

- ✔️ `packaging/windows/argusrm-agent.nsi` creates the service as `argus-agent`, removes a leftover `ArgusAgent` service, and names the shortcut Argus Agent.
- 🔷 Starting the service did not open the registration window. `.onInstSuccess` starts `argus-tray.exe` when the installer finishes.
- ✔️ `scripts/ci/windows-package-nsis.sh` sets the tray copy to the windows subsystem. `argus-agent.exe` stays a console program.
- ✔️ `controller/dialog/Pairing.vala` sets `selectable` on the PIN label and leaves it unfocused, so the digits are not shown selected.
- ✔️ The tray writes the window's `host:port` with the PIN. The service registers to that address.
- ✔️ From `snappr-win`, `argus-agent.exe --host 192.168.88.132 --port 819 --pin 000000` reached `Register.vala` and stopped with `os-release did not name debian or rpm` (`-32603`). TCP to port 819 succeeded. No certificate was sent. MSYS2 valac does not define `G_OS_WIN32`, so `shared/Register.vala` kept the Linux family.
- ✔️ After `-D G_OS_WIN32`, the same command gets past that check. With registration closed it stops on `Could not connect to 192.168.88.132: Socket I/O timed out`. Port 819 is firewalled until the controller opens a PIN.
- ✔️ A failed attempt writes `client.pem` before the server answers. The tray treated that file as registered and did not open the window. Startup now removes `client.pem`, `client-key.pem`, and `client.csr` when `ollmrpc-ca.pem` is absent.
- 🔷 The window came up and the PIN still failed. The server log had the offer and no registration connection. The tray closed the pipe when a peek failed, so the service never called `Register`. A broken pipe is the only peek that closes it now, and the service drops an instance that is not listening.
- ✔️ 0.1.4 is on the machine. The registration window title ends in 0.1.4. That build still does not register.
- ✔️ The agent browsed from 11:39. The controller published at 11:45 and 11:47. The browse log stayed empty. The same browse finds the server in under a second when the advertisement is already up. `shared/windows/Browse.vala` now stops and starts the browse every two seconds until a result arrives.
- ✔️ 0.1.5 is the build on the machine. The window title ends in 0.1.5. Its browse restarts every two seconds.
- ✔️ A probe on that machine, `DnsServiceBrowse` for `_rpc._tcp.local`, got `alan-office-desktop` immediately and the resolve never returned. Fifteen seconds later the same browse delivered the test service and resolved it to `192.168.88.132`. The agent drops that second result because the first resolve leaves it busy. The two-second restart cancels the browse before that result arrives. `shared/windows/Browse.vala` now keeps the later result and leaves the browse running.
- ✔️ 0.1.6 is on the machine. The window title ends in 0.1.6. The service was missing and was created again. Browse started at 12:34:53 with no result. A service published after that was logged at 12:35:26: `broadcast 22222222-2222-2222-2222-222222222222 192.168.88.132:819`.
- ✔️ A Windows program that called `OLLMrpc.args("ssssbss", ...)` wrote a 120-byte frame in which every string was the PIN. The same call on Linux wrote 450 bytes and included the certificate request. Building that list one value at a time produced the 450-byte frame, and that program registered: the server replied `ok`.

## Next

- ✔️ 0.1.8 registered from a pipe write. The tray then showed Disconnected because the stored download address was `0.0.0.0:818`. After reinstall the service was gone (`sc query` 1060). The offer at 14:39:50 got no `Agent.request_registration`.
- ✔️ A throwaway that stopped, deleted, and immediately created the service got stop state 3, delete 0, create 1072, then the service was gone (1060). Create after it was gone returned 0.
- ✔️ `OLLMrpc.args("ssssbss", ...)` on Windows wrote 120 bytes, every string the PIN. Linux wrote 450 bytes and included the certificate request. A hand-built list registered.
- ✔️ Without `GIO_MODULE_DIR` the service loads `GDummyTlsBackend` and aborts with `TLS support is not available`.
- 🚫 Do not `taskkill` the service. The installer stays stop, delete, create.
- ✔️ 17:10. The service log is still the 14:57 start. It has no `registration pin` line. The number typed in the window did not reach the service.
- ✔️ 17:16. `sc query argus-agent` is 1060. The service key is gone. `argus-tray.exe` is running. DisplayVersion is 0.1.12. A throwaway `CreateFile` of `\\.\pipe\Argus.Register` fails with error 2.
- ✔️ The same program then `CreateService` and `StartService`. The service reaches state 4 and stays there. The pipe opens.
- ✔️ Stop returns state 3 immediately, delete returns 0, and create at that moment returns 1072. The entry is gone 265 ms later, and create then returns 0. The service was started again and stayed in state 4.
- ✔️ `nsExec::ExecToStack` pops the exit code first. `cmd /c exit 3` pops `3`. `sc query` pops `0` while the service is running and `1060` when it is gone. The installer wait matches that.
- ✔️ A throwaway pipe with the service's flags (`PIPE_NOWAIT`, message mode, one instance) reads `123456\n192.168.88.132:819` and the client reads the reply `0`. Connect returns 536 while listening and 535 once the client is connected.
- ✔️ The registration window waits on a spinner until `CreateFile` of `\\.\pipe\Argus.Register` succeeds. `show_add` listens for the management server only after that.
- ✔️ The installer `sc create` line returns 1639. `binPath= "$\"...$\""` is not a command `sc` accepts. The same sequence with `binPath= "$INSTDIR\argus-agent.exe"` returns 0 and the service reaches state 4.

## Proposed fix

- ✔️ The installer waits until the service is gone, then creates it.
- ✔️ The reply does not send a download host. The client already connected to that host. The download port is `Argus.DOWNLOAD_PORT`. `Register.vala` stores `host` and that port.
- ℹ️ The Windows `args` packer is `OLLMchat/docs/bugs/2026-11-12-windows-args-va-list.md`. `Register.vala` keeps `OLLMrpc.args`. `libocrpc/namespace.vala` already has the `#if G_OS_WIN32` `ref va_list` change.
- ✔️ The registration window stays up unless the tip is `Connected to management server`.
- ✔️ `GIO_MODULE_DIR` is the `gio\modules` directory beside the executable, set before TLS.

### `packaging/windows/argusrm-agent.nsi`

#### Add

```
!include "LogicLib.nsh"
```

#### Add

```
Function WaitServiceGone
  Exch $R0
  Push $R1
  Push $0
  Push $1
  StrCpy $R1 0
  ${Do}
    nsExec::ExecToStack '"$SYSDIR\sc.exe" query $R0'
    Pop $0
    Pop $1
    ${If} $0 != "0"
      ${ExitDo}
    ${EndIf}
    IntOp $R1 $R1 + 1
    ${If} $R1 > 40
      ${ExitDo}
    ${EndIf}
    Sleep 250
  ${Loop}
  Pop $1
  Pop $0
  Pop $R1
  Pop $R0
FunctionEnd
```

#### Add

```
  Push "ArgusAgent"
  Call WaitServiceGone
  Push "${SERVICE_NAME}"
  Call WaitServiceGone
```

after the `sc delete` lines and before `SetOutPath`.

### `server/Agent.vala`

The download listener is the registration host on `Argus.DOWNLOAD_PORT`. The reply does not send that host again. `this.app.download` is only the bind address for the listener.

#### Remove

```
			packed.add(this.app.download);
			packed.add(path);
```

#### Replace with

```
			packed.add(path);
```

### `shared/Register.vala`

The reply is now the certificate, the CA, the download path, then the app socket addresses. The stored download address is the host argument of `try_connection` and `Argus.DOWNLOAD_PORT`.

#### Remove

```
			if (packed.length < 4) {
```

#### Replace with

```
			if (packed.length < 3) {
```

#### Remove

```
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download"), packed[2]);
```

#### Replace with

```
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download"),
					host + ":" + Argus.DOWNLOAD_PORT.to_string());
```

#### Remove

```
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download-path"), packed[3]);
```

#### Replace with

```
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download-path"), packed[2]);
```

#### Remove

```
			if (packed.length > 4) {
				var listed = packed[4];
```

#### Replace with

```
			if (packed.length > 3) {
				var listed = packed[3];
```

#### Remove

```
			this.download = packed[2];
			this.download_path = packed[3];
			if (packed.length > 4) {
				this.addresses = string.joinv("\n", packed[4:packed.length]);
```

#### Replace with

```
			this.download = host + ":" + Argus.DOWNLOAD_PORT.to_string();
			this.download_path = packed[2];
			if (packed.length > 3) {
				this.addresses = string.joinv("\n", packed[3:packed.length]);
```

### `agent/Win32/tray/Tray.vala`

#### Remove

```
				if (msg.has_prefix("tip ")) {
					this.set_tip(msg.substring(4));
					this.known = true;
				}
				if (msg.has_prefix("tip ") && this.window_up && !this.submitted) {
					this.registration.close();
				}
```

#### Replace with

```
				if (msg.has_prefix("tip ")) {
					var text = msg.substring(4).strip();
					this.set_tip(text);
					this.known = text == "Connected to management server";
				}
				if (this.known && this.window_up && !this.submitted) {
					this.registration.close();
				}
```

### `agent/Win32/main.vala`

#### Add

```
		// GIO loads TLS from a module. This executable is installed
		// outside the MSYS2 prefix, so the default search misses
		// libgiognutls.dll and GDummyTlsBackend is used. Certificate
		// load then aborts: "TLS support is not available". The
		// package copies that DLL to gio\modules beside the
		// executable. Point GIO there before any TLS call.
		var exe = Win32.g_utf8_to_utf16(string.nfill(259, ' '));
		if (Win32.GetModuleFileNameW(null, exe, 260) != 0) {
			try {
				var path = exe.to_utf8();
				var slash = path.last_index_of("\\");
				if (slash > 0) {
					GLib.Environment.set_variable("GIO_MODULE_DIR",
						path.substring(0, slash) + "\\gio\\modules", true);
				}
			} catch (GLib.ConvertError e) {
				GLib.warning("%s", e.message);
			}
		}
```

at the start of `main`, before the tray or service branch. `scripts/ci/copy-windows-runtime.sh` copies `libgiognutls.dll` into `gio/modules` beside the executable.
