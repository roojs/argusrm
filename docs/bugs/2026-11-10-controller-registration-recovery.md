# Stuck controller registration cannot be cleared

**Status:** ✔️ applied. Not committed.

**Pointer:** `docs/bug-fix-process.md` and `docs/guide-to-writing-plans.md` (Edit syntax contract)

---

## Problem

- 🔷 Local login says this machine is already registered, and the desktop has no certificate that can open the window.
- 🔷 That registration has to be recoverable without editing the database.
- 🔷 Recovery uses the existing deregister call. A second remove command is the wrong tool.
- 🔷 Root can run it from `argusrm-controller-cli`. The desktop reaches the same call through Polkit.
- 🔷 Starting the controller and failing to log in uses the existing Deregister locally button. That button clears the saved login and also sends this username to the server. The same call argument is a certificate fingerprint when a window is already connected. The server deletes that username's controller rows whose address is blank or `127.0.0.1`.

## Evidence

- ✔️ `Registration.certificate` refuses a second certificate when a `status = 1` controller row already has this username and hostname. The reply is `This machine is already registered.`
- ✔️ `Registration.deregister` accepts only the TLS connection, and the argument must be that connection's peer fingerprint. A Unix-socket caller receives `TCP only`.
- ✔️ The window command `Deregister this controller` uses that TLS call. With no saved certificate it stops at `The saved server has no certificate.`
- ✔️ Startup's `Deregister locally` deletes the keyring secret and `connections.json`. It does not call the server.
- ✔️ A saved server that never answers stops on `The saved server did not answer.` The buttons are Deregister locally, Retry, and Log in to register. `controller/dialog/Bootstrap.vala` `probe`.
- ✔️ A server that accepts TCP and then rejects the certificate stops on `Could not connect` with `rpc.connect_error`. The buttons are Retry and Log in to register. `Bootstrap.use`. Neither page calls `Registration.deregister`.
- ✔️ On this machine, `~/.config/argusrm/connections.json` was `[]` while six active controller rows remained for `alan` on `fastboy`.
- ℹ️ `controller/meson.build` still sets the Polkit executable to `bindir / 'argus-controller'`. The installed binary is `/usr/bin/argusrm-controller`.

## Root cause

- ✔️ Deregister can delete the row only after the controller has connected with the certificate being deleted. The lockout is the case where that certificate is already gone.

## Ruled out

- 🚫 A new `Registration.remove` method, or `--remove-controller`.
- 🚫 One option whose extra values are leftover positional arguments, such as `--deregister USERNAME 127.0.0.1`.
- 🚫 Hand-editing `agent` in `/var/lib/argusrm/argus.sqlite`.

## Proposed fix

The wire call stays one string. That string is either a certificate fingerprint or a username. `GLib.Checksum` SHA256 is 64 lowercase hex digits. A username is a short login name such as `alan`, so the two are not the same kind of string. The connected window still sends the fingerprint. The reset sends the username:

```sh
sudo argusrm-controller-cli --deregister alan
```

On the TLS connection the string must still be that connection's peer fingerprint. On `argus.sock`, root may pass either kind. A 64-digit hex string deletes that fingerprint. Anything else is a username, and the server deletes that username's controller rows whose `ip` is `''` or `127.0.0.1`. No address is passed in.

### 1. `server/Registration.vala` — `certificate`: store `127.0.0.1`

**Why:** A new local row should be one of the two addresses §2 deletes: blank, or `127.0.0.1`.

**Where:** `certificate`, the `insert` object, the line after `status = 0,`.

**Depends on:** none.

#### Add — after `status = 0,` in the `certificate` insert

```vala
						ip = "127.0.0.1",
```

### 2. `server/Registration.vala` — `deregister`

**Why:** Root on the Unix socket has no peer certificate. The same one-string argument is a fingerprint or a username. The TLS path below this edit is unchanged.

**Where:** `deregister`, the documentation, and the `ssl == null` branch. Ordered chunks.

**Depends on:** none.

##### Part 1 — Documentation

#### Remove

```vala
		/**
		 * Remove this certificate's controller row.
		 *
		 * The desktop calls this on the TLS connection already open
		 * for that certificate, then closes the connection. The
		 * fingerprint must be the peer certificate. A missing row
		 * is still success. The allowlist is refreshed from the
		 * rows that remain.
		 *
		 * @param request inbound RPC on the app socket
		 * @param fingerprint SHA256 of the client certificate
		 */
```

#### Replace with

```vala
		/**
		 * Remove a controller registration.
		 *
		 * ''fingerprint'' is one string. On the TLS connection it
		 * must be the peer certificate. On ''argus.sock'', root
		 * passes either that same SHA256 hex or a username. Sixty
		 * four lowercase hex digits are a fingerprint. Anything
		 * else is a username, and only rows with a blank ''ip'' or
		 * ''127.0.0.1'' are deleted. A missing row is still
		 * success.
		 *
		 * @param request inbound RPC on the app socket
		 * @param fingerprint SHA256 hex, or a username on the Unix socket
		 */
```

##### Part 2 — Unix socket branch

#### Remove

```vala
			if (ssl == null) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("TCP only")
				});
				return;
			}
```

#### Replace with

```vala
			if (ssl == null) {
				try {
					if (request.connection.stream == null ||
						request.connection.stream.get_socket().get_credentials().get_unix_user() != 0) {
						request.reply(new OLLMrpc.Response() {
							error = new OLLMrpc.Error.INVALID_REQUEST("root is required")
						});
						return;
					}
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("root is required")
					});
					return;
				}
				if (fingerprint == "") {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("fingerprint is required")
					});
					return;
				}
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("is_controller", 1);
				var where = "WHERE is_controller = $is_controller AND username = $username " +
					"AND (ip = '' OR ip = '127.0.0.1')";
				text_binds.set("username", fingerprint);
				// SHA256 hex is 64 digits. A username is a short login name.
				if (fingerprint.length == 64) {
					var hex = true;
					for (var i = 0; i < fingerprint.length; i++) {
						var c = fingerprint[i];
						if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
							hex = false;
							break;
						}
					}
					if (hex) {
						where = "WHERE fingerprint = $fingerprint AND is_controller = $is_controller";
						text_binds.unset("username");
						text_binds.set("fingerprint", fingerprint);
					}
				}
				Argus.Shared.Agent.query(this.app.db).deleteWhere(where, int_binds, text_binds);
				this.app.db.backupDB();
				this.app.firewall.apply(Agent.allowlist(this.app.db, this.app.interfaces));
				request.reply(new OLLMrpc.Response() {
					msg = "ok"
				});
				return;
			}
```

### 3. `controller/cli/Application.vala` — `--deregister`

**Why:** One option, one value. That value is a username or a fingerprint. The server tells them apart.

**Where:** fields, `app_options`, the start of `command_line`, the mode count, and `on_connect` after the `--agents` branch.

**Depends on:** §2.

##### Part 1 — Fields

#### Add — after `public static string command;`

The username or fingerprint from `--deregister`. Empty unless that flag was passed.

```vala
		public static string deregister_name;
```

##### Part 2 — Options

#### Add — in `app_options`, after the `--command` entry and before `{ null }`

```vala
			{ "deregister", 0, 0, GLib.OptionArg.STRING, ref deregister_name, "Username or fingerprint to deregister", "NAME" },
```

##### Part 3 — Reset the value

#### Remove

```vala
			agent = "";
			command = "";
```

#### Replace with

```vala
			agent = "";
			command = "";
			deregister_name = "";
```

##### Part 4 — One mode

#### Remove

```vala
			var chosen = (pin ? 1 : 0)
				+ (agents ? 1 : 0)
				+ (agent != "" || command != "" ? 1 : 0);
			var usage = """Usage:
  argusrm-controller-cli
  argusrm-controller-cli --pin
  argusrm-controller-cli --agents
  argusrm-controller-cli --agent ID --command COMMAND...
""";
```

#### Replace with

```vala
			var removing = deregister_name != "";
			var chosen = (pin ? 1 : 0)
				+ (agents ? 1 : 0)
				+ (removing ? 1 : 0)
				+ (agent != "" || command != "" ? 1 : 0);
			var usage = """Usage:
  argusrm-controller-cli
  argusrm-controller-cli --pin
  argusrm-controller-cli --agents
  argusrm-controller-cli --deregister NAME
  argusrm-controller-cli --agent ID --command COMMAND...
""";
```

#### Add — in `command_line`, immediately after the `chosen > 1` return

The process must be root.

```vala
			if (removing && Posix.geteuid() != 0) {
				command_line.printerr("root is required\n");
				return 1;
			}
```

##### Part 5 — Do not demand `--agent` for this mode

#### Remove

```vala
			if (agent == "" && !pin && !agents) {
				command_line.printerr("command needs --agent ID\n");
				return 1;
			}
```

#### Replace with

```vala
			if (agent == "" && !pin && !agents && !removing) {
				command_line.printerr("command needs --agent ID\n");
				return 1;
			}
```

#### Remove

```vala
			if (!pin && !agents && parts.size < 1) {
				command_line.printerr("command needs --command\n");
				return 1;
			}
```

#### Replace with

```vala
			if (!pin && !agents && !removing && parts.size < 1) {
				command_line.printerr("command needs --command\n");
				return 1;
			}
```

##### Part 6 — Call

#### Add — in `on_connect`, immediately after the `--agents` branch returns

```vala
			if (deregister_name != "") {
				this.rpc.call.begin(new OLLMrpc.Request() {
					method = "Registration.deregister",
					args = OLLMrpc.args("s", deregister_name)
				}, (call_obj, call_res) => {
					try {
						var response = this.rpc.call.end(call_res);
						if (response.error != null) {
							this.cli.printerr("%s\n", response.error.message);
							this.loop.quit();
							return;
						}
					} catch (GLib.Error e) {
						this.cli.printerr("%s\n", e.message);
						this.loop.quit();
						return;
					}
					this.cli.print("Deregistered %s.\n", deregister_name);
					this.code = 0;
					this.loop.quit();
				});
				return;
			}
```

### 4. `controller/Application.vala` — Polkit runs `--deregister`

**Why:** The desktop elevates this binary. It uses the same option as the command line.

**Where:** fields, `app_options`, the start of `command_line`, the window guard, and `on_connect`.

**Depends on:** §2.

##### Part 1 — Fields

#### Add — after `public static string give_certificate;`

```vala
		public static string deregister_name;
```

##### Part 2 — Options

#### Add — in `app_options`, after the `--give-me-a-certificate` entry and before `{ null }`

```vala
			{ "deregister", 0, 0, GLib.OptionArg.STRING, ref deregister_name, "Username or fingerprint to deregister", "NAME" },
```

##### Part 3 — Reset the value

#### Remove

```vala
			give_certificate = "";
```

#### Replace with

```vala
			give_certificate = "";
			deregister_name = "";
```

#### Add — in `command_line`, immediately after `debug_critical_enabled = opt_debug_critical;`

```vala
			if (give_certificate != "" && deregister_name != "") {
				command_line.printerr("Use one of --give-me-a-certificate or --deregister.\n");
				return 1;
			}
```

##### Part 4 — Open the window only when neither command was given

#### Remove

```vala
			if (give_certificate == "") {
```

#### Replace with

```vala
			if (give_certificate == "" && deregister_name == "") {
```

##### Part 5 — Call

#### Remove

```vala
			this.rpc.call.begin(new OLLMrpc.Request() {
				method = "Registration.certificate",
				args = OLLMrpc.args("s", give_certificate)
			}, (call_obj, call_res) => {
```

#### Replace with

```vala
			var method = "Registration.certificate";
			var call_args = OLLMrpc.args("s", give_certificate);
			if (deregister_name != "") {
				method = "Registration.deregister";
				call_args = OLLMrpc.args("s", deregister_name);
			}
			this.rpc.call.begin(new OLLMrpc.Request() {
				method = method,
				args = call_args
			}, (call_obj, call_res) => {
```

#### Add — in that callback, immediately after a null `response.error` check and before printing `response.retval`

A deregister success has no certificate object to print.

```vala
					if (deregister_name != "") {
						this.cli.print("%s\n", Json.gobject_to_data(new Argus.Shared.Registration.Data(), null));
						this.code = 0;
						this.loop.quit();
						return;
					}
```

### 5. `controller/dialog/Bootstrap.vala` — one root command for both

**Why:** Both callers use one pkexec route, `exe_root`. It is always pkexec, then this executable, then one option and one value. `--give-me-a-certificate` and `--deregister` are those options. A missing pkexec, or `/proc/self/exe` that cannot be read, stops. There is no other button.

**Where:** `register`, `issue` renamed to `exe_root`, the TLS failure page in `use`, and `deregister_local`. Ordered chunks.

**Depends on:** §4.

##### Part 1 — `register` asks `exe_root` to run

#### Remove

```vala
		 * Issue a certificate through Polkit.
		 *
		 * The login button is the prompt. There is no extra page
		 * explaining that administrator access is required.
```

#### Replace with

```vala
		 * Issue a certificate through Polkit.
		 *
		 * {@link exe_root} runs the root command. The login button
		 * is the prompt. There is no extra page explaining that
		 * administrator access is required.
```

#### Remove

```vala
#if LINUX
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				this.page("Could not request administrator access", "pkexec was not found.",
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var executable = "";
			try {
				executable = GLib.FileUtils.read_link("/proc/self/exe");
			} catch (GLib.FileError e) {
				this.page("Could not resolve argusrm-controller", e.message,
					{ "Retry", "Log in to register" }, { "retry", "register" });
				return;
			}
			var username = GLib.Environment.get_user_name();
			this.page("Registering server", "", {}, {});
			this.issue(pkexec, executable, username);
#else
			this.page("Could not register", "Local registration is Linux only.",
				{ "Retry", "Log in to register" }, { "retry", "register" });
#endif
```

#### Replace with

```vala
			this.exe_root("--give-me-a-certificate",
				GLib.Environment.get_user_name(), "Registering server", "");
```

##### Part 2 — `exe_root` is the pkexec route

#### Remove

```vala
		 * Run the privileged certificate command and store the connection.
		 *
		 * Standard output is {@link Argus.Shared.Registration.Data}.
		 * The private key stays on {@link Window}. The name, addresses,
		 * and port are written to ''connections.json''.
		 *
		 * @param pkexec path to pkexec
		 * @param executable this controller
		 * @param username controller login name
		 */
		private void issue(string pkexec, string executable, string username)
```

#### Replace with

```vala
		 * Run one privileged command and read its JSON.
		 *
		 * ''option'' is ''--give-me-a-certificate'' or
		 * ''--deregister''. Standard output is
		 * {@link Argus.Shared.Registration.Data}. A certificate
		 * is stored by {@link finish_registration}. A deregister
		 * with an empty error returns to the local-or-remote page.
		 * ''prior_error'' is shown when the command itself succeeds.
		 * A missing pkexec, or an unreadable ''/proc/self/exe'',
		 * stops with no further action.
		 *
		 * @param option root command option
		 * @param value username passed to that option
		 * @param waiting heading shown while the command runs
		 * @param prior_error earlier failure, or empty
		 */
		private void exe_root(string option, string value, string waiting, string prior_error)
```

#### Add — in `exe_root`, immediately after `this.generation++;`

The lookup `register` used to do. A missing pkexec or an unreadable `/proc/self/exe` is fatal: the page has no button. `pkexec` and `executable` are the locals the existing `argv` lines already append.

```vala
#if LINUX
			var failed = "Could not register";
			if (option == "--deregister") {
				failed = "Could not deregister";
			}
			var pkexec = GLib.Environment.find_program_in_path("pkexec");
			if (pkexec == null) {
				this.page("Could not request administrator access",
					"pkexec was not found.", {}, {});
				return;
			}
			var executable = "";
			try {
				executable = GLib.FileUtils.read_link("/proc/self/exe");
			} catch (GLib.FileError e) {
				this.page("Could not resolve argusrm-controller", e.message, {}, {});
				return;
			}
			this.page(waiting, "", {}, {});
```

#### Remove

```vala
			argv += "--give-me-a-certificate";
			argv += username;
```

#### Replace with

```vala
			argv += option;
			argv += value;
```

#### Remove

```vala
					this.page("Could not register", message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var data = new Argus.Shared.Registration.Data() {
					error = "The certificate command failed."
				};
```

#### Replace with

```vala
					this.page(failed, message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				var data = new Argus.Shared.Registration.Data() {
					error = "The command failed."
				};
```

#### Remove

```vala
				if (data.error != "" || data.name == "" || data.port < 1) {
					var message = data.error;
					if (message == "") {
						message = "The server did not return a connection.";
					}
					this.page("Could not register", message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				this.finish_registration(data);
```

#### Replace with

```vala
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
				if (data.error != "" || data.name == "" || data.port < 1) {
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
				this.finish_registration(data);
```

#### Add — in `exe_root`, immediately after the `});` that closes `communicate_utf8_async.begin`

This platform cannot run the route. That is a hard stop.

```vala
#else
			this.page("Could not request administrator access",
				"Local registration is Linux only.", {}, {});
#endif
```

##### Part 3 — TLS hello failed

#### Remove

```vala
					this.page("Could not connect", rpc.connect_error,
						{ "Retry", "Log in to register" }, { "retry", "register" });
```

#### Replace with

```vala
					this.page("Could not connect", rpc.connect_error,
						{ "Deregister locally", "Retry", "Log in to register" },
						{ "local", "retry", "register" });
```

##### Part 4 — Documentation

#### Remove

```vala
		/**
		 * Remove every saved login without calling the server.
		 *
		 * Each saved name drops its keyring secret and row.
		 * The empty-list page follows.
		 */
```

#### Replace with

```vala
		/**
		 * Deregister this controller.
		 *
		 * Each saved name drops its keyring secret and row.
		 * {@link exe_root} then runs ''--deregister'' for this username.
		 * A saved-login failure does not skip that command.
		 * The empty-list page follows when the command returns no error.
		 */
```

##### Part 5 — Keep going after a saved-login failure, then use `exe_root`

#### Remove

```vala
				try {
					data.clear_saved_login();
				} catch (GLib.Error e) {
					this.page("Could not deregister", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
			}
			this.connections.clear();
			this.reached.clear();
			this.credentials.clear();
			this.page("Argus Remote Manager", "",
				{ "Log in to local machine", "Connect a remote machine" },
				{ "register", "remote" });
```

#### Replace with

```vala
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
			this.exe_root("--deregister", GLib.Environment.get_user_name(),
				"Deregistering", local_error);
```

#### Add — in `deregister_local`, immediately before the `foreach`

The first saved-login failure is remembered. The loop still clears the other saved logins, and `exe_root` still runs. A missing pkexec does not.

```vala
			string local_error = "";
```

### 6. `controller/meson.build` — Polkit path

**Why:** The installed program is `argusrm-controller`. The policy still names `argus-controller`.

**Where:** `register_policy` configuration, `CONTROLLER_EXECUTABLE`.

**Depends on:** none.

#### Remove

```meson
			'CONTROLLER_EXECUTABLE': bindir / 'argus-controller',
```

#### Replace with

```meson
			'CONTROLLER_EXECUTABLE': bindir / 'argusrm-controller',
```

### 7. `controller/linux/org.roojs.ArgusController.register.policy.in` — allow `--deregister`

**Why:** Polkit matches the first argument. That argument is `--deregister`. The username follows it.

**Where:** after the existing `org.roojs.ArgusController.register` action, before `</policyconfig>`.

**Depends on:** §6.

#### Add — after the register action's closing `</action>`, before `</policyconfig>`

```xml
  <action id="org.roojs.ArgusController.deregister">
    <description>Deregister this Argus Remote Manager controller</description>
    <message>Authentication is required to deregister this Argus Remote Manager controller</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">@CONTROLLER_EXECUTABLE@</annotate>
    <annotate key="org.freedesktop.policykit.exec.argv1">--deregister</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
```

## Attempts

- ✔️ A separate `Registration.remove` and `--remove-controller` were added and then reverted.
- ✔️ A later draft used `--deregister USERNAME ADDRESS` and `Replace with` fences that did not show the removed lines. That draft is withdrawn.
- ✔️ A later draft added a second wire string for the username, then treated the single string as a hostname. The value is a username or a fingerprint. Those drafts are withdrawn.
- ✔️ A later draft added a second button, Reset connection, beside Deregister locally. One button tries both. That draft is withdrawn.
- ✔️ A later draft added `deregister_on_server`, then renamed that copy to `deregister_username`. The launch stays the one pkexec route, `exe_root`. Those drafts are withdrawn.
- ✔️ A later draft named that route `issue` and offered Retry when pkexec or `/proc/self/exe` failed. Those are hard stops. That draft is withdrawn.

## Next

- ⏳ Review the edits above. Nothing is applied until that review.
