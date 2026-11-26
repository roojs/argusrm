# Windows Remote Desktop dials through a virtual adapter

**Status:** ✔️

### User decisions required

None.

### User reported

- 🔷 Keep trying the Wintun idea. Set up a proof of concept and test it on the Windows machine.
- 🔷 This ends up in the Windows agent. Call it a fake tunnel.
- 🔷 Any other C code belongs in the Win32 area, or a vapi. It should not pollute the Windows agent code.
- 🔷 This needs its own bug report. It is not contained in the remote desktop bug. Describe what we want.
- 🔷 The proof of concept is done. This is the implementation plan.
- 🔷 Ship `wintun.dll` from packaging. Do not store it in git. The packaging flow checks that it has been downloaded and is available, then installs it.
- 🔷 Keep the adapter logic out of a C file. A Vala file calls vapi hooks.

### Success scenario

- The Windows agent's Remote Desktop connection is one Windows lists with remote address `10.200.0.1`.
- TermService on `10.200.0.2:3389` answers that connection.
- The byte copy to the relay stays [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala).
- The adapter sequence and the TCP connection live in [`agent/windows/Adapter.vala`](../../agent/windows/Adapter.vala).
- [`win32/win32.vapi`](../../win32/win32.vapi) is the hook list that file calls.
- [`agent/windows/Service.vala`](../../agent/windows/Service.vala) does not gain that code.
- The installed agent has `wintun.dll` beside the exe and loads it from that directory.
- Git does not contain `wintun.dll`.

### Current behavior

- What you said
  - The Wintun sketch should be tried on the Windows machine.
  - The result belongs in the Windows agent, with the C kept out of the agent Vala.
  - The description belongs in a new report.
- Tool calls
  - Wrote `/tmp/argus-wintun-probe.c`, copied it to `snappr-win` with the official Wintun 0.14 amd64 DLL, and compiled it with `C:\msys64\ucrt64\bin\gcc.exe`.
  - Ran `C:\Users\Alan\argus-wintun-probe\argus-wintun-probe.exe`.
  - Removed that directory after the run.
- Observable product outcome
  - The Windows dial is `Adapter.connect`. TermService is addressed as `10.200.0.1`.
  - Packaging copies `wintun.dll` into the installer stage when `dist-windows/wintun/wintun.dll` is missing.

### Codebase observed behavior

- [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala) `open_windows` dials port 3389 with `SocketClient.connect_to_host`. On Windows the host is `desktop_address`. Loopback is refused. `plain` is a `SocketConnection`.
- [`agent/windows/Service.vala`](../../agent/windows/Service.vala) holds that tunnel and does not open a network adapter.
- [`win32/meson.build`](../../win32/meson.build) builds C that is linked into the Windows agent and is not agent product code. [`win32/register-pipe.c`](../../win32/register-pipe.c) `argus_end_rdp_sessions` is the existing pattern. [`win32/win32.vapi`](../../win32/win32.vapi) declares it in namespace `Win32`.

### Debugging

#### Current debug output

- Throwaway on `snappr-win`, 2026-11-26. One exe. Adapter and driver removed afterward. The directory is gone.
  ```text
  address status 0
  route status 0
  neighbor status 0
  adapter open
  control connected from 10.200.0.2:57041
  control rdp (19) 03 00 00 13 0e d0 00 00 12 34 00 02 1f 08 00 02 00 00 00
  recv icmp type 0 code 0
  send tcp flags 0x02 seq 268435456 ack 0 len 0
  recv tcp flags 0x12 seq 2153120773 ack 268435457 len 0
  recv tcp flags 0x18 seq 2153120774 ack 268435476 len 19
  tcp3389 remote 10.200.0.1:51422 state 5
  tcp3389 remote 192.168.88.132:51982 state 5
  tunnel rdp (19) 03 00 00 13 0e d0 00 00 12 34 00 02 1f 08 00 02 00 00 00
  exit 0
  ```
  - Windows listed the injected connection as established from `10.200.0.1:51422`.
  - TermService's 19-byte answer matched a normal socket to `10.200.0.2:3389`.
  - That normal socket's source was `10.200.0.2`, an address on this PC.
  - The already open session from `192.168.88.132:51982` stayed established.
  - No logon was sent.

#### Debug code added (remove when complete)

None.

### Proposed fix

The proof connected once and stopped. This plan keeps that connection open and gives it to the tunnel that already copies bytes.

The name in the product is the virtual adapter. `Tunnel` stays the relay byte pipe.

### ✔️ Phase 1 — Vala owns the adapter

- Why
  - TermService has to list the peer as `10.200.0.1`.
  - A normal socket to `10.200.0.2` is sourced from this PC. The probe's control socket was `10.200.0.2`.
  - The order of calls is the product logic. That order is Vala.
  - Each vapi entry is one hook. Load a library, resolve one export, or write one IP row.
- Where
  - [`agent/windows/Adapter.vala`](../../agent/windows/Adapter.vala), class `Argus.Agent.Rdp.Adapter`. Windows sources only, in [`agent/meson.build`](../../agent/meson.build).
  - Wintun delegates, `LoadLibraryW`, and `GetProcAddress` in [`win32/win32.vapi`](../../win32/win32.vapi).
  - Three IP-row hooks in [`win32/adapter-row.c`](../../win32/adapter-row.c), declared in that vapi. [`agent/meson.build`](../../agent/meson.build) links `iphlpapi`.
  - [`agent/windows/Service.vala`](../../agent/windows/Service.vala) does not gain this code.
- What
  - `Adapter.ensure` loads `wintun.dll` from the exe directory, creates `ArgusWintun0`, calls the three row hooks, and starts the session.
  - The adapter stays up for the process. A later `connect` does not create a second one.
  - `connect` listens on loopback with `GLib.SocketListener` and returns that `SocketConnection`.
  - `splice` is the probe's IPv4 TCP, as methods on this class. Source `10.200.0.1`, destination `10.200.0.2:3389`. It runs on a thread for the life of the accepted socket.
  - No `WintunDeleteDriver`. The probe called it because that process was about to exit.

#### Add — `win32/win32.vapi`, next to `argus_end_rdp_sessions`

```vala
	[CCode (cname = "LoadLibraryW", cheader_filename = "win32.h")]
	public void* LoadLibraryW (string16 path);
	[CCode (cname = "GetProcAddress", cheader_filename = "win32.h")]
	public void* GetProcAddress (void* module, string name);
	[CCode (cname = "GetModuleFileNameW", cheader_filename = "win32.h")]
	public uint32 GetModuleFileNameW (void* module, uint16[] filename, uint32 size);
	[CCode (cname = "GetLastError", cheader_filename = "win32.h")]
	public uint32 GetLastError ();
	[CCode (cname = "ERROR_OBJECT_ALREADY_EXISTS", cheader_filename = "win32.h")]
	public const uint32 ERROR_OBJECT_ALREADY_EXISTS;

	[CCode (has_target = false)]
	public delegate void* WintunCreateAdapter (string16 name, string16 tunnel_type, void* guid);
	[CCode (has_target = false)]
	public delegate void* WintunOpenAdapter (string16 name);
	[CCode (has_target = false)]
	public delegate void WintunCloseAdapter (void* adapter);
	[CCode (has_target = false)]
	public delegate void WintunGetLuid (void* adapter, out uint64 luid);
	[CCode (has_target = false)]
	public delegate void* WintunStartSession (void* adapter, uint32 capacity);
	[CCode (has_target = false)]
	public delegate void* WintunReceive (void* session, out uint32 size);
	[CCode (has_target = false)]
	public delegate void WintunRelease (void* session, void* packet);
	[CCode (has_target = false)]
	public delegate void* WintunAllocSend (void* session, uint32 size);
	[CCode (has_target = false)]
	public delegate void WintunSend (void* session, void* packet);
	[CCode (has_target = false)]
	public delegate void* WintunWait (void* session);

	[CCode (cheader_filename = "adapter-row.h")]
	public uint32 argus_adapter_address (uint64 luid, string ip, uint8 prefix);
	[CCode (cheader_filename = "adapter-row.h")]
	public uint32 argus_adapter_route (uint64 luid, string ip);
	[CCode (cheader_filename = "adapter-row.h")]
	public uint32 argus_adapter_neighbor (uint64 luid, string ip);
```

#### Add — `win32/adapter-row.h`

```c
#include <stdint.h>
uint32_t argus_adapter_address(uint64_t luid, const char *ip, uint8_t prefix);
uint32_t argus_adapter_route(uint64_t luid, const char *ip);
uint32_t argus_adapter_neighbor(uint64_t luid, const char *ip);
```

#### Add — `win32/adapter-row.c`

Each function fills one Windows row and returns the status. Vala decides what the status means.

```c
uint32_t argus_adapter_address(uint64_t luid, const char *ip, uint8_t prefix)
{
	MIB_UNICASTIPADDRESS_ROW row;
	IN_ADDR addr;
	NET_LUID id;

	InitializeUnicastIpAddressEntry(&row);
	if (InetPtonA(AF_INET, ip, &addr) != 1) {
		return ERROR_INVALID_PARAMETER;
	}
	memcpy(&id, &luid, sizeof(id));
	row.InterfaceLuid = id;
	row.Address.Ipv4.sin_family = AF_INET;
	row.Address.Ipv4.sin_addr = addr;
	row.OnLinkPrefixLength = prefix;
	row.DadState = IpDadStatePreferred;
	return CreateUnicastIpAddressEntry(&row);
}
```

`argus_adapter_route` does the same for `CreateIpForwardEntry2` with destination `ip` as a /32. `argus_adapter_neighbor` does the same for `CreateIpNetEntry2`, state reachable, for that same `ip`.

#### Add — `agent/windows/Adapter.vala`

```vala
namespace Argus.Agent.Rdp
{
	public class Adapter : GLib.Object
	{
		private void* module;
		private void* wintun_adapter;
		private void* session;
		private Win32.WintunCreateAdapter create_adapter;
		private Win32.WintunOpenAdapter open_adapter;
		private Win32.WintunCloseAdapter close_adapter;
		private Win32.WintunGetLuid get_luid;
		private Win32.WintunStartSession start_session;
		private Win32.WintunReceive receive_packet;
		private Win32.WintunRelease release_packet;
		private Win32.WintunAllocSend alloc_send;
		private Win32.WintunSend send_packet;
		private Win32.WintunWait wait_event;

		public GLib.SocketConnection connect() throws GLib.Error
		{
			this.ensure();
			var listener = new GLib.SocketListener();
			GLib.SocketAddress? bound = null;
			listener.add_address(
				new GLib.InetSocketAddress(
					new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0),
				GLib.SocketType.STREAM,
				GLib.SocketProtocol.TCP,
				null,
				out bound);
			var inet = (GLib.InetSocketAddress) bound;
			var client = new GLib.SocketClient();
			var local = client.connect_to_host("127.0.0.1", inet.get_port());
			var accepted = listener.accept();
			listener.close();
			new GLib.Thread<int>("adapter", () => {
				this.splice(accepted);
				return 0;
			});
			return local;
		}

		private void ensure() throws GLib.Error
		{
			uint32 status;
			uint64 luid = 0;
			if (this.session != null) {
				return;
			}
			this.load();
			var leftover = this.open_adapter("ArgusWintun0");
			if (leftover != null) {
				this.close_adapter(leftover);
				GLib.Thread.usleep(300000);
			}
			this.wintun_adapter = this.create_adapter("ArgusWintun0", "ArgusTunnel", null);
			if (this.wintun_adapter == null) {
				throw new GLib.IOError.FAILED("create adapter failed");
			}
			this.get_luid(this.wintun_adapter, out luid);
			status = Win32.argus_adapter_address(luid, "10.200.0.2", 32);
			if (status != 0 && status != Win32.ERROR_OBJECT_ALREADY_EXISTS) {
				throw new GLib.IOError.FAILED(@"address status $status");
			}
			status = Win32.argus_adapter_route(luid, "10.200.0.1");
			if (status != 0 && status != Win32.ERROR_OBJECT_ALREADY_EXISTS) {
				throw new GLib.IOError.FAILED(@"route status $status");
			}
			status = Win32.argus_adapter_neighbor(luid, "10.200.0.1");
			if (status != 0 && status != Win32.ERROR_OBJECT_ALREADY_EXISTS) {
				throw new GLib.IOError.FAILED(@"neighbor status $status");
			}
			this.session = this.start_session(this.wintun_adapter, 0x400000);
			if (this.session == null) {
				throw new GLib.IOError.FAILED("start session failed");
			}
		}
	}
}
```

`load` resolves each `Wintun*` delegate with `GetProcAddress`. `splice` is the probe's send and receive, calling `alloc_send`, `send_packet`, `receive_packet`, and `release_packet`. A close of the socket returned by `connect` ends that TCP connection.

#### Add — `win32/meson.build`, in `win32_c_sources`

```meson
	'adapter-row.c',
```

#### Add — `agent/meson.build`, Windows `sources`, and with the other `find_library` lines

```meson
		'windows/Adapter.vala',
```

```meson
	deps += meson.get_compiler('c').find_library('iphlpapi')
```

- Not in this phase
  - [`agent/windows/Service.vala`](../../agent/windows/Service.vala).
  - lwIP. The probe already spoke TCP. A second stack is a later change if this stream cannot carry a desktop.
  - The relay, the viewer, and the tray.

### ✔️ Phase 2 — The Windows dial uses that socket

- Why
  - Three places in [`agent/Rdp/Tunnel.vala`](../../agent/Rdp/Tunnel.vala) call `connect_to_host` for port 3389. On Windows each one has to be a new virtual-adapter connection.
  - The Linux relay test compiles this file without `WINDOWS`. That path still dials `127.0.0.1`.
- Where
  - `open_windows`, `handle_stream`, and `reopen`'s follow-up dial.
- What
  - One new method, `dial_desktop`, because those three sites share it. The plan asks for that method.
  - On Windows it calls `Adapter.connect`. That returns the loopback `SocketConnection`.
  - `argus_end_rdp_sessions` stays where it already is. This plan does not change who is logged off.
  - [`agent/windows/Service.vala`](../../agent/windows/Service.vala) is unchanged.

#### Add — `agent/Rdp/Tunnel.vala`, next to `open_windows`

```vala
#if WINDOWS
		private Adapter adapter;
#endif

		private GLib.SocketConnection dial_desktop() throws GLib.Error
		{
#if WINDOWS
			if (this.adapter == null) {
				this.adapter = new Adapter();
			}
			return this.adapter.connect();
#else
			return this.dial.connect_to_host(this.windows_host, 3389);
#endif
		}
```

#### Replace — `agent/Rdp/Tunnel.vala`, `open_windows` doc and dial

The rest of `open_windows` stays, from the nodelay `try` through the desktop thread.

```vala
		/**
		 * Dial Windows and join the server as ''agent''.
		 *
		 * The app connection is not this socket. ''Relay.write''
		 * carries bytes read from the desktop. ''relay.data'' is
		 * written back. On Windows that socket is the local end
		 * of the virtual adapter. TermService sees 10.200.0.1.
		 * An existing Remote Desktop session is logged off first.
		 *
		 * @param rpc the agent's second connection
		 */
		public void open_windows(OLLMrpc.Transport.TlsClient rpc) throws GLib.Error
		{
			this.dial = new GLib.SocketClient();
			this.dial.timeout = 10;
#if WINDOWS
			Win32.argus_end_rdp_sessions();
#else
			this.windows_host = "127.0.0.1";
#endif
			this.plain = this.dial_desktop();
			this.plain.socket.timeout = 0;
```

#### Replace — `agent/Rdp/Tunnel.vala`, the redial after a short read

```vala
#if WINDOWS
						Win32.argus_end_rdp_sessions();
#endif
						this.plain = this.dial_desktop();
						this.plain.socket.timeout = 0;
```

#### Replace — `agent/Rdp/Tunnel.vala`, the fresh-cut dial

```vala
					this.plain = this.dial_desktop();
					this.plain.socket.timeout = 0;
```

### ✔️ Phase 3 — Install `wintun.dll` from the package step

- Why
  - The DLL is loaded by name from the exe directory. It is not a link dependency, so [`scripts/ci/copy-windows-runtime.sh`](../../scripts/ci/copy-windows-runtime.sh) will not see it.
  - [`packaging/windows/argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi) already copies the staged directory.
  - The DLL is not a file in this repo. `dist-windows/` is gitignored. That is the download cache.
- Where
  - [`scripts/ci/windows-package-nsis.sh`](../../scripts/ci/windows-package-nsis.sh), after the stage directory is created and before `makensis`.
- What
  - If `dist-windows/wintun/wintun.dll` is already there and not empty, use it.
  - If it is missing, download `https://www.wintun.net/builds/wintun-0.14.1.zip` and take `wintun/bin/amd64/wintun.dll`. The site rejects a bare curl client, so the request sends an agent string.
  - Copy that file to `dist-windows/Argus/wintun.dll`. Refuse to package when the file is still missing.

#### Add — `scripts/ci/windows-package-nsis.sh`, after `mkdir -p "${stage}"`

```bash
wintun_cache="${out_dir}/wintun/wintun.dll"
wintun_url="https://www.wintun.net/builds/wintun-0.14.1.zip"
if [[ ! -s "${wintun_cache}" ]]; then
	mkdir -p "$(dirname "${wintun_cache}")"
	wintun_tmp="$(mktemp -d)"
	curl -fsSL -A "Argus" -o "${wintun_tmp}/wintun.zip" "${wintun_url}"
	unzip -p "${wintun_tmp}/wintun.zip" wintun/bin/amd64/wintun.dll > "${wintun_cache}"
	rm -rf "${wintun_tmp}"
fi
if [[ ! -s "${wintun_cache}" ]]; then
	echo "wintun.dll is not available" >&2
	exit 1
fi
cp -f "${wintun_cache}" "${stage}/wintun.dll"
```

### LLM

- ℹ️ Split out of `2026-11-17-remote-desktop.md`. That report keeps the viewer, the relay, and the session behavior.
- ℹ️ Throwaway source was `/tmp/argus-wintun-probe.c`. It is not in the tree. Wintun 0.14. The send path is `WintunAllocateSendPacket` then `WintunSendPacket`. The LUID export is `WintunGetAdapterLUID`.
- ℹ️ The inbound Remote Desktop firewall rules were already enabled on that PC. A closed firewall group is not part of this evidence.
- 🚫 A kernel `connect` to `10.200.0.2` or to `desktop_address`. The probe's control socket came from `10.200.0.2`.
- 🚫 The 4-byte frame from the sketch. TermService answered real IPv4 TCP.
- 🚫 Putting the adapter in [`agent/windows/Service.vala`](../../agent/windows/Service.vala).
- 🚫 A C file that loads Wintun, orders the setup, or speaks TCP. That sequence is [`agent/windows/Adapter.vala`](../../agent/windows/Adapter.vala).
- 🚫 Naming a new `Tunnel` class. That name is the relay pipe.
- 🚫 Committing `wintun.dll`. Packaging downloads it into `dist-windows/wintun/` when that cache is empty, then copies it into the installer stage.
- 🚫 Treating the 19-byte negotiation answer as a desktop that stayed on screen.
- ✔️ Product code is in the tree. This report stays active until a Windows run confirms it.
- ℹ️ `load` resolves the Wintun exports. `splice` is the probe TCP kept open, copying both ways until the loopback socket closes.
- ℹ️ `connect` accepts on a thread before the loopback dial. `connect_to_host` blocks until `accept`, so the fence order deadlocks.
- ℹ️ `argus_adapter_read`, `argus_adapter_write`, and `argus_adapter_move` copy packet bytes. Wintun returns a pointer Vala cannot index.
- ℹ️ `GetModuleFileNameW`, `GetLastError`, and `WaitForSingleObject` were already in `win32.vapi`. `ERROR_NO_MORE_ITEMS` was not.
- ℹ️ The agent links `ws2_32` because `InetPtonA` lives there.
- ℹ️ `Adapter.connect` is marked `new`. That name hides `GLib.Object.connect`.
- ℹ️ `valac` typechecked `Adapter.vala`. `x86_64-w64-mingw32-gcc` compiled `adapter-row.c`. The Windows agent was not linked here.
- ℹ️ The blank header is a namespace `const`, outside the class. `agent/linux/Adapter.vala` is the same two methods with no desktop behind them, so `Tunnel` has no `#if WINDOWS`. The relay test still dials the desk from `Tunnel.run`.
- ℹ️ The Wintun delegate types live in `win32.h`. A vapi delegate does not emit a C typedef, and the Windows compile stopped on those names.
- ℹ️ 0.1.57 reached "The desktop data is coming through" and then sent nothing back. TermService stayed established from `10.200.0.1:51422` and retransmitted one 59-byte segment. The captured segment was `10.200.0.1.768 > 10.200.0.2.19` with TCP header length 0. The desktop bytes were copied at offset 20, which is the TCP header. The handshake has no payload, so it still completed. Payload now starts at offset 40.
