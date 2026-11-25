# Provisional registration broadcast for office Windows bulk enroll

**Status:** ⏳

**Priority:** High — confirmed for next Windows office rollout.

### User decisions required

None.

### User reported

- 🔷 Bundle provisional broadcast, controller Agents UI, Windows desk enroll, and Linux bulk into one feature (prior chat).
- 🔷 **Reject / status poll** on registration port (~10 min client poll); **Accept** keeps registration port open until the machine finishes full registration on the app socket; ~30 min without upgrade → warn; app-level banner when some registrations failed to complete.
- 🔷 **Pending registration** tab: hide when empty; select by default when pending exist; emphasize (e.g. red) when the queue is non-empty.
- 🔷 **[`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala)** — PIN + countdown only for **Agent registration** and **Controller registration**; no pending list and no bulk inside the dialog.
- 🔷 Product spec in **Proposed fix** phases only.
- 🔷 **RPC:** Registration moves to **`Offering.*`** on the wire — **no** **`Agent.offer`** forwarders or backward compatibility.

### Success scenario

- Field verify: each phase’s **Done when** bullets pass on a lab controller, Linux agent, and Windows install.

### Current behavior

- [`controller/tab/Agent.vala`](../../controller/tab/Agent.vala) — one **Agent or Controller** button → [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala).
- [`server/Agent.vala`](../../server/Agent.vala) — **`Agent.stop`** deletes all **`agent_pending`**; batch queue only via pin **`0000`** + batch flag.
- [`agent/Win32/tray/Tray.vala`](../../agent/Win32/tray/Tray.vala) + [`shared/Register.vala`](../../shared/Register.vala) — unregistered tray opens dialog and browses **`_rpc._tcp`**, but user must type PIN manually; no provisional vs instant on the wire.
- [`shared/Register.vala`](../../shared/Register.vala) **`try_batch`** — polls the **app** socket with **`RPC-Daemon.hello`** (not registration port).
- [`server/Agent.vala`](../../server/Agent.vala) **`reject`** — deletes **`agent_pending`** only; client not informed.

### Codebase observed behavior

- [`controller/tab/Assets.vala`](../../controller/tab/Assets.vala) — **ViewSwitcher** + **ViewStack** (**Machines** / **Software**).
- [`controller/tab/Pairing.vala`](../../controller/tab/Pairing.vala) — tick list (today inside Register dialog).
- [`shared/Browse.vala`](../../shared/Browse.vala), [`shared/windows/Browse.vala`](../../shared/windows/Browse.vala) — mDNS browse.
- [`docs/rpc-commands.md`](../../docs/rpc-commands.md) — today **`Agent.offer`**, **`request_registration`**, **`accept`**, **`reject`**, **`stop`** (→ **`Offering.*`** in this feature).

### Debugging

#### Current debug output

None yet.

#### Debug code added (remove when complete)

None.

### Proposed fix

#### Phase 1 — Server: second Avahi publish + registration lifecycle

**Where it lives today (Phase 1 touchpoints)**

- **Single registration story on the server**
  - [`server/Agent.vala`](../../server/Agent.vala) — all RPC: **`offer`**, **`stop`**, **`request_registration`**, **`accept`**, **`reject`** (registered in **`rpc_register`** ~L43–54).
  - [`server/Application.vala`](../../server/Application.vala) — **`register_listen`** (`SslListen` with **`registration = true`**, endpoint **`registration`**), **`ssl_listen`** (app / management port), **`publish`** (`PairPublish`), **`register_firewall`** (`NFTables` on **`Argus.REGISTER_PORT`**).
  - [`docs/rpc-commands.md`](../../docs/rpc-commands.md) — contract for the above (today **`stop`** wipes **`agent_pending`**).
- **Offer + broadcast (one mode)**
  - **`Agent.offer`** (~L387): random six-digit **`listen.pin`**, **`register_listen.listen()`**, **`publish.start(addrs, register_port)`**, **`register_firewall.disable()`**, 60s timeout, **`publish.stop()`** on close.
  - `libocrpc/Transport/PairPublish.vala` (OLLMchat dependency) — one **`_rpc._tcp`** service; TXT **`id`** is a persisted **server UUID**, not the six-digit PIN.
- **Enroll decision**
  - **`request_registration`** (~L94): **`queued`** = batch + pin **`0000`** + **`!is_controller`** + (**`listen.pin`** or **`listen.accepting`**).
  - Matching PIN → immediate **`agent`** row + firewall + download listen; **`0000`** batch → **`agent_pending`** + **`msg` `pending`** + **`event.pair`**; wrong pin → **`number rejected`**.
  - No “provisional PIN enroll” path; no block on **controller** using agent PIN when window is open.
- **Pending persistence**
  - [`shared/AgentPending.vala`](../../shared/AgentPending.vala) — table **`agent_pending`**; no server **`list`** RPC — controller learns pending rows only via **`event.pair` `pending`** ([`controller/store/Pairing.vala`](../../controller/store/Pairing.vala), [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala)).
- **TLS gates**
  - [`server/Net/SslListen.vala`](../../server/Net/SslListen.vala) — registration listener: handshake without client cert only while **`pin != ""`** or **`accepting`** (~L176–181).
  - [`server/Net/SslConnection.vala`](../../server/Net/SslConnection.vala) — **`allow_request`**: only **`Agent.request_registration`** without approved **`agent`** row; **`agent_pending`** fingerprints are invisible (no status RPC exists).
- **Client enroll + wrong post-pending poll**
  - [`shared/Register.vala`](../../shared/Register.vala) — **`try_connection`** → TLS registration port → **`Agent.request_registration`**; **`try_batch`** / **`--request`** (Linux) polls **app** port with **`RPC-Daemon.hello`** (~L665+), not registration port.
  - [`shared/Browse.vala`](../../shared/Browse.vala), [`shared/windows/Browse.vala`](../../shared/windows/Browse.vala) — browse **`_rpc._tcp`**; find server by UUID TXT, then user types PIN (no PIN on wire in mDNS today).
  - [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala) — **`AgentService.register`**; tray [`agent/Win32/tray/Tray.vala`](../../agent/Win32/tray/Tray.vala) → [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala).
- **Controller today**
  - [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala) — **`Agent.offer`** + PIN UI + embeds pending list; **`Agent.stop`** on close.
  - [`controller/cli/Pin.vala`](../../controller/cli/Pin.vala) — CLI **`Agent.offer`**.

**Design gaps (underlying registration flow — Phase 1 must address)**

- **One `offer` + one publish** — instant active agent and batch queue share the same pin/broadcast/socket; provisional bulk needs a **second publish** and separate server mode without reusing **`stop`** semantics.
- **PIN is not on mDNS** — TXT **`id`** is server UUID; six-digit PIN exists only on controller dialog / memory (**`listen.pin`**). Auto-enroll from browse needs browse/client + server enrol changes (Phase 3–4); **`PairPublish`** in libocrpc stays as-is unless a **separate** decision extends Avahi there.
- **Pending cert has no server-side lifecycle** — **`agent_pending`** is insert/delete only; **reject** does not answer clients; **accept** promotes to **`agent`** but clients poll the **wrong socket** (**`hello`** on app port fails **`allow_request`**).
- **Registration TLS is window-gated** — after **`offer`** ends, **`register_listen.stop()`** and **`pin == ""`** → no handshake for status polls; conflicts with “keep registration port open until client is active”.
- **`Agent.stop` conflates teardown + queue wipe** — bulk close, dialog **X**, and instant offer end all delete **`agent_pending`** (~L776).
- **Controller gate missing** — **`is_controller`** is allowed through the same PIN path as agents; only duplicate-row check for active controllers.

**Phase 1 refactor — `server/Offering/` (encapsulate before or with provisional work)**

- **Design rule (this report)**
  - **Do not add Vala types** under **`Offering`** unless you **explicitly approve** the class name in chat. **Approved:** **Rpc**, **Network**, **Certificate**. **Rejected:** **`Offering.Enroll`**, **`EnrollDone`**, nested bags without sign-off. DB helpers → **`SQT.Agent`** when that file lands.
  - **`Argus.Server.SQT.Agent`** (fleet **`list`** / **`remove`** + **`allowlist`**) — sign-off stub below with **Offering** stubs.
  - **`PairPublish`** lives on **`Offering.Network`** (not **`Application.publish`**). Prose says **PairPublish** / **mDNS** — not “publish” as a generic noun. **No** edits to **`libocrpc/Transport/PairPublish.vala`** unless you ask. **No** extra Vala types (e.g. **`Offering.Publish`**) without approval.

- **Name**
  - **Offering** — network registration window (PIN, broadcast, registration TLS, pending queue, accept/reject), distinct from [`server/Registration.vala`](../../server/Registration.vala) (local Unix-socket controller cert) and from **`Agent`** (registered fleet CRUD).
  - Follow existing pattern: [`server/Rdp/`](../../server/Rdp/) subfolder + `Argus.Server.Rdp` namespace.
- **Layout** (`server/meson.build`)

```text
server/Offering/
  namespace.vala
  Network.vala      →  registration desk
  Certificate.vala  →  CSR signing
  Rpc.vala          →  OLLMrpc class Offering
```

- **No `Offering.Session`.** No **`Offering.Publish`**. **No `Offering.Firewall`** — **`Network.firewall`** is the offering-port **`NFTables`** (not named **`register_firewall`** on **`Network`**).
- [`Application`](../../server/Application.vala) drops **`publish`**; **`Offering.Network`** owns **`PairPublish`**, registration **`SslListen`** (was **`register_listen`**), and registration-port firewall. **`Offering.Rpc`** on Application as before.
- **Vala types in this sign-off (pending your approval)**
  - **`Network`**, **`Rpc`** (+ `namespace.vala`).
  - **Rejected / removed from report:** **`Session`**, **`Publish`**, **`Enroll`**, **`EnrollDone`**.
  - **Wire names and methods** in the stubs below are proposals — not new classes.

- **RPC wire rename (no backward compatibility)** — wire surface below; fleet **`Agent.list`** / **`Agent.remove`** unchanged.

```vala
// was Agent.offer (PIN) and new bulk window — one RPC, bool pending
	OLLMrpc.Request.add_class("Offering", typeof(Rpc),
		"open", "b",    // pending false = six-digit PIN; true = bulk / agent_pending
		"close", "b",   // same flag: which window; bulk close keeps agent_pending rows
		"enroll", "...",
		"status", "",
		"accept", "ai",
		"reject", "ai");
// was Agent.request_registration → Offering.enroll
// was Agent.stop → Offering.close (bulk close does not wipe agent_pending)
```

- Same change updates [`docs/rpc-commands.md`](../../docs/rpc-commands.md), [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala), [`controller/cli/Pin.vala`](../../controller/cli/Pin.vala), [`shared/Register.vala`](../../shared/Register.vala), [`server/Net/SslConnection.vala`](../../server/Net/SslConnection.vala) (`Offering.enroll` / `Offering.status` allowlist), server tests.

**Sign-off — class method map (from → to)**

- **Stubs below are API shape only.** Phase 1a/1 **implementation** must follow [`docs/coding-standards.md`](../../docs/coding-standards.md) — especially **`brace-placement`** (class/method braces on their own lines) and **`line-length-breaking`** (no gratuitous one-arg-per-line wraps; no space before **`(`** on definitions or calls; match surrounding files). Do **not** copy stub formatting literally into product code.

```vala
// Application.vala — owning field + quit teardown (firewall.apply/enable stay in command_line)
	public class Application
	{
		public Offering.Network offering_network { get; private set; }
		public Offering.Rpc offering_rpc { get; private set; }
		// on_quit: offering_network.update_pin(CLOSED); pair_publish.stop(); firewall.enable()
	}
```

```vala
// Offering.Network — desk (tree today still has legacy open/close → listen only)
	public enum DeskState {
		OPEN,     // listener, pair_publish, firewall disable, pin or accepting
		ARM,      // PIN: 60s expiry; both kinds: disconnect poll
		POLLING,  // mDNS off; listener may stay up; polling=true
		CLOSED,   // desk fully down
	}

	public class Network : GLib.Object
	{
		public Application app { get; private set; }
		public Net.SslListen listen { get; private set; }
		public Net.NFTables firewall { get; private set; }

		public OLLMrpc.Transport.PairPublish pair_publish {
			get; set; default = new OLLMrpc.Transport.PairPublish() {
				min_port = 1
			};
		}

		public string endpoint { get; set; }
		public bool pending { get; internal set; default = false; }
		public bool polling { get; set; default = false; }
		public string pin { get; set; }
		public bool accepting { get; set; }

		// Rpc sets before ARM; timers use .running — not passed into update_*
		public weak OLLMrpc.Connection? supervising_connection { get; set; }

		construct {
			pair_publish.failed.connect(() => {
				GLib.warning("Could not publish the pairing service");
			});
		}

		public Network(Application app);

		// PIN dialog lines — filled on OPEN only; iface + IPv4 from endpoint/mDNS addrs
		public string[] open_lines { get; private set; }

		public bool update_listener(bool up);
		// Registration TLS bind only — listen.listen() / listen.stop().
		// Does not touch pair_publish, firewall, pin, accepting, polling.
		// Rpc does not call this; update_pin / update_bulk do.

		public bool update_pin(DeskState state);
		public bool update_bulk(DeskState state);
		// OPEN → update_listener(true); pair_publish; firewall disable; pin or accepting
		// OPEN false = listener did not bind. update_pin sets open_lines.
		// ARM → timers. PIN CLOSED → flags, pair_publish off, firewall on, update_listener(false)
		// BULK POLLING → mDNS off, polling=true; listener stays up (no update_listener(false))
	}
```

```vala
// Offering.Rpc — wire + request.reply; enroll policy lives here
	public class Rpc : GLib.Object
	{
		public Application app { get; private set; }
		public Network network { get; private set; }

		public Rpc.for_rpc(Application app, Network network);

		public static void register();

		public void open(OLLMrpc.Request request, bool pending);
		public void close(OLLMrpc.Request request, bool pending);

		public void enroll(OLLMrpc.Request request, ...);
		// pin/window, new Certificate(app, csr), DB, desk

		private void enroll_success(
			OLLMrpc.Request request,
			Certificate signed,
			string family,
			Argus.Shared.AgentPending? pending_row,
			Argus.Shared.Agent? agent_row);
		// family: wire only (osquery path). Exactly one of pending_row / agent_row.

		public void status(OLLMrpc.Request request);
		public void accept(OLLMrpc.Request request, int[] ids);
		public void reject(OLLMrpc.Request request, int[] ids);
	}
```

```vala
// Offering.Certificate — one CSR in; signed fields out as properties
	public class Certificate : GLib.Object
	{
		public string csr { get; private set; }
		public string crt_pem { get; private set; }
		public string fingerprint { get; private set; }
		public string ca_pem { get; private set; }
		public bool bad_csr { get; private set; }

		public Certificate(Application app, string csr);
	}
```

```vala
// Offering.Network — public IPv4 only; Rpc builds retval as + reply
	public async string lookup_ip(GLib.Cancellable? cancel = null);
```

```vala
// Argus.Server.SQT.Agent — NOT IN TREE YET (still server/Agent.vala for list/remove/allowlist)
	public class Agent : Argus.Shared.Agent
	{
		public static Gee.ArrayList<InetAddress> allowlist(
			SQ.Database db, Net.Interfaces interfaces);

		public Gee.ArrayList<Argus.Shared.Agent> find_active_controller(
			SQ.Database db, string username, string hostname);

		public int64 insert_pending(SQ.Database db, AgentPending row);
		public int insert_active(SQ.Database db, Argus.Shared.Agent row);
		// accept/reject pending: used from Offering.Rpc.accept / reject (or static here)
	}
```

Out-of-band [`Network.vala`](../../server/Offering/Network.vala), [`Certificate.vala`](../../server/Offering/Certificate.vala), [`Rpc.vala`](../../server/Offering/Rpc.vala): **`enroll`** + **`certificate.sign_csr`** + **`enroll_success`** (no extra types). Not in **`server/meson.build`** yet.

```vala
// server/SQT/Agent.vala — fleet list/remove + allowlist (replaces server/Agent.vala)
	public class Agent : Argus.Shared.Agent
	{
		public Application app { get; private set; }
		public Agent()
		{
			Object();
		}
		public Agent.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}
		public static new void rpc_register()
		{
			Argus.Shared.Agent.rpc_register();
			OLLMrpc.Request.add_class(
				"Agent", typeof(Agent),
				"list", "i",
				"remove", "i");
		}
		public void list(OLLMrpc.Request request, int agent_id);
		public void remove(OLLMrpc.Request request, int id);
		public static Gee.ArrayList<GLib.InetAddress> allowlist(
			SQ.Database db, Net.Interfaces interfaces);
	}
```

- **`SQT.Agent.list`:** `agent_id` &lt; 1 → all rows; else one row; set **`connected`** from **`ssl_listen.by_id`**; reply **`o`** array of **`Argus.Shared.Agent`**.
- **`SQT.Agent.remove`:** controller only; delete row; **`agent.removed`**; **`firewall.apply(allowlist(...))`**.
- **`SQT.Agent.allowlist`:** active **`agent.ip`** + **`Interfaces.route`** filter + local addresses; not RPC.

```vala
// server/SQT/namespace.vala
	public static void rpc_register()
	{
		// ... existing ...
		Agent.rpc_register();
	}
	public static void register(Application app)
	{
		// ... existing ...
		OLLMrpc.Request.register("Agent", new Agent.for_rpc(app));
	}
```

- **`server/meson.build`:** add **`SQT/Agent.vala`**; remove **`Agent.vala`**. **`docs/meson.build`** valadoc list too.
- **Wire (unchanged for fleet):** **`Agent.list`** `i` **`agent_id`**; **`Agent.remove`** `i` **`id`**. Docs stay in [`docs/rpc-commands.md`](../../docs/rpc-commands.md) — only ℹ️ path becomes **`server/SQT/Agent.vala`**.

- **Two different “Agent” types (not the same thing)**
  - [`shared/Agent.vala`](../../shared/Agent.vala) **`Argus.Shared.Agent`** — one **row** in SQLite table **`agent`**. **`query(db)`**, **`init_db`**, wire serialization **`Argus.Agent`** in **`Agent.list`** replies. **Unchanged** in this feature.
  - [`server/Agent.vala`](../../server/Agent.vala) **`Argus.Server.Agent`** — today a **800-line RPC blob** whose name collides with the shared row type. **Not** a DB wrapper. **Almost all of it leaves**; see table below.

- **`server/Agent.vala` — what leaves vs what might remain**

| Code in [`server/Agent.vala`](../../server/Agent.vala) today | After Phase 1 refactor |
| --- | --- |
| **`offer`**, **`stop`** | **`Offering.Rpc.open`**, **`close`** |
| **`request_registration`** (+ CSR signing helpers) | **`Offering.Rpc.enroll`** (helpers stay private on **`Offering.Rpc`** or a package-private Vala unit — **no new public class** without approval) |
| **`accept`**, **`reject`** | **`Offering.Rpc.accept`**, **`reject`** |
| **`list`**, **`remove`** | **`server/SQT/Agent.vala`** — same pattern as [`server/SQT/Task.vala`](../../server/SQT/Task.vala) / **`ScriptRepository`**: row in **shared**, RPC handler in **`Argus.Server.SQT`**. Wire stays **`Agent.list`** / **`Agent.remove`**. |
| **`allowlist(db, interfaces)`** | **`Argus.Server.SQT.Agent.allowlist`** — **not** an RPC; static on the same class as **`list`** / **`remove`** (data from table **`agent`** via **`Argus.Shared.Agent.query`**). |

  **SQT split (how the rest of the server already works)**

  | Layer | Today for **Task** | Target for **registered machines** |
  | --- | --- | --- |
  | Row + **`query(db)`** + bin **`Argus.*`** | [`shared/SQT/Task.vala`](../../shared/SQT/Task.vala) | [`shared/Agent.vala`](../../shared/Agent.vala) today (**`Argus.Shared.Agent`**, table **`agent`**). Optional later: move file to **`shared/SQT/Agent.vala`** — **separate approval**; not required for Phase 1a. |
  | Server RPC **`list`** / **`remove`** / … | [`server/SQT/Task.vala`](../../server/SQT/Task.vala) **`Task.for_rpc(app)`** | **New** [`server/SQT/Agent.vala`](../../server/SQT/Agent.vala) **`Agent.for_rpc(app)`** — **`list`**, **`remove`** in **`rpc_register`**; **`public static allowlist(db, interfaces)`** (moved unchanged from old [`server/Agent.vala`](../../server/Agent.vala)). |
  | **`Application` registration** | [`server/SQT/namespace.vala`](../../server/SQT/namespace.vala) **`SQT.register(app)`** | Add **`Agent`** there; remove **`OLLMrpc.Request.register("Agent", new Agent.for_rpc(this))`** from [`Application.command_line`](../../server/Application.vala). |
  | Delete | — | **[`server/Agent.vala`](../../server/Agent.vala) file removed** — no **`Argus.Server.Agent`** class left. |

  **Pairing / pending queue:** only **`Offering.Rpc`** + **`Offering.Network`**.

  **`SQT.Agent.allowlist` (app-port firewall IPs)**

  - Today: static on [`server/Agent.vala`](../../server/Agent.vala) ~L797 — misplaced next to pairing RPC.
  - **User decision:** lives on **[`server/SQT/Agent.vala`](../../server/SQT/Agent.vala)** with **`list`** / **`remove`**, because it only reads **`agent`** rows (active **`status = 1`**) via **`Argus.Shared.Agent.query`**, then filters with [`Net.Interfaces.route`](../../server/Net/Interfaces.vala) and adds this host’s addresses. Result goes to **`app.firewall.apply(...)`** — not registration nftables.
  - Call sites become **`Argus.Server.SQT.Agent.allowlist`** (or a **`using`** alias in server code). **`Net.NFTables`** stays the kernel side; it does not own the DB query.

  **Phase 1a (out-of-band):** land **`Offering.Network`** + **`Offering.Rpc`**; add **`server/SQT/Agent.vala`** (**`list`**, **`remove`**, **`allowlist`**); delete **`server/Agent.vala`**. Product behavior in Phase 1 proper. Class layout reviewed before merge.
  - ✔️ 2026-11-25: [`server/Offering/Network.vala`](../../server/Offering/Network.vala) + [`namespace.vala`](../../server/Offering/namespace.vala) — **not** in **`server/meson.build`** yet; review before wire-up. **`Network`** ctor parses **`Application.registration`**, sets **`listen`** + **`firewall`**; **`firewall.apply`** / **`enable`** stay on **`Application.command_line`** (no **`bootstrap_firewall`**).
  - ✔️ 2026-11-25: [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) — **`for_rpc(app, network)`**, wire **`Offering.*`**; uses **`network`** only for listen / PairPublish / offering firewall; **`status`** stub; **`Agent.allowlist`** until **`SQT.Agent`** lands.
  - **Out-of-band rule:** new **`Offering`** code calls **`Network`** / future **`Rpc`** APIs only — **no** adapters that forward to **`Application.register_listen`**, **`Application.publish`**, or **`Agent.offer`** while both exist.
- **Application vs Offering — what each listener is**

  The daemon is one process with **several doors**. Config lines under `/etc/argusrm/` are **`socket`**, **`download`**, **`register`** (each **`host:port`**). **`Application`** still owns process lifetime, config strings, DB, schedulers, and everything that is **not** the registration window.

| Piece on [`Application`](../../server/Application.vala) today | Port / path | Who connects | Stays on **`Application`** after refactor? |
| --- | --- | --- | --- |
| **`listen`** (`SocketListen`) | Unix **`…/argus.sock`** | Controller on same host (local); **`Agent.offer`**, **`Agent.list`**, **`Registration.*`**, most management RPC | **Yes** — local admin pipe; not part of **`Offering.Network`**. |
| **`ssl_listen`** (`Net.SslListen`, `registration = false`) | **App** port (`Argus.SOCKET_PORT` / `socket`) | Registered **controllers and agents** with a **issued client cert**; normal RPC (**`OSQuery`**, **`Command`**, **`RPC-Daemon.hello`**, …) | **Yes** — the long-lived **management** TLS socket. Binds at startup. Requires client certificate. |
| **`firewall`** (`Net.NFTables`) | rules for **app** port only | Kernel: who may reach **`ssl_listen`** | **Yes** — IPs from **`SQT.Agent.allowlist`** (was **`Agent.allowlist`** on old server class). **Not** the registration-port firewall. |
| **`download_listen`** (`Net.Download`) | **Download** port | Agents fetching osquery/debian payloads during/after enroll | **Yes** — separate HTTP-style downloader; unrelated to pairing UI. |
| **`registration`** (string) | — | Config only: **`host:port`** for registration TLS | **Yes** — still read in **`command_line`**; copied into **`Offering.Network.endpoint`**. |
| **`register_listen`** (`SslListen`, `registration = true`) | **Registration** port (`REGISTER_PORT` / `register`) | **Unregistered** machines during a pairing window (no client cert yet, or provisional cert for status); **`Agent.request_registration`**, future **`Offering.enroll`** / **`Offering.status`** | **Moves** → **`Offering.Network.listen`**. Usually **down** until **`Offering.open`**; may stay up with **`polling`** after bulk close. |
| **`register_firewall`** (`NFTables`) | rules for **registration** port | Kernel: wide open while **`disable()`** during offer; **locked** (empty allow) when window closed | **Moves** → **`Offering.Network.firewall`** (not named **`register_firewall`** on **`Network`**). |
| **`publish`** (`PairPublish`) | mDNS **`_rpc._tcp`** | LAN discovery: agents/controllers learn registration **host:port** | **Moves** → **`Offering.Network.pair_publish`**. Started/stopped by **`Offering.Rpc`**, not fields on **`Application`**. |

  Short version: **`Application`** = “always-on server” (app TLS, app firewall, download, Unix socket, database, broadcast to connected clients). **`Offering.Network`** = “registration desk” (registration TLS + registration nftables + mDNS while the desk is open).

- **Done when (refactor)**
  - Grep finds no **`Application.publish`**; **`Offering.Rpc`** drives **`offering_network.pair_publish`** like **`Agent.offer`** did.

**Phase 1 target changes**

- **PairPublish / mDNS**
  - Provisional bulk may use a **second `PairPublish`** on **`Offering.Network`** (product decision) — same libocrpc class, not a new Offering type.
- **Provisional enroll**
  - Bulk listener open → enrollments → **`agent_pending`** only, reply **`pending`**, **`event.pair` `pending`**.
  - **Close bulk listener:** **`pair_publish.stop()`** (and any second PairPublish) and stop new provisional enroll; **do not** delete **`agent_pending`** rows.
- **Instant agent enroll**
  - **Agent registration** dialog path: issued PIN → active **`agent`** immediately (unchanged intent).
- **Controller vs agent paths**
  - A **controller** must not register using an **agent** registration PIN or the **provisional bulk** listener.
  - Server refuses with a short plain **`error.message`** (e.g. “This registration is for agents only.”) — no controller row created.
- **Registration port stays open**
  - After an operator ticks a row and **Accept**, keep the **registration** TLS listener up until that client has **completed full registration** (status poll returns **`accepted`**, then client connects on the **app** socket and is **active** / connected).
  - Same port serves **pending** / **rejected** status polls for rows still in **`agent_pending`** or waiting after **Accept**.
  - Close bulk broadcast does **not** mean closing registration TLS while any pending row or any **Accept** awaiting client upgrade remains — keep **`Network.open`** with **`polling = true`** (no PIN, no PairPublish).
- **Pending status poll + reject** (replaces **`try_batch`** app **`hello`** loop)
  - Clients poll **registration** host/port (~**ten minutes**; poll soon after enroll).
  - Registration handshake accepts **provisional client certificates** for the status RPC.
  - New registration-socket RPC (document in [`docs/rpc-commands.md`](../../docs/rpc-commands.md) with the change):
    - **`pending`** — still in **`agent_pending`**.
    - **`accepted`** — promoted to **`agent`**; client should move to app socket.
    - **`rejected`** — row removed; client wipes cert and shows “last registration was rejected”.
- **Stalled after Accept**
  - When **Accept** runs, start a **~30 minute** watchdog per machine.
  - If the agent has not status-polled, upgraded, and shown **connected** on the app socket within that window → mark **failed to complete registration** (stalled).
  - Controller: row state or badge on **Pending registration** tab; drive app-level warning (Phase 2).
- **Done when**
  - **Accept** then inactive client for 30+ minutes surfaces stalled state; active client clears watchdog; **Reject** returns **`rejected`** on next poll.

#### Phase 2 — Controller Agents page

- **Tabs** ([`controller/tab/Assets.vala`](../../controller/tab/Assets.vala) pattern)
  - **Agents** — registered grid.
  - **Pending registration**
    - **Hidden** when **`agent_pending`** is empty and no stalled **Accept** awaiting client upgrade (exact visibility rule in implementation).
    - **Selected by default** when the tab becomes visible because new pending rows exist.
    - **Visible emphasis** when the queue is non-empty (e.g. red tab label or indicator).
    - Embed [`controller/tab/Pairing.vala`](../../controller/tab/Pairing.vala): tick, **Accept**, **Reject** on the page bar.
- **Page toolbar**
  - **Bulk registration** — start/stop provisional broadcast + banner on page (“close when finished”).
  - **Agent registration** — opens [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala) (**PIN + countdown** only).
  - **Controller registration** — same dialog pattern, controller PIN only; server blocks agent/bulk paths (Phase 1).
  - No pending list inside the dialog.
- **Application warning**
  - Banner at top of controller window when **any** registration **failed to complete** (stalled after **Accept**, or operator-facing summary of stalled set).
  - Copy along the lines of: some registrations did not finish — check **Pending registration**.
- **Done when**
  - Tab hide/show/select/red behavior; banner appears when a stalled **Accept** is present.

#### Phase 3 — Windows client (unregistered)

- **Install** → tray → immediate **Register** dialog + background browse (provisional + instant agent publish).
- **Auto-register** on broadcast hit (PIN from TXT) where applicable.
- **Provisional** → **`pending`** cert → registration-port status poll (~10 min) → **`accepted`** → app socket + connected; **`rejected`** → wipe cert, show **last registration was rejected**, hunt again.
- If browse sees both offers, use **first resolved** offer (simultaneous dual offer is out of scope).
- **Done when**
  - Bulk on → auto provisional enroll → **Accept** on controller → Windows client reaches connected without manual PIN entry.

#### Phase 4 — Linux and shared register client

- Provisional broadcast + registration-port status poll (same as Phase 1 / 3).
- **`rejected`** / stall behavior matches Windows.
- **Done when**
  - Linux host **Reject** → next poll clears cert; **Accept** → full agent within 30 min or controller shows stall warning.

#### Phase 5 — End-to-end verify

- Bulk on → two provisionals → bulk off → queue remains → **Accept** one / **Reject** one.
- **Accept** then power off VM → within ~30 min controller shows stalled registration + app banner.
- **Agent registration** dialog: PIN only, instant one agent.
- Controller cannot enroll via agent PIN or bulk listener (plain error on server).

### LLM

- ℹ️ 2026-11-24: **`PairPublish`** on **`Offering.Network`** (`pair_publish`); not **`Application.publish`**; avoid “publish” as a generic name.
- ℹ️ 2026-11-24: user called out invented **`Session`** — removed.
- ℹ️ 2026-11-24: **No RPC backward compatibility** — wire is **`Offering.*`** only; sign-off method map in Phase 1 refactor.
- ℹ️ 2026-11-25: **`Offering.open`** / **`Offering.close`** `b` **`pending`**; not separate **`open_agent`** / **`open_pending`** RPCs. **`Network.pending`** mirrors the last open.
- ℹ️ 2026-11-25: **`Agent.list`** / **`Agent.remove`** + static **`allowlist`** → **`server/SQT/Agent.vala`**; delete **`server/Agent.vala`**. No **`Net/Allowlist`**. Row stays **`shared/Agent.vala`** until optional move to **`shared/SQT/`**.
- ℹ️ 2026-11-25: sign-off Vala stubs are not style templates — implement per **`docs/coding-standards.md`** (no space before **`(`**, **`brace-placement`**, grouped call wraps).
- ℹ️ 2026-11-25: **`Offering.Network`** implemented out-of-band under **`server/Offering/`**; build unchanged until **`Application`** adopts **`offering_network`**.
- ℹ️ 2026-11-25: no legacy hooks — **`Offering.Rpc`** will call **`Network`** only, not **`app.publish`** / **`register_listen`**.
- ℹ️ 2026-11-25: **`Offering.Certificate`** approved (thin **`sign_csr`**); **`EnrollDone`** rejected.
- ℹ️ 2026-11-25: **`Rpc.enroll_success`** — **`Certificate`**, wire **`family`**, and **`AgentPending?`** / **`Agent?`** row (not loose id/ip/name/queued flags).
- ℹ️ 2026-11-25: **`Network.lookup_ip`** (async **string**); **`Rpc.open`** builds **`retval as`**.
- ℹ️ 2026-11-25: **`server/SQT/Agent.vala`** — plan only; fleet DB helpers + **`allowlist`**; not created yet.
- ℹ️ 2026-11-25: **`update_pin`** / **`update_bulk(DeskState)`**; **`update_listener(bool)`**; **`lookup_ip`** on **`Network`**.
- ℹ️ 2026-11-24: Phase 1 **code map** + **design gaps** for “where are the bits” / registration-flow debt.
- ℹ️ 2026-11-24: user decisions closed — high priority; second Avahi publish; tab **Pending registration**; Pairing PIN-only; registration port until client active; 30 min stall + app banner.
- ℹ️ Removed opaque “CSR” wording; controller-on-agent-path = plain **error.message**.
- ℹ️ `docs/bug-fix-process.md`, `docs/guide-to-writing-bug-reports.md`.