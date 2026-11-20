# Local registration — wire clients to `SQT.Server` (cutover)

**Status:** ✅ closed 2026-11-20 — fenced cutover **landed** in tree (agent **`Register.save`**, **`client_db`**, **A1–A5**; controller **Bootstrap** / **Settings** on **`Store.Server`** + **`Controller.SQT.Server`**; **`controller/Connection.vala`** removed; **`clear_saved_login`** gone). **Remainder:** [2026-11-20-local-registration-cutover-remainder.md](../2026-11-20-local-registration-cutover-remainder.md).

**Pointer:** `docs/guide-to-writing-plans.md` (**Edit syntax contract**), `docs/bug-fix-process.md`, [done/2026-11-20-FIXED-local-registration-data-store.md](done/2026-11-20-FIXED-local-registration-data-store.md)

---

## Closure (do not extend)

| Area | ✔️ in tree |
| --- | --- |
| **A1–A5** | Agent **`client_db`**, **`Agent.SQT.Server`**, **`Register.server_row`** + **`Register.save`** (`client_db`, `host_name` on **`Register`**) |
| **C1** | **Bootstrap** probe/register on **`Controller.SQT.Server`** + **`Store.Server`** |
| **C2** | **Settings** loads **`store.list()`**, **`window.server`** — live-row insert withdrawn (see remainder **Withdrawn**); connected server is always saved first |
| **C3.1** | **`clear_saved_login`** removed |
| **C3.2** (partial) | **Window** deregister passes **`server`** + **`client_db`**; **`Registration.Data`** flow still on window |
| **C4** | **`Connection.vala`** deleted; **Window** **`server`** property |

**Archived below** — historical fences and **Rejected** notes; implementation truth is the tree + remainder bug.

---

Intro for hunks below: edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding lines before applying.

## Implementation scope (frozen)

- ✅ **In scope for this bug:** apply **only** paired **Remove** / **Replace with** / **Add** **fenced Vala** (and **C4.1**-style explicit file deletes) in **this** document. Review is those diffs only.
- 🚫 **Out of scope here:** prose, 💩 notes, **Open** table, **Next** ordering, refactors with no fence, or “thread `row` / fix callers” unless a **Replace with** block shows the full new text.
- 📋 **Separate bug required** before landing anything in the right-hand column:

| Item | Why |
| --- | --- |
| **C3.3** | Deregister off `Window` + `server` — **no verbatim hunks** (prose only). |
| **C3.2** tail | `deregister()` signature / `Window` call sites — described, not fenced end-to-end. |
| **C4.1** refs | Ripgrep cleanup beyond the two `meson.build` lines (e.g. `Rdp/Screen`, `Tab/Agent`) — only if a new bug adds fences. |
| **Open #2–#4** | Product choices; not implementation. |
| **L** | Link migration bug already owns this. |

- ✔️ **C0** `title` / `addresses_subtitle` — already in [`shared/SQT/Server.vala`](../../shared/SQT/Server.vala); do not re-apply unless fences drift.

---

## Purpose

- 🔷 `⏳` **C1–C4** — controller cutover off `connections.json` / keyring DTO persistence onto `Store.Server` + `Controller.SQT.Server`. **🚫 No `Registration.Data` on the registration UI path** — `RegisterWindow` hands off `Argus.Shared.Register`; **`Controller.SQT.Server.save`** persists.
- ℹ️ **`Registration.Data`** after cutover: **server RPC wire** (`Registration.deregister` fingerprint, `--give-me-a-certificate` JSON) until **C3.3** moves deregister onto `Window` + `server` only — **not** a client persistence DTO.
- 🔷 `⏳` **A1–A5** — agent cutover off `data_dir/server`, loose PEM metadata files, and ad-hoc `checking_config` reads onto `client_db` + `Agent.SQT.Server` (one row — **no** `Agent.Store`; inline `query` + `load_certificates` at call sites).
- ℹ️ Link **`mark_down()`** / tray migration — **[2026-11-19-management-link-application-migration.md](2026-11-19-management-link-application-migration.md)** after **A4** (`checking_config` uses the store).

**In tree (do not re-design):** [`agent/SQT/Server.vala`](../../agent/SQT/Server.vala) PEM I/O; mirror controller for DB open pattern in [`controller/Application.vala`](../../controller/Application.vala).

---

## C1 — `controller/dialog/Bootstrap.vala`

### C1.1 — Saved-server fields

**Where:** class fields after `actions` (~lines 58–66).

**Depends on:** none.

#### Remove

```vala
		private Gee.ArrayList<Connection> connections {
			get; set; default = new Gee.ArrayList<Connection>();
		}
		private Gee.ArrayList<Connection> reached {
			get; set; default = new Gee.ArrayList<Connection>();
		}
		private Gee.HashMap<string, Argus.Shared.Registration.Data> credentials {
			get; set; default = new Gee.HashMap<string, Argus.Shared.Registration.Data>();
		}
```

#### Replace with

```vala
		private Gee.ArrayList<Argus.Controller.SQT.Server> servers {
			get; set; default = new Gee.ArrayList<Argus.Controller.SQT.Server>();
		}
		private Gee.ArrayList<Argus.Controller.SQT.Server> reached {
			get; set; default = new Gee.ArrayList<Argus.Controller.SQT.Server>();
		}
```

---

### C1.2 — `check()` load path

**Where:** `private void check()` — from `this.connections.clear()` through the `this.credentials.size < 1` return (lines ~184–333).

**Depends on:** C1.1.

#### Remove

```vala
			this.connections.clear();
			this.reached.clear();
			this.credentials.clear();
			this.answered.clear();
			this.next = 0;
			this.address_index = 0;
			if (!this.adding) {
				this.page("Checking connections", "", {}, {});
			}
			var path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "connections.json");
```

Through (inclusive):

```vala
			if (this.credentials.size < 1) {
#if ANDROID
				this.page("Could not connect", "The saved server has no certificate.",
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not connect", "The saved server has no certificate.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
```

(Everything between those anchors in the tree today: JSON parse, `connections` fill, Linux/Android secret loops.)

#### Replace with

```vala
			this.servers.clear();
			this.reached.clear();
			this.answered.clear();
			this.next = 0;
			this.address_index = 0;
			if (!this.adding) {
				this.page("Checking connections", "", {}, {});
			}
			try {
				var store = new Argus.Controller.Store.Server(this.app);
				this.servers = store.list();
			} catch (GLib.Error e) {
#if ANDROID
				this.page("Could not connect", e.message,
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not connect", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
			var with_pem = new Gee.ArrayList<Argus.Controller.SQT.Server>();
			foreach (var row in this.servers) {
				if (row.has_certificate) {
					with_pem.add(row);
				}
			}
			this.servers = with_pem;
			if (this.servers.size < 1 || this.adding) {
#if ANDROID
				this.page("Argus Remote Manager", "",
					{ "Connect a remote machine" }, { "remote" });
#else
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
#endif
				return;
			}
```

(Keep the existing `this.arm_local_offer(ticket);` / `this.probe(ticket);` lines immediately after this hunk — unchanged.)

---

### C1.3 — `probe()` row + hosts

**Where:** `private void probe(int ticket)` while-loop guard and host pick (~348–366).

**Depends on:** C1.1.

#### Remove

```vala
			while (this.next < this.connections.size) {
				var connection = this.connections.get(this.next);
				if (this.prefer != "" && connection.name != this.prefer) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				if (!this.credentials.has_key(connection.name) ||
					connection.port < 1 || connection.port > 65535 ||
					this.address_index >= connection.addresses.length) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				var client = new GLib.SocketClient();
				client.set_timeout(3);
				var host = connection.addresses[this.address_index];
				this.address_index++;
				client.connect_to_host_async.begin(host, (uint16) connection.port, null, (obj, res) => {
```

#### Replace with

```vala
			while (this.next < this.servers.size) {
				var row = this.servers.get(this.next);
				if (this.prefer != "" && row.name != this.prefer) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				if (!row.has_certificate) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				var hosts = row.address_list();
				if (this.address_index >= hosts.size) {
					this.next++;
					this.address_index = 0;
					continue;
				}
				var client = new GLib.SocketClient();
				client.set_timeout(3);
				var host = hosts[this.address_index];
				this.address_index++;
				client.connect_to_host_async.begin(host, (uint16) row.port, null, (obj, res) => {
```

#### Remove

```vala
					this.reached.add(connection);
					this.answered.set(connection.name, host);
					if (this.prefer != "" && connection.name == this.prefer) {
						this.use(connection);
```

#### Replace with

```vala
					this.reached.add(row);
					this.answered.set(row.name, host);
					if (this.prefer != "" && row.name == this.prefer) {
						this.use(row);
```

#### Remove

```vala
				foreach (var connection in this.reached) {
					labels += connection.name;
					responses += connection.name;
```

#### Replace with

```vala
				foreach (var row in this.reached) {
					labels += row.name;
					responses += row.name;
```

---

### C1.4 — `finish_registration()`

**Where:** entire `private void finish_registration(...)` (~653–803) and **`connect_remote`** `certificate_received` handler (~876–892).

**Depends on:** C1.1, **C1.7**.

#### Remove

The full `finish_registration` body from the tree (Connection merge, `connections.json`, libsecret / Android DTO files, `credentials.set`, `saved.name` page title).

```vala
				if (window.issued == null) {
```

through:

```vala
				this.finish_registration(window.issued);
```

#### Replace with

```vala
				var reg = window.registration;
				if (reg == null || reg.server_row == null || !reg.server_row.has_certificate) {
#if ANDROID
					this.page("Could not register",
						"The server did not return a connection.",
						{ "Connect a remote machine" }, { "remote" });
#else
					this.page("Could not register",
						"The server did not return a connection.",
						{ "Log in to local machine", "Connect a remote machine" },
						{ "register", "remote" });
#endif
					return;
				}

```vala
				var src = reg.server_row;
				var row = new Argus.Controller.SQT.Server() {
					name = window.registration_name,
					port = src.port,
					addresses = src.addresses,
					download = src.download,
					download_path = src.download_path,
					pem_private_key = src.pem_private_key,
					pem_client_certificate = src.pem_client_certificate,
					pem_ca_certificate = src.pem_ca_certificate
				};
				this.finish_registration(row);
```

#### Remove

Method signature `finish_registration(Argus.Shared.Registration.Data data)`.

#### Replace with

```vala
		private void finish_registration(Argus.Controller.SQT.Server row)
		{
#if LINUX
			try {
				var ca_cert = new GLib.TlsCertificate.from_pem(
					row.pem_ca_certificate, row.pem_ca_certificate.length);
				var fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256, ca_cert.certificate.data);
				var store = new Argus.Controller.Store.Server(this.app);
				foreach (var existing in store.list()) {
					if (existing.name != row.name || existing.pem_ca_certificate == "") {
						continue;
					}
					var old_ca = new GLib.TlsCertificate.from_pem(
						existing.pem_ca_certificate, existing.pem_ca_certificate.length);
					var old_fp = GLib.Checksum.compute_for_data(
						GLib.ChecksumType.SHA256, old_ca.certificate.data);
					if (old_fp != fingerprint) {
						this.page("Could not register",
							"The saved server certificate does not match.",
							{ "Retry", "Log in to register" }, { "retry", "register" });
						return;
					}
					break;
				}
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
#endif
			try {
				row.save(this.app.client_db);
			} catch (GLib.Error e) {
#if ANDROID
				this.page("Could not register", e.message,
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not register", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
			var replaced = false;
			for (var i = 0; i < this.servers.size; i++) {
				if (this.servers.get(i).name != row.name) {
					continue;
				}
				this.servers.set(i, row);
				replaced = true;
				break;
			}
			if (!replaced) {
				this.servers.add(row);
			}
			this.page("Server registered", row.name, {}, {});
			GLib.Timeout.add_seconds(2, () => {
				if (!this.running || this.opened) {
					return false;
				}
				this.reached.clear();
				this.answered.clear();
				this.next = 0;
				this.address_index = 0;
				this.generation++;
				this.probe(this.generation);
				return false;
			});
		}
```

---

### C1.5 — `deregister_local()`

**Where:** loop + clears (~817–831).

**Depends on:** C1.1.

#### Remove

```vala
			foreach (var connection in this.connections) {
				var data = new Argus.Shared.Registration.Data() {
					name = connection.name
				};
				try {
					data.clear_saved_login();
				} catch (GLib.Error e) {
					if (local_error == "") {
						local_error = e.message;
					}
				}
			}
			this.connections.clear();
			this.reached.clear();
			this.credentials.clear();
```

#### Replace with

```vala
			try {
				var store = new Argus.Controller.Store.Server(this.app);
				foreach (var row in store.list()) {
					try {
						row.remove(this.app.client_db);
					} catch (GLib.Error e) {
						if (local_error == "") {
							local_error = e.message;
						}
					}
				}
			} catch (GLib.Error e) {
				if (local_error == "") {
					local_error = e.message;
				}
			}
			this.servers.clear();
			this.reached.clear();
```

---

### C1.6 — `use()` TLS + `Window` ctor

**Where:** `private void use(Connection connection)` (~916–1027). **C4** drops `Registration.Data` from `Window` open.

**Depends on:** C1.1, C1.3.

#### Remove

```vala
		private void use(Connection connection)
		{
			if (this.opened) {
				return;
			}
			this.generation++;
			this.opened = true;
			var issued = new Argus.Shared.Registration.Data();
			if (this.credentials.has_key(connection.name)) {
				issued = this.credentials.get(connection.name);
			}
			issued.name = connection.name;
			var host = this.answered.get(connection.name);
```

#### Replace with

```vala
		private void use(Argus.Controller.SQT.Server server)
		{
			if (this.opened) {
				return;
			}
			this.generation++;
			this.opened = true;
			var host = this.answered.get(server.name);
```

#### Remove

```vala
			try {
				var pem = issued.client_certificate + "\n" + issued.private_key;
				certificate = new GLib.TlsCertificate.from_pem(pem, pem.length);
```

Through:

```vala
				GLib.FileUtils.set_contents(ca_path, issued.ca_certificate);
```

#### Replace with

```vala
			try {
				certificate = server.tls_certificate();
```

Through:

```vala
				GLib.FileUtils.set_contents(ca_path, server.pem_ca_certificate);
```

#### Remove

```vala
			var rpc = new OLLMrpc.Client("", "",
				"tcp://" + host + ":" + connection.port.to_string()) {
```

#### Replace with

```vala
			var rpc = new OLLMrpc.Client("", "",
				"tcp://" + host + ":" + server.port.to_string()) {
```

#### Remove

```vala
				app.window.open(connection, issued, host);
```

#### Replace with

```vala
				app.window.open(server, host);
```

(Android `Window.open(app, server, host)` — same.)

#### Remove

```vala
				var window = new Window(app, connection, issued, host);
```

#### Replace with

```vala
				var window = new Window(app, server, host);
```

---

### C1.7 — `shared/RegisterWindow.vala` — `Register` handoff (not `Registration.Data`)

**Where:** property `issued` (~41); `remember()` (~670–729); `issued = null` resets (~430, ~452).

**Depends on:** **A3** (`Register` PEM fields on memory only).

**Rule:** The dialog does **not** build or expose `Argus.Shared.Registration.Data`. Controllers map **`registration` + `registration_name`** → **`Controller.SQT.Server`** in **C1.4**. Agent gtk only restarts the service on **`certificate_received`** — no DTO.

#### Remove

```vala
		public Argus.Shared.Registration.Data? issued { get; private set; }
```

#### Replace with

```vala
		/**
		 * Successful {@link Register.try_connection} outcome for this dialog.
		 * Null until {@link remember} succeeds.
		 */
		public Register? registration { get; private set; }
		/**
		 * Row {@link Argus.Shared.SQT.Server.name} — connected registration host.
		 */
		public string registration_name { get; private set; default = ""; }
```

#### Remove

`this.issued = null` (both sites) and the whole `this.issued = new Argus.Shared.Registration.Data() { ... }` block at the end of `remember()`.

#### Replace with

Rename `remember(string host, int port, string addresses)` → `remember(Register registration, string host, int port, string addresses)`.

After host-list merge (unchanged logic), require **`registration.server_row != null && registration.server_row.has_certificate`**, then:

```vala
			this.registration = registration;
			this.registration_name = host;
			return true;
```

#### Remove — file reads in `remember()` (same as old **A3.1**)

```vala
			var client = "";
			var key = "";
			var ca = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client.pem"), out client);
```

through the matching `catch` that calls `error_occurred`.

(Call site in the pin loop: `remember(registration, host, registration.server_row.port, registration.server_row.addresses)`.)

---

## C0 — `shared/SQT/Server.vala` list labels

**Where:** after `has_certificate` (~126–132).

**Depends on:** none (land before **C2**).

#### Add

```vala
		/**
		 * List row title: {@link name}, else the first {@link address_list}
		 * host, else ''Server''.
		 */
		public string title {
			get {
				if (this.name != "") {
					return this.name;
				}
				var hosts = this.address_list();
				if (hosts.size > 0) {
					return hosts.get(0);
				}
				return "Server";
			}
		}

		/**
		 * Comma-separated {@link address_list} for a list subtitle, or
		 * empty when there are no hosts.
		 */
		public string addresses_subtitle {
			get {
				var hosts = this.address_list();
				if (hosts.size == 0) {
					return "";
				}
				return string.joinv(", ", hosts.to_array());
			}
		}
```

(✔️ in tree — keep **C0** hunk aligned if the shared file drifts.)

---

## C2 — `controller/tab/Settings.vala`

### C2.1 — Load saved servers

**Where:** `Settings` constructor — load block (~62–93).

**Depends on:** C1 (SQLite has rows); **C4** for `window.server` vs `window.connection`.

#### Remove

```vala
			var path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "connections.json");
			var saved = new Connections();
			var broken = false;
			if (GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				var text = "";
				try {
					GLib.FileUtils.get_contents(path, out text);
					var loaded = Json.gobject_from_data(typeof(Connections),
						"{\"rows\":" + text + "}") as Connections;
					if (loaded == null) {
						throw new GLib.FileError.FAILED("The saved connections could not be read.");
					}
					saved = loaded;
				} catch (GLib.Error e) {
					broken = true;
				}
			}
			if (broken) {
				servers.description = "The saved connections could not be read.";
			}
			var listed = false;
			for (var i = 0; i < saved.rows.size; i++) {
				if (saved.rows.get(i).name == this.window.connection.name &&
					this.window.connection.name != "") {
					listed = true;
					break;
				}
			}
			if (!listed) {
				saved.rows.insert(0, this.window.connection);
			}
```

#### Replace with

```vala
			var saved = new Gee.ArrayList<Argus.Controller.SQT.Server>();
			var broken = false;
			try {
				var store = new Argus.Controller.Store.Server(this.window.app);
				saved = store.list();
			} catch (GLib.Error e) {
				broken = true;
			}
			if (broken) {
				servers.description = "The saved connections could not be read.";
			}
			var live_name = this.window.connection.name;
```

(💩 After **C4**, `live_name` becomes `this.window.server.name` and optionally insert live `server` at 0 if missing from `list()`.)

---

### C2.2 — Settings row loop

**Where:** `for (var i = 0; i < saved.rows.size; i++)` (~94–117).

**Depends on:** **C0** (`row.title`, `row.addresses_subtitle`).

#### Remove

```vala
			for (var i = 0; i < saved.rows.size; i++) {
				var row = saved.rows.get(i);
				if (row.name == "" && row != this.window.connection) {
					continue;
				}
				var server_name = row.name;
				var open = server_name != "" &&
					server_name == this.window.connection.name;
				if (row == this.window.connection) {
					open = true;
				}
				var title = server_name;
				if (title == "" && row.addresses.length > 0) {
					title = row.addresses[0];
				}
				if (title == "") {
					title = "Server";
				}
				var server = new Adw.ExpanderRow() {
					title = title
				};
				if (row.addresses.length > 0) {
					server.subtitle = string.joinv(", ", row.addresses);
				}
```

#### Replace with

```vala
			for (var i = 0; i < saved.size; i++) {
				var row = saved.get(i);
				if (row.name == "") {
					continue;
				}
				var server_name = row.name;
				var open = server_name != "" && server_name == live_name;
				var server = new Adw.ExpanderRow() {
					title = row.title
				};
				if (row.addresses_subtitle != "") {
					server.subtitle = row.addresses_subtitle;
				}
```

---

## C3 — `shared/Registration/Data.vala` + `Window`

🚫 **`Registration.Data` is not part of registration UI or client storage after this cutover.** It remains only for **server→client RPC** until **C3.3** removes the type from `Window` entirely.

### C3.1 — Drop client persistence

**Where:** `public void clear_saved_login()`.

**Depends on:** C1.5 (no callers).

#### Remove

Entire `clear_saved_login()` method (~148–209).

#### Replace with

Nothing — delete the method. Grep `clear_saved_login` → zero in controller.

---

### C3.2 — `deregister()` local cleanup

**Where:** `clear_and_finish()` (~234–248).

#### Remove

```vala
		private void clear_and_finish()
		{
			try {
				this.clear_saved_login();
			} catch (GLib.Error e) {
				this.fail(e.message);
				return;
			}
```

#### Replace with

```vala
		private void clear_and_finish(
			Argus.Controller.SQT.Server row,
			Argus.Controller.Application app)
		{
			try {
				row.remove(app.client_db);
			} catch (GLib.Error e) {
				this.fail(e.message);
				return;
			}
```

(🔷 Thread `row` + `app` from `deregister()` callers on `Window` — add parameters to `deregister(parent, rpc, row, app)` and update `clear_and_finish` call sites in the same file.)

### C3.3 — `Window` deregister without `Registration.Data`

**Status:** 🚫 **not in this bug** — no fenced hunks; draft a **new** `docs/bugs/…` with full **Remove** / **Replace with** before implementation.

**Intent (reference only):** drop `Window.issued`; deregister RPC + `server.remove(client_db)` on the window. Wire `Registration.Data` may remain for `--give-me-a-certificate` only.

---

## C4 — Retire `Connection`

### C4.1 — Delete type file

#### Remove

- [`controller/Connection.vala`](../../controller/Connection.vala)
- `'Connection.vala'` from [`controller/meson.build`](../../controller/meson.build) and [`docs/meson.build`](../../docs/meson.build)

---

### C4.2 — `Window` properties + constructor

**Where:** [`controller/Window.vala`](../../controller/Window.vala) (~52–112).

#### Remove

```vala
		public Connection connection { get; set; default = new Connection(); }
		public Argus.Shared.Registration.Data issued {
			get; set; default = new Argus.Shared.Registration.Data();
		}
```

```vala
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued,
			string host
		) {
			this.app = app;
			this.connection = connection;
			this.issued = issued;
			this.host = host;
			this.issued.name = connection.name;
```

#### Replace with

```vala
		public Argus.Controller.SQT.Server server {
			get; set; default = new Argus.Controller.SQT.Server();
		}
```

```vala
		public Window(
			Application app,
			Argus.Controller.SQT.Server server,
			string host
		) {
			this.app = app;
			this.server = server;
			this.host = host;
```

(**C3.3** rewires deregister off **`server`**, not **`issued`**.)

#### Remove

References to `this.window.connection` in Settings (**C2.1** uses `server` / `live_name`).

---

## A1 — `agent/Application.vala` client database

**Where:** class fields + constructor (~42–250).

**Depends on:** none.

#### Add

```vala
		/**
		 * Local ''server.sqlite'' under {@link data_dir}.
		 */
		internal SQ.Database client_db { get; private set; }
```

#### Add

In the constructor, after `this.osquery = new OSQuery.Execute(this);` — same shape as controller `Application`:

```vala
			if (GLib.DirUtils.create_with_parents(this.data_dir, 0700) != 0) {
				GLib.warning("Could not create the data directory");
			} else {
				var path = GLib.Path.build_filename(this.data_dir, "server.sqlite");
				this.client_db = new SQ.Database(path, true);
				Argus.Shared.SQT.Server.init_db(this.client_db);
			}
			this.shutdown.connect(() => {
				if (this.client_db != null) {
					this.client_db.backup_real();
				}
			});
```

---

## A2 — `agent/SQT/Server.vala` `query` only

**Where:** [`agent/SQT/Server.vala`](../../agent/SQT/Server.vala) (after class opening).

**Depends on:** **A1** (`app.client_db`).

🚫 **No `agent/store/Server.vala`.** The agent has at most one saved server; **`Connection`** and **`try_batch`** load that row inline.

#### Add

```vala
		public static SQ.Query<Server> query(SQ.Database db)
		{
			return new SQ.Query<Server>(db, "server");
		}
```

#### Add — `store_certificates` download sidecars

**Where:** end of [`agent/SQT/Server.vala`](../../agent/SQT/Server.vala) `store_certificates`, after PEM writes (before `#if !G_OS_WIN32` / Win32 `Cert.ensure`).

🚫 **`Register`** does not write `download` / `download-path`; the agent row does when saved.

```vala
			if (this.download != "") {
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(this.data_dir, "download"),
					this.download);
			}
			if (this.download_path != "") {
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(this.data_dir, "download-path"),
					this.download_path);
			}
```

(💩 Later: `Download` / `Initialize` read row columns only and delete these sidecars.)

**Inline load** (repeat at **A4** / **A3** `try_batch` — first `deleted_dt = 0` row, then PEMs):

```vala
			var rows = new Gee.ArrayList<Argus.Agent.SQT.Server>();
			Argus.Agent.SQT.Server.query(this.app.client_db).selectWhere(
				"WHERE deleted_dt = 0", null, null, rows);
			if (rows.size < 1) {
				throw new GLib.IOError.FAILED("no saved server");
			}
			var row = rows.get(0);
			row.data_dir = this.app.data_dir;
			row.load_certificates();
```

---

## A3 — `shared/Register.vala` RPC only (no persistence)

**Where:** class fields (~51–117); `try_connection` success path (~232–281); docblock opening lines.

**Depends on:** none.

**Rule:** **`Register`** performs TLS + `Agent.request_registration`, then builds one in-memory **`Argus.Shared.SQT.Server`** (`server_row`). **🚫 No** parallel PEM fields on `Register`. **🚫 No** ad-hoc PEM files in `try_connection` — **`save`** + platform **`store_certificates`** persist (**A5**, **C1.4**). Callers pass an **`Agent.SQT.Server`** / **`Controller.SQT.Server`** instance into **`save`** (subclasses differ on cert storage).

#### Add — after `hostname`

```vala
		/**
		 * Reply material from the last successful {@link try_connection}.
		 * Null until a success path assigns it. Not saved — callers
		 * {@link Argus.Shared.SQT.Server.save} a platform subclass copy.
		 */
		public Argus.Shared.SQT.Server? server_row { get; private set; }
```

(At start of `try_connection`, set `this.server_row = null`.)

#### Remove — all registration persistence in `try_connection`

```vala
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "client.pem"), packed[0]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download"),
					host + ":" + Argus.DOWNLOAD_PORT.to_string());
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download-path"), packed[2]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
```

```vala
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "server"),
					host + ":" + stored_port);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls_files.ensure();
```

#### Replace with

```vala
			var key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client-key.pem"), out key_pem);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var listen = "";
			if (packed.length > 3) {
				listen = string.joinv("\n", packed[3:packed.length]);
			}
			this.server_row = new Argus.Shared.SQT.Server() {
				name = requester,
				port = int.parse(stored_port),
				addresses = listen,
				download = host + ":" + Argus.DOWNLOAD_PORT.to_string(),
				download_path = packed[2],
				pem_private_key = key_pem.strip(),
				pem_client_certificate = packed[0].strip(),
				pem_ca_certificate = packed[1].strip()
			};
			this.download = this.server_row.download;
			this.download_path = this.server_row.download_path;
			this.addresses = listen;
			if (response.msg == "pending") {
				this.pending = true;
			}
			return 0;
```

(Remove the duplicate assignments + `tls_files.ensure()` + `return 0` that followed the old file writes in the tree — this block is the full tail of the success path.)

#### Remove — `try_batch` poll host/port from `server` file

```vala
			var text = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "server"), out text);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			text = text.strip();
			var mark = text.last_index_of(":");
			var poll_port = 0;
			if (mark > 0) {
				poll_port = int.parse(text.substring(mark + 1));
			}
			if (text == "" || mark < 1 || poll_port <= 0 || poll_port > 65535) {
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			var poll_host = text.substring(0, mark);
```

#### Replace with

Poll uses the **pending** reply already on `this` from the last `try_connection` inside the batch loop — **no** SQLite and **no** `server` file until **A5** saves after `try_batch` returns `0`.

```vala
			if (this.server_row == null || !this.server_row.has_certificate) {
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			GLib.InetSocketAddress poll;
			try {
				poll = this.server_row.socket(0);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			var poll_host = poll.get_address().to_string();
			var poll_port = poll.get_port();
```

#### Remove — `try_batch` poll TLS from on-disk `Cert`

```vala
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
```

#### Replace with

```vala
			GLib.TlsCertificate tls_cert;
			try {
				tls_cert = this.server_row.tls_certificate();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
```

(Use `tls_cert` on `TlsClient` instead of `tls_files.certificate`.)

(💩 `try_batch` failure paths that `remove(client.pem)` → set **`this.server_row = null`**; caller **`save`** only after `try_batch` returns `0` (**A5**). After save, use **`row.remove(client_db)`**.)

---

(Controller **`RegisterWindow`** — **C1.7**, not agent.)

---

## A4 — `agent/Connection.vala` config + wipe

**Where:** `on_checking_config()` (~147–185); `enter_dead()` wipe (~369–378); constructor gate (~86–94).

**Depends on:** **A1**, **A2**.

#### Remove — `on_checking_config` body

```vala
		private void on_checking_config()
		{
			var dir = this.app.data_dir;
			string host = "";
			uint16 port = 0;
			var text = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "server"), out text);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.schedule_retry(false);
				return;
			}
			text = text.strip();
			var mark = text.last_index_of(":");
			if (text == "" || mark < 1) {
				this.schedule_retry(false);
				return;
			}
			host = text.substring(0, mark);
			var parsed = int.parse(text.substring(mark + 1));
			if (parsed < 1 || parsed > 65535) {
				this.schedule_retry(false);
				return;
			}
			port = (uint16) parsed;
			var ca = GLib.Path.build_filename(dir, "ollmrpc-ca.pem");
			var cert = GLib.Path.build_filename(dir, "client.pem");
			var key = GLib.Path.build_filename(dir, "client-key.pem");
			if (!GLib.FileUtils.test(ca, GLib.FileTest.EXISTS) ||
				!GLib.FileUtils.test(cert, GLib.FileTest.EXISTS) ||
				!GLib.FileUtils.test(key, GLib.FileTest.EXISTS)) {
				this.enter_dead("No certificate for the management server.", false);
				return;
			}
			this.attempt_host = host;
			this.attempt_port = port;
			this.enter_state(State.CONNECTING);
		}
```

#### Replace with

```vala
		private void on_checking_config()
		{
			Argus.Agent.SQT.Server row;
			try {
				if (this.app.client_db == null) {
					throw new GLib.IOError.FAILED("client database is not open");
				}
				var rows = new Gee.ArrayList<Argus.Agent.SQT.Server>();
				Argus.Agent.SQT.Server.query(this.app.client_db).selectWhere(
					"WHERE deleted_dt = 0", null, null, rows);
				if (rows.size < 1) {
					throw new GLib.IOError.FAILED("no saved server");
				}
				row = rows.get(0);
				row.data_dir = this.app.data_dir;
				row.load_certificates();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.schedule_retry(false);
				return;
			}
			if (!row.has_certificate) {
				this.enter_dead("No certificate for the management server.", false);
				return;
			}
			GLib.InetSocketAddress endpoint;
			try {
				endpoint = row.socket(0);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.schedule_retry(false);
				return;
			}
			this.attempt_host = endpoint.get_address().to_string();
			this.attempt_port = endpoint.get_port();
			this.enter_state(State.CONNECTING);
		}
```

#### Remove — `enter_dead` file wipe

```vala
			if (wipe_registration) {
				var dir = this.app.data_dir;
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
				GLib.debug("registration cleared");
			}
```

#### Replace with

```vala
			if (wipe_registration && this.app.client_db != null) {
				try {
					var rows = new Gee.ArrayList<Argus.Agent.SQT.Server>();
					Argus.Agent.SQT.Server.query(this.app.client_db).selectWhere(
						"WHERE deleted_dt = 0", null, null, rows);
					if (rows.size > 0) {
						var row = rows.get(0);
						row.data_dir = this.app.data_dir;
						row.load_certificates();
						row.remove(this.app.client_db);
					}
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				GLib.debug("registration cleared");
			}
```

#### Remove — constructor early return

```vala
			if (!GLib.FileUtils.test(
				GLib.Path.build_filename(this.app.data_dir, "client.pem"),
				GLib.FileTest.EXISTS)) {
				return;
			}
```

#### Replace with

```vala
			if (this.app.client_db == null) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Agent.SQT.Server>();
			try {
				Argus.Agent.SQT.Server.query(this.app.client_db).selectWhere(
					"WHERE deleted_dt = 0", null, null, rows);
			} catch (GLib.Error e) {
				return;
			}
			if (rows.size < 1) {
				return;
			}
			var row = rows.get(0);
			row.data_dir = this.app.data_dir;
			try {
				row.load_certificates();
			} catch (GLib.Error e) {
				return;
			}
```

---

## A5 — agent callers: `SQT.Server.save` after `Register`

**Where:** every agent path where `try_connection` / `try_batch` returns `0`.

**Depends on:** **A1**, **A2**, **A3**.

**Rule:** Agent callers set **`data_dir`**, **`client_db`**, and **`host_name`** on **`Register`** at construction. After RPC, build **`Argus.Agent.SQT.Server`** (with **`data_dir`**), then **`registration.save(row)`** copies **`server_row`** and **`row.save(client_db)`**.

| File | After `code == 0` |
| --- | --- |
| [`agent/Application.vala`](../../agent/Application.vala) | save row (both registration paths); then `attach_connection()` |
| [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala) | save row before `attach_connection()` |
| [`agent/linux/Application.vala`](../../agent/linux/Application.vala) | save row after CLI / gtk registration |
| [`agent/linux/Application.cli.vala`](../../agent/linux/Application.cli.vala) | same |
| [`shared/Register.vala`](../../shared/Register.vala) `try_batch` | after `return 0`, same **`row.save`** as `try_connection`; pending poll stays in-memory (**A3**). |

#### Add — `shared/Register.vala` `save`

```vala
		public bool save(Argus.Shared.SQT.Server row) {
			var src = this.server_row;
			var db = this.client_db;
			if (db == null || row == null || src == null || !src.has_certificate) {
				return false;
			}
			if (row.name == "") {
				if (src.name != "") {
					row.name = src.name;
				} else if (this.host_name != "") {
					row.name = this.host_name;
				} else {
					row.name = GLib.Environment.get_host_name();
				}
			}
			row.port = src.port;
			row.addresses = src.addresses;
			row.download = src.download;
			row.download_path = src.download_path;
			row.pem_private_key = src.pem_private_key;
			row.pem_client_certificate = src.pem_client_certificate;
			row.pem_ca_certificate = src.pem_ca_certificate;
			try {
				row.save(db);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return false;
			}
			return true;
		}
```

#### Add — example caller (`agent/Application.vala` after successful `try_connection`)

```vala
			var registration = new Argus.Shared.Register() {
				data_dir = this.data_dir,
				client_db = this.client_db,
				host_name = GLib.Environment.get_host_name(),
			};
			var code = registration.try_connection(this.host, (uint16) this.port, this.pin);
			…
				var row = new Argus.Agent.SQT.Server() {
					data_dir = registration.data_dir != "" ? registration.data_dir : this.data_dir,
				};
				if (!registration.save(row)) {
					command_line.printerr("registration failed: could not save\n");
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
```

### Rejected (implementation drift — do not land)

- 🚫 **`Argus.Agent.SQT.Server.save_shared_row`** — static helper wrapping copy + `save(db)`. **Not** in A5; use the **Add — example** block inline at each caller only.
- 🚫 **`Argus.Agent.Application.save_registration`** — registration persistence on `Application`; same rule — inline **A5** at `try_connection` / `try_batch` success sites.
- 🚫 **`Argus.AGENT_DATA_DIR`** passed into the save path instead of `registration.data_dir != "" ? registration.data_dir : this.data_dir` (Linux service/CLI duplicated the old `Register` initializer constant).
- 🚫 **Duplicated inline copy + `row.save` at every caller** — use **`Register.save`** with a platform row the caller constructs (**`data_dir`** on agent, **`name`** preset on controller when needed).

---

## L — link migration (separate bug)

- ℹ️ **`Connection.mark_down()`**, **`attach_connection`**, tray **`notify::state`** — not in this cutover; tracked in [2026-11-19-management-link-application-migration.md](2026-11-19-management-link-application-migration.md).
- 🔷 Unblock those items only after **A4** so `checking_config` does not read the legacy `server` file.

---

## Open

| # | Question |
| --- | --- |
| 2 | First connect try: `address_list()` order only, or prefer `last_host` when set (agent + controller probe). |
| 3 | Linux libsecret `server` CA fingerprint attribute — **C1.4** keeps pre-save compare only; extend `store_certificates`? |
| 4 | **Resolved for cutover:** `download` / `download-path` sidecars written in **`Agent.SQT.Server.store_certificates`** (**A2**); later read from SQLite only. |

---

## Next

✅ Closed — follow [2026-11-20-local-registration-cutover-remainder.md](../2026-11-20-local-registration-cutover-remainder.md).