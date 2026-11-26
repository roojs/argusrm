# The controller does not see the registration broadcast over the VPN

**Status:** ✅ closed 2026-11-26 — `shared/TunnelScan.vala`, `shared/RegisterWindow.vala`: when a tunnel is up, probe the /24 for the registration port in parallel with mDNS (0.1.56). No Avahi/mDNS change on the VPN.

### User decisions required

None.

### User reported

- 🔷 From the Argus Controller on this desktop, the server did not show up by itself over the VPN.
- 🔷 The registration command on the server listed the tunnel, so the broadcast was on the tunnel.
- 🔷 The broadcast should have been picked up on the controller.
- 🔷 Research said a broadcast over the VPN does not work, and that is not certain.
- 🔷 The original design was the OLLMchat broadcast, and that used to arrive over a VPN.
- 🔷 No broadcast is arriving.
- 🔷 If the controller sees it is on a VPN, probably because `tun0` is up, it scans that network's 255 addresses.
- 🔷 It pings them very quickly and finds any that are up.
- 🔷 While it is doing that, it tells the user: I've got a VPN. Seeing if I can find any servers.
- 🔷 If it then connects to the standard port and gets an answer, it says: I've got an Argus server around here. Do you want to connect to it?
- 🔷 The user presses Connect, then types the number.

### Success scenario

- `tun0` up is enough for the controller to decide it is on a VPN.
- It tells the user: I've got a VPN. Seeing if I can find any servers.
- It pings the 255 addresses on that network quickly and keeps the ones that are up.
- It tries the standard registration port on those machines.
- An answer shows: I've got an Argus server around here. Do you want to connect to it?
- Connect asks for the number. The user types it. No address is typed.

### Current behavior

- What you said
  - The server does not appear on its own over the VPN.
  - The registration command lists the tunnel.
  - Nothing from that publish is arriving at the controller.
- Registration command on the server, 2026-11-25, PIN `613224`
  - `Broadcast on:` listed `eth0 192.168.254.88` and `tun0 10.9.188.77`.
- Controller on this desktop, same minute
  - Browse for `_rpc._tcp` ran.
  - The cache completed.
  - No service was resolved.
  - The address was typed after that.

### Codebase observed behavior

- Registration publish uses the OLLMchat type [`OLLMchat/libocrpc/Transport/PairPublish.vala`](../../../OLLMchat/libocrpc/Transport/PairPublish.vala) `start`.
- That call is Avahi on interface `UNSPEC`, service `_rpc._tcp`, plus one A record per address passed in.
- [`server/Offering/Network.vala`](../../server/Offering/Network.vala) `update_pin` passes every up non-loopback IPv4 from [`OLLMchat/libocrpc/Transport/TcpListen.vala`](../../../OLLMchat/libocrpc/Transport/TcpListen.vala) `ifaces` when the listen host is `0.0.0.0`.
- `Broadcast on` is those addresses with interface names. It is printed by [`controller/cli/Pin.vala`](../../controller/cli/Pin.vala) from the `Offering.open` reply. It does not record that a packet left the machine.
- The controller listens with [`shared/Browse.vala`](../../shared/Browse.vala) `start` for `_rpc._tcp` and a TXT `id`.

### Debugging

#### Current debug output

- `~/.cache/argusrm/controller.log`, 2026-11-25, controller `0.1.54`, before the address was typed.

```text
18:18:45.822552: G_LOG_LEVEL_DEBUG : Browse.vala:69: browsing _rpc._tcp
18:18:45.824992: G_LOG_LEVEL_DEBUG : Browse.vala:146: browse client running
18:18:45.825372: G_LOG_LEVEL_DEBUG : Browse.vala:173: browse client running
18:18:45.835780: G_LOG_LEVEL_DEBUG : Browse.vala:131: browse cache complete
```

- No `service`, `resolved`, or `broadcast` line follows that cache line.

#### Debug code added (remove when complete)

- None.

### Proposed fix

- Leave the VPN alone. The shout does not cross it.
- When `tun0` is up, the controller says: I've got a VPN. Seeing if I can find any servers.
- It pings the 255 addresses on that network quickly.
- On each address that is up, it tries the standard registration port.
- An answer says: I've got an Argus server around here. Do you want to connect to it?
- Connect goes to the number. The user types the number.

### LLM

- ℹ️ The unseen broadcast was written into `2026-11-24-FIXED-vpn-registration-stops-after-number.md`. The change applied there is the registration reply after the number. This file is only the missing publish.
- ✔️ 2026-11-26: Product fix is tunnel scan + registration dialog UI, not multicast on `tun0`. Ping step dropped; TCP connect to `Argus.REGISTER_PORT` on the tunnel /24 every twenty seconds while the connect dialog is open.
- 💩 A note in that report said a tunnel usually cannot carry a local-network shout, so the shout still leaves on `eth0` with the tunnel address named inside it. That was not measured. The user says the OLLMchat publish of this same class used to arrive over a VPN.
- 🚫 Do not treat `Broadcast on: tun0 10.9.188.77` as proof the packets left `tun0`, and do not treat it as proof they cannot.
- ℹ️ `ifaces` keeps every up IPv4 except `0.0.0.0` and `127.0.0.1`. It does not drop a tunnel. `tun0` was in the command output, so that address was in the list given to `PairPublish.start`.
- ℹ️ Product files: `server/Offering/Network.vala`, `shared/Browse.vala`, `controller/cli/Pin.vala`. Publish implementation: `OLLMchat/libocrpc/Transport/PairPublish.vala`, `OLLMchat/libocrpc/Transport/TcpListen.vala`.
- ℹ️ 2026-11-25 research. The library is Avahi. `PairPublish` talks to `avahi-daemon` and asks for interface `UNSPEC`, service `_rpc._tcp`, UDP port 5353, group `224.0.0.251`. The daemon chooses the interfaces.
- ℹ️ Avahi `allow-point-to-point` defaults to `no`. A `tun` interface is point-to-point, so the daemon ignores it unless that option is `yes`. It also requires the multicast flag. `ip link set dev tun0 multicast on` was required in one report before the daemon noticed the interface. Man page: https://manpages.opensuse.org/Tumbleweed/avahi/avahi-daemon.conf.5.en.html
- ℹ️ OpenVPN's own getting-started page says the usual setup is `dev tun`, and a TUN device passes TCP/IP and does not provide broadcast traffic. https://community.openvpn.net/Pages/Getting%20started%20with%20OpenVPN
- ℹ️ OpenVPN maintainers on ticket 513: Bonjour is link-local multicast, and the server has no code that handles it. They describe that as not handling it. https://community.openvpn.net/openvpn/ticket/513
- ℹ️ TAP can carry the Ethernet frames. OpenVPN still has no IGMP routing. Ticket 79 says multicast is forwarded on TAP by treating it as a broadcast to every client. https://community.openvpn.net/openvpn/ticket/79
- ℹ️ People who crossed a TUN with Avahi set `allow-point-to-point=yes` and `enable-reflector=yes` on both ends. That still fails when the tunnel does not forward `224.0.0.251`. A working WireGuard case also put that group in the peer allow list. https://github.com/avahi/avahi/issues/262
- ℹ️ OLLMchat using this same class can arrive over a VPN only when that VPN already delivers the multicast, or when `avahi-daemon` is already reflecting onto an interface it is willing to use. This tree does not change the daemon configuration.
