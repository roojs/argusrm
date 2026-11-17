# Windows task quotes the whole command line

**Status:** closed 2026-11-17 — `GLib.Shell.parse_argv` is in the tree (`0.1.22`). The launch is `start_in_session`, not `cmd.exe /c`. The installed-agent check is the NSIS setup test in [2026-11-17-windows-command-session-job.md](../2026-11-17-windows-command-session-job.md).

**Pointer:** `docs/bug-fix-process.md`, `agent/Win32/Command.vala`, [2026-11-16-FIXED-task-stays-running-without-child.md](2026-11-16-FIXED-task-stays-running-without-child.md)

---

## Problem

- 🔷 Uninstalling Adobe Illustrator on `DESKTOP-GITPJFF` ran and the Tasks pane showed success. The output said the uninstaller path was not recognized, then `Command succeeded (exit 0)`.
- 🔷 **Expected:** the uninstall program starts, and the exit code is the process exit code.
- 🔷 **Actual:** `cmd` looked for a program whose name included backslash-quotes. The pane still said exit 0.

---

## Evidence

- ✔️ The stored command was `"C:\Program Files (x86)\Common Files\Adobe\Adobe Desktop Common\HDBox\Uninstaller.exe" --uninstall=1 ...`. `Test-Path` on that exe was true.
- ✔️ The error line was `'\"C:\Program Files (x86)\Common Files\Adobe\Adobe Desktop Common\HDBox\Uninstaller.exe\"' is not recognized`.
- ✔️ `/tmp/argus-cmd-quote.c` on `snappr-win` used `g_spawn_sync`. One argv element holding the quoted path failed with that same message and status 1. Separate arguments ran and returned status 0. `exit 7` returned status 7.
- ✔️ `g_shell_parse_argv` on the Illustrator uninstall string returns the exe path and each argument, with the backslashes kept. That is what `g_spawn_command_line_sync` does before `g_spawn_sync`. The same pair, run on `snappr-win` against `"C:\msys64\tmp\argus-quote\Program Files (x86)\where.exe" where`, printed `status 0` and `C:\Windows\System32\where.exe`.
- ✔️ `agent/Win32/Command.vala` passed `{ "cmd.exe", "/c", command }` to `spawn_async_with_pipes`, and sent `Command.ended` with `0` after the pipes closed.

---

## Root cause

- ✔️ The registry string is one Windows command line. Putting that whole string, quotes included, into one `argv` element makes GLib escape the quotes for `CreateProcess`. `cmd` then searches for the escaped name. The exit code was never read from the process.

---

## Proposed fix

- 🔷 Parse with `GLib.Shell.parse_argv` and pass that vector to `spawn_async_with_pipes`. Read the process exit code with `GetExitCodeProcess` and send that to `Command.ended`.

#### Remove — `agent/Win32/Command.vala` (`spawn`)

```vala
			string[] argv = { "cmd.exe", "/c", this.command };
```

#### Replace with — `agent/Win32/Command.vala` (`spawn`)

```vala
			string[] argv;
			GLib.Shell.parse_argv(this.command, out argv);
```

#### Remove — `agent/Win32/Command.vala` (`spawn`, the `Command.ended` call)

```vala
					args = OLLMrpc.args("ii", this.identifier, 0)
```

#### Replace with — `agent/Win32/Command.vala` (`spawn`, the `Command.ended` call)

```vala
			uint32 code = 1;
			Win32.WaitForSingleObject((void*) child, Win32.INFINITE);
			Win32.GetExitCodeProcess((void*) child, (void*) (&code));
			GLib.Process.close_pid(child);
			args = OLLMrpc.args("ii", this.identifier, (int) code)
```

## Attempts / changelog

- ✔️ `agent/Win32/Command.vala` parses the command with `GLib.Shell.parse_argv` and reports the process exit code. Changelog `0.1.22`.
- ✔️ The wait on that one process was replaced by the job in [2026-11-17-windows-command-session-job.md](../2026-11-17-windows-command-session-job.md).
