# Local registration — Unix `Registration.certificate`

**Status:** ✅ closed 2026-11-21 — R1–R5 fenced in product; **R6/R7** closed in 2026-11-21-FIXED-local-registration-docs-polkit.md.

**Goal:** Co-located enroll (agent or controller): root → `argus.sock` → `Registration.certificate` → JSON `SQT.Server` → client `Register.save`. Remote agent stays PIN + registration TCP.

**Gtk notice:** 2026-11-21-FIXED-agent-gtk-notice.md — **Connect locally** wired to `enroll_local_certificate`.

**How to implement:** Only apply code changes that have **Remove** / **Replace with** / **Add** fenced blocks below.

**Wire (fixed here):**

- **Entry point:** [`argusrm-server`](../../server/Application.vala) only (server package). Not agent, not controller, not controller-cli.
- **Client mode:** `argusrm-server --give-me-a-certificate agent` **xor** `--give-me-a-certificate controller` (root). Talks to the **running** daemon; prints JSON; exits. Does not bind TLS sockets.
- **Unix socket:** always `GLib.Path.build_filename(data_dir, "argus.sock")` with the same **`--data-dir`** as the daemon (default [`Argus.SERVER_DATA_DIR`](../../paths.vala.in)). No separate socket path flag.
- **RPC:** `Registration.certificate` with `s` — non-empty ⇒ controller username (`get_user_name()`); empty ⇒ managed agent.
- **Hello client name:** `argusrm-server`.

**Daemon `--register`:** unchanged — still **registration listen** `HOST:PORT`. Local enroll uses **`--give-me-a-certificate`** only.

---

## R1 — `argusrm-server --give-me-a-certificate` (server package)

No new type. **Client mode** is an early return in [`server/Application.vala`](../../server/Application.vala) `command_line` (lift connect + `Registration.certificate` from [`controller/Application.vala`](../../controller/Application.vala) `on_connect`).

### Add — field and option in [`server/Application.vala`](../../server/Application.vala)

Option backing fields use the existing server rule: **`opt_*`** (see `opt_socket`, `opt_data_dir`).

```vala
		private static string opt_give_certificate = "";
```

In `app_options` (after existing entries, before `{ null }`):

```vala
			{ "give-me-a-certificate", 0, 0, GLib.OptionArg.STRING,
				ref opt_give_certificate,
				"Local Unix enrollment", "agent|controller" },
```

In `command_line`, with the other option resets:

```vala
			opt_give_certificate = "";
```

After `opt_context.parse`, before daemon socket setup:

```vala
			if (opt_give_certificate != "") {
				var code = this.issue_local_certificate(
					command_line, opt_give_certificate);
				Posix._exit(code);
				return code;
			}
```

### Add — one method on [`server/Application.vala`](../../server/Application.vala) `Application`

Hello, `Registration.certificate`, and JSON print stay in **`issue_local_certificate`**. Failures **`throw new GLib.IOError.FAILED(...)`** (connect or RPC); **`catch`** prints JSON, then **`loop.quit(); return;`**. Success prints JSON, sets **`exit_code = 0`**, then **`loop.quit(); return;`**.

```vala
		private int issue_local_certificate(
			GLib.ApplicationCommandLine command_line,
			string role)
		{
#if LINUX
			if (Posix.geteuid() != 0) {
				command_line.print("%s\n", Json.gobject_to_data(
					new Argus.Shared.SQT.Server() {
						error = "root is required"
					}, null));
				return 1;
			}
#else
			command_line.print("%s\n", Json.gobject_to_data(
				new Argus.Shared.SQT.Server() {
					error = "local certificate issue is Linux only"
				}, null));
			return 1;
#endif
			if (role != "agent" && role != "controller") {
				command_line.print("%s\n", Json.gobject_to_data(
					new Argus.Shared.SQT.Server() {
						error = "use --give-me-a-certificate agent or controller"
					}, null));
				return 1;
			}
			var username = role == "controller" ?
				GLib.Environment.get_user_name() : "";
			var data_dir = opt_data_dir != "" ?
				opt_data_dir : Argus.SERVER_DATA_DIR;
			var sock = GLib.Path.build_filename(data_dir, "argus.sock");
			var loop = new GLib.MainLoop();
			var exit_code = 1;
			var rpc = new OLLMrpc.Client("", "", sock) {
				live_handles = true,
				call_timeout_seconds = 5
			};
			rpc.debug = false;
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "argusrm-server", Argus.VERSION)
			}, null, (obj, res) => {
				try {
					if (!rpc.connect.end(res)) {
						throw new GLib.IOError.FAILED(rpc.connect_error);
					}
				} catch (GLib.Error e) {
					command_line.print("%s\n", Json.gobject_to_data(
						new Argus.Shared.SQT.Server() {
							error = e.message
						}, null));
					loop.quit();
					return;
				}
				rpc.call.begin(new OLLMrpc.Request() {
					method = "Registration.certificate",
					args = OLLMrpc.args("s", username)
				}, (call_obj, call_res) => {
					try {
						var response = rpc.call.end(call_res);
						if (response.error != null) {
							throw new GLib.IOError.FAILED(
								response.error.message);
						}
						command_line.print("%s\n", Json.gobject_to_data(
							(Argus.Shared.SQT.Server) response.retval, null));
						exit_code = 0;
					} catch (GLib.Error e) {
						command_line.print("%s\n", Json.gobject_to_data(
							new Argus.Shared.SQT.Server() {
								error = e.message
							}, null));
					}
					loop.quit();
					return;
				});
			});
			loop.run();
			return exit_code;
		}
```

**Review:** `Argus.Shared.SQT.Server.rpc_register()` must run before client mode (already in daemon path via `OLLMrpc.rpc_register`; add `Argus.Shared.SQT.rpc_register()` in `command_line` if missing). Tests aim the client at a temp daemon with **`--data-dir`** only, same as today’s controller test uses **`--server-socket`** today.

### R1.2 — Installed path for pkexec

#### Add — [`paths.vala.in`](../../paths.vala.in)

```vala
	public const string SERVER_EXECUTABLE = "@SERVER_EXECUTABLE@";
```

#### Add — [`meson.build`](../../meson.build) `paths` configure (with other substitutions)

```meson
		'SERVER_EXECUTABLE': server_executable,
```

Bootstrap, agent Gtk, and tests spawn **`Argus.SERVER_EXECUTABLE --give-me-a-certificate …`**.

---

## R2 — Server `Registration.certificate` (agent branch)

**Where:** [`server/Registration.vala`](../../server/Registration.vala) `certificate`.

### Replace — docblock first paragraph

```vala
		/**
		 * Generate one pending local credential on the Unix socket.
		 *
		 * Non-empty ''username'': controller ({@link is_controller} true).
		 * Empty ''username'': managed agent on this host ({@link is_controller} false).
```

### Replace — after root check, replace `username is required` gate

```vala
			var hostname = GLib.Environment.get_host_name();
			var is_controller = username != "";
			if (!is_controller) {
				var existing_agent = new Gee.ArrayList<Argus.Shared.Agent>();
				var agent_binds = new Gee.HashMap<string, int>();
				var agent_text = new Gee.HashMap<string, string>();
				agent_binds.set("status", 1);
				agent_binds.set("is_controller", 0);
				agent_text.set("hostname", hostname);
				try {
					Argus.Shared.Agent.query(this.app.db).selectWhere(
						"WHERE status = $status AND is_controller = $is_controller " +
							"AND hostname = $hostname",
						agent_binds, agent_text, existing_agent);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("could not read registration")
					});
					return;
				}
				if (existing_agent.size > 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(
							"This machine is already registered.")
					});
					return;
				}
			}
			if (is_controller) {
				// existing controller duplicate check (status 1, username + hostname) unchanged
			}
```

### Replace — common name and DB insert (controller block today)

```vala
			var common_name = is_controller ?
				username + "@" + hostname :
				hostname;
			// ... key generation and sign unchanged ...
			int_binds.set("status", is_controller ? 0 : 1);
			int_binds.set("is_controller", is_controller ? 1 : 0);
			if (is_controller) {
				text_binds.set("username", username);
				text_binds.set("hostname", hostname);
				Argus.Shared.Agent.query(this.app.db).deleteWhere(
					"WHERE status = $status AND is_controller = $is_controller " +
						"AND username = $username AND hostname = $hostname",
					int_binds, text_binds);
			} else {
				var requester = hostname;
				text_binds.set("hostname", hostname);
				Argus.Shared.Agent.query(this.app.db).deleteWhere(
					"WHERE status = $status AND is_controller = $is_controller " +
						"AND hostname = $hostname",
					int_binds, text_binds);
				Argus.Shared.Agent.query(this.app.db).insert(
					new Argus.Shared.Agent() {
						fingerprint = fingerprint,
						status = 1,
						ip = "127.0.0.1",
						created = new GLib.DateTime.now_utc().to_unix(),
						requester = requester,
						hostname = hostname,
						is_controller = false
					});
				this.app.db.backupDB();
				this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
				// agent reply: add download + download_path like Agent.request_registration (debian path)
				request.reply(new OLLMrpc.Response() {
					retval = OLLMrpc.val("o", data),
					msg = "ok"
				});
				return;
			}
			// existing controller insert (status 0) unchanged below
```

---

## R3 — `docs/rpc-commands.md`

### Replace — `Registration.certificate` bullet list

```markdown
### `Registration.certificate`

- Socket: the Unix socket.
- Direction: privileged local enroll (`argusrm-server --give-me-a-certificate …`), root client to running daemon.
- Arguments `s`: controller OS login name, or **empty** for a managed agent on this host.
- Unix peer uid `0` required.
- Refuses an active row for the same role and host (controller: username + hostname; agent: hostname).
- Reply `retval` `o`: `Argus.Shared.SQT.Server` (PEM fields, `addresses`, optional `download` / `download_path` for agents).
- Controller row: `status = 0` until first TLS hello. Agent row: `status = 1`.
- ℹ️ [`server/Registration.vala`](../../server/Registration.vala).
```

---

## R4 — Controller Bootstrap / drop duplicate mode

### Replace — [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) `register` button handler

```vala
				if (response == "register") {
					this.exe_register_local("Registering server", "");
					return;
				}
```

### Add — [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) (after `exe_root`)

```vala
		private void exe_register_local(string waiting, string prior_error)
		{
			this.exe_root_helper({
				Argus.SERVER_EXECUTABLE,
				"--give-me-a-certificate",
				"controller"
			}, waiting, prior_error, false);
		}
```

**Review:** Refactor `exe_root` so certificate issue uses `Argus.SERVER_EXECUTABLE` argv; keep `--deregister` on `argusrm-controller` until R4b moves it.

### Remove — [`controller/Application.vala`](../../controller/Application.vala)

- Option `--give-me-a-certificate`.
- Entire `command_line` branch from `#if LINUX` root check through `on_connect` / `Registration.certificate` (Bootstrap and tests use `argusrm-server --give-me-a-certificate`).

### Replace — [`server/tests/registration-local-login.vala`](../../server/tests/registration-local-login.vala) spawn argv

```vala
				proc = launcher.spawnv({
					server_exe,
					"--data-dir", data_dir,
					"--give-me-a-certificate", "controller"
				});
```

**Review:** Temp harness already uses `data_dir`; drop `--server-socket` from the old controller spawn. Daemon and client share the same `--data-dir` so `argus.sock` matches.

---

## R5 — Agent Gtk **Connect locally** (after gtk notice table lands)

### Add — [`agent/linux/Application.vala`](../../agent/linux/Application.vala)

```vala
		private async void enroll_local_certificate(
			ServiceManager service,
			Argus.Shared.Register reg) throws GLib.Error
		{
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				throw new GLib.IOError.FAILED("pkexec was not found");
			}
			var executable = Argus.SERVER_EXECUTABLE;
			if (!GLib.FileUtils.test(executable, GLib.FileTest.IS_EXECUTABLE)) {
				throw new GLib.IOError.FAILED("argusrm-server is missing");
			}
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
			var proc = launcher.spawnv({
				pkexec, executable,
				"--give-me-a-certificate", "agent"
			});
			string? stdout_text = null;
			string? stderr_text = null;
			yield proc.communicate_utf8_async(null, null, out stdout_text, out stderr_text);
			var output = stdout_text != null ? stdout_text.strip() : "";
			if (output == "") {
				throw new GLib.IOError.FAILED(
					stderr_text != null && stderr_text != "" ?
						stderr_text.strip() : "Administrator access was not granted.");
			}
			var data = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), output)
				as Argus.Shared.SQT.Server;
			if (data == null || data.error != "" || !data.has_certificate) {
				throw new GLib.IOError.FAILED(
					data != null && data.error != "" ? data.error : "Registration failed");
			}
			reg.server_row = data;
			var row = new Argus.Agent.SQT.Server() { data_dir = this.data_dir };
			if (!reg.save(row)) {
				throw new GLib.IOError.FAILED("Could not save the server row");
			}
			service.restart();
		}
```

**Where:** gtk notice `RegistrationOpen.LOCAL` → waiting notice → `enroll_local_certificate.begin` (same JSON path as Bootstrap `finish_registration`, no `try_batch`).

---

## Follow-up (not this change)

**R6** and **R7** — ✔️ 2026-11-21-FIXED-local-registration-docs-polkit.md.

Gtk notice **Connect locally** uses `enroll_local_certificate` (2026-11-21-FIXED-agent-gtk-notice.md) with pkexec via `org.roojs.ArgusServer.register`.

🚫 Do not add certificate flags on `argusrm-agent` or `argusrm-controller` (server binary only). 🚫 Gtk **Connect locally** must not use `try_batch` or registration PIN.