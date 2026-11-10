# Local login is refused by the port firewall

**Status:** ✅ closed 2026-11-10. Local login is allowed through the port firewall.

**Pointer:** `docs/bug-fix-process.md`

ℹ️ [6.1](../plans/6.1-nftables-firewall.md) — the firewall blocks every source except addresses stored on a registered row. A private address and a public address are the same case.

---

## Problem

- 🔷 The firewall blocks every incoming source except the listed addresses.
- 🔷 Registering is what puts a source address on that list.
- 🔷 Local login registered, then the window said the saved server did not answer.
- 🔷 The allowlist includes this machine's own addresses. No controller row is consulted.

## Evidence

- ✔️ `argusrm-server.service` started at 11:26:58 and logged `SSL listening on 0.0.0.0:817`.
- ✔️ At 11:27:22 the log shows `Registration.certificate` for `argus-controller`. The local login itself succeeded.
- ✔️ The window then probes port 817 at `192.168.88.132`, `10.0.3.1`, `192.168.122.1`, `10.9.188.9`, `172.17.0.1`, and `172.18.0.1`. Each connect is refused. `127.0.0.1:818` on the same process accepts.
- ✔️ `Agent.request_registration` reads the TCP peer, stores it on the row with status 1, then calls `firewall.apply()`. That is the whitelist.
- ✔️ `Registration.certificate` is the local login. It inserts the controller with status 0 and no `ip`, and it does not call `firewall.apply()`.
- ✔️ `Agent.allowlist` reads `SELECT DISTINCT ip FROM agent WHERE status = 1 AND ip != ''`. The local row matches neither part.

## Root cause

- ✔️ The firewall is doing what it is for. This machine's source address was never listed.
- ✔️ The whitelist is filled only when registration arrives over TCP. Local login arrives on the Unix socket, so that step never runs.
- ✔️ The controller then connects over TCP from this machine and is refused like any other unlisted source.

## Ruled out

- 🚫 The server failed to start.
- 🚫 The certificate command failed.
- 🚫 Limiting the rule to addresses that look public.
  - The rule stays on every interface.
  - A container's reachable address is often in `10.*` or `192.168.*`.
- 🚫 A separate loopback check. Add every address on this machine.
- 🚫 Looking for `is_controller = 1` and a blank `ip` before adding those addresses.
- 🚫 Refreshing the firewall from `Registration.certificate`. Startup already applies the allowlist.
- 🚫 A new static method for the test. The checks stay in `main`.
- 🚫 Writing the result to the terminal. The server records `GLib.debug`, `GLib.warning`, and `GLib.critical` through its log handler. This change adds no log line.

## Proposed fix

- 🔷 `Agent.allowlist` adds every address on this machine after the registered source addresses.
- 🔷 Registered rows are unchanged. A remote machine is still listed only after it registers.

### 1. `server/Agent.vala` — `allowlist()`: add this machine

**Why:** This machine is always a permitted source. The registered rows do not have to record it.

**Where:** `allowlist`, the docblock and the body, before the return.

**Depends on:** none

#### Remove

```vala
		/**
		 * Registered addresses this machine can reach.
		 *
		 * Distinct active ''agent.ip'' values are parsed, then kept
		 * when {@link Net.Interfaces.route} returns a source. A private
		 * route counts. No route leaves the address out. Invalid stored
		 * text is logged and left out.
		 * {@link Net.NFTables.apply} receives only these addresses.
		 *
		 * @param db agent table
		 * @param interfaces local addresses and routes
		 * @return the IPv4 and IPv6 allowlist
		 */
		public static Gee.ArrayList<GLib.InetAddress> allowlist(SQ.Database db, Net.Interfaces interfaces)
		{
			var kept = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
			var query = Argus.Shared.Agent.query(db);
			foreach (var text in query.fetchAllString(query.selectPrepare(
				"SELECT DISTINCT ip FROM agent WHERE status = 1 AND ip != ''"))) {
				var address = new GLib.InetAddress.from_string(text);
				if (address == null) {
					GLib.warning("stored address is not an IP: %s", text);
					continue;
				}
				var source = interfaces.route(address);
				if (source == null) {
					continue;
				}
				kept.add(address);
			}
			return kept;
		}
```

#### Replace with

```vala
		/**
		 * Registered source addresses, plus every address on this machine.
		 *
		 * Active ''agent.ip'' values are kept when
		 * {@link Net.Interfaces.route} returns a source. A private
		 * route counts. This machine's own addresses are added after
		 * that. {@link Net.NFTables.apply} receives only these
		 * addresses.
		 *
		 * @param db agent table
		 * @param interfaces local addresses and routes
		 * @return the IPv4 and IPv6 allowlist
		 */
		public static Gee.ArrayList<GLib.InetAddress> allowlist(SQ.Database db, Net.Interfaces interfaces)
		{
			var kept = new Gee.ArrayList<GLib.InetAddress>((a, b) => {
				return a.equal(b);
			});
			var query = Argus.Shared.Agent.query(db);
			foreach (var text in query.fetchAllString(query.selectPrepare(
				"SELECT DISTINCT ip FROM agent WHERE status = 1 AND ip != ''"))) {
				var address = new GLib.InetAddress.from_string(text);
				if (address == null) {
					GLib.warning("stored address is not an IP: %s", text);
					continue;
				}
				var source = interfaces.route(address);
				if (source == null) {
					continue;
				}
				kept.add(address);
			}
			foreach (var item in interfaces.addresses) {
				if (kept.contains(item.address)) {
					continue;
				}
				kept.add(item.address);
			}
			return kept;
		}
```

### 2. `server/tests/allowlist.vala` — `main()`: this machine is always listed

**Why:** The empty table used to produce an empty allowlist. It now contains this machine. The size check has to count those addresses. Both checks stay in `main`.

**Where:** `main`, the empty-table check, and the final size check.

**Depends on:** section 1

#### Remove

```vala
			note(Agent.allowlist(db, interfaces).size == 0, "empty table", "");
```

#### Replace with

```vala
			var empty = Agent.allowlist(db, interfaces);
			if (empty.size != interfaces.addresses.size) {
				failures++;
			}
```

#### Remove

```vala
			note(list.size == included, "allowlist size matches routed addresses", list.size.to_string());
```

#### Replace with

```vala
			var extras = 0;
			foreach (var item in interfaces.addresses) {
				var seen = false;
				foreach (var text in probes) {
					var probe = new GLib.InetAddress.from_string(text);
					if (probe != null && probe.equal(item.address) &&
						interfaces.route(probe) != null) {
						seen = true;
					}
				}
				if (!seen) {
					extras++;
				}
			}
			if (list.size != included + extras) {
				failures++;
			}
```

## Next

- ✅ Closed. Sections 1–2 are in the tree. Local login opens the window.
