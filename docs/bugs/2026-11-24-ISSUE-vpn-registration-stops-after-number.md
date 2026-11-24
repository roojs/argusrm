# Registration over the VPN asks for the number, then stops

**Status:** ⏳

### User decisions required

- None.

### User reported

- 🔷 From the Argus Controller on this desktop, the server did not show up by itself over the VPN.
- 🔷 Typing the address made the window ask for the number, so the desktop had reached the server.
- 🔷 Something went wrong after the number.
- 🔷 If the desktop is coming in over the VPN, the server can see that address. That address should be allowed. It is not clear what the public-address lookup has to do with that.
- 🔷 The broadcast should have been picked up on the controller. If that does not happen, typing the address should at least finish registration.
- 🔷 The registration command on the server listed the tunnel, so the broadcast was on the tunnel.
- 🔷 Stay on the controller and the server. Leave the agent out of this.

### Success scenario

- The controller on the VPN sees the server from the broadcast, without typing an address.
- If the broadcast is not seen, typing the address and the six-digit number still finishes registration.

### Current behavior

- What you said
  - The server did not appear on its own over the VPN.
  - Typing the address got as far as the six-digit number.
  - Registration did not finish after that.
- What the registration command printed
  - The number was `121465`.
  - It listed `eth0 192.168.254.88` and `tun0 10.9.188.77`.
- What the server log shows
  - The server issued a number and opened registration for the controller.
  - The controller reached that port. The window asking for the number matches that check.
  - The controller then sent the number.
  - The server refused it. A controller for login `alan` on `alan-office-desktop` is already saved.
  - The desktop showed that same sentence.
  - The server closed the connection and stayed up. It did not save a second controller, and it did not allow a new address.

### Codebase observed behavior

- The public-address lookup is the server asking the internet for its own public address after the number is already issued. The controller’s VPN address is not part of that lookup. [`server/Agent.vala`](../../server/Agent.vala) `offer`
- The controller’s connection carries the controller’s address. If the server accepts the number, it saves that address with this controller. [`server/Agent.vala`](../../server/Agent.vala) `request_registration`
- After a successful save, the server allows that address on the normal management port when it has a route back to it. A VPN address qualifies when the server is on that VPN. [`server/Agent.vala`](../../server/Agent.vala) `allowlist` and [`server/Net/Interfaces.vala`](../../server/Net/Interfaces.vala) `route`
- While the number is valid, registration is open. After a successful registration it closes again. The controller’s address is not added to that temporary opening.

```vala
listen.pin = "";
listen.accepting = false;
this.app.publish.stop();
this.app.register_firewall.enable();
this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
```

- Those lines did not run for this attempt. Turning the registration lock back on logs `firewall enforced on port 819`. Updating the allowed list logs a firewall line for port 817. Neither line is in the log after the number arrived.

### Debugging

#### Current debug output

- `argusrm-controller-cli` on the server, same attempt, pasted from `root@argusrm`.

```text
Registration PIN: 121465
Registration is open for 60 seconds. Press Ctrl+C to close it early.
Broadcast on:
eth0 192.168.254.88
tun0 10.9.188.77
```

- “Broadcast on” is the list of addresses handed to the broadcaster. `tun0` is in that list. The line does not show that the controller received it.
- Server log pasted from `root@argusrm`, 2026-11-24, controller `0.1.45`.

```text
17:01:59.567482: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=1 method=RPC-Daemon.hello conn=0x55f79a354ab0
17:01:59.567570: G_LOG_LEVEL_DEBUG : Daemon.vala:67: hello argus-controller 1 0.1.45
17:01:59.567869: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=2 method=Agent.offer conn=0x55f79a354ab0
17:01:59.568024: G_LOG_LEVEL_DEBUG : SslListen.vala:261: SSL listening on 0.0.0.0:819
17:01:59.568149: G_LOG_LEVEL_DEBUG : Agent.vala:425: publishing 192.168.254.88 10.9.188.77 port 819
17:01:59.572016: G_LOG_LEVEL_DEBUG : NFTables.vala:266: firewall open on port 819
17:01:59.581798: G_LOG_LEVEL_WARNING : Agent.vala:532: Unacceptable TLS certificate
17:02:21.487882: G_LOG_LEVEL_WARNING : SslListen.vala:192: ssl handshake failed: Peer failed to perform TLS handshake: The TLS connection was non-properly terminated.
17:02:27.940715: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=0 method=Agent.request_registration conn=0x55f79a2767e0
17:02:28.041906: G_LOG_LEVEL_WARNING : Connection.vala:381: Unexpected early end-of-stream
```

- The certificate warning is the public-address lookup failing. The number was already issued.
- The handshake line is the desktop checking that the port is open, then closing. That is why the window asked for the number.
- The number arrived. Nothing after that shows the controller being saved.
- The server then crashed while closing that connection. `$rbx` is still `0x5555556f5e20`, but that memory is no longer a connection. It has been freed and reused. The controller record read from it is the smashed pointer.
- Server log pasted from `root@argusrm`, 2026-11-24, after the close fix, controller `0.1.46`. The server was restarted under gdb because the binary had changed. It did not crash.

```text
18:19:06.228096: G_LOG_LEVEL_DEBUG : Daemon.vala:67: hello argus-controller 1 0.1.46
18:19:06.228684: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=2 method=Agent.offer conn=0x55555575a080
18:19:06.228964: G_LOG_LEVEL_DEBUG : SslListen.vala:261: SSL listening on 0.0.0.0:819
18:19:06.229164: G_LOG_LEVEL_DEBUG : Agent.vala:442: publishing 192.168.254.88 10.9.188.77 port 819
18:19:06.237436: G_LOG_LEVEL_DEBUG : NFTables.vala:266: firewall open on port 819
18:19:06.248206: G_LOG_LEVEL_WARNING : Agent.vala:549: Unacceptable TLS certificate
18:19:53.061687: G_LOG_LEVEL_WARNING : SslListen.vala:192: ssl handshake failed: Peer failed to perform TLS handshake: The TLS connection was non-properly terminated.
18:19:57.141883: G_LOG_LEVEL_DEBUG : Connection.vala:389: recv id=0 method=Agent.request_registration conn=0x555555f8c720
18:19:57.142515: G_LOG_LEVEL_WARNING : Agent.vala:151: This machine is already registered. alan alan-office-desktop
18:19:57.244546: G_LOG_LEVEL_WARNING : Connection.vala:381: Unexpected early end-of-stream
18:19:57.244620: G_LOG_LEVEL_DEBUG : SslConnection.vala:143: closing connection 0
```

- The desktop said this machine is already registered. That is the sentence the server sent.
- `closing connection 0` is the registration connection. It had no saved id. The server stayed up.

#### Debug code added (remove when complete)

- [`shared/Register.vala`](../../shared/Register.vala) keeps the server’s refusal and shows it on the controller. The installed server already sends that sentence. Rebuild the controller here and register again. The window says the reason. The server package does not need to change for that.
- [`server/Agent.vala`](../../server/Agent.vala) writes the same reason into the server log. That part waits until the next server package.

### Proposed fix

#### ✔️ `server/Agent.vala` — a matching number replaces the saved controller

**Why:** The number was accepted. The server then refused because a controller for that login and machine name was already saved. The typed-number window has no way past that sentence, so registration cannot finish.

The matching number removes that saved row, closes a live connection for it, and saves the new certificate. The log says `replaced registration` with the login and machine name.

#### ✔️ `server/Net/SslConnection.vala` — keep the connection alive until close finishes

**Why:** The registration connection was freed during `base.stop()` while `stop()` was still reading the controller record. The next read crashed. A reference taken at the start of `stop()` keeps that memory alive until the method returns. A second close during that work returns.

#### Replace with — `stop`

```vala
public override void stop()
{
	if (this.closing) {
		GLib.warning("connection close already in progress");
		return;
	}
	this.closing = true;
	this.ref();
	var user_id = this.user.id;
	var controller = this.user.is_controller;
	var tell = this.running && user_id > 0;
	GLib.debug("closing connection %s", user_id.to_string());
	if (tell) {
		var rows = new Gee.ArrayList<Argus.Shared.Agent>();
		var int_binds = new Gee.HashMap<string, int>();
		var text_binds = new Gee.HashMap<string, string>();
		int_binds.set("id", (int) user_id);
		Argus.Shared.Agent.query(this.app.db).selectWhere(
			"WHERE id = $id", int_binds, text_binds, rows);
		if (rows.size > 0) {
			rows.get(0).last_connected = new GLib.DateTime.now_utc().to_unix();
			Argus.Shared.Agent.query(this.app.db).updateById(rows.get(0));
		}
	}
	if (tell && !controller) {
		new Argus.Server.SQT.Task.for_rpc(this.app).connection_lost(user_id);
	}
	base.stop();
	if (tell) {
		this.app.broadcast(new OLLMrpc.Notification() {
			method = "event.agent",
			action = "disconnected"
		});
	}
	var listen = this.get_data<SslListen>("argus-listen");
	if (listen == null) {
		this.unref();
		return;
	}
	listen.connections.remove(this);
	if (user_id < 1 || listen.by_id.get((int) user_id) != this) {
		this.unref();
		return;
	}
	listen.by_id.unset((int) user_id);
	this.unref();
}
```

### LLM

- ℹ️ Scope is the controller and the server. The agent hint at the bottom of the CLI paste is left out of the report.
- 💩 “Broadcast on: tun0” means that address was included in what the server handed to the broadcaster (`controller/cli/Pin.vala` prints reply entries after the public address). It does not mean a shout left `tun0` and arrived at the controller. The broadcaster shouts on interfaces that can carry a local-network shout. A tunnel usually cannot, so the shout still goes out on `eth0`, with the tunnel address named inside it. The controller at the far end of the VPN does not hear that.
- 🚫 The server did not omit `tun0`. The command listed it.
- ℹ️ ✔️ Controller keeps `response.error.message` in `Register.detail` instead of replacing it with “Registration failed”. Server `request_registration` warnings name the refusal. Early returns used to be silent.
- ✔️ 2026-11-24 18:19: the number was accepted. The server refused a second controller for `alan` on `alan-office-desktop`. The desktop showed that sentence. `closing connection 0` ran and the process stayed up. A wrong number would have logged `number rejected`. A sign failure would have logged `could not sign`. Neither did.
- ℹ️ The check was an active controller (`status` 1) with the same `is_controller`, username, and hostname. It does not look at the VPN address. The desktop had no next step. Local login can offer re-register. The typed-number window only showed the sentence.
- ✔️ A matching number now removes that saved controller and finishes the new registration. The server log says `replaced registration` with the login and machine name. `Registration.certificate` on the local socket still refuses a second certificate.
- 🚫 ifconfig.me is not the peer address and not the allowlist. `Agent.vala` `offer` resolves it only to fill the public address in the offer reply. The warning at `Agent.vala:532` is `e.message` from that HTTPS fetch (`remote-connectable` to `34.160.111.145:443`).
- 🚫 Do not treat “firewall cut the reply” as this failure. `register_firewall.enable()` logs `firewall enforced on port 819`. `firewall.apply` logs an allowlist line for port 817. Neither appears after `Agent.request_registration`. The success block in `request_registration` did not run.
- ℹ️ Those warnings are on the refusal itself: number rejected, registration closed, already registered (with login and machine name), bad certificate request, could not sign.
- ℹ️ 2026-11-24 gdb: `$rbx` `0x5555556f5e20` matches the registration connection, but `x/32gx $rbx` starts with a zero class pointer and glibc chunk sizes (`0x21`, `0x31`, `0x51`) plus the bytes `ng=01;35`. Use after free inside `SslConnection.stop` after `base.stop()`, at the second `user.id` read before `by_id.get`. `$r12` `0x55555568d5b0` still looks like the listener. `$rax` `0x99e309bc0e9ac53c`.
- ℹ️ `allowlist` keeps `agent.ip` only when `Interfaces.route` finds a local source. The registration peer is stored as `ip` only on the success path.
- ℹ️ Registration port 819 stays an empty allowlist. `disable` opens it for the number. `enable` closes it to everyone. The desktop’s VPN address is a candidate for port 817 only, and only after a successful save.
- ℹ️ Broadcast addresses in the log are the server’s own: `192.168.254.88` and `10.9.188.77`. They are not the desktop’s source address.
- ℹ️ Product files: `server/Agent.vala`, `server/Net/Interfaces.vala`, `server/Net/NFTables.vala`, `shared/Register.vala`.
