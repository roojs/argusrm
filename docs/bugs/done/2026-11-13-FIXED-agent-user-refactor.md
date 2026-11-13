# Refactor caller `Agent.user` lookup and `SslConnection.user`

**Status:** ✅ closed 2026-11-13.

**Pointer:** `docs/bug-fix-process.md`. Split out of [5.10.1-REJECTED-package-updates.md](../../plans/done/5.10.1-REJECTED-package-updates.md).

---

## Problem

- 🔷 RPC handlers in `shared/OSQuery/` need the caller's `Argus.Shared.Agent` row without repeating the `cert_fingerprint` SQL query at every call site, and without adding redundant `agent_id` or `is_controller` fields onto `SslConnection`.
- 🔷 When a connection is made, the `user` is set up on `SslConnection` (`SslListen` on handshake), and prior to running an RPC call the connection must validate and check freshness — blocking and closing the connection if the user was deactivated or deleted since the connection started.
- 🔷 No changes to `libocrpc` are needed: `OLLMrpc.Transport.Connection` already provides `public virtual bool allow_request(OLLMrpc.Request request)` before `request.dispatch()`, and arbitrary per-connection data can use `GLib.Object.set_data` / `get_data`.
- 🔷 An invalid, deactivated, or deleted certificate on `SslConnection` must not receive an error reply: the connection refreshes the nftables allowlist and shuts down (`stop()`).
- 🔷 `SslConnection` currently stores only `int64 agent_id` instead of the `Argus.Shared.Agent` row (`user`), leaving `server/` unable to read `connection.user.is_controller` when notifying connected controllers.

## Evidence

- ✔️ `OLLMrpc.Transport.Connection` in `OLLMchat` (`libocrpc/Transport/Connection.vala`) already calls `this.allow_request(request)` before `request.dispatch()` in `on_input_ready`.
- ✔️ `server/Net/SslConnection.vala` already subclasses `OLLMrpc.Transport.Connection` and overrides `allow_request(request)`, querying `agent` by `this.cert_fingerprint` before every RPC call (except `Agent.request_registration`).
- ✔️ `shared/Agent.vala` `is_a_controller` queries `WHERE fingerprint = $fingerprint AND status = 1 AND is_controller = 1` inline, and there is no shared `Agent.user(request)` method for agent RPC handlers in `shared/`.
- ✔️ `server/Net/SslConnection.vala` stores `public int64 agent_id { get; set; default = -1; }` and replies `client certificate required` or `certificate not registered` without refreshing the firewall or closing the socket.
- ✔️ `server/Net/SslListen.vala`, `server/OSQuery.vala`, `server/Agent.vala`, and `server/Command.vala` all read or write `connection.agent_id`.
- 🚫 Rejected prior drafts:
  - `Ffi` `GError**` + `Request.dispatch() throws` + `Connection.dispatch_error` + `throws GLib.Error` on every RPC method.
  - Adding `user` / `block_request` / `accepted` to `libocrpc` (`Connection.allow_request` already handles pre-dispatch validation and blocking).

## Root cause

- ✔️ Caller resolution was split between `SslConnection.agent_id` (an `int64` id only visible to `server/`, leaving sockets open on rejection) and `Agent.is_a_controller` (a boolean controller-only query in `shared/` that swallowed the caller row). Keeping `user` (`Argus.Shared.Agent`) on `SslConnection` (synced via `set_data` for `shared/`) and validating freshness in `SslConnection.allow_request` before dispatch lets `Agent.user(request)` read the validated caller directly without touching `libocrpc`, repeating SQL queries, or plumbing `GError` through `Ffi`.

## Proposed fix

- 🔷 No `OLLMchat` / `libocrpc` changes required.
- 🔷 In `server/Net/SslConnection.vala`, replace `agent_id` with `public Argus.Shared.Agent user { get; set; default = new Argus.Shared.Agent(); }`, syncing `set_data("argus-user", this.user)` on `notify["user"]`.
- 🔷 In `server/Net/SslListen.vala`, set `rpc.user = row` on handshake when an active row matches.
- 🔷 In `server/Net/SslConnection.allow_request`, check freshness (`status == 1`) against `agent` before every RPC call (except `Agent.request_registration`) and refresh `this.user = row`. On missing, deactivated (`status != 1`), or empty `cert_fingerprint`, send no reply, log with `GLib.debug()`, refresh `this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces))`, call `this.stop()`, and return `false`.
- 🔷 In `shared/Agent.vala`, add non-throwing `Agent.user(OLLMrpc.Request request)` (reading `get_data<Agent>("argus-user")`, returning a local controller for empty `cert_fingerprint`, or querying `agent` as fallback), and update `Agent.is_a_controller(request)` to use `Agent.user(request)`.
- 🔷 Replace `connection.agent_id` with `connection.user.id` in `server/OSQuery.vala`, `server/Agent.vala`, and `server/Command.vala`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### 1. `shared/Agent.vala` — `user` and `is_a_controller`

**Why:** centralize caller lookup on `Agent` without throwing across `Ffi` or repeating the SQL query when `SslConnection` already attached the validated `Agent` via `set_data`.

**Where:** `user` before `is_a_controller`, and `is_a_controller`.

#### Add — before `is_a_controller`, resolve the caller `Agent` row

```vala
		/**
		 * Caller row for an inbound RPC request.
		 *
		 * The Unix socket has no certificate and returns a local
		 * controller with ''id'' zero. A TLS caller returns the
		 * active ''Agent'' attached to the connection (or queries
		 * ''agent'' by fingerprint when unattached), or an empty
		 * inactive row if none matches.
		 *
		 * @param request inbound RPC request
		 * @return caller ''Agent'' row
		 */
		public static Agent user(OLLMrpc.Request request)
		{
			if (request.connection.cert_fingerprint == "") {
				return new Agent() {
					status = 1,
					is_controller = true
				};
			}
			var caller = request.connection.get_data<Agent>("argus-user");
			if (caller != null) {
				return caller;
			}
			var rows = new Gee.ArrayList<Agent>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", request.connection.cert_fingerprint);
			Agent.query(Agent.db).selectWhere(
				"WHERE fingerprint = $fingerprint AND status = 1",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				return rows.get(0);
			}
			return new Agent();
		}
```

#### Remove

```vala
		 * @param request inbound RPC request
		 * @return true when the caller is a controller
		 */
		public static bool is_a_controller(OLLMrpc.Request request)
		{
			if (request.connection.cert_fingerprint == "") {
				return true;
			}
			var rows = new Gee.ArrayList<Agent>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			text_binds.set("fingerprint", request.connection.cert_fingerprint);
			Agent.query(Agent.db).selectWhere(
				"WHERE fingerprint = $fingerprint AND status = 1 AND is_controller = 1",
				int_binds, text_binds, rows);
			if (rows.size > 0) {
				return true;
			}
```

#### Replace with

```vala
		 * @param request inbound RPC request
		 * @return true when the caller is a controller
		 */
		public static bool is_a_controller(OLLMrpc.Request request)
		{
			var caller = Agent.user(request);
			if (caller.status == 1 && caller.is_controller) {
				return true;
			}
```

### 2. `server/Net/SslConnection.vala` and `server/Net/SslListen.vala` — `SslConnection.user` and freshness gate

**Why:** store the `Argus.Shared.Agent` row directly on `SslConnection` as `user` (syncing `set_data("argus-user", this.user)` for `shared/`) and check freshness and shut down invalid/deactivated/deleted certificates without replying while refreshing the firewall.

**Where:** `SslConnection` (`user`, constructor, `allow_request`, `stop`) and `SslListen` (`rpc.user` on handshake).

**Depends on:** ### 1.

##### Part 1 — `server/Net/SslConnection.vala`

#### Remove

```vala
		/**
		 * ''agent.id'' for this certificate. ''-1'' until
		 * {@link allow_request} finds an approved row.
		 * ''0'' is the Unix controller, not a TLS agent.
		 */
		public int64 agent_id { get; set; default = -1; }

		public SslConnection(GLib.SocketConnection stream, Application app)
		{
			GLib.Object(stream: stream, app: app);
		}
```

#### Replace with

```vala
		/**
		 * Approved ''agent'' row for this certificate.
		 *
		 * ''id'' is ''0'' until {@link SslListen} or
		 * {@link allow_request} finds an approved row.
		 */
		public Argus.Shared.Agent user {
			get; set; default = new Argus.Shared.Agent();
		}

		public SslConnection(GLib.SocketConnection stream, Application app)
		{
			GLib.Object(stream: stream, app: app);
			this.notify["user"].connect(() => {
				this.set_data("argus-user", this.user);
			});
		}
```

#### Remove

```vala
			if (this.cert_fingerprint == "") {
				this.reply(request, new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("client certificate required")
				});
				return false;
			}
```

#### Replace with

```vala
			if (this.cert_fingerprint == "") {
				GLib.debug("closing connection without client certificate (%s)", request.method);
				this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
				this.stop();
				return false;
			}
```

#### Remove

```vala
				if (row.status == 1) {
					this.agent_id = row.id;
					return true;
				}
				if (row.status == 0 && row.is_controller &&
					request.method == "RPC-Daemon.hello") {
					row.status = 1;
					row.last_connected = new GLib.DateTime.now_utc().to_unix();
					cert_q.updateById(row);
					this.app.db.backupDB();
					this.agent_id = row.id;
					return true;
				}
			}
			this.reply(request, new OLLMrpc.Response() {
				error = new OLLMrpc.Error.CERT_NOT_REGISTERED("certificate not registered")
			});
			return false;
		}
```

#### Replace with

```vala
				if (row.status == 1) {
					this.user = row;
					return true;
				}
				if (row.status == 0 && row.is_controller &&
					request.method == "RPC-Daemon.hello") {
					row.status = 1;
					row.last_connected = new GLib.DateTime.now_utc().to_unix();
					cert_q.updateById(row);
					this.app.db.backupDB();
					this.user = row;
					return true;
				}
			}
			GLib.debug("closing connection for failed certificate %s (%s)",
				this.cert_fingerprint, request.method);
			this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
			this.stop();
			return false;
		}
```

#### Remove

```vala
			var tell = this.running && this.agent_id > 0;
			if (tell) {
				var rows = new Gee.ArrayList<Argus.Shared.Agent>();
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", (int) this.agent_id);
```

#### Replace with

```vala
			var tell = this.running && this.user.id > 0;
			if (tell) {
				var rows = new Gee.ArrayList<Argus.Shared.Agent>();
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", (int) this.user.id);
```

##### Part 2 — `server/Net/SslListen.vala`

#### Remove

```vala
						rpc.agent_id = row.id;
						known = true;
```

#### Replace with

```vala
						rpc.user = row;
						known = true;
```

### 3. `server/OSQuery.vala`, `server/Agent.vala`, and `server/Command.vala` — replace `connection.agent_id` with `connection.user.id`

**Why:** `SslConnection.agent_id` is replaced by `SslConnection.user`.

**Where:** `sync` in `server/OSQuery.vala`; `list` and `remove` in `server/Agent.vala`; `dispatch`, `send`, `stdout`, `stderr`, and `ended` in `server/Command.vala`.

**Depends on:** ### 2.

#### `server/OSQuery.vala` — Remove

```vala
			if (!model.sync(this.app.db, connection.agent_id, rows)) {
```

#### `server/OSQuery.vala` — Replace with

```vala
			if (!model.sync(this.app.db, connection.user.id, rows)) {
```

#### `server/Agent.vala` — Remove

```vala
			foreach (var connection in this.app.ssl_listen.connections) {
				if (!connection.running || connection.agent_id < 1) {
					continue;
				}
				live.set((int) connection.agent_id, true);
			}
```

#### `server/Agent.vala` — Replace with

```vala
			foreach (var connection in this.app.ssl_listen.connections) {
				if (!connection.running || connection.user.id < 1) {
					continue;
				}
				live.set((int) connection.user.id, true);
			}
```

#### `server/Agent.vala` — Remove

```vala
				if (connection.agent_id != id) {
```

#### `server/Agent.vala` — Replace with

```vala
				if (connection.user.id != id) {
```

#### `server/Command.vala` — Remove

```vala
				if (!connection.running || connection.agent_id != agent_id) {
```

#### `server/Command.vala` — Replace with

```vala
				if (!connection.running || connection.user.id != agent_id) {
```

#### `server/Command.vala` — Remove

```vala
			var name = Command.agents.get(identifier).agent_id.to_string() + "-" + identifier.to_string() + ".stdin";
```

#### `server/Command.vala` — Replace with

```vala
			var name = Command.agents.get(identifier).user.id.to_string() + "-" + identifier.to_string() + ".stdin";
```

#### `server/Command.vala` — Remove

```vala
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.agent_id != Command.agents.get(identifier).agent_id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).agent_id.to_string() + "-" + identifier.to_string() + ".stdout";
```

#### `server/Command.vala` — Replace with

```vala
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user.id != Command.agents.get(identifier).user.id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).user.id.to_string() + "-" + identifier.to_string() + ".stdout";
```

#### `server/Command.vala` — Remove

```vala
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.agent_id != Command.agents.get(identifier).agent_id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).agent_id.to_string() + "-" + identifier.to_string() + ".stderr";
```

#### `server/Command.vala` — Replace with

```vala
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user.id != Command.agents.get(identifier).user.id) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown command")
				});
				return;
			}
			var name = Command.agents.get(identifier).user.id.to_string() + "-" + identifier.to_string() + ".stderr";
```

#### `server/Command.vala` — Remove

```vala
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.agent_id != Command.agents.get(identifier).agent_id) {
```

#### `server/Command.vala` — Replace with

```vala
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user.id != Command.agents.get(identifier).user.id) {
```

## Attempts / changelog

- ℹ️ Split out of [5.10.1-REJECTED-package-updates.md](../../plans/done/5.10.1-REJECTED-package-updates.md) on 2026-11-13 so the `Agent.user` / `SslConnection.user` refactor lands before package update notifications.
- 🔷 Revised on 2026-11-13: dropped all `libocrpc` changes because `OLLMrpc.Transport.Connection` already calls `this.allow_request(request)` before `request.dispatch()`, and `server/Net/SslConnection.vala` already overrides `allow_request` to validate certificate freshness before every call.
- ✔️ Applied `### 1`–`### 3` on 2026-11-13 (`shared/Agent.vala`, `server/Net/SslConnection.vala`, `server/Net/SslListen.vala`, `server/OSQuery.vala`, `server/Agent.vala`, `server/Command.vala`; `notify_controllers` removed per user review). `ninja -C build` compiled cleanly.
- ✅ User closed on 2026-11-13.

## Next

- ✅ Closed. `Agent.user` and `SslConnection.user` freshness checks are in the tree; package updates are resolved in [2026-11-13-FIXED-package-updates.md](2026-11-13-FIXED-package-updates.md).
