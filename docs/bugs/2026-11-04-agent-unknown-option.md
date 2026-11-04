# `argus-agent --agents` shows the admin dialog

**Status:** ✔️ applied in tree

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 `argus-agent --agents` showed the upgrade-permissions dialog.
- 🔷 It should have said the command was wrong and exited.
- ℹ️ `--agents` is `argus-controller`, not the agent.
- ℹ️ The controller does not register with a PIN. It hellos on the local Unix socket. The PIN is for agents.

---

## Evidence

- ✔️ `agent/linux/Application.vala` `command_line` only special-cases `--help` and `--service`.
- ✔️ An unprivileged desktop launch then shows the admin notice.
- ✔️ Unknown flags are never parsed on that path.
- ✔️ The base `Argus.Agent.Application.command_line` already rejects unknown options with `OptionContext`.
- ✔️ Extra arguments are only refused later in `registration()`, and only as root.

---

## Root cause

- ✔️ The Linux override skips option parsing until after elevation.

---

## Proposed fix

- 🔷 Parse `app_options` before the admin dialog, same as the base class.
- 🔷 Unknown option: print the `OptionError` and exit `1`. No dialog.

### `agent/Application.vala` — options visible to Linux

The `OptionEntry` table refs the flag statics. Both have to be `protected`.

#### Remove

```vala
		private static bool opt_debug;
		private static bool opt_debug_critical;
		private static string opt_host;
		private static int opt_port;
		private static string opt_pin;
		private static bool opt_service;
		private static bool debug_on;
```

#### Replace with

```vala
		protected static bool opt_debug;
		protected static bool opt_debug_critical;
		protected static string opt_host;
		protected static int opt_port;
		protected static string opt_pin;
		protected static bool opt_service;
		private static bool debug_on;
```

#### Remove

```vala
		private const GLib.OptionEntry[] app_options = {
```

#### Replace with

```vala
		protected const GLib.OptionEntry[] app_options = {
```

### `agent/linux/Application.vala` — parse before elevation

#### Add — after the `--help` / `--service` scan, before the service / admin paths

```vala
			var opt_context = new GLib.OptionContext(this.application_id);
			opt_context.set_help_enabled(true);
			opt_context.add_main_entries(app_options, null);
			unowned string[] leftover = args;
			try {
				opt_context.parse(ref leftover);
			} catch (GLib.OptionError e) {
				command_line.printerr("error: %s\n", e.message);
				command_line.printerr("Run '%s --help' to see a full list of available command line options.\n",
					args[0]);
				return 1;
			}
```

---

## Attempts / changelog

- ✔️ Fences applied. `meson compile -C build` succeeded.
- ✔️ `argus-agent --agents` prints the unknown-option error and exits `1`.
