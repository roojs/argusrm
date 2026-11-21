# Local registration — what’s left after the cutover

**Status:** ✅ closed 2026-11-21 — remainder items verified in tree (see **Closure** below).

**Background:** The main cutover is [done/2026-11-20-FIXED-local-registration-cutover.md](done/2026-11-20-FIXED-local-registration-cutover.md). This file archived the post-cutover polish; **do not reopen** — new work needs a new bug with fences.

## Closure (in tree)

| Item | ✔️ |
| --- | --- |
| R1 deregister on `Register` + `Window` signals | `Register.remove` / `remove_local`; `controller/Window.vala`; `Registration.Data` gone; SQT wire via [2026-11-21-FIXED-registration-reply-use-sqt-server.md](done/2026-11-21-FIXED-registration-reply-use-sqt-server.md) |
| R1.3 mirrored `download` / `addresses` on `Register` | Removed; `server_row` only |
| R2 Bootstrap `reg.save` | `finish_registration(reg, row)` |
| R3 comments | e.g. `Bootstrap.check()` SQLite doc; no `connections.json` in `*.vala` |
| R4 `can_route_to` | `shared/SQT/Server.vala` `address_list()` |
| Local Unix cert enroll (separate track) | [2026-11-21-FIXED-local-agent-registration-certificate.md](done/2026-11-21-FIXED-local-agent-registration-certificate.md) + gtk + polkit bugs |

**Also see:** [2026-11-19-desktop-status-and-reconnect.md](2026-11-19-desktop-status-and-reconnect.md) for reconnect/RDP/tray tail; management migration archived in [done/2026-11-19-FIXED-management-link-application-migration.md](done/2026-11-19-FIXED-management-link-application-migration.md).

**How to implement:** Only apply code changes that have **Remove** / **Replace with** / **Add** fenced blocks below (same rules as `docs/guide-to-writing-plans.md`).

---

## What we still need

1. **Deregister from the main window** — **delete** deregister from **`Argus.Shared.Registration.Data`** (wire DTO only). **`Argus.Shared.Register.remove`** is the enroll inverse of **`save`**: server RPC + **`row.remove(client_db)`**, **no Gtk**. Outcomes are **`Register` signals**; **`controller/Window`** (and android twin) connect them to **`Notice`** dialogs. **`Controller.SQT.Server`** stays persistence + optional **fingerprint** helper — **no** Gtk on SQT types.
2. **`Register` transition residue** — drop mirrored **`download` / `download_path` / `addresses`** on **`Register`**; **`server_row`** (then **`save`**) is the only enroll outcome shape. Update **`RegisterWindow`** to read **`server_row`**.
3. **Register dialog → save** — after registration, use `Register.save` like the agent does, instead of copying certificate fields by hand in Bootstrap.
4. **Cleanup** — wrong comments (still mentioning `connections.json`), small wiring nits, and any leftover references to the deleted `Connection` type.
5. **Saved server row** — **`Argus.Shared.SQT.Server.address_list()`** omits unroutable hosts (Linux **`can_route_to`**); **not** at registration/enroll; see **R4**.
6. **R4** — route-aware probes (Linux); CA/keyring question **settled** (no extra fingerprint in libsecret).

---

## Withdrawn — Settings “insert live server” (not a real scenario)

The old cutover plan copied behaviour from **`connections.json`**: the in‑memory “current connection” could exist **before** it was written to the file, so Settings prepended it to the list.

That does **not** apply after the cutover:

- **Bootstrap** only opens a main window after **`use(server)`**, and that `server` row came from **`store.list()`** (saved SQLite rows), or from **`finish_registration`**, which **`row.save(client_db)`** runs **before** probing and opening the window.
- So if you are connected, that server **should already be in the database** with the same name Settings uses for the green dot.

If the dot is missing but the server **is** in the list, the bug is more likely a **name mismatch** (connected as one string, saved under another), not “missing from the list.” If you ever see connected-but-not-saved, that would be a **new** bug in the open path (save failed or was skipped), not a Settings list workaround.

---

## R1 — Deregister off `Registration.Data`; orchestration on `Register`

**Review:** No product choices — same dialogs and RPC. **`Registration.Data`** becomes **only** the JSON/RPC result struct (**delete** all Gtk deregister code there). **`Register.remove(row, rpc)`** and **`Register.remove_local(row)`** use **`this.client_db`** like **`save`**. **`Register`** emits signals; **`Window`** presents **`Notice`** and re-enables **`win.deregister`**. **Do not** put Gtk on **`Controller.SQT.Server`**.

🚫 No replacement “flow” class (`Deregister`, etc.). 🚫 No Gtk inside **`Register.remove`**.

| Signal | Meaning | Window |
| --- | --- | --- |
| **`remove_failed`** | Certificate parse error, server rejected the call, or local **`row.remove`** failed | Error **`Notice`** → re-enable action |
| **`remove_server_unreachable`** | Management server did not answer (timeout or transport error) | **`Notice`**: user may **Deregister locally** → **`remove_local(this.server)`** |
| **`remove_row_deleted`** | Row removed from SQLite | Success **`Notice`** → quit (same as today’s **`finished(true)`**) |

---

### R1.1 — [`shared/Registration/Data.vala`](../../shared/Registration/Data.vala)

#### Remove — class docblock

```vala
	/**
	 * Local controller registration result.
	 *
	 * The running server returns this object over the Unix RPC connection.
	 * The privileged controller command serializes it to standard output.
	 * {@link deregister} removes the server row for this certificate
	 * on the TLS connection already open, then closes that connection.
	 * If the server does not answer, the dialog can still remove the
	 * keyring secret and the saved connection.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var data = new Argus.Shared.Registration.Data() {
	 *     name = "office-server",
	 *     addresses = { "192.0.2.10" },
	 *     port = 817
	 * };
	 * }}}
	 */
```

#### Remove — deregister members (after property fields, before `rpc_register`)

```vala
		/**
		 * Deregister finished.
		 *
		 * @param removed true when the saved login was deleted
		 */
		public signal void finished(bool removed);

		private unowned Gtk.Widget deregister_parent;
		private Argus.Shared.SQT.Server? clear_row;
		private SQ.Database? clear_db;

```

#### Remove — deregister methods

```vala
		/**
		 * Remove this controller's server row and saved login.
		 *
		 * The call uses the TLS connection already open for this
		 * certificate. The connection closes after the server
		 * answers. The call has five seconds. If it does not answer,
		 * the dialog can still drop the saved login. {@link finished}
		 * reports the outcome.
		 *
		 * @param parent window that presents the dialogs
		 * @param rpc open TLS client for this server
		 * @param row saved server row for this window
		 * @param db controller client database
		 */
		public void deregister(
			Gtk.Widget parent,
			OLLMrpc.Client rpc,
			Argus.Shared.SQT.Server row,
			SQ.Database db)
		{
			this.deregister_parent = parent;
			this.clear_row = row;
			this.clear_db = db;
			if (row.pem_client_certificate == "") {
				this.fail("The saved server has no certificate.");
				return;
			}
			GLib.TlsCertificate cert;
			try {
				cert = new GLib.TlsCertificate.from_pem(
					row.pem_client_certificate, row.pem_client_certificate.length);
			} catch (GLib.Error e) {
				this.fail(e.message);
				return;
			}
			var fingerprint = GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, cert.certificate.data);
			if (!rpc.connected) {
				this.offer_local("The server did not answer.");
				return;
			}
			var settled = false;
			uint wait = 0;
			wait = GLib.Timeout.add_seconds(5, () => {
				if (settled) {
					return false;
				}
				settled = true;
				wait = 0;
				this.offer_local("The server did not answer.");
				return false;
			});
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Registration.deregister",
				args = OLLMrpc.args("s", fingerprint)
			}, (call_obj, call_res) => {
				if (settled) {
					return;
				}
				settled = true;
				if (wait != 0) {
					GLib.Source.remove(wait);
					wait = 0;
				}
				var response = new OLLMrpc.Response();
				try {
					response = rpc.call.end(call_res);
				} catch (GLib.Error e) {
					this.offer_local(e.message);
					return;
				}
				if (response.error != null) {
					this.fail(response.error.message);
					return;
				}
				rpc.disconnect();
				this.clear_and_finish(row, db);
			});
		}

		/**
		 * Offer to drop the saved login after the server call stops.
		 *
		 * @param message why the server call stopped
		 */
		private void offer_local(string message)
		{
			this.finished(false);
			var down = new Argus.Shared.Notice("Could not deregister", message);
			down.add_response("cancel", "Cancel");
			down.add_response("local", "Deregister locally");
			down.responded.connect((response) => {
				if (response != "local") {
					return;
				}
				if (this.clear_row != null && this.clear_db != null) {
					this.clear_and_finish(this.clear_row, this.clear_db);
				}
			});
			down.present(this.deregister_parent);
		}

		/**
		 * Drop the saved login and report it on OK.
		 */
		private void clear_and_finish(
			Argus.Shared.SQT.Server row,
			SQ.Database db)
		{
			try {
				row.remove(db);
			} catch (GLib.Error e) {
				this.fail(e.message);
				return;
			}
			var done = new Argus.Shared.Notice("Deleted okay", "");
			done.add_response("ok", "OK");
			done.closed.connect(() => {
				this.finished(true);
			});
			done.present(this.deregister_parent);
		}

		/**
		 * Show a deregister failure.
		 *
		 * @param message failure text
		 */
		private void fail(string message)
		{
			this.finished(false);
			var failed = new Argus.Shared.Notice("Could not deregister", message);
			failed.add_response("ok", "OK");
			failed.present(this.deregister_parent);
		}
```

#### Replace with — class docblock (before `public class Data`)

```vala
	/**
	 * Registration reply from the management server (RPC / JSON).
	 *
	 * The privileged controller command prints this type. Deregister is
	 * {@link Argus.Shared.Register.remove}; notices are on
	 * {@link Argus.Controller.Window}, not this class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var data = new Argus.Shared.Registration.Data() {
	 *     name = "office-server",
	 *     addresses = { "192.0.2.10" },
	 *     port = 817
	 * };
	 * }}}
	 */
```

---

### R1.2 — [`shared/Register.vala`](../../shared/Register.vala): `remove` + signals

**Where:** class `Register`, after the **`save`** method. **No Gtk.**

#### Add — signals (after `server_row` property, with other registration state)

```vala
		/**
		 * Deregister could not complete.
		 */
		public signal void remove_failed(string message);

		/**
		 * {@link Registration.deregister} did not complete (timeout or transport).
		 * UI may still call {@link remove_local}.
		 */
		public signal void remove_server_unreachable(string message);

		/**
		 * The saved server row was removed from {@link client_db}.
		 */
		public signal void remove_row_deleted();
```

#### Add — methods (end of class)

```vala
		/**
		 * Ask the management server to drop this certificate, then remove the
		 * local {@link Argus.Shared.SQT.Server} row.
		 *
		 * Uses the TLS {@link OLLMrpc.Client} already open for this
		 * registration. Emits {@link remove_server_unreachable}, {@link remove_failed},
		 * or {@link remove_row_deleted}. {@link client_db} must be set.
		 */
		public void remove(Argus.Shared.SQT.Server row, OLLMrpc.Client rpc)
		{
			var db = this.client_db;
			if (db == null) {
				this.remove_failed("The client database is not set.");
				return;
			}
			if (row.pem_client_certificate == "") {
				this.remove_failed("The saved server has no certificate.");
				return;
			}
			GLib.TlsCertificate cert;
			try {
				cert = new GLib.TlsCertificate.from_pem(
					row.pem_client_certificate, row.pem_client_certificate.length);
			} catch (GLib.Error e) {
				this.remove_failed(e.message);
				return;
			}
			var fingerprint = GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, cert.certificate.data);
			if (!rpc.connected) {
				this.remove_server_unreachable("The server did not answer.");
				return;
			}
			var settled = false;
			uint wait = 0;
			wait = GLib.Timeout.add_seconds(5, () => {
				if (settled) {
					return false;
				}
				settled = true;
				wait = 0;
				this.remove_server_unreachable("The server did not answer.");
				return false;
			});
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Registration.deregister",
				args = OLLMrpc.args("s", fingerprint)
			}, (call_obj, call_res) => {
				if (settled) {
					return;
				}
				settled = true;
				if (wait != 0) {
					GLib.Source.remove(wait);
					wait = 0;
				}
				var response = new OLLMrpc.Response();
				try {
					response = rpc.call.end(call_res);
				} catch (GLib.Error e) {
					this.remove_server_unreachable(e.message);
					return;
				}
				if (response.error != null) {
					this.remove_failed(response.error.message);
					return;
				}
				rpc.disconnect();
				this.remove_local(row);
			});
		}

		/**
		 * Remove the local row only (after {@link remove_server_unreachable}).
		 */
		public void remove_local(Argus.Shared.SQT.Server row)
		{
			var db = this.client_db;
			if (db == null) {
				this.remove_failed("The client database is not set.");
				return;
			}
			try {
				row.remove(db);
			} catch (GLib.Error e) {
				this.remove_failed(e.message);
				return;
			}
			this.remove_row_deleted();
		}
```

#### Replace — class doc (enroll/remove pairing)

**Replace** the opening class doc so it names **`save`** and **`remove`** as the SQLite persistence pair; keep **`try_connection`** / **`try_batch`** as today.

---

### R1.3 — [`shared/Register.vala`](../../shared/Register.vala): drop mirrored server fields

**Why:** After the SQLite cutover, **`server_row`** holds the enroll outcome. **`download`**, **`download_path`**, and **`addresses`** on **`Register`** are leftover copies of **`SQT.Server`** columns (see cutover note in [done/2026-11-20-FIXED-local-registration-cutover.md](done/2026-11-20-FIXED-local-registration-cutover.md)).

#### Remove — duplicate properties (and their docblocks)

```vala
		/**
		 * Download socket, ''host:port''.
		 *
		 * The host is the one {@link try_connection} connected to.
		 * The port is {@link Argus.DOWNLOAD_PORT}. Empty until
		 * registration stores it. Also written as ''download'' next
		 * to the certificate files.
		 */
		public string download = "";

		/**
		 * Download URL path from the registration reply.
		 *
		 * Empty until a reply stores it. Also written as
		 * ''download-path'' next to the certificate files. The
		 * path includes the extension for the OS family this call
		 * sent. The server chooses it.
		 */
		public string download_path = "";

		/**
		 * Listen addresses from the registration reply, one per line.
		 *
		 * Empty when the reply has none after the download URL path.
		 */
		public string addresses = "";
```

#### Remove — mirror writes in `try_connection` (after `server_row` assignment)

```vala
			this.download = this.server_row.download;
			this.download_path = this.server_row.download_path;
			this.addresses = listen;
```

#### Replace with — [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala) (~650–662)

Use **`registration.server_row`** only (success path already requires a row):

```vala
				var lines = registration.server_row.addresses.split("\n");
				if (lines.length > 0) {
					var listed = lines[0].strip();
					var mark = listed.last_index_of(":");
					if (mark > 0) {
						int.try_parse(listed.substring(mark + 1), out app_port);
					}
				}
				this.registered_url = "tcp://" + host + ":" + app_port.to_string();
				this.registered_addresses = registration.server_row.addresses;
				if (!this.remember(
					registration, host, registration.server_row.port,
					registration.server_row.addresses)) {
```

---

### R1.4 — [`controller/SQT/Server.vala`](../../controller/SQT/Server.vala)

**Where:** end of class `Server`, after `store_certificates`. **No Gtk. No `Notice`.**

#### Add

```vala
		/**
		 * SHA-256 fingerprint of the client certificate (deregister RPC argument).
		 */
		public string fingerprint() throws GLib.Error
		{
			if (this.pem_client_certificate == "") {
				throw new GLib.IOError.FAILED("The saved server has no certificate.");
			}
			GLib.TlsCertificate cert = new GLib.TlsCertificate.from_pem(
				this.pem_client_certificate, this.pem_client_certificate.length);
			return GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, cert.certificate.data);
		}
```

---

### R1.5 — [`controller/Window.vala`](../../controller/Window.vala)

#### Remove

```vala
		private Argus.Shared.Registration.Data deregister_flow {
			get; set; default = new Argus.Shared.Registration.Data();
		}
```

#### Remove

```vala
			this.deregister_flow.finished.connect((removed) => {
				if (removed) {
					this.app.quit();
					return;
				}
				this.deregister_action.set_enabled(true);
			});
```

#### Remove

```vala
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.deregister_flow.deregister(
					this, this.app.rpc, this.server, this.app.client_db);
			});
```

#### Add — field (with other `Window` members)

```vala
		private Argus.Shared.Register registration {
			get; set; default = new Argus.Shared.Register();
		}
```

#### Add — in constructor (where `deregister_flow.finished` was removed)

```vala
			this.registration.remove_failed.connect((message) => {
				this.deregister_action.set_enabled(true);
				var failed = new Argus.Shared.Notice("Could not deregister", message);
				failed.add_response("ok", "OK");
				failed.present(this);
			});
			this.registration.remove_server_unreachable.connect((message) => {
				this.deregister_action.set_enabled(true);
				var down = new Argus.Shared.Notice("Could not deregister", message);
				down.add_response("cancel", "Cancel");
				down.add_response("local", "Deregister locally");
				down.responded.connect((response) => {
					if (response != "local") {
						return;
					}
					this.deregister_action.set_enabled(false);
					this.registration.client_db = this.app.client_db;
					this.registration.remove_local(this.server);
				});
				down.present(this);
			});
			this.registration.remove_row_deleted.connect(() => {
				var done = new Argus.Shared.Notice("Deleted okay", "");
				done.add_response("ok", "OK");
				done.closed.connect(() => {
					this.app.quit();
				});
				done.present(this);
			});
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.registration.client_db = this.app.client_db;
				this.registration.remove(this.server, this.app.rpc);
			});
```

---

### R1.6 — [`controller/android/Window.vala`](../../controller/android/Window.vala)

#### Remove

```vala
		private Argus.Shared.Registration.Data deregister_flow {
			get; set; default = new Argus.Shared.Registration.Data();
		}
```

#### Remove — inside `open()`, after `this.host = host;`

```vala
			this.deregister_flow.finished.connect((removed) => {
				if (removed) {
					this.app.quit();
					return;
				}
				this.deregister_action.set_enabled(true);
			});
```

#### Remove

```vala
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.deregister_flow.deregister(
					this, this.app.rpc, this.server, this.app.client_db);
			});
```

#### Add — same as R1.5 (field, signal handlers, `deregister_action.activate`)

Mirror **R1.5** on android: **`registration`**, connect **`remove_failed`**, **`remove_server_unreachable`**, **`remove_row_deleted`**, and call **`remove` / `remove_local`** with **`this.app.client_db`**.

---

## R2 — Bootstrap: save registration through `Register.save`

**Review:** No product choices — same **persist** implementation as the agent (`Register.save` → **`row.save`**). **Controller only:** the Linux CA compare in **`finish_registration`** must run **before** any save (it reads existing libsecret PEMs via **`Store.Server.list()`**). Do **not** call **`reg.save`** in **`certificate_received`** and then **`finish_registration`** — that would write the new CA first and void the check. **`finish_registration`** should call **`Register.save`** after the compare (or take a **`Register`** and delegate).

**Call-site contract (doc only, no extra keyring field):** **`Argus.Shared.Register.save`** on the controller is for **`finish_registration`** / Bootstrap — not a second public persist path beside **`finish_registration`**. Agents call **`save`** directly (no CA compare).

**Files:** [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) — **`certificate_received`** (~690–718) and **`finish_registration`** (~546–614).

#### Remove

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

#### Replace with

```vala
				reg.client_db = this.app.client_db;
				var row = new Argus.Controller.SQT.Server() {
					name = window.registration_name,
				};
				this.finish_registration(reg, row);
```

#### Add / replace — `finish_registration` (use `Register.save` after CA compare, not `row.save` alone)

**Remove** the trailing **`row.save(this.app.client_db)`** inside **`finish_registration`** and **replace** with:

```vala
			reg.client_db = this.app.client_db;
			if (!reg.save(row)) {
#if ANDROID
				this.page("Could not register",
					"The registration could not be saved.",
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
#else
				this.page("Could not register",
					"The registration could not be saved.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
				return;
			}
```

**Change** the method signature to accept the successful **`Register`** from the dialog (e.g. **`finish_registration(Argus.Shared.Register reg, Argus.Controller.SQT.Server row)`**). **Local pkexec** path builds a row from **`Registration.Data`** and calls the same method with a **`Register`** whose **`server_row`** (or equivalent) is already populated, or a one-shot **`Register`** + field copy — keep **CA compare first**, then **`reg.save(row)`**.

#### Add — doc on [`shared/Register.vala`](../../shared/Register.vala) **`save`**

In the **`save`** docblock, note that **controllers** persist enroll outcomes through **`Bootstrap.finish_registration`** (CA policy on Linux); agents may call **`save`** directly.

---

## R3 — Comments and stale names

**Review:** Comment and doc fixes only — no behaviour change except **`RegisterWindow.client_db`** wiring.

---

### R3.1 — [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) `check()` doc

#### Replace

```vala
		/**
		 * Load ''connections.json'' and try each saved server.
		 *
		 * A missing or empty file offers ''Log in to register''.
		 * An unreadable file offers retry and registration.
		 */
```

#### With

```vala
		/**
		 * Load saved servers from SQLite and try each address.
		 *
		 * An empty list offers ''Log in to register''.
		 * An unreadable store offers retry and registration.
		 */
```

---

### R3.2 — [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala) + [`agent/linux/Application.vala`](../../agent/linux/Application.vala)

**Goal:** Set **`client_db`** when **`RegisterWindow`** constructs **`Register`**, not in **`certificate_received`**.

#### Add — on `RegisterWindow` (near `data_dir`)

```vala
		/**
		 * Client SQLite for {@link Argus.Shared.Register.save} on the agent.
		 */
		public SQ.Database? client_db = null;
```

#### Add — in `send_pin` handler where `new Register()` is built (~615)

```vala
				client_db = this.client_db,
```

#### Replace — [`agent/linux/Application.vala`](../../agent/linux/Application.vala) `present_registration`

```vala
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = this.data_dir
			};
```

#### With

```vala
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = this.data_dir,
				client_db = this.client_db
			};
```

#### Remove — inside `certificate_received`

```vala
				reg.client_db = this.client_db;
```

---

### R3.3 — [`controller/Window.vala`](../../controller/Window.vala) stale example / `@param`

#### Replace — class example (~45)

```vala
	 * var window = new Argus.Controller.Window(app, connection, issued, host);
```

#### With

```vala
	 * var window = new Argus.Controller.Window(app, server, host);
```

#### Replace — constructor doc (`@param connection`, `@param issued`)

```vala
		 * @param connection the server that answered
		 * @param issued certificate from this process, or empty
		 * @param host the server that answered
```

#### With

```vala
		 * @param server saved management-server row for this window
		 * @param host address that answered the startup probe
```

**Product ripgrep (2026-11-20):** no `window.connection` / `Controller.Connection` left in `*.vala`. **`controller/Rdp/Screen.vala`** and open bugs may still mention old names — fix when those files are touched.

---

### R3.4 — [`docs/valadoc-wiki/index.valadoc`](../../docs/valadoc-wiki/index.valadoc)

#### Replace — Controller bullet (~41)

```text
  * ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Application.html|Application]]'' hellos on the Unix socket. ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Bootstrap.html|Bootstrap]]'' may open ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Window.html|Window]]''. ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Pin.html|Pin]]'', ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Agents.html|Agents]]'', ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Command.html|Command]]'', ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Connection.html|Connection]]'', ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.PairingDialog.html|PairingDialog]]''.
```

#### With

```text
  * ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Application.html|Application]]'' hellos on the Unix socket. ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Bootstrap.html|Bootstrap]]'' may open ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Window.html|Window]]''. Saved rows: ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.SQT.Server.html|Controller.SQT.Server]]'' and ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.Store.Server.html|Controller.Store.Server]]''. ''[[https://roojs.github.io/argusrm/argus/Argus.Controller.PairingDialog.html|PairingDialog]]''.
```

---

## R4 — Connect address order and route filter

### Settled — filter in the server row only

**Do not** filter on registration (`Register.try_connection`, Bootstrap pkexec JSON, etc.). SQLite **`addresses`** keeps the full text from the reply.

1. **Single place:** [`shared/SQT/Server.vala`](../../shared/SQT/Server.vala) **`address_list()`** — when parsing **`this.addresses`** into the in-memory array, **do not add** a line whose host fails **`Argus.Shared.Net.Route.can_route_to`** (Linux).
2. **Consumers** (**`Bootstrap.probe`**, agent **`socket(index)`**, subtitles) use **`address_list()`** — try order **0 .. n−1** on that array only.
3. **`last_host`** rotation is **not** in scope.

**Today in tree:** **`address_list()`** adds every line; **R4** changes that loop only.

**Route code to reuse:** [`server/Net/Interfaces.vala`](../../server/Net/Interfaces.vala) **`route(GLib.InetAddress)`** (netlink lookup, cached). **R4.1** adds a **Linux-only** copy in **`shared/linux/Net/Route.vala`** (same **`libnl-route-3`** / vapi as server). Server may call shared later; not required for this bug.

💩 **Windows / Android:** **`can_route_to`** returns **true** (try connect as today).

---

### R4.1 — New [`shared/linux/Net/Route.vala`](../../shared/linux/Net/Route.vala)

**Review:** Port the **destination route lookup** from **`Server.Net.Interfaces.route`** into a static helper. **No Gtk.**

#### Add — new file (minimal public API)

```vala
namespace Argus.Shared.Net
{
	/**
	 * Whether this host has a kernel route (Linux netlink).
	 */
	public class Route : GLib.Object
	{
		/**
		 * @param host destination hostname or IP
		 * @return false when there is no routable path (Linux); always true elsewhere
		 */
		public static bool can_route_to(string host)
		{
#if LINUX
			/* Same netlink rtnl_route_lookup logic as Argus.Server.Net.Interfaces.route;
			 * omit local-address membership check — we only need reachable vs unrouted. */
			// … body adapted from server/Net/Interfaces.vala …
			return false;
#else
			return true;
#endif
		}
	}
}
```

💩 Implementer copies the **`Nl.Route.lookup`** block from **`server/Net/Interfaces.vala`** (`route()`), returns **true** when lookup succeeds with a preferred source, **false** on miss / parse error.

---

### R4.2 — [`shared/meson.build`](../../shared/meson.build) (Linux)

#### Add — when `host_machine.system() == 'linux'`

- Source: **`linux/Net/Route.vala`** appended to **`shared_sources`** (and **`shared_cli_lib`** inputs).
- Deps: **`libnl-3.0`** + **`nl-route-3`** (same pattern as [`server/meson.build`](../../server/meson.build)).
- Vala: **`--vapidir`** `../server/vapi`, **`--pkg`** `libnl-3.0`, **`-D`** `LINUX`.

---

### R4.3 — [`shared/SQT/Server.vala`](../../shared/SQT/Server.vala) `address_list()`

#### Replace — loop body

```vala
					foreach (var line in this.addresses.split("\n")) {
						var text = line.strip();
						if (text != "") {
							this.address_list_hosts.add(text);
						}
					}
```

#### With

```vala
					foreach (var line in this.addresses.split("\n")) {
						var text = line.strip();
						if (text == "") {
							continue;
						}
						var host = text;
						var mark = text.last_index_of(":");
						if (mark > 0) {
							host = text.substring(0, mark);
						}
						if (!Argus.Shared.Net.Route.can_route_to(host)) {
							continue;
						}
						this.address_list_hosts.add(text);
					}
```

**No change** to **`Register`**, **`Bootstrap`** address assembly, or **`Bootstrap.probe`** (it already uses **`row.address_list()`**).

---

### Settled — CA fingerprint and libsecret (controller only)

| Topic | Truth in tree |
| --- | --- |
| **Who** | **Controller** re‑register / local pkexec path only. **`Bootstrap.finish_registration`** (Linux) before **`row.save`**. **Agents** do not run this CA compare; they keep PEMs under **`data_dir`** + SQLite and replace certs on a new successful register. |
| **What is stored** | **`Controller.SQT.Server.store_certificates`** already **`Json.gobject_to_data(this)`** into libsecret (full row object: client key, client cert, **CA PEM**). SQLite holds non‑secret columns only. There is **no** separate fingerprint field today. |
| **What the fingerprint is for** | A **one‑time SHA‑256 of the CA cert bytes** to block re‑registering the **same server name** when the new management CA **does not match** the saved one (“The saved server certificate does not match.”). That is **not** the TLS **client** fingerprint used for **`Registration.deregister`**. |
| **Need a keyring fingerprint?** | **No.** Load existing PEMs from libsecret (or empty), hash **`pem_ca_certificate`** at register time — same data as the serialized object. A duplicate fingerprint attribute would not add behaviour unless you wanted compare **without** loading secrets (not a current requirement). |

**Conclusion:** Keep pre‑save compare in **`finish_registration`**; keep whole‑object JSON in libsecret. No separate fingerprint field. Remote register today already goes **`certificate_received` → `finish_registration`** (CA check then save) — not a product gap, only a **call-site contract** documented in **R2** and **`Register.save`**.

(Question 4 from the old cutover bug — download path sidecar files — is settled: the agent writes them in `store_certificates`.)

---

## Suggested order

1. **R1.1–R1.2** — strip **`Registration.Data`** deregister; add **`Register.remove`** + signals.
2. **R1.3** — drop mirrored **`Register`** server fields; fix **`RegisterWindow`**.
3. **R1.4–R1.6** — controller fingerprint helper (optional if **`remove`** parses PEM inline); wire **`Window`** / android to signals.
4. **R2** — Bootstrap **`reg.save`**.
5. **R3** — comments and grep.
6. **R4** — **`can_route_to`** in **`SQT.Server.address_list()`** only.
7. When deregister and config reads are in good shape, pick up reconnect/tray items in [desktop-status](2026-11-19-desktop-status-and-reconnect.md) (management migration closed — see [done/2026-11-19-FIXED-management-link-application-migration.md](done/2026-11-19-FIXED-management-link-application-migration.md)).