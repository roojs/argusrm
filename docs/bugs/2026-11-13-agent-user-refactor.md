# Refactor caller `Agent.user` lookup and `SslConnection.user`

**Status:** ⏳ proposed — await apply approval

**Pointer:** `docs/bug-fix-process.md`. Split out of [5.10.1-package-updates.md](../plans/5.10.1-package-updates.md).

---

## Problem

- 🔷 RPC handlers in `shared/OSQuery/` need the caller's `Argus.Shared.Agent` row without repeating the `cert_fingerprint` SQL query at every call site, and without adding redundant `agent_id` or `is_controller` fields onto `SslConnection`.
- 🔷 When a certificate has no active `agent` row (for example after an agent or controller was deleted), `Agent.user` must throw rather than returning an empty row, and RPC handlers (`is_a_controller`, `list`, `send_pending`, etc.) must not catch that error locally — it must propagate up to the connection level.
- 🔷 An invalid or deleted certificate on `SslConnection` must not receive an error reply: the connection refreshes the nftables allowlist and shuts down (`stop()`).
- 🔷 `SslConnection` currently stores only `int64 agent_id` instead of the `Argus.Shared.Agent` row (`user`), leaving `server/` unable to read `connection.user.is_controller` when notifying connected controllers.

## Evidence

- ✔️ `shared/Agent.vala` `is_a_controller` queries `WHERE fingerprint = $fingerprint AND status = 1 AND is_controller = 1` inline, and there is no shared `Agent.user(request)` method for agent RPC handlers in `shared/`.
- ✔️ `server/Net/SslConnection.vala` stores `public int64 agent_id { get; set; default = -1; }` and replies `client certificate required` or `certificate not registered` without refreshing the firewall or closing the socket.
- ✔️ `server/Net/SslListen.vala`, `server/OSQuery.vala`, `server/Agent.vala`, and `server/Command.vala` all read or write `connection.agent_id`.
- ℹ️ `OLLMrpc.Ffi.dispatch` in `OLLMchat` (`libocrpc/Ffi.vala`) currently invokes `Request.add_class` methods without a trailing `GError**` slot, and `Connection.on_input_ready` has no virtual `dispatch_error` hook yet.

## Root cause

- ✔️ Caller resolution was split between `SslConnection.agent_id` (an `int64` id only visible to `server/`, leaving sockets open on rejection) and `Agent.is_a_controller` (a boolean controller-only query in `shared/` that swallowed the caller row). Storing `user` (`Argus.Shared.Agent`) on `SslConnection` and resolving `Agent.user(request) throws GLib.Error` in `shared/Agent.vala` unifies both sides and lets unhandled caller errors shut down the connection and refresh the firewall at the connection layer.

## Proposed fix

- 🔷 Add `Argus.Shared.Agent.user(OLLMrpc.Request request) throws GLib.Error` in `shared/Agent.vala`. On the Unix socket (`cert_fingerprint == ""`), return a local controller `Agent` (`status = 1`, `is_controller = true`). On TLS, return the active `agent` row or throw `OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED`.
- 🔷 Change `Argus.Shared.Agent.is_a_controller` to `throws GLib.Error` and call `Agent.user(request)` without catching the error.
- 🔷 Propagate `throws GLib.Error` on every RPC method that calls `is_a_controller` across `shared/` and `server/`.
- 🔷 Replace `SslConnection.agent_id` with `public Argus.Shared.Agent user { get; set; default = new Argus.Shared.Agent(); }`, updating `SslListen`, `SslConnection.stop`, `server/OSQuery.vala`, `server/Agent.vala`, and `server/Command.vala` to use `user` / `user.id`.
- 🔷 In `SslConnection.allow_request` (and a new `SslConnection.dispatch_error` override), send no reply on missing/unregistered certificates or unhandled dispatch errors — refresh `this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces))` and call `this.stop()`.
- 🔷 Add `NotifyControllers` (`Argus.Shared.Agent.notify_controllers`) wired in `server/Application.vala` to broadcast on `this.listen` (Unix controllers) and write to running `ssl_listen` connections where `connection.user.is_controller` is true.
- 💩 Prerequisite in `OLLMchat` (`libocrpc`): `Ffi.dispatch` appends a `GError**` slot and throws on error; `Request.dispatch` is `throws GLib.Error`; `Connection.on_input_ready` catches `GLib.Error` and calls `public virtual void dispatch_error(Request request, GLib.Error e)`.

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### 1. `shared/Agent.vala` — `notify_controllers`, `user`, and `is_a_controller`

**Why:** centralize fingerprint lookup and the controller-notification callback on `Agent`, throwing `CERT_NOT_REGISTERED` when no active row exists and letting `is_a_controller` pass that error up.

**Where:** top of `Agent` (`NotifyControllers` and `notify_controllers`), `user` before `is_a_controller`, and `is_a_controller`.

**Depends on:** `libocrpc` `Ffi` `GError**` + `Connection.dispatch_error` in `OLLMchat`.

#### Remove

```vala
	public class Agent : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		private static SQ.Database db;
```

#### Replace with

```vala
	public delegate void NotifyControllers(OLLMrpc.Notification notification);

	public class Agent : GLib.Object, SQ.Interface, OLLMrpc.Bin.Serializable
	{
		private static SQ.Database db;

		/**
		 * Server callback that sends a notification to connected controllers.
		 */
		public static NotifyControllers notify_controllers = (notification) => {};
```

#### Add — before `is_a_controller`, resolve the caller `Agent` row or throw

```vala
		/**
		 * Caller row for an inbound RPC request.
		 *
		 * The Unix socket has no certificate and returns a local
		 * controller with ''id'' zero. A TLS caller returns its
		 * active ''agent'' row, or throws when no active row
		 * matches.
		 *
		 * @param request inbound RPC request
		 * @return caller ''Agent'' row
		 * @throws GLib.Error ''CERT_NOT_REGISTERED'' when not found
		 */
		public static Agent user(OLLMrpc.Request request) throws GLib.Error
		{
			if (request.connection.cert_fingerprint == "") {
				return new Agent() {
					status = 1,
					is_controller = true
				};
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
			throw new OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED("certificate not registered");
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
		 * @throws GLib.Error when no active caller row exists
		 */
		public static bool is_a_controller(OLLMrpc.Request request) throws GLib.Error
		{
			if (Agent.user(request).is_controller) {
				return true;
			}
```

### 2. `server/Net/SslConnection.vala`, `server/Net/SslListen.vala`, and `server/Application.vala` — `SslConnection.user`, firewall refresh + disconnect, and `notify_controllers`

**Why:** store the `Argus.Shared.Agent` row directly on `SslConnection` as `user` (removing `agent_id`), shut down invalid/deleted certificates without replying while refreshing the firewall, and wire `Agent.notify_controllers` using `connection.user.is_controller`.

**Where:** `SslConnection` (`user`, `allow_request`, `dispatch_error`, `stop`), `SslListen` (`rpc.user` on handshake), and `server/Application.vala` (`command_line` after `Agent.init_db`).

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
			this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
			this.stop();
			return false;
		}

		/**
		 * Refresh the firewall and drop the socket when a handler throws.
		 *
		 * @param request inbound RPC that failed
		 * @param e unhandled error from dispatch
		 */
		public override void dispatch_error(OLLMrpc.Request request, GLib.Error e)
		{
			GLib.warning("%s", e.message);
			this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
			this.stop();
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

##### Part 3 — `server/Application.vala`

#### Remove

```vala
			Argus.Shared.Agent.init_db(this.db);
```

#### Replace with

```vala
			Argus.Shared.Agent.init_db(this.db);
			Argus.Shared.Agent.notify_controllers = (notification) => {
				this.listen.broadcast(notification);
				foreach (var connection in this.ssl_listen.connections) {
					if (!connection.running || !connection.user.is_controller) {
						continue;
					}
					connection.write(notification);
				}
			};
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

### 4. Propagate `throws GLib.Error` on `is_a_controller` callers

**Why:** RPC handlers must not catch `Agent.user` / `is_a_controller` errors locally; declaring `throws GLib.Error` passes the error up to the connection level.

**Where:** method signatures of `is_a_controller` callers across `shared/` and `server/` (plus `server/tests/packages.vala` `main`).

**Depends on:** ### 1.

#### `shared/OSQuery/DebPackages.vala` — Remove

```vala
		public void list(OLLMrpc.Request request, int agent_id, int since)
```

#### `shared/OSQuery/DebPackages.vala` — Replace with

```vala
		public void list(OLLMrpc.Request request, int agent_id, int since) throws GLib.Error
```

#### `shared/OSQuery/RpmPackages.vala` — Remove

```vala
		public void list(OLLMrpc.Request request, int agent_id, int since)
```

#### `shared/OSQuery/RpmPackages.vala` — Replace with

```vala
		public void list(OLLMrpc.Request request, int agent_id, int since) throws GLib.Error
```

#### `shared/OSQuery/Programs.vala` — Remove

```vala
		public void list(OLLMrpc.Request request, int agent_id, int since)
```

#### `shared/OSQuery/Programs.vala` — Replace with

```vala
		public void list(OLLMrpc.Request request, int agent_id, int since) throws GLib.Error
```

#### `shared/OSQuery/SystemInfo.vala` — Remove

```vala
		public void list(OLLMrpc.Request request, bool join)
```

#### `shared/OSQuery/SystemInfo.vala` — Replace with

```vala
		public void list(OLLMrpc.Request request, bool join) throws GLib.Error
```

#### `server/Agent.vala` — Remove

```vala
		public void offer(OLLMrpc.Request request)
```

#### `server/Agent.vala` — Replace with

```vala
		public void offer(OLLMrpc.Request request) throws GLib.Error
```

#### `server/Agent.vala` — Remove

```vala
		public void remove(OLLMrpc.Request request, int id)
```

#### `server/Agent.vala` — Replace with

```vala
		public void remove(OLLMrpc.Request request, int id) throws GLib.Error
```

#### `server/Command.vala` — Remove

```vala
		public void send(OLLMrpc.Request request, int identifier, string text)
```

#### `server/Command.vala` — Replace with

```vala
		public void send(OLLMrpc.Request request, int identifier, string text) throws GLib.Error
```

#### `server/SQT/Script.vala` — Remove / Replace with

#### Remove

```vala
		public void create(OLLMrpc.Request request, string path, string body)
```

#### Replace with

```vala
		public void create(OLLMrpc.Request request, string path, string body) throws GLib.Error
```

#### Remove

```vala
		public void update(OLLMrpc.Request request, int id, string body)
```

#### Replace with

```vala
		public void update(OLLMrpc.Request request, int id, string body) throws GLib.Error
```

#### Remove

```vala
		public void read(OLLMrpc.Request request, int id)
```

#### Replace with

```vala
		public void read(OLLMrpc.Request request, int id) throws GLib.Error
```

#### Remove

```vala
		public void list(OLLMrpc.Request request, int repository_id)
```

#### Replace with

```vala
		public void list(OLLMrpc.Request request, int repository_id) throws GLib.Error
```

#### Remove

```vala
		public void enable(OLLMrpc.Request request, int script_id, int agent_id)
```

#### Replace with

```vala
		public void enable(OLLMrpc.Request request, int script_id, int agent_id) throws GLib.Error
```

#### Remove

```vala
		public void disable(OLLMrpc.Request request, int script_id, int agent_id)
```

#### Replace with

```vala
		public void disable(OLLMrpc.Request request, int script_id, int agent_id) throws GLib.Error
```

#### Remove

```vala
		public void agents(OLLMrpc.Request request, int script_id)
```

#### Replace with

```vala
		public void agents(OLLMrpc.Request request, int script_id) throws GLib.Error
```

#### `server/SQT/Task.vala` — Remove / Replace with

#### Remove

```vala
		public void create(OLLMrpc.Request request, Argus.Shared.SQT.Task row)
```

#### Replace with

```vala
		public void create(OLLMrpc.Request request, Argus.Shared.SQT.Task row) throws GLib.Error
```

#### Remove

```vala
		public void update(OLLMrpc.Request request, Argus.Shared.SQT.Task row)
```

#### Replace with

```vala
		public void update(OLLMrpc.Request request, Argus.Shared.SQT.Task row) throws GLib.Error
```

#### Remove

```vala
		public void list(OLLMrpc.Request request)
```

#### Replace with

```vala
		public void list(OLLMrpc.Request request) throws GLib.Error
```

#### Remove

```vala
		public void target(OLLMrpc.Request request, int task_id, GLib.Variant agent_ids)
```

#### Replace with

```vala
		public void target(OLLMrpc.Request request, int task_id, GLib.Variant agent_ids) throws GLib.Error
```

#### Remove

```vala
		public void approve(OLLMrpc.Request request, int task_id, bool approved)
```

#### Replace with

```vala
		public void approve(OLLMrpc.Request request, int task_id, bool approved) throws GLib.Error
```

#### Remove

```vala
		public void watch(OLLMrpc.Request request, int target_id)
```

#### Replace with

```vala
		public void watch(OLLMrpc.Request request, int target_id) throws GLib.Error
```

#### Remove

```vala
		public void duplicate(OLLMrpc.Request request, int task_id)
```

#### Replace with

```vala
		public void duplicate(OLLMrpc.Request request, int task_id) throws GLib.Error
```

#### Remove

```vala
		public void targets(OLLMrpc.Request request, int task_id)
```

#### Replace with

```vala
		public void targets(OLLMrpc.Request request, int task_id) throws GLib.Error
```

#### `server/SQT/ScriptRepository.vala` — Remove / Replace with

#### Remove

```vala
		public void clone(OLLMrpc.Request request, Argus.Shared.SQT.ScriptRepository row)
```

#### Replace with

```vala
		public void clone(OLLMrpc.Request request, Argus.Shared.SQT.ScriptRepository row) throws GLib.Error
```

#### Remove

```vala
		public void pull(OLLMrpc.Request request, int id)
```

#### Replace with

```vala
		public void pull(OLLMrpc.Request request, int id) throws GLib.Error
```

#### Remove

```vala
		public void remove(OLLMrpc.Request request, int id)
```

#### Replace with

```vala
		public void remove(OLLMrpc.Request request, int id) throws GLib.Error
```

#### Remove

```vala
		public void list(OLLMrpc.Request request)
```

#### Replace with

```vala
		public void list(OLLMrpc.Request request) throws GLib.Error
```

#### `server/tests/packages.vala` — Remove

```vala
		static int main()
```

#### `server/tests/packages.vala` — Replace with

```vala
		static int main() throws GLib.Error
```

## Attempts / changelog

- ℹ️ Split out of [5.10.1-package-updates.md](../plans/5.10.1-package-updates.md) on 2026-11-13 so the `Agent.user` / `SslConnection.user` refactor lands before package update notifications.

## Next

- 💩 ⏳ Land `Ffi` `GError**` + `Connection.dispatch_error` in `OLLMchat` (`libocrpc`).
- 🔷 ⏳ Apply `### 1`–`### 4` in Argus once approved, then implement [5.10.1-package-updates.md](../plans/5.10.1-package-updates.md).
