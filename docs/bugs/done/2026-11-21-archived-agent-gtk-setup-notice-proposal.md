# ARCHIVED — Linux agent GTK setup notice (long proposal)

**Do not implement from this file.** Closed: [2026-11-21-FIXED-agent-gtk-notice.md](2026-11-21-FIXED-agent-gtk-notice.md). Kept for Phase 1–4 Vala fences and changelog only.

**Status:** 📦 archived 2026-11-21

**Scope:** Linux desktop agent (`argusrm-agent-gtk`). **Not** Windows tray.

**Pointers:** [`docs/plans/2.6.1-management-client-link-spec.md`](../plans/2.6.1-management-client-link-spec.md), [`agent/Connection.vala`](../../agent/Connection.vala), [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala), [`docs/bugs/done/2026-11-09-FIXED-agent-running-dialog.md`](done/2026-11-09-FIXED-agent-running-dialog.md)

---

## Problem

- 🔷 The running **Notice** always offers **Close** and **Restart** even when the header already has an **X**.
- 🔷 “Configured” follows `client.pem` on disk, not the saved `server` row that [`Connection`](../../agent/Connection.vala) loads in **checking_config**.
- 🔷 **Restart** appears while the link is still retrying with matching versions. Restart does not fix reachability.
- 🔷 Co-located **argusrm-server** should offer **Connect locally** when a local server is up — implementation waits on [done/2026-11-21-FIXED-local-agent-registration-certificate.md](done/2026-11-21-FIXED-local-agent-registration-certificate.md) (not batch PIN, not management-port probe alone).

---

## Root cause

- ✔️ Browse, loopback probe, address polling, and enroll today live in [`RegisterWindow`](../../shared/RegisterWindow.vala). The Gtk window owns the registration connection machine.
- ✔️ [`Application.registration()`](../../agent/linux/Application.vala) only calls D-Bus **status()** and tests **`client.pem`**. It does not read the saved server row or link outcome.
- ℹ️ Management hello and version compare already live on [`Connection`](../../agent/Connection.vala). The notice must not open a second hello or duplicate `order > 0` logic.

---

## Desired notice behaviour

| State | Body (typical) | Actions |
| --- | --- | --- |
| No saved server row | No management server is configured. | **Configure**; **Connect locally** when loopback registration accepts TCP |
| Saved row, service **CONNECTED** | Connected to the management server. | Header **X** only |
| Saved row, service **STOPPED** | Agent service is not running. | **Restart** (agent service) |
| Saved row, **RUNNING**, link says client newer (`order > 0`) | Not connected (link `failure_detail` when surfaced) | **Restart** only |
| Saved row, **RUNNING**, otherwise | Not connected to the management server. | **Retry**, **Reconfigure**, **Connect locally** when loopback registration is up |

- **Retry** and **Restart** both call `ServiceManager.restart()`. The label reflects intent.
- **Configure**, **Reconfigure**, and **Connect locally** open [`RegisterWindow`](../../shared/RegisterWindow.vala) on the same shared [`Register`](../../shared/Register.vala) instance.

---

## What moves out of `RegisterWindow` (bulk of the change)

This is not a thin Gtk tweak. Most of the registration flow code **leaves the window**.

- ✔️ **Remove** the window’s `Browse` instance, `browse_id`, `poll_id`, `poll_token`, `found`, `by_address`, and field `server_id` used only for the connection flow.
- ✔️ **Remove** the whole method [`on_wait`](../../shared/RegisterWindow.vala) (~lines 374–429). That is the **20 s** timer that TCP-probes a typed `host:port` until the **registration port** accepts a connection.
- ✔️ **Remove** from [`show_add`](../../shared/RegisterWindow.vala) the idle callback and nested **200 ms** timeout that call `browse.start()` and `browse.poll()` (~lines 490–549). That loop is mDNS discovery, not a new invented name.
- ✔️ **Keep** in the window: widgets, PIN entry, `use_pipe` / Windows `send_pin`, `certificate_received`, and layout. The window **listens** to `Register` properties and updates labels and visibility.

**Land in** [`Register.vala`](../../shared/Register.vala):

- The mDNS poll loop (today inside `show_add`).
- The TCP probe loop (today `on_wait`).
- Co-located server detection for the notice **Connect locally** button (mechanism in [done/2026-11-21-FIXED-local-agent-registration-certificate.md](done/2026-11-21-FIXED-local-agent-registration-certificate.md) — not registration-port probe alone).
- Properties the UI binds: `phase`, `host`, `port`, `hostport` (combined getter/setter), `server_id`, `detail`.
- Methods: `start_browse()`, `connect(host, port)`, `stop()`, `submit_pin(pin)` (async enroll via existing `try_connection`).
- Signal `enrolled` when `try_connection` succeeds.

**Do not add:**

- 🚫 `set_phase()` — assign `this.phase` and `this.detail` inline where the state changes.
- 🚫 `connect_local()` — **Connect locally** calls `connect("127.0.0.1", (uint16) Argus.REGISTER_PORT)` at the call site.

**Private methods:** `on_mdns_poll` (mDNS **200 ms** `Timeout` from `show_add`). `probe` (the **20 s** `Timeout` callback; moved from the window’s `on_wait` — not a GObject signal handler). `on_probe_complete` (`connect_to_host_async` finished).

---

## Phases

- ⏳ 🔷 **Phase 1 — Link mirror for the notice.** `client_newer` on [`Connection`](../../agent/Connection.vala), set when hello has `order > 0`. D-Bus mirror from `--service`, same pattern as `status()`.
- ⏳ 🔷 **Phase 2 — `Register` owns registration connection state.** Move browse poll and address probe from `RegisterWindow`. Drop trivial helpers above.
- ⏳ 🔷 **Phase 3 — Thin `RegisterWindow`.** Construct with a shared `Register`. `notify::phase` / `notify::detail` → sync widgets. Delete removed fields and handlers listed above.
- ⏳ 🔷 **Phase 4 — Gtk notice.** [`Application.registration()`](../../agent/linux/Application.vala) reads saved server row, D-Bus link fields, and `Register.local_registration`. Button set per table. No sockets in `registration()`.

🚫 Do not reimplement management hello outside `Connection`. 🚫 Do not put browse or probe logic in `Application.registration()`.

ℹ️ Proposed Vala fences follow [`docs/coding-standards.md`](../../docs/coding-standards.md):

- **Shared `Register` on the window** — one constructor like today: `public RegisterWindow () { Object (); … }`. `reg` is `{ get; construct; default = new Register (); }`. Gtk passes the notice’s shared instance with `new RegisterWindow (reg: reg) { … }` — **not** a second ctor or `: this (new Register ())` chain.
- **Call-site GObject properties:** `new Type (ctor_args) { prop = value, … }` — not ctor args plus separate assignment lines for the same props.
- **Notice `responded`:** `switch (response)`, not `if` chains (`switch-case`).
- **Async paths only:** no `{ prop = … }` on `new`; assign on the lines after `new` (`gobject-construct-blocks`).

```vala
// Good — same single constructor as today
public RegisterWindow ()
{
    Object ();
    // … widget build …
}

// Good — Gtk shares one Register from registration()
var window = new Argus.Shared.RegisterWindow (reg: reg) {
    data_dir = this.data_dir,
    client_db = this.client_db,
    title = "Argus Remote Management Agent " + Argus.VERSION
};

// Good — tray / bootstrap unchanged (default reg)
var window = new Argus.Shared.RegisterWindow () {
    data_dir = this.data_dir
};

// Good — Register fields on a GObject
var reg = new Argus.Shared.Register () {
    data_dir = this.data_dir,
    client_db = this.client_db
};

// Bad — chained ctor
public RegisterWindow () : this (new Register ())
{
}
```

---

## Phase 1 — Link mirror for the notice

Set true in hello when `order > 0`. Clear on successful connect and when entering retry. Expose on D-Bus from `--service` for the notice.

#### Add in [`agent/Connection.vala`](../../agent/Connection.vala)

```vala
		internal bool client_newer { get; private set; default = false; }
```

Wire in hello when `order > 0`, and mirror `client_newer()` on D-Bus (same pattern as `status()`).

---

## Phase 2 — `Register` owns registration connection state

Existing `try_connection`, `save`, `remove`, and deregister signals stay for CLI and one-shot callers.

- 🔷 **`host` and `port` hold the registration target.** `hostport` is a combined getter and setter only: get joins `host` and `port`; set parses `host:port` into the two fields. Flow code sets `host`/`port` directly or assigns one browse string through `hostport`. No repeated `last_index_of(":")` in probe or enroll.

#### Add — `Phase` enum and properties (in [`shared/Register.vala`](../../shared/Register.vala), after existing fields, before deregister signals)

```vala
	public enum Phase
	{
		IDLE,
		BROWSING,
		PROBING,
		AWAITING_PIN,
		ENROLLING,
		SUCCEEDED,
		FAILED
	}

	public Phase phase { get; private set; default = Phase.IDLE; }

	/**
	 * Registration host (from browse, manual entry, or
	 * {@link hostport} setter).
	 */
	public string host { get; private set; default = ""; }

	/**
	 * Registration port.
	 */
	public uint16 port { get; private set; default = 0; }

	/**
	 * ''host:port'' view of {@link host} and {@link port}.
	 *
	 * Set parses a combined string; get returns ''host:port'' or
	 * empty when either part is missing.
	 */
	public string hostport
	{
		get
		{
			if (this.host == "" || this.port < 1) {
				return "";
			}
			return this.host + ":" + this.port.to_string();
		}
		set
		{
			var mark = value.last_index_of(":");
			if (mark <= 0) {
				this.host = "";
				this.port = 0;
				return;
			}
			var parsed = 0;
			if (!int.try_parse(value.substring(mark + 1), out parsed) ||
				parsed < 1 || parsed > 65535) {
				this.host = "";
				this.port = 0;
				return;
			}
			this.host = value.substring(0, mark);
			this.port = (uint16) parsed;
		}
	}

	/**
	 * Server id from the browse TXT record.
	 */
	public string server_id { get; private set; default = ""; }

	/**
	 * ''127.0.0.1'' registration port is accepting TCP.
	 */
	public bool local_registration { get; private set; default = false; }

	/**
	 * Label text for UI (status or last error).
	 */
	public string detail { get; private set; default = ""; }

	/**
	 * Registration finished; {@link server_row} is set.
	 */
	public signal void enrolled();

	private Browse browse = new Browse();
	private uint browse_source = 0;
	private uint poll_source = 0;
	private int poll_token = 0;
	private bool probe_by_address = false;
```

#### Add — flow entry points

```vala
	/**
	 * Update {@link local_registration} without starting a flow.
	 */
	public void probe_local()
	{
		GLib.SocketConnection conn;
		try {
			var client = new GLib.SocketClient () {
				timeout = 2
			};
			conn = client.connect_to_host(
				"127.0.0.1", (uint16) Argus.REGISTER_PORT, null
			);
		} catch (GLib.Error e) {
			this.local_registration = false;
			return;
		}
		try {
			conn.close();
		} catch (GLib.Error e) {
			GLib.warning("%s", e.message);
		}
		this.local_registration = true;
	}

	public void stop()
	{
		this.poll_token++;
		if (this.browse_source != 0) {
			GLib.Source.remove(this.browse_source);
			this.browse_source = 0;
		}
		if (this.poll_source != 0) {
			GLib.Source.remove(this.poll_source);
			this.poll_source = 0;
		}
		this.browse.stop();
		this.host = "";
		this.port = 0;
		this.server_id = "";
		this.probe_by_address = false;
		this.phase = Phase.IDLE;
	}

	public void start_browse()
	{
		this.stop();
		this.phase = Phase.BROWSING;
		this.detail = "Looking for a management server…";
		this.browse.start();
		this.browse_source = GLib.Timeout.add(200, this.on_mdns_poll);
	}

	public void connect(string host, uint16 port)
	{
		this.stop();
		this.probe_by_address = true;
		this.host = host;
		this.port = port;
		this.server_id = "";
		this.phase = Phase.PROBING;
		this.detail = "Looking for a management server…";
		this.poll_source = GLib.Timeout.add_seconds(20, this.probe);
		this.probe();
	}

	/**
	 * Send the PIN on the current {@link hostport}.
	 */
	public async void submit_pin(string pin) throws GLib.Error
	{
		if (this.phase != Phase.AWAITING_PIN) {
			throw new GLib.IOError.FAILED("registration is not waiting for a PIN");
		}
		this.phase = Phase.ENROLLING;
		this.detail = "Registering…";
		if (this.host == "" || this.port < 1) {
			this.phase = Phase.FAILED;
			this.detail = "Bad address";
			return;
		}
		var requester = this.host_name != "" ?
			this.host_name : GLib.Environment.get_host_name();
		var code = this.try_connection(this.host, this.port, pin, requester);
		if (code != 0) {
			this.phase = Phase.FAILED;
			this.detail = "Registration failed";
			return;
		}
		this.phase = Phase.SUCCEEDED;
		this.detail = "Registration succeeded";
		this.enrolled();
	}
```

#### Add — private handlers (moved from [`RegisterWindow`](../../shared/RegisterWindow.vala))

`on_mdns_poll` is the **200 ms** `browse.poll()` loop from `show_add` (~502–547). `probe` is the **20 s** timer that tries TCP to {@link host} and {@link port} (moved from `RegisterWindow.on_wait`, ~374–429). The `connect_to_host_async` callback is {@link on_probe_complete}.

```vala
	/**
	 * Poll mDNS while {@link phase} is ''BROWSING''.
	 *
	 * Logic moved from {@link RegisterWindow.show_add}.
	 */
	private bool on_mdns_poll()
	{
		if (this.phase != Phase.BROWSING) {
			return false;
		}
		var hit = this.browse.poll();
		if (hit == "") {
			return true;
		}
		if (hit == "none") {
			this.detail = "No management server found";
			this.browse.start();
			return true;
		}
		this.browse.stop();
		this.browse_source = 0;
		var nl = hit.index_of("\n");
		if (nl <= 0 || !GLib.Uuid.string_is_valid(hit.substring(0, nl))) {
			this.phase = Phase.FAILED;
			this.detail = "No server id";
			return false;
		}
		this.server_id = hit.substring(0, nl);
		this.hostport = hit.substring(nl + 1);
		this.probe_by_address = false;
		this.phase = Phase.AWAITING_PIN;
		this.detail = "Management server found. Enter the six-digit PIN.";
		return false;
	}

	/**
	 * Start one async TCP check to the registration port on
	 * {@link host} and {@link port}. The 20 s timer calls this again until the
	 * port answers or the flow is cancelled.
	 *
	 * @return true to leave the timer running
	 */
	private bool probe()
	{
		if (this.phase != Phase.PROBING) {
			return false;
		}
		if (this.host == "" || this.port < 1) {
			this.phase = Phase.FAILED;
			this.detail = "Not active";
			return false;
		}
		var token = this.poll_token;
		var client = new GLib.SocketClient () {
			timeout = 5
		};
		client.connect_to_host_async.begin(
			this.host, this.port, null,
			(obj, res) => {
				this.on_probe_complete(token, client, res);
			}
		);
		return true;
	}

	/**
	 * Handle {@link GLib.SocketClient.connect_to_host_async} for
	 * {@link probe}.
	 *
	 * @param token {@link poll_token} when the probe started
	 * @param client socket client for this attempt
	 * @param res async result
	 */
	private void on_probe_complete(
		int token, GLib.SocketClient client, GLib.AsyncResult res)
	{
		if (token != this.poll_token) {
			return;
		}
		if (this.phase != Phase.PROBING) {
			return;
		}
		var opened = false;
		try {
			var conn = client.connect_to_host_async.end(res);
			opened = true;
			try {
				conn.close();
			} catch (GLib.Error close_error) {
				GLib.warning("%s", close_error.message);
			}
		} catch (GLib.Error e) {
			opened = false;
		}
		if (!opened) {
			this.detail = "Not active";
			return;
		}
		if (this.poll_source != 0) {
			GLib.Source.remove(this.poll_source);
			this.poll_source = 0;
		}
		this.poll_token++;
		this.phase = Phase.AWAITING_PIN;
		this.detail = "Okay";
	}
```

ℹ️ Vala may require a small adapter lambda for `begin` if the compiler will not bind `on_probe_complete` directly — the body above is the contract; the lambda only forwards to this method.

---

## Phase 3 — Thin `RegisterWindow`

#### Remove — fields ([`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala) ~86–93)

```vala
		private string found = "";
		private uint browse_id = 0;
		private uint close_id = 0;
		private int close_remaining = 0;
		private uint poll_id = 0;
		private int poll_token = 0;
		private bool by_address = false;
		private Browse browse = new Browse();
```

(`close_id` / `close_remaining` stay if still used elsewhere; drop only browse/poll/`found`/`by_address`/`browse` fields.)

#### Remove — [`on_wait`](../../shared/RegisterWindow.vala) in full (~374–429)

The whole method body moves to `Register.probe` and `Register.on_probe_complete`.

#### Remove — address Connect button tail (~296–312)

```vala
				this.poll_token++;
				this.by_address = true;
				this.found = host + ":" + port.to_string();
				this.server_id = "";
				this.pin_box.visible = false;
				this.listen_label.label = "Looking for a management server…";
				if (this.browse_id != 0) {
					GLib.Source.remove(this.browse_id);
					this.browse_id = 0;
				}
				this.browse.stop();
				if (this.poll_id != 0) {
					GLib.Source.remove(this.poll_id);
					this.poll_id = 0;
				}
				this.poll_id = GLib.Timeout.add_seconds(20, this.on_wait);
				this.on_wait();
```

#### Replace with — address Connect button tail

```vala
				this.reg.connect(host, (uint16) port);
```

#### Remove — `show_add` browse block (~482–549)

```vala
			if (this.poll_id != 0) {
				GLib.Source.remove(this.poll_id);
				this.poll_id = 0;
			}
			if (this.close_id != 0) {
				GLib.Source.remove(this.close_id);
				this.close_id = 0;
			}
			if (this.browse_id != 0) {
				GLib.Source.remove(this.browse_id);
				this.browse_id = 0;
			}
			this.browse_id = GLib.Idle.add(() => {
				this.browse_id = 0;
				var window = this.get_root() as Gtk.Window;
				if (window == null) {
					this.listen_label.label = "No management server found";
					return false;
				}
				this.browse.start();
				this.browse_id = GLib.Timeout.add(200, () => {
					var hit = this.browse.poll();
					if (hit == "") {
						return true;
					}
					if (hit == "none") {
#if ANDROID
						if (!this.by_address) {
							this.browse.start();
							return true;
						}
#endif
						var root = this.get_root() as Gtk.Window;
						if (root != null) {
							this.browse.stop();
						}
						this.browse_id = 0;
						this.listen_label.label = "No management server found";
						return false;
					}
					var root = this.get_root() as Gtk.Window;
					if (root != null) {
						this.browse.stop();
					}
					this.browse_id = 0;
					var nl = hit.index_of("\n");
					if (nl <= 0 || !GLib.Uuid.string_is_valid(hit.substring(0, nl))) {
						this.listen_label.label = "No server id";
						return false;
					}
					this.server_id = hit.substring(0, nl);
					this.found = hit.substring(nl + 1);
					this.by_address = false;
					this.poll_token++;
					if (this.poll_id != 0) {
						GLib.Source.remove(this.poll_id);
						this.poll_id = 0;
					}
					this.offer_box.visible = false;
					this.address_box.visible = false;
					this.listen_label.label =
						"Management server found. Enter the six-digit PIN.";
					this.pin_box.visible = true;
					this.pin_entry.grab_focus();
					return false;
				});
				return false;
			});
```

#### Replace with — `show_add` signature and tail

Add parameter `bool connect_local = false`. After the same reset / `use_pipe` / spinner block as today (~466–481):

```vala
			this.listen_label.label = "Looking for a management server…";
			if (connect_local) {
				this.reg.connect("127.0.0.1", (uint16) Argus.REGISTER_PORT);
				return;
			}
			this.reg.start_browse();
```

The top of `show_add` (~442–481) is **unchanged** except dropping assignments to `found`, `by_address`, `browse_id`, `poll_id` that only served the removed timers. `show_add` is not a one-line helper — it still resets widgets, handles Windows pipe/spinner, then hands off browse or local probe to `Register`.

#### Add — shared `Register` on the window

```vala
		public Register reg {
			get;
			construct;
			default = new Register ();
		}
```

#### Replace — start of constructor ([`RegisterWindow()`](../../shared/RegisterWindow.vala) ~162)

Keep the existing **parameterless** constructor. Add `Object ();` as the first line, then the existing widget build (header, pin box, `listen_label`, …). Wire `this.reg` at the end of that block:

```vala
		public RegisterWindow ()
		{
			Object ();
			// … existing widget build unchanged …
			this.reg.notify.connect((obj, pspec) => {
				if (pspec.name != "phase" && pspec.name != "detail") {
					return;
				}
				this.listen_label.label = this.reg.detail;
				if (this.reg.phase == Register.Phase.AWAITING_PIN) {
					this.offer_box.visible = false;
					this.address_box.visible = false;
					this.pin_box.visible = true;
					this.pin_entry.grab_focus();
				}
			});
			this.reg.enrolled.connect(() => {
				this.certificate_received();
			});
		}
```

Gtk passes the shared `Register` and directory fields (construct / settable props on the window):

```vala
			var window = new Argus.Shared.RegisterWindow (reg: reg) {
				data_dir = this.data_dir,
				client_db = this.client_db,
				title = "Argus Remote Management Agent " + Argus.VERSION
			};
```

Copy `data_dir` and `client_db` onto `this.reg` from the window fields when they are set (same as today’s inner `new Register()` in `request()`). Gtk widget lines in the middle of the constructor stay in **`new Widget () { prop = value, … }`** form (unchanged from today’s `RegisterWindow`).

#### Replace — `closed` handler cleanup (~340–359)

Stop calling `this.browse.stop()`; call `this.reg.stop()` instead. Drop `browse_id` / `poll_id` removal.

---

## Phase 4 — Gtk notice

#### Add — [`agent/linux/Application.vala`](../../agent/linux/Application.vala) (Gtk binary)

One state instead of `open_local` / `open_configure` / `open_reconfigure` booleans:

```vala
		private enum RegistrationOpen
		{
			NONE,
			CONFIGURE,
			LOCAL,
			RECONFIGURE
		}
```

`CONFIGURE` and `RECONFIGURE` both call `show_add()` (mDNS browse). `LOCAL` calls `show_add(true)` (loopback `Register.connect`).

#### Add — D-Bus on [`agent/linux/Application.cli.vala`](../../agent/linux/Application.cli.vala)

```vala
		public abstract bool client_newer() throws GLib.DBusError, GLib.IOError;
```

Implement on the service `Application` by reading `this.connection.client_newer` (Phase 1). Gtk calls it through `ServiceManager` the same way as `status()`.

#### Remove — [`registration()`](../../agent/linux/Application.vala) uses `client.pem` as “configured” (~293–325)

```vala
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				Gtk.init();
				var failed = false;
				var configuring = false;
				var offer_configure = false;
				var heading = "Argus agent is running";
				var detail = "Not connected to the management server.";
				try {
					switch (service.status()) {
						case ServiceStatus.CONNECTED:
							detail = "Connected to the management server.";
							break;

						case ServiceStatus.RUNNING:
							offer_configure = true;
							break;

						case ServiceStatus.STOPPED:
							heading = "Argus agent is not running";
							detail = "The Argus agent service is not running.";
							break;
					}
				} catch (GLib.Error e) {
					detail = e.message;
				}
				var notice = new Argus.Shared.Notice(heading, detail);
				notice.title = "Argus Remote Management Agent " + Argus.VERSION;
				notice.add_response("close", "Close");
				notice.add_response("restart", "Restart");
				if (offer_configure) {
					notice.add_response("configure", "Configure");
				}
```

#### Replace with — running notice (same method, after `service.setup()`)

```vala
			Gtk.init();
			if (!this.ensure_client_db()) {
				var failed = new Argus.Shared.Notice (
					"Could not open the agent database",
					"Run this application as administrator.") {
					title = "Argus Remote Management Agent " + Argus.VERSION
				};
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			var saved_server = false;
			var rows = new Gee.ArrayList<Argus.Agent.SQT.Server>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			Argus.Agent.SQT.Server.query(this.client_db).selectWhere(
				"WHERE deleted_dt = 0", int_binds, text_binds, rows);
			saved_server = rows.size > 0;
			var reg = new Argus.Shared.Register () {
				data_dir = this.data_dir,
				client_db = this.client_db
			};
			reg.probe_local();
			var status = ServiceStatus.STOPPED;
			var client_newer = false;
			var failure_detail = "";
			try {
				status = service.status();
				client_newer = service.client_newer();
			} catch (GLib.Error e) {
				failure_detail = e.message;
			}
			var heading = "Argus agent is running";
			var detail = failure_detail != "" ? failure_detail :
				"Not connected to the management server.";
			if (!saved_server) {
				heading = "Argus agent is not configured";
				detail = "No management server is configured.";
			}
			if (saved_server && status == ServiceStatus.CONNECTED) {
				detail = "Connected to the management server.";
			}
			if (saved_server && status == ServiceStatus.STOPPED) {
				heading = "Argus agent is not running";
				detail = "The Argus agent service is not running.";
			}
			var notice = new Argus.Shared.Notice (heading, detail) {
				title = "Argus Remote Management Agent " + Argus.VERSION
			};
			var open = RegistrationOpen.NONE;
			if (!saved_server) {
				if (reg.local_registration) {
					notice.add_response("local", "Connect locally");
				}
				notice.add_response("configure", "Configure");
			}
			if (saved_server && status == ServiceStatus.STOPPED) {
				notice.add_response("restart", "Restart");
			}
			if (saved_server && status == ServiceStatus.RUNNING && client_newer) {
				notice.add_response("restart", "Restart");
			}
			if (saved_server && status == ServiceStatus.RUNNING && !client_newer) {
				notice.add_response("retry", "Retry");
				notice.add_response("reconfigure", "Reconfigure");
				if (reg.local_registration) {
					notice.add_response("local", "Connect locally");
				}
			}
			var restart_work = false;
			notice.responded.connect((response) => {
				switch (response) {
					case "local":
						open = RegistrationOpen.LOCAL;
						notice.close();
						return;

					case "configure":
						open = RegistrationOpen.CONFIGURE;
						notice.close();
						return;

					case "reconfigure":
						open = RegistrationOpen.RECONFIGURE;
						notice.close();
						return;

					case "restart":
					case "retry":
						restart_work = true;
						try {
							service.restart();
						} catch (GLib.Error e) {
							restart_work = false;
							var error_notice = new Argus.Shared.Notice (
								"Could not restart the Argus agent service",
								e.message) {
								title = "Argus Remote Management Agent " + Argus.VERSION
							};
							error_notice.add_response("ok", "OK");
							error_notice.closed.connect(() => {
								this.quit();
							});
							error_notice.present(null);
						}
						return;

					default:
						return;
				}
			});
			notice.closed.connect(() => {
				if (open != RegistrationOpen.NONE) {
					this.present_registration(service, reg, open);
					return;
				}
				if (!restart_work) {
					this.quit();
				}
			});
			notice.present(null);
			this.hold();
			return 0;
```

When connected (`saved_server` && `CONNECTED`): **no** `add_response` buttons — header **X** only. No **Close** duplicate.

Drop the branch that only ran when `client.pem` existed; unconfigured machines hit the same notice path with `saved_server == false`, then fall through to `present_registration` when there is no saved row (today’s ~360–363 path unchanged except it shares `reg` setup).

#### Replace — [`present_registration`](../../agent/linux/Application.vala)

```vala
		private void present_registration(
			ServiceManager service,
			Argus.Shared.Register reg,
			RegistrationOpen open = RegistrationOpen.CONFIGURE)
		{
			if (!this.ensure_client_db()) {
				// … existing db failure notice …
				return;
			}
			var window = new Argus.Shared.RegisterWindow (reg: reg) {
				data_dir = this.data_dir,
				client_db = this.client_db,
				title = "Argus Remote Management Agent " + Argus.VERSION
			};
			switch (open) {
				case RegistrationOpen.LOCAL:
					window.show_add(true);
					break;

				case RegistrationOpen.CONFIGURE:
				case RegistrationOpen.RECONFIGURE:
					window.show_add();
					break;

				default:
					break;
			}
			// … existing certificate_received → save → service.restart() …
		}
```

Callers that open registration without going through the notice pass `RegistrationOpen.CONFIGURE` (today’s `present_registration(service)` only).

ℹ️ `request()` in the window should use `this.reg` for enroll instead of `new Register()` when flow moves to Phase 3.

---

## Out of scope

- 🚫 Windows tray.
- 🚫 Init scripts for a local server — loopback registration TCP only.

---

## Test plan

- `meson test -C build registration-local-probe registration-local-batch` — unprivileged; no `argusrm-agent` or pkexec.
- No row: **Configure**; loopback up → **Connect locally** → batch CLI (manual, root).
- Row, link retrying, same version: **Retry** / **Reconfigure**, not **Restart**.
- Row, link dead after `order > 0`: **Restart** only; body matches link detail when exposed.
- Connected: no action buttons.

---

## Next

- ⏳ Implement approved fences phase by phase (1 → 4). Cert `enroll_local_certificate` is in tree but unwired until Phase 4 + polkit.
- ℹ️ See **Test plan** when Phases 1–4 are complete in tree.

## Attempts / changelog

- ✔️ 2026-11-21: First draft used `set_phase`, `connect_local`, and `on_browse_tick`. Revised: inline `phase`/`detail`, local path via `connect` at call site, `on_mdns_poll` named for mDNS loop from `show_add`, `on_wait` kept as moved probe from the window.
- ✔️ 2026-11-21: Removed full code fences during a standards pass. Fences restored under each phase for review.
- ✔️ 2026-11-21: 20 s handler is `probe`; public TCP entry is `connect`. Async complete is `on_probe_complete`. `RegisterWindow` stays one ctor; Gtk uses `new RegisterWindow (reg: reg)`. Phase 4 `registration` / `present_registration` Remove/Replace fences added.
- ✔️ 2026-11-21: `Register` stores `host` and `port`; `hostport` is combined getter/setter. Probe and `submit_pin` use the fields directly.
- ✔️ 2026-11-21: Proposals use Gtk `new Type () { prop = value }`, `new RegisterWindow (reg: reg)` (no chained ctor), and `switch` on notice `responded`.
- ✔️ 2026-11-21: `RegistrationOpen` enum replaces notice open flags; `present_registration` takes one `open` value.
- ✔️ 2026-11-21: User approved proposal (Register API, single `RegisterWindow()` + `reg: reg` at call site, notice table, deletion list).
- 🚫 2026-11-21: **Implementation attempt** (Phase 4 + **Connect locally** via batch/PIN) removed from tree — proposal above stays approved. Local enroll wire: [done/2026-11-21-FIXED-local-agent-registration-certificate.md](done/2026-11-21-FIXED-local-agent-registration-certificate.md).