# Provisional registration — remaining work

**Status:** ✔️

### User decisions required

- 💩 **Second `PairPublish` on bulk open** — separate mDNS publish from the six-digit PIN window, or keep one `pair_publish` for both until lab needs split (see **Proposed fix → Phase 1 → `Offering.Network` second publish**).

### User reported

- 🔷 Ship provisional bulk registration for the next Windows office rollout: queue on the server, status on the registration port, controller Agents UI and clients in later phases.

### Success scenario

- Phase 1 — `meson test offering-registration` passes status and polling-enroll checks; field script bulk on → two provisionals → bulk off → queue persists → accept one / reject one; registration port stays up through accept/poll.
- Phase 2 — pending tab, toolbar modes, stall banner on controller.
- Phase 3 — Windows auto provisional enroll and registration-port poll.
- Phase 4 — Linux `Register.try_batch` uses registration port, not app `hello`.
- Phase 5 — archived end-to-end scenarios (stall after accept, controller blocked on agent paths).

### Current behavior

- Phase 1a wire and `offering-registration` integration test are in the tree (see **LLM** sign-off table).
- Phase 1 lifecycle items are still open: `Offering.status` stub, polling enroll bug, reject/accept client lifecycle, watchdog, controller-on-agent-path.

### Codebase observed behavior

- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) `status` replies `status not implemented`.
- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) `enroll` treats `polling` as open, so `0000` batch can still queue after bulk close.

```vala
var open = net.pin != "" || net.accepting || net.polling;
var queued = batch && pin == "0000" && !is_controller && open;
```

- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) `reject` deletes `agent_pending` rows only; no tombstone for status poll.
- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) `accept` promotes rows; no stall notification; no reject tombstone for status.
- [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala) `accept` loads each pending row with `selectWhere` per `id` in the loop (wasteful for multi-select).
- [`server/Offering/Network.vala`](../../server/Offering/Network.vala) bulk `DeskState.ARM` calls `update_bulk(DeskState.CLOSED)` when the supervising controller disconnects, even when pending rows remain.
- [`shared/Register.vala`](../../shared/Register.vala) `try_batch` still polls **`RPC-Daemon.hello`** on the app socket (Phase 4).
- [`docs/rpc-commands.md`](../rpc-commands.md) documents `Offering.status` as a stub.

### Debugging

#### Current debug output

- None yet.

#### Debug code added (remove when complete)

- None.

### Proposed fix

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify surrounding lines before applying. Vala in fences matches [`docs/coding-standards.md`](../coding-standards.md).

### ✔️ Phase 1 — server lifecycle

Approved types only: **Network**, **Rpc**, **Certificate**. Use existing **`pending`**, **`polling`**, **`pin`**, **`update_bulk(DeskState)`** — no new enums, no lifecycle helper methods.

#### `server/Offering/Rpc.vala` — reject tombstones (in-memory)

**Why:** `Offering.reject` deletes the row; `Offering.status` must still answer **`rejected`** for that client cert until the client clears it.

#### Remove — fields on `Rpc` at start of class

```vala
		public Application app { get; private set; }
		public Network network { get; private set; }
```

#### Replace with

```vala
		public Application app { get; private set; }
		public Network network { get; private set; }

		private Gee.HashSet<string> rejected_provisional =
			new Gee.HashSet<string>();
```

#### `server/Offering/Rpc.vala` — `Offering.status`

**Why:** Provisional clients poll the registration port instead of app `hello`.

#### Remove

```vala
		public void status(OLLMrpc.Request request)
		{
			request.reply(new OLLMrpc.Response() {
				error = new OLLMrpc.Error.INVALID_REQUEST(
					"status not implemented")
			});
		}
```

#### Replace with

```vala
		public void status(OLLMrpc.Request request)
		{
			var rpc = request.connection as Net.SslConnection;
			if (rpc == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(
						"socket registration only")
				});
				return;
			}
			if (rpc.cert_fingerprint == "") {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(
						"provisional certificate required")
				});
				return;
			}
			if (this.rejected_provisional.contains(rpc.cert_fingerprint)) {
				request.reply(new OLLMrpc.Response() {
					msg = "rejected"
				});
				return;
			}
			var pending = new Gee.ArrayList<Argus.Shared.AgentPending>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", rpc.cert_fingerprint);
			Argus.Shared.AgentPending.query(this.app.db).selectWhere(
				"WHERE fingerprint = $fingerprint",
				int_binds, text_binds, pending);
			if (pending.size > 0) {
				request.reply(new OLLMrpc.Response() {
					msg = "pending"
				});
				return;
			}
			var agents = new Gee.ArrayList<Argus.Shared.Agent>();
			Argus.Shared.Agent.query(this.app.db).selectWhere(
				"WHERE fingerprint = $fingerprint AND status = 1",
				int_binds, text_binds, agents);
			if (agents.size > 0) {
				request.reply(new OLLMrpc.Response() {
					msg = "accepted"
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				error = new OLLMrpc.Error.INVALID_REQUEST(
					"unknown registration")
			});
		}
```

#### `server/Offering/Rpc.vala` — `enroll` (bulk queue + controller gate)

**Why:** `polling` must allow status TLS only, not new `0000` rows. Controller must not use agent PIN or bulk desk.

#### Remove — after existing `var net = this.network;` in `enroll`

```vala
			var open = net.pin != "" || net.accepting || net.polling;
			var queued = batch && pin == "0000" && !is_controller && open;
```

#### Replace with

```vala
			if (is_controller &&
				(batch || net.pending || net.polling || net.pin != "")) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(
						"This registration is for agents only.")
				});
				return;
			}
			var queued = batch && pin == "0000" && !is_controller &&
				net.pending && !net.polling;
```

- ℹ️ `var net = this.network` stays as in tree today (`enroll` body); this hunk drops **`open`** and fixes **`queued`** only. New **`Offering.status`** uses `rpc.cert_fingerprint` with no `fp` alias.

#### `server/Offering/Rpc.vala` — `reject` records fingerprint

**Why:** Status poll returns **`rejected`** after the row is gone.

#### Remove — `reject` foreach body

```vala
			foreach (var id in ids) {
				Argus.Shared.AgentPending.query(this.app.db).deleteId(id);
			}
			this.app.db.backupDB();
```

#### Replace with

```vala
			var pending_rows = new Gee.ArrayList<Argus.Shared.AgentPending>();
			Argus.Shared.AgentPending.query(this.app.db).select("", pending_rows);
			var pending_by_id = new Gee.HashMap<int, Argus.Shared.AgentPending>();
			foreach (var pending_row in pending_rows) {
				pending_by_id.set((int) pending_row.id, pending_row);
			}
			foreach (var id in ids) {
				if (!pending_by_id.has_key(id)) {
					continue;
				}
				var row = pending_by_id.get(id);
				if (row.fingerprint != "") {
					this.rejected_provisional.add(row.fingerprint);
				}
				Argus.Shared.AgentPending.query(this.app.db).deleteId(id);
			}
			this.app.db.backupDB();
```

#### `server/Offering/Rpc.vala` — `accept` pending lookup (one load)

**Why:** Tree today runs `selectWhere` on `agent_pending` once per `id` in the loop; same queue read as **`reject`**.

#### Remove — `accept` body after `var changed = false;` through `var row = rows.get(0);`

```vala
			foreach (var id in ids) {
				var rows = new Gee.ArrayList<Argus.Shared.AgentPending>();
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", id);
				Argus.Shared.AgentPending.query(this.app.db).selectWhere(
					"WHERE id = $id", int_binds, text_binds, rows);
				if (rows.size < 1) {
					continue;
				}
				var row = rows.get(0);
```

#### Replace with

```vala
			var pending_rows = new Gee.ArrayList<Argus.Shared.AgentPending>();
			Argus.Shared.AgentPending.query(this.app.db).select("", pending_rows);
			var pending_by_id = new Gee.HashMap<int, Argus.Shared.AgentPending>();
			foreach (var pending_row in pending_rows) {
				pending_by_id.set((int) pending_row.id, pending_row);
			}
			foreach (var id in ids) {
				if (!pending_by_id.has_key(id)) {
					continue;
				}
				var row = pending_by_id.get(id);
```

- ℹ️ Per-id **`agent`** fingerprint lookup in **`accept`** stays (promote path).

#### `server/Offering/Rpc.vala` — stalled after Accept (~30 min)

**Why:** Phase 2 banner; Phase 1 only needs `event.pair` `stalled` on the wire. Cancelling the timer when the agent connects on the app socket is Phase 2.

#### Remove — end of `accept` loop body (after `deleteId`)

```vala
				Argus.Shared.AgentPending.query(this.app.db).deleteId(row.id);
				changed = true;
```

#### Replace with

```vala
				Argus.Shared.AgentPending.query(this.app.db).deleteId(row.id);
				if (row.fingerprint != "") {
					GLib.Timeout.add_seconds(30 * 60, () => {
						this.app.broadcast(new OLLMrpc.Notification() {
							method = "event.pair",
							action = "stalled",
							args = OLLMrpc.args("s", row.fingerprint)
						});
						return false;
					});
				}
				changed = true;
```

#### `server/Offering/Network.vala` — bulk ARM supervisor drop

**Why:** Do not call `CLOSED` while `agent_pending` rows still exist.

#### Remove — `update_bulk` `DeskState.ARM` supervisor disconnect branch

```vala
						this.update_bulk(DeskState.CLOSED);
						GLib.debug(
							"registration closed after controller disconnected");
```

#### Replace with

```vala
						var pending_rows =
							new Gee.ArrayList<Argus.Shared.AgentPending>();
						Argus.Shared.AgentPending.query(this.app.db)
							.select("", pending_rows);
						if (pending_rows.size > 0) {
							this.update_bulk(DeskState.POLLING);
						} else {
							this.update_bulk(DeskState.CLOSED);
						}
						GLib.debug(
							"registration closed after controller disconnected");
```

#### `docs/rpc-commands.md` — `Offering.status`

#### Remove — `### Offering.status` section

```markdown
### `Offering.status`

- Socket: the registration socket with the provisional client certificate.
- Direction: agent calls the server.
- Arguments: none.
- ℹ️ Stub in `server/Offering/Rpc.vala` until registration-port status polling lands.
```

#### Replace with

```markdown
### `Offering.status`

- Socket: the registration socket with the provisional client certificate from `Offering.enroll`.
- Direction: agent calls the server.
- Arguments: none.
- Reply `msg`: `pending` while the fingerprint is in `agent_pending`; `accepted` after `Offering.accept` promoted the row to `agent` with `status = 1`; `rejected` after `Offering.reject` removed that pending row (client wipes local cert).
- No client certificate: `provisional certificate required`. Unknown fingerprint: `unknown registration`.
- ℹ️ `server/Offering/Rpc.vala`.
```

#### `server/tests/offering-registration.vala` — status and polling enroll

**Why:** Integration test still expects the stub.

#### Remove

```vala
			var status = status_tls(reg_port);
			note(status != null && status.error != null,
				"Offering.status returns error while stub");
			note(status != null && status.error != null &&
				status.error.message.index_of("not implemented") >= 0,
				"Offering.status stub message");
```

#### Replace with — after `note(registration_tls_handshake(reg_port), "registration TLS up in polling");`

```vala
			var accepted = status_tls(reg_port);
			note(accepted != null && accepted.error == null &&
				accepted.msg == "accepted",
				"Offering.status accepted after accept");

			var late_bulk = enroll_tls(reg_port, "0000", csr_bulk_b,
				"late-bulk", true);
			note(late_bulk == null || late_bulk.msg != "pending",
				"no provisional enroll while polling");
```

#### `Offering.Network` second publish (optional)

**Why:** Product decision — instant PIN vs bulk may need separate Avahi publishes.

#### Add — on `Network` when user approves

```vala
		public OLLMrpc.Transport.PairPublish bulk_publish {
			get; set; default = new OLLMrpc.Transport.PairPublish() {
				min_port = 1
			};
		}
```

- `update_pin(OPEN)` keeps `pair_publish`.
- `update_bulk(OPEN)` starts `bulk_publish` instead of `pair_publish`.
- `POLLING` / `CLOSED` stops both.

### Phase 2 — controller Agents page

- Pending registration tab; toolbar **Bulk registration**, **Agent registration**, **Controller registration**; consume `event.pair` `stalled`.
- **Done when:** tab behaviour + banner verified on lab controller.

### Phase 3 — Windows client (unregistered)

- Auto provisional enroll; registration-port status poll (~10 min); `accepted` / `rejected` handling.
- **Done when:** bulk on → **Accept** on controller → Windows connected without manual PIN.

### Phase 4 — Linux / shared register client

- Same status poll; replace `try_batch` app `hello` loop with `Offering.status` on registration TLS.

### Phase 5 — end-to-end verify

- Archived scenarios: bulk queue, stall after accept, controller blocked on agent paths.

### LLM

- ℹ️ Priority: high — next Windows office rollout.
- ℹ️ Full spec (archived): `docs/bugs/done/2026-11-24-archived-provisional-registration-broadcast.md`.
- ℹ️ Process: `docs/bug-fix-process.md`, `docs/rpc-commands.md`, `server/Offering/`.
- ℹ️ 2026-11-25: Active tracker split from archived feature doc; Phase 1a + `offering-registration` test signed off below.

**Closed in tree (2026-11-25) — do not re-litigate**

| Item | ✔️ |
| --- | --- |
| **`Offering.*`** wire (`open`, `close`, `enroll`, `accept`, `reject`; **`status`** stub) | [`server/Offering/Rpc.vala`](../../server/Offering/Rpc.vala), [`docs/rpc-commands.md`](../rpc-commands.md) |
| **`Offering.Network`** (registration TLS, offering nftables, PairPublish) | [`server/Offering/Network.vala`](../../server/Offering/Network.vala) |
| **`Application.offering`**; no **`register_listen`** / **`publish`** on app | [`server/Application.vala`](../../server/Application.vala) |
| Delete **`server/Agent.vala`**; fleet **`SQT.Agent`** | [`server/SQT/Agent.vala`](../../server/SQT/Agent.vala) |
| Clients: **`Offering.enroll`**, controller open/close/accept/reject | [`shared/Register.vala`](../../shared/Register.vala), [`controller/dialog/Pairing.vala`](../../controller/dialog/Pairing.vala), [`controller/cli/Pin.vala`](../../controller/cli/Pin.vala) |
| Registration TLS gate **`Offering.enroll`** / **`Offering.status`** | [`server/Net/SslConnection.vala`](../../server/Net/SslConnection.vala) |
| Integration test | [`server/tests/offering-registration.vala`](../../server/tests/offering-registration.vala), `meson test offering-registration` |

- ℹ️ 2026-11-26: Phase 1 **Proposed fix** rewritten per `docs/guide-to-writing-bug-reports.md` (Remove/Replace with/Add).
- 🚫 **`Offering.Desk`** — not in approved sign-off.
- 🚫 **Lifecycle helper soup** — `RegistrationAudience`, `sync_listener_for_queue`, `accept_watch_*`, etc.; Phase 1 proposal trimmed to **`Rpc`** field + wire methods and one **`Network`** ARM branch.
- ℹ️ 2026-11-26: Every **Replace with** paired with verbatim **Remove** from tree (`docs/guide-to-writing-plans.md` edit contract).
- ℹ️ 2026-11-26: Proposed Vala fences — no trivial aliases (`docs/coding-standards.md` **Temporary Variables**); use `rpc.cert_fingerprint`, `this.network`, `row` like `accept` already does.
- ✔️ 2026-11-26: Phase 1 landed; `meson test offering-registration` OK. Extra: `server/Net/SslListen.vala` — registration listener must not run app-socket “known agent” task connect path (crash on status with accepted cert).