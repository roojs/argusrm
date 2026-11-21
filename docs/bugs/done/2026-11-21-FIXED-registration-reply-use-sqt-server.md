# Registration reply — align with `SQT.Server`

**Status:** ✅ closed 2026-11-21 — registration RPC and pkexec JSON use **`Argus.Shared.SQT.Server`**; server **`RegistrationData`** removed; **`Registration.Data`** off the build (orphan `shared/Registration/Data.vala` may be deleted as cleanup).

**Background:** Local certificate issue used parallel DTOs under **`Argus.Registration.Data`**. Shipped path: [`server/Registration.vala`](../../server/Registration.vala) **`retval`**, controller pkexec JSON, and [`Bootstrap.exe_root`](../../controller/dialog/Bootstrap.vala) all use [`Argus.Shared.SQT.Server`](../../shared/SQT/Server.vala) with no field-copy bridge.

**Depends on:** [2026-11-20-local-registration-cutover-remainder.md](../2026-11-20-local-registration-cutover-remainder.md) (enroll/deregister on `Register` + `SQT.Server` persistence).

**How to implement:** Fenced **Remove** / **Replace with** / **Add** only (see [`docs/guide-to-writing-plans.md`](../../docs/guide-to-writing-plans.md)). Implement in **Suggested order** after remainder work is on the branch.

---

## Goal

Use **`Argus.Shared.SQT.Server`** for the **registration RPC / pkexec JSON reply** (success and failure), so Bootstrap and `--give-me-a-certificate` deserialize once and hand off to `Register` / `finish_registration` without a second DTO. Retire **`Registration.Data`** / **`RegistrationData`** and stop registering **`Argus.Registration.Data`**.

---

## Settled policy

| Topic | Decision |
| --- | --- |
| **Failure JSON** | Same row type. Non-empty **`error`** string; other fields empty or omitted. No separate envelope type. |
| **Wire / bin type** | **`Argus.Shared.SQT.Server`** (shared server row), not **`Argus.Registration.Data`**. |
| **PEM JSON names** | **`pem_private_key`**, **`pem_client_certificate`**, **`pem_ca_certificate`** on the wire (match the row today). |
| **`addresses`** | Newline **`string`** on the row, built that way when the server issues the cert. |
| **`download` / `download_path`** | **Not** on the local registration reply unless we need them later. Omit; do not send empty placeholders. |

---

## Suggested order

1. **S1** — **`error`** + **`Server.rpc_register`** on shared row.
2. **S2** — hook **`rpc_register`** in shared **`SQT`** namespace (controller + android activate).
3. **S3** — server **`Registration.certificate`** returns **`Argus.Shared.SQT.Server`**.
4. **S4** — delete **`RegistrationData`** (server).
5. **S5** — controller cli **`Application`** pkexec JSON.
6. **S6** — **`Bootstrap.exe_root`** parse + enroll handoff.
7. **S7** — delete **`Registration.Data`** (shared) + meson + valadoc.
8. **S8** — **`docs/rpc-commands.md`** reply type.

---

## S1 — [`shared/SQT/Server.vala`](../../shared/SQT/Server.vala)

**Review:** Add wire-only **`error`**. Register bin name **`Argus.Shared.SQT.Server`**.

#### Add — after `deleted_dt` (before `pem_private_key`)

```vala
		/**
		 * Failure text on local registration JSON / RPC only; not a SQLite column.
		 */
		public string error { get; set; default = ""; }
```

#### Add — end of class (before closing `}` of `Server`)

```vala
		/**
		 * Register the saved-server row type with the ''OLLMrpc'' bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Shared.SQT.Server", typeof(Server));
		}
```

---

## S2 — [`shared/SQT/namespace.vala`](../../shared/SQT/namespace.vala)

#### Add — inside `rpc_register()`, after `DistributableVersion.rpc_register();`

```vala
		Server.rpc_register();
```

---

## S3 — [`server/Registration.vala`](../../server/Registration.vala)

**Review:** Success and failure **`retval`** use **`Argus.Shared.SQT.Server`**. **`addresses`** is one newline string. No **`download`**. PEM fields use **`pem_*`**.

#### Replace — `rpc_register()`

```vala
		public static void rpc_register()
		{
			Argus.Shared.SQT.Server.rpc_register();
			OLLMrpc.Request.add_class("Registration", typeof(Registration),
				"certificate", "s", "deregister", "s");
		}
```

#### Replace — from `var data = new RegistrationData()` through `data.port = port;` and the `if (host == "0.0.0.0")` / `if (host != "0.0.0.0")` address blocks

```vala
			var addresses_text = host;
			if (host == "0.0.0.0") {
				addresses_text = string.joinv("\n", OLLMrpc.Transport.TcpListen.ifaces());
			}
			var data = new Argus.Shared.SQT.Server() {
				pem_private_key = (string) private_key_buf,
				pem_client_certificate = (string) certificate_buf,
				pem_ca_certificate = ca_pem,
				name = hostname,
				port = port,
				addresses = addresses_text
			};
```

#### Replace — `TlsCertificate.from_pem(data.client_certificate, data.client_certificate.length)`

```vala
				var issued = new GLib.TlsCertificate.from_pem(
					data.pem_client_certificate, data.pem_client_certificate.length);
```

---

## S4 — [`server/RegistrationData.vala`](../../server/RegistrationData.vala)

#### Remove — file

#### Remove — [`server/meson.build`](../../server/meson.build) source line `'RegistrationData.vala',`

#### Remove — [`docs/meson.build`](../../docs/meson.build) valadoc entry `'../server/RegistrationData.vala',`

---

## S5 — [`controller/Application.vala`](../../controller/Application.vala)

**Review:** Privileged cli stdout is **`Argus.Shared.SQT.Server`** JSON ( **`error`** on failure). Drop **`Registration.Data.rpc_register()`** — **`Argus.Shared.SQT.rpc_register()`** already registers the row type after **S2**.

#### Remove — line `Argus.Shared.Registration.Data.rpc_register();`

#### Replace with — every `new Argus.Shared.Registration.Data()` in `command_line` / `on_connect` (failure shells, deregister empty success, success print, cast)

Use `new Argus.Shared.SQT.Server()` and `typeof(Argus.Shared.SQT.Server)` for **`Json.gobject_to_data`** / **`Json.gobject_from_data`** where applicable.

#### Replace — success print cast

```vala
					this.cli.print("%s\n", Json.gobject_to_data((Argus.Shared.SQT.Server) response.retval, null));
```

---

## S6 — [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) `exe_root`

**Review:** Parse **`Argus.Shared.SQT.Server`**. **`--give-me-a-certificate`**: set **`reg.server_row = data`** (no PEM / address copy). Deregister success still checks **`data.error == ""`**.

#### Replace — docblock sentence `Standard output is {@link Argus.Shared.Registration.Data}.`

```vala
		 * Standard output is {@link Argus.Shared.SQT.Server}.
```

#### Replace — from `var data = new Argus.Shared.Registration.Data()` through the manual `server_row = new Argus.Shared.SQT.Server() { … }` block before `finish_registration`

```vala
				var data = new Argus.Shared.SQT.Server() {
					error = "The command failed."
				};
				try {
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), output)
						as Argus.Shared.SQT.Server;
					if (parsed != null) {
						data = parsed;
					}
				} catch (GLib.Error e) {
					data.error = error_output != "" ? error_output : e.message;
				}
				if (option == "--deregister") {
					if (data.error != "") {
						this.page(failed, data.error,
							{ "Retry", "Log in to register" }, { "retry", "register" });
						return;
					}
					if (prior_error != "") {
						this.page(failed, prior_error,
							{ "Retry", "Log in to register" }, { "retry", "register" });
						return;
					}
					this.page("Argus Remote Manager", "",
						{ "Log in to local machine", "Connect a remote machine" },
						{ "register", "remote" });
					return;
				}
				if (data.error != "" || data.name == "" || data.port < 1 || !data.has_certificate) {
					var message = data.error;
					if (message == "") {
						message = "The server did not return a connection.";
					}
					if (message == "This machine is already registered.") {
						this.page(failed, message,
							{ "Deregister locally", "Retry" }, { "local", "retry" });
						return;
					}
					this.page(failed, message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var reg = new Argus.Shared.Register() {
					client_db = this.app.client_db,
					server_row = data
				};
				var row = new Argus.Controller.SQT.Server() {
					name = data.name
				};
```

**Keep** — existing `this.finish_registration(reg, row);` call immediately after.

---

## S7 — [`shared/Registration/Data.vala`](../../shared/Registration/Data.vala)

#### Remove — file

#### Remove — [`shared/meson.build`](../../shared/meson.build) `'Registration/Data.vala',`

#### Remove — [`docs/meson.build`](../../docs/meson.build) `'../shared/Registration/Data.vala',`

#### Replace — [`docs/valadoc-wiki/index.valadoc`](../../docs/valadoc-wiki/index.valadoc): drop the **Registration** / **Data** bullet (local issue uses **`Argus.Shared.SQT.Server`**).

---

## S8 — [`controller/android/Application.vala`](../../controller/android/Application.vala)

#### Remove — `Argus.Shared.Registration.Data.rpc_register();` in `activate` ( **S2** covers registration via **`Argus.Shared.SQT.rpc_register()`**).

---

## S9 — [`docs/rpc-commands.md`](../../docs/rpc-commands.md)

#### Replace — `Registration.certificate` reply line

```markdown
- Reply `retval` `o`: `Argus.Shared.SQT.Server`.
  - PEM fields are `pem_private_key`, `pem_client_certificate`, `pem_ca_certificate`.
  - `addresses` is one host per line (newline-separated text), not a JSON array.
  - On failure the controller may print JSON with `error` set and other fields empty.
```

---

## Not in scope

- Remote `Agent.request_registration` reply (still string array on TLS).
- Gtk / `RegisterWindow` (already uses `Register.server_row`).
- Changing **OLLMrpc** RPC-level errors (`response.error`) — those still map to **`error`** in pkexec stdout JSON on the controller.