# Agent `--server` and controller paste command

**Status:** ⏳ applied in the tree. Not user-verified. Section 7 clears `--server` with the other options. Its earlier replace fence was a copy of the base command line, so that fence was not applied.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 `argus-agent` accepts `--server` with an IP address.
- 🔷 `argus-agent` accepts `--pin`, so `sudo argus-agent --server IP --pin PIN` registers in one command.
- 🔷 When the controller opens registration, keep `Registration PIN: %s` and `Registration is open for 60 seconds. Press Ctrl+C to close it early.`
- 🔷 After those lines, recommend the agent command for a remote terminal, including that PIN.
- 🔷 Root, no command, no desktop: bare `argus-controller` opens registration.
- ℹ️ A public server does not broadcast Avahi. That is context. It is not a separate change.
- 🔷 The address in the recommendation is the public IPv4. `server/Net/Interfaces.vala` `public_ip()` connects to https://ifconfig.me with libsoup over IPv4. It does not hunt for an address.

## Ruled out of this proposal

- 🚫 `--server` values wrapped in `[ ]`.
- 🚫 A port glued on with `IP:port`.
- 🚫 Removing the GTK registration window.
- 🚫 The controller enrolling with `--server` and `--pin`.
- 🚫 Reading `socket` under `Argus.SERVER_SYSCONFDIR`, or listing interfaces, to choose the address in the remote command. That address is `Interfaces.public_ip()`.
- 🚫 Rebuilding the pkexec command. A desktop launch forwards nothing: not `--server`, `--host`, `--port`, `--pin`, or the debug flags.

## Proposed fix

### 1. `agent/Application.vala` — class doc: `--server`

**Why:** `--server` is the management IP. A missing address still browses.

**Where:** Class doc of `Argus.Agent.Application`, the sentence that names `--debug`.

**Depends on:** none

#### Remove

```vala
	 * {@link app_options}, including ''--debug''. {@link host},
	 * {@link port}, and {@link pin} are the registration properties.
		 * {@link hold} keeps the process up. With no host and port,
```

#### Replace with

```vala
	 * {@link app_options}, including ''--debug''. ''--server'' is
	 * the management IP. {@link host},
	 * {@link port}, and {@link pin} are the registration properties.
	 * {@link hold} keeps the process up. With no address,
```

### 2. `agent/Application.vala` — `opt_server`

**Why:** Hold the `--server` value next to the other option statics.

**Where:** Static fields, immediately after `opt_port`.

**Depends on:** none

#### Remove

```vala
		protected static int opt_port;
		protected static string opt_pin;
```

#### Replace with

```vala
		protected static int opt_port;
		protected static string opt_server;
		protected static string opt_pin;
```

### 3. `agent/Application.vala` — `app_options`: `--server=IP`

**Why:** Accept `--server` as one IP. The port stays `--port`.

**Where:** `app_options`, immediately after the `--port` entry.

**Depends on:** §2

#### Remove

```vala
			{ "port", 0, 0, GLib.OptionArg.INT, ref opt_port, "Argus port", "PORT" },
			{ "pin", 0, 0, GLib.OptionArg.STRING, ref opt_pin, "Number from the registration window", "PIN" },
```

#### Replace with

```vala
			{ "port", 0, 0, GLib.OptionArg.INT, ref opt_port, "Argus port", "PORT" },
			{ "server", 0, 0, GLib.OptionArg.STRING, ref opt_server, "Argus server IP address", "IP" },
			{ "pin", 0, 0, GLib.OptionArg.STRING, ref opt_pin, "Number from the registration window", "PIN" },
```

### 4. `agent/Application.vala` — `command_line` doc

**Why:** Document `--server` on the base command line, which Linux root registration does not call.

**Where:** `command_line` docblock, the `--debug` sentence.

**Depends on:** §3

#### Remove

```vala
		 * ''--debug'' shows log lines on stderr. ''--host'', ''--port'',
		 * and ''--pin'' together call {@link Argus.Shared.Register}
```

#### Replace with

```vala
		 * ''--debug'' shows log lines on stderr. ''--server'' is the
		 * management IP. ''--port'' overrides {@link Argus.SOCKET_PORT}.
		 * ''--server'' or ''--host'' with ''--port'' and ''--pin'' call
		 * {@link Argus.Shared.Register}
```

### 5. `agent/Application.vala` — reset `opt_server`

**Why:** Clear `--server` at the start of every launch.

**Where:** `command_line`, the option resets, immediately after `opt_port = 0`.

**Depends on:** §2

#### Remove

```vala
			opt_host = "";
			opt_port = 0;
			opt_pin = "";
```

#### Replace with

```vala
			opt_host = "";
			opt_port = 0;
			opt_server = "";
			opt_pin = "";
```

### 6. `agent/Application.vala` — `command_line`: copy `--server` onto `host`

**Why:** `--server` is one IP. It is not split on `:`. A missing `--port` uses `Argus.SOCKET_PORT`. Both `--server` and `--host` is an error.

**Where:** `command_line`, immediately after `this.pin = opt_pin` and before `var open_window`.

**Depends on:** §5

#### Remove

```vala
			this.host = opt_host;
			this.port = opt_port;
			this.pin = opt_pin;
			var open_window = false;
```

#### Replace with

```vala
			this.host = opt_host;
			this.port = opt_port;
			this.pin = opt_pin;
			if (opt_server != "" && opt_host != "") {
				command_line.printerr("registration needs one address\n");
				return 1;
			}
			if (opt_server != "") {
				var inet = new GLib.InetAddress.from_string(opt_server.strip());
				if (inet == null || inet.is_any || inet.is_multicast) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
				this.host = inet.to_string();
				if (this.port <= 0) {
					this.port = Argus.SOCKET_PORT;
				}
				if (this.port > 65535) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
			}
			var open_window = false;
```

### 7. `agent/linux/Application.vala` — reset `opt_server`

**Why:** The Linux command line parses options itself. Clear `--server` with the others.

**Where:** `command_line`, the option resets, immediately after `opt_port = 0`.

**Depends on:** §2

#### Remove

```vala
			opt_host = "";
			opt_port = 0;
			opt_pin = "";
			opt_service = false;
```

#### Replace with

```vala
			opt_host = "";
			opt_port = 0;
			opt_server = "";
			opt_pin = "";
			opt_service = false;
```

### 8. `agent/linux/Application.vala` — reject positional arguments

**Why:** Flags are parsed above. A leftover word is still rejected before elevation.

**Where:** `command_line`, immediately after the `OptionError` catch and before `if (service_mode)`.

**Depends on:** §7

#### Remove

```vala
				return 1;
			}
			if (service_mode) {
```

#### Replace with

```vala
				return 1;
			}
			if (leftover.length > 1) {
				command_line.printerr("argus-agent does not accept registration arguments.\n");
				return 1;
			}
			if (service_mode) {
```

### 9. `agent/linux/Application.vala` — `is_desktop`, once

**Why:** Read the display variables once. Later code uses `this.is_desktop`. A non-root desktop launch still does not forward flags, and `--server` there is rejected. `on_start_admin` still reads the variables because pkexec needs their values.

**Where:** The `is_desktop` field, the start of `command_line`, and the headless check after the root return.

**Depends on:** §7

##### Part 1 — field

#### Remove

```vala
		private uint bus_owner = 0;
```

#### Replace with

```vala
		private uint bus_owner = 0;

		private bool is_desktop = false;
```

##### Part 2 — set it first

#### Remove

```vala
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			var args = command_line.get_arguments();
```

#### Replace with

```vala
		public override int command_line(GLib.ApplicationCommandLine command_line)
		{
			var display = GLib.Environment.get_variable("DISPLAY");
			var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			this.is_desktop = (display != null && display != "") || (wayland != null && wayland != "");
			var args = command_line.get_arguments();
```

##### Part 3 — headless check and `--server`

#### Remove

```vala
			var display = GLib.Environment.get_variable("DISPLAY");
			var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			if ((display == null || display == "") && (wayland == null || wayland == "")) {
				command_line.printerr("Run argus-agent as root.\n");
				return 1;
			}
			Gtk.init();
```

#### Replace with

```vala
			if (!this.is_desktop) {
				command_line.printerr("Run argus-agent as root.\n");
				return 1;
			}
			if (opt_server != "") {
				Gtk.init();
				var rejected = new Argus.Shared.Notice("argus-agent does not accept --server", "");
				rejected.add_response("ok", "OK");
				rejected.closed.connect(() => {
					this.quit();
				});
				rejected.present(null);
				this.hold();
				return 0;
			}
			Gtk.init();
```

### 10. `agent/linux/Application.vala` — `registration()` and `cli()`

**Why:** `registration()` is the desktop path: service setup, the already-registered notice, and `RegisterWindow`. `cli()` is the command-line path: `--server`, `--pin`, browse, and the PIN prompt. Root with a desktop and no registration flags calls `registration()`. Root otherwise calls `cli()`.

**Where:** The root branch in `command_line`, then the whole `registration()` method, which is replaced by the two methods.

**Depends on:** §9

##### Part 1 — choose the method

#### Remove

```vala
			if (Posix.geteuid() == 0) {
				return this.registration(command_line);
			}
```

#### Replace with

```vala
			if (Posix.geteuid() == 0) {
				if (this.is_desktop && opt_server == "" && opt_host == "" && opt_pin == "" && opt_port <= 0) {
					return this.registration();
				}
				return this.cli(command_line);
			}
```

##### Part 2 — desktop method, and the command-line method

#### Remove

```vala
		private int registration(GLib.ApplicationCommandLine command_line)
		{
			var args = command_line.get_arguments();
			var have_display = GLib.Environment.get_variable("DISPLAY");
			var have_wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
			var desktop = (have_display != null && have_display != "") || (have_wayland != null && have_wayland != "");
			if (args.length > 1) {
				if (!desktop) {
					command_line.printerr("argus-agent does not accept registration arguments.\n");
					return 1;
				}
				Gtk.init();
				var failed = new Argus.Shared.Notice("argus-agent does not accept registration arguments", "");
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				if (!desktop) {
					command_line.printerr("Could not set up the Argus agent service: %s\n", e.message);
					return 1;
				}
				Gtk.init();
				var failed = new Argus.Shared.Notice("Could not set up the Argus agent service", e.message);
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				if (!desktop) {
					command_line.print("Argus agent is already registered.\n");
					return 0;
				}
				Gtk.init();
				var failed = false;
				var notice = new Argus.Shared.Notice("Argus agent is running", "");
				notice.add_response("close", "Close");
				notice.add_response("restart", "Restart");
				notice.responded.connect((response) => {
					if (response != "restart") {
						return;
					}
					try {
						service.restart();
					} catch (GLib.Error e) {
						failed = true;
						var error_notice = new Argus.Shared.Notice("Could not restart the Argus agent service", e.message);
						error_notice.add_response("ok", "OK");
						error_notice.closed.connect(() => {
							this.quit();
						});
						error_notice.present(null);
					}
				});
				notice.closed.connect(() => {
					if (!failed) {
						this.quit();
					}
				});
				notice.present(null);
				this.hold();
				return 0;
			}
			if (desktop) {
				Gtk.init();
				var window = new Argus.Shared.RegisterWindow() {
					data_dir = Argus.AGENT_DATA_DIR
				};
				window.show_add();
				window.certificate_received.connect(() => {
					try {
						service.restart();
					} catch (GLib.Error e) {
						window.error_occurred("Registered, but could not restart the Argus agent service: " + e.message);
						return;
					}
					GLib.Idle.add(() => {
						window.listen_label.label = "Registration succeeded. The Argus agent is running and connected. This window will close in 10 seconds.";
						return false;
					});
				});
				window.present(null);
				window.closed.connect(() => {
					this.quit();
				});
				this.hold();
				return 0;
			}
			var browse = new Argus.Shared.Browse();
			browse.start();
			command_line.print("Looking for a management server…\n");
			var found = browse.poll();
			while (found == "") {
				GLib.MainContext.default().iteration(true);
				found = browse.poll();
			}
			browse.stop();
			if (found == "none") {
				command_line.printerr("No management server found.\n");
				return 1;
			}
			var newline = found.index_of("\n");
			if (newline <= 0 || !GLib.Uuid.string_is_valid(found.substring(0, newline))) {
				command_line.printerr("No management server found.\n");
				return 1;
			}
			var hostport = found.substring(newline + 1);
			var colon = hostport.last_index_of(":");
			if (colon <= 0) {
				command_line.printerr("No management server found.\n");
				return 1;
			}
			var port = 0;
			if (!int.try_parse(hostport.substring(colon + 1), out port) || port <= 0 || port > 65535) {
				command_line.printerr("No management server found.\n");
				return 1;
			}
			var registration = new Argus.Shared.Register() {
				data_dir = Argus.AGENT_DATA_DIR
			};
			while (true) {
				command_line.print("Enter registration PIN: ");
				GLib.stdout.flush();
				var line = GLib.stdin.read_line();
				if (line == null) {
					command_line.printerr("\n");
					return 1;
				}
				var pin = line.strip();
				var valid_pin = pin.length == 6;
				for (var i = 0; valid_pin && i < pin.length; i++) {
					if (pin[i] < '0' || pin[i] > '9') {
						valid_pin = false;
					}
				}
				if (!valid_pin) {
					command_line.printerr("Enter the six digits.\n");
					continue;
				}
				var code = registration.try_connection(hostport.substring(0, colon), (uint16) port, pin, GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					continue;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n", e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
		}
```

#### Replace with

```vala
		/**
		 * Register this machine from the desktop.
		 *
		 * The service is set up first. An existing certificate
		 * shows the running notice. Otherwise the registration
		 * window opens. Command-line registration is {@link cli}.
		 *
		 * @return zero when a window is open
		 */
		private int registration()
		{
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				Gtk.init();
				var failed = new Argus.Shared.Notice("Could not set up the Argus agent service", e.message);
				failed.add_response("ok", "OK");
				failed.closed.connect(() => {
					this.quit();
				});
				failed.present(null);
				this.hold();
				return 0;
			}
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				Gtk.init();
				var failed = false;
				var notice = new Argus.Shared.Notice("Argus agent is running", "");
				notice.add_response("close", "Close");
				notice.add_response("restart", "Restart");
				notice.responded.connect((response) => {
					if (response != "restart") {
						return;
					}
					try {
						service.restart();
					} catch (GLib.Error e) {
						failed = true;
						var error_notice = new Argus.Shared.Notice("Could not restart the Argus agent service", e.message);
						error_notice.add_response("ok", "OK");
						error_notice.closed.connect(() => {
							this.quit();
						});
						error_notice.present(null);
					}
				});
				notice.closed.connect(() => {
					if (!failed) {
						this.quit();
					}
				});
				notice.present(null);
				this.hold();
				return 0;
			}
			Gtk.init();
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = Argus.AGENT_DATA_DIR
			};
			window.show_add();
			window.certificate_received.connect(() => {
				try {
					service.restart();
				} catch (GLib.Error e) {
					window.error_occurred("Registered, but could not restart the Argus agent service: " + e.message);
					return;
				}
				GLib.Idle.add(() => {
					window.listen_label.label = "Registration succeeded. The Argus agent is running and connected. This window will close in 10 seconds.";
					return false;
				});
			});
			window.present(null);
			window.closed.connect(() => {
				this.quit();
			});
			this.hold();
			return 0;
		}

		/**
		 * Register this machine from the command line.
		 *
		 * ''--server'' is the management IP. ''--pin'' uses that
		 * number instead of asking. Both together register in one
		 * step. No address browses, then asks for the PIN.
		 *
		 * @param command_line arguments for this launch
		 * @return zero when registration finished, otherwise the
		 *   setup or registration error
		 */
		private int cli(GLib.ApplicationCommandLine command_line)
		{
			if (opt_server != "" && opt_host != "") {
				command_line.printerr("registration needs one address\n");
				return 1;
			}
			if (opt_port < 0 || opt_port > 65535) {
				command_line.printerr("registration needs an IP address\n");
				return 1;
			}
			if (opt_port > 0 && opt_server == "" && opt_host == "") {
				command_line.printerr("registration needs an IP address\n");
				return 1;
			}
			var host = "";
			var port = Argus.SOCKET_PORT;
			if (opt_port > 0) {
				port = opt_port;
			}
			if (opt_server != "") {
				var inet = new GLib.InetAddress.from_string(opt_server.strip());
				if (inet == null || inet.is_any || inet.is_multicast) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
				host = inet.to_string();
			}
			if (opt_host != "") {
				var named = new GLib.InetAddress.from_string(opt_host);
				if (named == null || named.is_any || named.is_multicast) {
					command_line.printerr("registration needs an IP address\n");
					return 1;
				}
				host = named.to_string();
			}
			var given_pin = opt_pin.strip();
			if (given_pin != "") {
				if (!GLib.Regex.match_simple("^[0-9]{6}$", given_pin)) {
					command_line.printerr("Enter the six digits.\n");
					return 1;
				}
			}
			var service = new ServiceManager();
			try {
				service.setup();
			} catch (GLib.Error e) {
				command_line.printerr("Could not set up the Argus agent service: %s\n", e.message);
				return 1;
			}
			var certificate = GLib.Path.build_filename(Argus.AGENT_DATA_DIR, "client.pem");
			if (GLib.FileUtils.test(certificate, GLib.FileTest.EXISTS)) {
				command_line.print("Argus agent is already registered.\n");
				return 0;
			}
			if (host == "") {
				var browse = new Argus.Shared.Browse();
				browse.start();
				command_line.print("Looking for a management server…\n");
				var found = browse.poll();
				while (found == "") {
					GLib.MainContext.default().iteration(true);
					found = browse.poll();
				}
				browse.stop();
				if (found == "none") {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				var newline = found.index_of("\n");
				if (newline <= 0 || !GLib.Uuid.string_is_valid(found.substring(0, newline))) {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				var hostport = found.substring(newline + 1);
				var colon = hostport.last_index_of(":");
				if (colon <= 0) {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				var announced = 0;
				if (!int.try_parse(hostport.substring(colon + 1), out announced) ||
					announced <= 0 || announced > 65535) {
					command_line.printerr("No management server found.\n");
					return 1;
				}
				host = hostport.substring(0, colon);
				port = announced;
			}
			var registration = new Argus.Shared.Register() {
				data_dir = Argus.AGENT_DATA_DIR
			};
			if (given_pin != "") {
				var code = registration.try_connection(host, (uint16) port, given_pin,
					GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					return 1;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n", e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
			while (true) {
				command_line.print("Enter registration PIN: ");
				GLib.stdout.flush();
				var line = GLib.stdin.read_line();
				if (line == null) {
					command_line.printerr("\n");
					return 1;
				}
				var pin = line.strip();
				if (!GLib.Regex.match_simple("^[0-9]{6}$", pin)) {
					command_line.printerr("Enter the six digits.\n");
					continue;
				}
				var code = registration.try_connection(host, (uint16) port, pin,
					GLib.Environment.get_host_name());
				if (code != 0) {
					command_line.printerr("Registration failed: %d\n", code);
					continue;
				}
				try {
					service.restart();
				} catch (GLib.Error e) {
					command_line.printerr("Registered, but could not restart the Argus agent service: %s\n", e.message);
					return 1;
				}
				command_line.print("Registration succeeded. The Argus agent is running and connected.\n");
				return 0;
			}
		}
```

### 11. `controller/Application.vala` — class doc

**Why:** Headless root with no flags opens registration. Any other headless launch with no flags prints usage.

**Where:** Class doc of `Argus.Controller.Application`, the headless sentence.

**Depends on:** none

#### Remove

```vala
	 * {@link Agents}, or {@link Command}. No flag on a headless
	 * machine prints usage.
```

#### Replace with

```vala
	 * {@link Agents}, or {@link Command}. No flag on a headless
	 * root machine opens registration. Any other headless launch
	 * with no flag prints usage.
```

### 12. `controller/Application.vala` — `command_line` doc

**Why:** Same headless-root sentence on the method that implements it.

**Where:** `command_line` docblock.

**Depends on:** §11

#### Remove

```vala
		 * No flag on a desktop opens {@link Bootstrap}. The Unix
		 * socket is ''argus.sock'' under {@link Argus.SERVER_DATA_DIR}.
```

#### Replace with

```vala
		 * No flag on a desktop opens {@link Bootstrap}. No flag on a
		 * headless root machine opens registration. The Unix socket
		 * is ''argus.sock'' under {@link Argus.SERVER_DATA_DIR}.
```

### 13. `controller/Application.vala` — no flags

**Why:** Headless root sets `pin` and falls through into `Pin.run()`. Headless non-root prints usage. A desktop with no flags still opens `Bootstrap`.

**Where:** `command_line`, the `if (chosen == 0)` block.

**Depends on:** §12

#### Remove

```vala
			if (chosen == 0) {
				var display = GLib.Environment.get_variable("DISPLAY");
				var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				if ((display == null || display == "") && (wayland == null || wayland == "")) {
					command_line.printerr("Usage:\n  argus-controller --pin\n  argus-controller --agents\n  argus-controller --give-me-a-certificate USERNAME\n  argus-controller --agent ID --command COMMAND...\n");
					return 1;
				}
				Gtk.init();
				var bootstrap = new Bootstrap(this);
				bootstrap.present(null);
				this.hold();
				return 0;
			}
```

#### Replace with

```vala
			if (chosen == 0) {
				var display = GLib.Environment.get_variable("DISPLAY");
				var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				var headless = (display == null || display == "") && (wayland == null || wayland == "");
				if (headless) {
#if LINUX
					if (Posix.geteuid() == 0) {
						pin = true;
					}
#endif
					if (!pin) {
						command_line.printerr("Usage:\n  argus-controller --pin\n  argus-controller --agents\n  argus-controller --give-me-a-certificate USERNAME\n  argus-controller --agent ID --command COMMAND...\n");
						return 1;
					}
				}
				if (!headless) {
					Gtk.init();
					var bootstrap = new Bootstrap(this);
					bootstrap.present(null);
					this.hold();
					return 0;
				}
			}
```

### 14. `controller/Pin.vala` — class doc

**Why:** The PIN lines stay. After them, the remote-terminal command uses the address from `Interfaces.public_ip()`.

**Where:** Class doc of `Argus.Controller.Pin`.

**Depends on:** none

#### Remove

```vala
	 * Asks ''Agent.offer'' for a six-digit pin and prints it.
	 * The number lasts sixty seconds. {@link Application}
	 * already hellos.
```

#### Replace with

```vala
	 * Asks ''Agent.offer'' for a six-digit pin and prints it.
	 * The number lasts sixty seconds. It then recommends the
	 * agent command for a remote terminal, using the public
	 * address from that reply. {@link Application} already hellos.
```

### 15. `controller/Pin.vala` — `run()`: remote-terminal line

**Why:** Keep the PIN line and the sixty-second line. After them, print the remote command. `Agent.offer` returns a string array: the six digits, then the address from `Interfaces.public_ip()`.

**Where:** `Pin.run`, the success path, the existing `Registration PIN` print.

**Depends on:** §14 and §16

#### Remove

```vala
					var pin = response.retval as string;
					if (pin == null || pin.length != 6) {
						this.app.cli.printerr("The server did not return a number.\n");
						this.app.loop.quit();
						return;
					}
					this.app.cli.print("Registration PIN: %s\nRegistration is open for 60 seconds. Press Ctrl+C to close it early.\n", pin);
```

#### Replace with

```vala
					var reply = (string[]) response.retval;
					if (reply.length != 2 || reply[0].length != 6) {
						this.app.cli.printerr("The server did not return a number.\n");
						this.app.loop.quit();
						return;
					}
					var pin = reply[0];
					this.app.cli.print("Registration PIN: %s\nRegistration is open for 60 seconds. Press Ctrl+C to close it early.\n", pin);
					this.app.cli.print("""On a remote terminal you can use:
sudo argus-agent --server %s --pin %s
""".printf(reply[1], pin));
```

### 16. `server/Agent.vala` — `offer()` returns the public address

**Why:** `Interfaces.public_ip()` is the address in the remote command. `Agent.offer` returns a string array in `retval`: the six digits, then that address. `msg` stays `"ok"`.

**Where:** `Agent.offer` docblock, then the success `request.reply`.

**Depends on:** none. `Interfaces.public_ip()` is already in the tree.

##### Part 1 — docblock

#### Remove

```vala
		 * The controller calls this with no arguments. The reply
		 * is the six digits. This opens the app socket and
```

#### Replace with

```vala
		 * The controller calls this with no arguments. The reply
		 * is the six digits, then the public address. This opens
		 * the app socket and
```

##### Part 2 — reply

#### Remove

```vala
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("s", issued),
				msg = "ok"
			});
```

#### Replace with

```vala
			var address = "";
			try {
				address = this.app.interfaces.public_ip();
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			var reply = new string[] { issued, address };
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("as", reply),
				msg = "ok"
			});
```

### 17. `controller/PairingDialog.vala` — `arm()` reads the PIN from the array

**Why:** `Agent.offer` no longer returns a single string. The dialog still shows the six digits, which are the first element.

**Where:** `PairingDialog.arm`, the success path that reads `response.retval`.

**Depends on:** §16

#### Remove

```vala
					var number = response.retval as string;
					if (number == null || number.length != 6) {
						this.note.label = "The server did not return a number.";
						return;
					}
					this.pin_label.label = number;
```

#### Replace with

```vala
					var reply = (string[]) response.retval;
					if (reply.length < 1 || reply[0].length != 6) {
						this.note.label = "The server did not return a number.";
						return;
					}
					this.pin_label.label = reply[0];
```

