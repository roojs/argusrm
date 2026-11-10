# Second local login registers the same controller again

**Status:** ✅ closed 2026-11-10. A second local login is refused.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 Settings, Add a connection, then Log in to local machine completes.
- 🔷 That machine is already a controller on this server. A second row appears.
- 🔷 A second registration of the same controller on the same machine must stop and say this machine is already registered.

## Evidence

- ✔️ `controller/tab/Settings.vala` Add a connection opens `Dialog.Bootstrap` with `add`.
- ✔️ Log in to local machine runs `--give-me-a-certificate`, which calls `Registration.certificate`.
- ✔️ That call deletes only `status = 0` rows for the same username and hostname, then inserts a new pending certificate.
- ✔️ The next hello promotes that pending row to `status = 1`. The earlier active row stays.
- ✔️ `Agent.request_registration` inserts another `status = 1` row for a controller with the same username and hostname.

## Root cause

- ✔️ An active controller is identified by certificate fingerprint. The login and the machine name are not checked before a new certificate is stored.

## Proposed fix

- 🔷 `Registration.certificate` refuses when a `status = 1` controller row already has this username and hostname. The reply is `This machine is already registered.` A pending row is still replaced.
- 🔷 `Agent.request_registration` uses the same refusal for a controller. The registration window shows that sentence.

#### Add

```vala
			var hostname = GLib.Environment.get_host_name();
			var existing = new Gee.ArrayList<Argus.Shared.Agent>();
			var found_binds = new Gee.HashMap<string, int>();
			var found_text = new Gee.HashMap<string, string>();
			found_binds.set("status", 1);
			found_binds.set("is_controller", 1);
			found_text.set("username", username);
			found_text.set("hostname", hostname);
			try {
				Argus.Shared.Agent.query(this.app.db).selectWhere(
					"WHERE status = $status AND is_controller = $is_controller " +
						"AND username = $username AND hostname = $hostname",
					found_binds, found_text, existing);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not read registration")
				});
				return;
			}
			if (existing.size > 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(
						"This machine is already registered.")
				});
				return;
			}
```

#### Add

```vala
			if (is_controller && username != "" && hostname != "") {
				var existing = new Gee.ArrayList<Argus.Shared.Agent>();
				var found_binds = new Gee.HashMap<string, int>();
				var found_text = new Gee.HashMap<string, string>();
				found_binds.set("status", 1);
				found_binds.set("is_controller", 1);
				found_text.set("username", username);
				found_text.set("hostname", hostname);
				try {
					Argus.Shared.Agent.query(this.app.db).selectWhere(
						"WHERE status = $status AND is_controller = $is_controller " +
							"AND username = $username AND hostname = $hostname",
						found_binds, found_text, existing);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("could not read registration")
					});
					return;
				}
				if (existing.size > 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(
							"This machine is already registered.")
					});
					return;
				}
			}
```

#### Replace with

```vala
			if (response.error != null) {
				if (response.error.message == "This machine is already registered.") {
					return 1;
				}
				return response.error.code;
			}
```

#### Replace with

```vala
				if (code != 0) {
					var label = "The management server rejected the request.";
					if (code == 1) {
						label = "This machine is already registered.";
					}
```

## Next

- ✅ Closed. A second local login says this machine is already registered.
- ℹ️ The row already created stays until it is removed from the agent list.
