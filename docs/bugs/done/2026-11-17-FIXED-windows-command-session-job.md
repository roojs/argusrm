# Windows command stops at the first process, in session 0

**Status:** ✅ closed 2026-11-17 — `0.1.26` starts the command on the signed-in desktop and keeps the task running while `Set-up.exe` is alive.

**Pointer:** `docs/bug-fix-process.md`, `agent/Win32/Command.vala`, `agent/Win32/Service.vala`

---

## Problem

- 🔷 A Windows task ends when the process it spawned exits. The exit code is that process. The Tasks pane shows Failed or Completed from that code.
- 🔷 **Expected:** the task stays Running until every process that command started has exited. The exit code is the last of those processes. A program that has a window is started on the signed-in desktop.
- 🔷 **Actual:** the agent service creates the process in session 0 and waits on that one handle. A launcher that starts another process and exits ends the task. The window, when there is one, is on the service desktop.

This is any command the agent runs. The Illustrator uninstall is the run that showed it.

---

## Evidence

- ✔️ Command 5 on agent 11, 2026-11-17 14:34:53. The stored line was the Illustrator `Uninstaller.exe` command. `Command.stdin` and `Command.ended` are 35 ms apart in `/var/log/argusrm/server.log`. There is no `11-5.stderr`. The pane showed `Command failed (exit 1)`.
- ✔️ `C:\Windows\Temp\CreativeCloud\ACC\AdobeDownload\HDInstaller.log` at 14:34:54. Pid 12060 parsed that command, logged `Copied and launched self to run from temp location`, and logged `Workflow end`. Pid 20156 then started as `C:\Windows\Temp\{BEA4DB50-8454-47E0-B0BD-B3555CB26C11}\Set-up.exe` with `--uninstall=1`. Its next error is `Failed to acquire Bootstrapper Lock`.
- ✔️ `Set-up.exe` pid 20872 has been in session 0 since 2026-10-29 12:17. The same log shows it loaded a UI that day. Pid 20156 and pid 7376, started 14:34:54, are also session 0. `argus-agent.exe` is session 0.
- ✔️ `agent/Win32/Command.vala` `spawn` calls `GLib.Process.spawn_async_with_pipes` and later `WaitForSingleObject` on that one `GLib.Pid`. The poll loop breaks when that handle is signaled.
- ✔️ `agent/Win32/Service.vala` already starts `argus-tray.exe` with `CreateProcessAsUserW` on the active session token and desktop `winsta0\default`.
- ✔️ `/tmp/argus-exec-probe.c` on `snappr-win` spawned a child through `g_shell_parse_argv` and `g_spawn_async_with_pipes`. While that child was alive, `QueryFullProcessImageNameW` and `GetProcessTimes` printed `argus-exec-probe.exe` and a CPU time that climbed `0.5s` through `2.5s`. After it exited, the image query returned Windows error 31. Exit status was 0.
- ℹ️ `StartupInfo` in `agent/Win32/win32.vapi` has `cb` and `lpDesktop` only. `CreateProcessAsUserW` is already bound. A call that passes standard handles needs the full `STARTUPINFOW` layout.
- ✔️ `/tmp/argus-job-probe.c` on `snappr-win`. A parent exited 1 after starting a child that exited 7. The completion port reported `NEW_PROCESS`, `NEW_PROCESS`, `EXIT_PROCESS` 1, `EXIT_PROCESS` 7, then `ACTIVE_PROCESS_ZERO`. The stored status was 7. The probe exited 0.

---

## Root cause

- ✔️ `spawn_async_with_pipes` from the service creates the process in session 0. The task waits for that process alone. A command that replaces itself, or starts a worker and exits, finishes the task on the first exit. A window created there is not on the signed-in desktop, so the process can sit there and keep holding whatever lock it took.

---

## Ruled out

- 🚫 Do not special-case one vendor, one lock, or one executable name.
- 🚫 Do not stop the process that already holds a lock. That is a leftover of this launch. It is not the fix.
- 🚫 Do not report the first process exit and also keep the task Running. One result, when the tree is gone.

---

## Proposed fix

- 🔷 When a user is signed in, start the command on that session's desktop. When nobody is signed in, start it in the service session as today.
- 🔷 Put that process in a job object before it runs, with breakaway left off. The task ends when the job's active process count is zero. `Command.ended` gets the exit code of the last process that left the job.
- 💩 `GLib.Process.spawn_async_with_pipes` cannot take a user token, cannot create the process suspended, and cannot assign a job before the process runs. The launch becomes `CreateProcessAsUserW` with the command string as the Windows command line. `GLib.Shell.parse_argv` still supplies `lpApplicationName` from the first argument.
- 💩 No interactive token: `CreateProcessW` in the service session, still inside the same job.

#### Replace with — `agent/Win32/win32.vapi` (`StartupInfo`)

```vala
	[CCode (cname = "STARTUPINFOW", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct StartupInfo {
		[CCode (cname = "cb")]
		public uint32 cb;
		[CCode (cname = "lpReserved")]
		public string16 reserved;
		[CCode (cname = "lpDesktop")]
		public string16 desktop;
		[CCode (cname = "lpTitle")]
		public string16 title;
		[CCode (cname = "dwX")]
		public uint32 x;
		[CCode (cname = "dwY")]
		public uint32 y;
		[CCode (cname = "dwXSize")]
		public uint32 width;
		[CCode (cname = "dwYSize")]
		public uint32 height;
		[CCode (cname = "dwXCountChars")]
		public uint32 x_chars;
		[CCode (cname = "dwYCountChars")]
		public uint32 y_chars;
		[CCode (cname = "dwFillAttribute")]
		public uint32 fill;
		[CCode (cname = "dwFlags")]
		public uint32 flags;
		[CCode (cname = "wShowWindow")]
		public uint16 show;
		[CCode (cname = "cbReserved2")]
		public uint16 reserved2;
		[CCode (cname = "lpReserved2")]
		public void* reserved2_bytes;
		[CCode (cname = "hStdInput")]
		public void* stdin_handle;
		[CCode (cname = "hStdOutput")]
		public void* stdout_handle;
		[CCode (cname = "hStdError")]
		public void* stderr_handle;
	}
```

#### Add — `agent/Win32/win32.vapi`

```vala
	[CCode (cname = "CREATE_SUSPENDED", cheader_filename = "win32.h")]
	public const uint32 CREATE_SUSPENDED;
	[CCode (cname = "STARTF_USESTDHANDLES", cheader_filename = "win32.h")]
	public const uint32 STARTF_USESTDHANDLES;
	[CCode (cname = "JobObjectAssociateCompletionPortInformation", cheader_filename = "win32.h")]
	public const int JobObjectAssociateCompletionPortInformation;
	[CCode (cname = "JOB_OBJECT_MSG_NEW_PROCESS", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_NEW_PROCESS;
	[CCode (cname = "JOB_OBJECT_MSG_EXIT_PROCESS", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_EXIT_PROCESS;
	[CCode (cname = "JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO;
	[CCode (cname = "CreateJobObjectW", cheader_filename = "win32.h")]
	public void* CreateJobObjectW (void* security, string16 name);
	[CCode (cname = "SetInformationJobObject", cheader_filename = "win32.h")]
	public bool SetInformationJobObject (void* job, int klass, void* info, uint32 length);
	[CCode (cname = "AssignProcessToJobObject", cheader_filename = "win32.h")]
	public bool AssignProcessToJobObject (void* job, void* process);
	[CCode (cname = "CreateIoCompletionPort", cheader_filename = "win32.h")]
	public void* CreateIoCompletionPort (void* file, void* existing, uint64 key, uint32 threads);
	[CCode (cname = "GetQueuedCompletionStatus", cheader_filename = "win32.h")]
	public bool GetQueuedCompletionStatus (void* port, out uint32 bytes, out uint64 key, out void* overlapped, uint32 ms);
	[CCode (cname = "ResumeThread", cheader_filename = "win32.h")]
	public uint32 ResumeThread (void* thread);
	[CCode (cname = "CreateProcessW", cheader_filename = "win32.h")]
	public bool CreateProcessW (string16 app, void* command, void* process_attr, void* thread_attr, bool inherit, uint32 flags, void* env, string16 cwd, StartupInfo* startup, out ProcessInfo info);
```

#### Remove — `agent/Win32/Command.vala` (`spawn`)

```vala
				GLib.Process.spawn_async_with_pipes(
					this.cwd != "" ? this.cwd : null,
					argv,
					this.environment.length > 0 ? this.environment : null,
					GLib.SpawnFlags.SEARCH_PATH,
					null,
					out child,
					out stdin_fd,
					out stdout_fd,
					out stderr_fd);
```

#### Replace with — `agent/Win32/Command.vala` (`spawn`)

```vala
				this.start_in_session(argv, out child, out stdin_fd, out stdout_fd, out stderr_fd);
```

#### Add — `agent/Win32/Command.vala` (`start_in_session`)

```vala
		/**
		 * Start this command on the signed-in desktop, inside a job.
		 *
		 * The active session token and desktop are the same pair the
		 * service uses for the tray. No signed-in session starts the
		 * process in this service session. The process is created
		 * suspended, assigned to a new job, then resumed, so every
		 * process it starts stays in the job. Standard handles are
		 * the pipes the caller polls.
		 *
		 * @param argv program and arguments from ''GLib.Shell.parse_argv''
		 * @param child process handle of the first process
		 * @param stdin_fd write end for the child's stdin
		 * @param stdout_fd read end for the child's stdout
		 * @param stderr_fd read end for the child's stderr
		 */
		private void start_in_session(string[] argv, out GLib.Pid child, out int stdin_fd, out int stdout_fd, out int stderr_fd) throws GLib.Error
		{
			child = (GLib.Pid) 0;
			stdin_fd = -1;
			stdout_fd = -1;
			stderr_fd = -1;
			// Pipes, job, and completion port are created here.
			// lpApplicationName is argv[0]. A bare name is resolved with SearchPathW.
			// lpCommandLine is this.command.
			// CREATE_SUSPENDED, AssignProcessToJobObject, then ResumeThread.
			// A signed-in session uses CreateProcessAsUserW and winsta0\default.
			// Otherwise CreateProcessW.
			// Throws GLib.Error, which spawn already turns into Command.ended 127.
		}
```

The method in `agent/Win32/Command.vala` does those steps. `spawn` reads the completion port until `ACTIVE_PROCESS_ZERO`, and `Command.ended` sends the last exit.

#### Remove — `agent/Win32/Command.vala` (`spawn`, after the pipes close)

```vala
			uint32 code = 1;
			Win32.WaitForSingleObject((void*) child, Win32.INFINITE);
			Win32.GetExitCodeProcess((void*) child, (void*) (&code));
			GLib.Process.close_pid(child);
```

#### Replace with — `agent/Win32/Command.vala` (`spawn`, after the pipes close)

```vala
			uint32 code = 1;
			// Read the job completion port until ACTIVE_PROCESS_ZERO.
			// NEW_PROCESS opens that process. EXIT_PROCESS stores its exit code.
			// code is the exit code of the last process that left the job.
			Win32.CloseHandle(this.job);
```

The poll loop's `WaitForSingleObject` on the first process stops breaking out while the job still has processes. Pipe EOF still ends the read. The job wait is what decides `Command.ended`.

---

## Attempts / changelog

- ✔️ Read command 5's logs and `HDInstaller.log`. Listed the session 0 `Set-up.exe` processes on `DESKTOP-GITPJFF`.
- ✔️ `/tmp/argus-exec-probe.c` showed that a spawned process reports a rising CPU time until it exits.
- ✔️ `/tmp/argus-job-probe.c` reported exit 7 for a child whose parent had already exited 1.
- ✔️ `start_in_session` is in `agent/Win32/Command.vala`. `ninja -C build-windows agent/argus-agent.exe` on `snappr-win` linked `agent/argus-agent.exe`.

## Next

- ✅ `ArgusAgent-0.1.26-Setup.exe` is installed. Command 27 at 18:01 put the Adobe uninstall window on the signed-in desktop. The task reported `Set-up.exe` while it ran.
- ℹ️ The October session-0 `Set-up.exe` pair, and the 14:34 pair, were stopped by hand so the next uninstall could take the bootstrapper lock. That was a leftover on this machine, not a change to the launch.
