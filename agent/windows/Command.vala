/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Agent
{
	/**
	 * Run one command on Windows.
	 *
	 * The wire name is ''Argus.Command''. {@link run} parses the command
	 * line with {@link GLib.Shell.parse_argv}. The first argument is the
	 * program. The command string is the Windows command line. A signed-in
	 * user starts that program on the desktop ''winsta0\default''. Otherwise
	 * it starts in this service session. The process is placed in a job
	 * before it runs, so the task stays up until every process it starts
	 * has exited. The working directory and the environment are passed
	 * through. Output is read with {@link GLib.IOChannel.win32_poll}. The
	 * command line goes out as ''Command.stdin'' once the child exists.
	 * Stdout goes out as ''Command.stdout''. Stderr goes out as
	 * ''Command.stderr''. While a process in the job is alive and the
	 * pipes are silent, stderr gets that executable's name and its CPU
	 * time every five seconds. An empty working directory or an empty
	 * environment inherits this process. The exit code is the exit code
	 * of the last process that left the job.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Agent.Command();
	 * order.identifier = 1;
	 * order.command = "hostname";
	 * order.run(connection);
	 * }}}
	 */
	public class Command : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * Register the wire name ''Argus.Command''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Command", typeof(Command));
		}

		/**
		 * Run identifier from the server.
		 */
		public int identifier { get; set; default = 0; }

		/**
		 * Command line. {@link run} parses it with {@link GLib.Shell.parse_argv}.
		 */
		public string command { get; set; default = ""; }

		/**
		 * Environment, each entry ''NAME=value''.
		 *
		 * Empty inherits this process.
		 */
		public string[] environment { get; set; default = {}; }

		/**
		 * Working directory. Empty inherits this process.
		 */
		public string cwd { get; set; default = ""; }

		/**
		 * One call at a time on the shared app socket.
		 */
		internal static GLib.Mutex send_lock;

		/**
		 * Commands still running, keyed by {@link identifier}.
		 *
		 * {@link send} writes the follow-up text to that command's stdin.
		 */
		internal static Gee.HashMap<int, Command> running;

		/**
		 * Stdin of the child. Left open so a later write can reach the
		 * command.
		 */
		private int stdin_fd = -1;

		/**
		 * Job that holds this command and every process it starts.
		 */
		private void* job;

		/**
		 * Completion port for {@link job}.
		 *
		 * Messages name a new process, an exit, or an empty job.
		 */
		private void* job_port;

		/**
		 * One process handle held for this command's job.
		 */
		private class JobProcess : GLib.Object {
			/**
			 * Process handle. Closed when that process leaves the job.
			 */
			public void* handle;

			/**
			 * @param handle process handle to keep
			 */
			public JobProcess(void* handle) {
				this.handle = handle;
			}
		}

		/**
		 * Processes still in {@link job}, keyed by process id.
		 */
		private Gee.HashMap<uint32, JobProcess> job_processes;

		/**
		 * One live process in {@link job}, for the CPU line.
		 */
		private void* live;

		/**
		 * Set when the job reports no active processes.
		 */
		private bool job_done;

		/**
		 * Exit code of the last process that left {@link job}.
		 */
		private uint32 job_code = 1;

		/**
		 * Spawn this command and send its output.
		 *
		 * Stdout bytes are ''Command.stdout''. Stderr bytes are
		 * ''Command.stderr''. Each call is that chunk.
		 *
		 * @param connection server connection already open
		 */
		public void run(OLLMrpc.Transport.TlsClient connection)
		{
			new GLib.Thread<int>("command", () => {
				this.spawn(connection);
				return 0;
			});
		}

		/**
		 * Spawn this command and poll its stdout and stderr.
		 *
		 * Stdin stays open. Stdout bytes are ''Command.stdout''. Stderr bytes
		 * are ''Command.stderr''. The task ends when the job is empty.
		 *
		 * @param connection server connection already open
		 */
		private void spawn(OLLMrpc.Transport.TlsClient connection)
		{
			string[] argv;
			GLib.Pid child;
			int stdin_fd;
			int stdout_fd;
			int stderr_fd;
			try {
				GLib.Shell.parse_argv(this.command, out argv);
				this.start_in_session(argv, out child, out stdin_fd, out stdout_fd, out stderr_fd);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				Command.send_lock.lock();
				try {
					connection.call(new OLLMrpc.Request() {
						method = "Command.stderr",
						args = OLLMrpc.args("is", this.identifier, e.message + "\n")
					});
					connection.call(new OLLMrpc.Request() {
						method = "Command.ended",
						args = OLLMrpc.args("ii", this.identifier, 127)
					});
				} catch (GLib.Error send_error) {
					GLib.warning("%s", send_error.message);
				}
				Command.send_lock.unlock();
				return;
			}
			this.stdin_fd = stdin_fd;
			Command.send_lock.lock();
			if (Command.running == null) {
				Command.running = new Gee.HashMap<int, Command>();
			}
			Command.running.set(this.identifier, this);
			Command.send_lock.unlock();
			var shown = this.command;
			if (shown != "" && !shown.has_suffix("\n")) {
				shown += "\n";
			}
			if (shown != "") {
				Command.send_lock.lock();
				try {
					var response = connection.call(new OLLMrpc.Request() {
						method = "Command.stdin",
						args = OLLMrpc.args("is", this.identifier, shown)
					});
					if (response.error != null) {
						GLib.warning("command %d", response.error.code);
					}
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				Command.send_lock.unlock();
			}
			var stdout_channel = new GLib.IOChannel.win32_new_fd(stdout_fd);
			var stderr_channel = new GLib.IOChannel.win32_new_fd(stderr_fd);
			stdout_channel.set_close_on_unref(true);
			stderr_channel.set_close_on_unref(true);
			stdout_channel.set_buffered(false);
			stderr_channel.set_buffered(false);
			try {
				stdout_channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				stderr_channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				stdout_channel.set_flags(GLib.IOFlags.NONBLOCK);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			try {
				stderr_channel.set_flags(GLib.IOFlags.NONBLOCK);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			var stdout_open = true;
			var stderr_open = true;
			var told_running = GLib.get_monotonic_time();
			while (stdout_open || stderr_open) {
				var out_fd = GLib.PollFD();
				var err_fd = GLib.PollFD();
				out_fd.fd = -1;
				err_fd.fd = -1;
				if (stdout_open) {
					stdout_channel.win32_make_pollfd(
						GLib.IOCondition.IN | GLib.IOCondition.HUP, ref out_fd);
				}
				if (stderr_open) {
					stderr_channel.win32_make_pollfd(
						GLib.IOCondition.IN | GLib.IOCondition.HUP, ref err_fd);
				}
				GLib.PollFD[] polls = { out_fd, err_fd };
				var ready = GLib.IOChannel.win32_poll(polls, 1000);
				if (ready < 0) {
					GLib.warning("poll failed");
					break;
				}
				string[] methods = {};
				string[] texts = {};
				var out_ready = stdout_open &&
					(polls[0].revents & (GLib.IOCondition.IN | GLib.IOCondition.HUP)) != 0;
				if (out_ready) {
					char[] buf = new char[4096];
					size_t got = 0;
					GLib.IOStatus status = GLib.IOStatus.NORMAL;
					try {
						status = stdout_channel.read_chars(buf, out got);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						stdout_open = false;
						status = GLib.IOStatus.ERROR;
					}
					if (status == GLib.IOStatus.EOF ||
						(got == 0 && (polls[0].revents & GLib.IOCondition.HUP) != 0)) {
						stdout_open = false;
					}
					if (got > 0) {
						var raw = new uint8[got + 1];
						GLib.Memory.copy(raw, buf, got);
						methods += "Command.stdout";
						texts += (string) raw;
					}
				}
				var err_ready = stderr_open &&
					(polls[1].revents & (GLib.IOCondition.IN | GLib.IOCondition.HUP)) != 0;
				if (err_ready) {
					char[] buf = new char[4096];
					size_t got = 0;
					GLib.IOStatus status = GLib.IOStatus.NORMAL;
					try {
						status = stderr_channel.read_chars(buf, out got);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						stderr_open = false;
						status = GLib.IOStatus.ERROR;
					}
					if (status == GLib.IOStatus.EOF ||
						(got == 0 && (polls[1].revents & GLib.IOCondition.HUP) != 0)) {
						stderr_open = false;
					}
					if (got > 0) {
						var raw = new uint8[got + 1];
						GLib.Memory.copy(raw, buf, got);
						methods += "Command.stderr";
						texts += (string) raw;
					}
				}
				var now_us = GLib.get_monotonic_time();
				this.drain_job(0);
				if (methods.length > 0) {
					told_running = now_us;
				}
				if (!this.job_done && this.live != null && methods.length == 0 &&
					now_us - told_running >= 5 * 1000000) {
					methods += "Command.stderr";
					texts += this.activity((GLib.Pid) this.live);
					told_running = now_us;
				}
				for (var i = 0; i < methods.length; i++) {
					Command.send_lock.lock();
					try {
						var response = connection.call(new OLLMrpc.Request() {
							method = methods[i],
							args = OLLMrpc.args("is", this.identifier, texts[i])
						});
						if (response.error != null) {
							GLib.warning("command %d", response.error.code);
						}
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
					Command.send_lock.unlock();
				}
				if (this.job_done) {
					break;
				}
			}
			while (!this.job_done) {
				var now_us = GLib.get_monotonic_time();
				this.drain_job(1000);
				if (this.job_done) {
					break;
				}
				if (this.live == null) {
					continue;
				}
				if (now_us - told_running < 5 * 1000000) {
					continue;
				}
				told_running = now_us;
				Command.send_lock.lock();
				try {
					connection.call(new OLLMrpc.Request() {
						method = "Command.stderr",
						args = OLLMrpc.args("is", this.identifier,
							this.activity((GLib.Pid) this.live))
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				Command.send_lock.unlock();
			}
			var code = this.job_code;
			this.close_job();
			Command.send_lock.lock();
			try {
				connection.call(new OLLMrpc.Request() {
					method = "Command.ended",
					args = OLLMrpc.args("ii", this.identifier, (int) code)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			Command.send_lock.unlock();
		}

		/**
		 * Start this command on the signed-in desktop, inside a job.
		 *
		 * The active session token and desktop are the same pair the
		 * service uses for the tray. No signed-in session starts the
		 * process in this service session. The process is created
		 * suspended, assigned to a new job, then resumed, so every
		 * process it starts stays in the job. Standard handles are the
		 * pipes the caller polls.
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
			if (argv.length < 1 || argv[0] == "") {
				throw new GLib.IOError.FAILED("command is empty");
			}
			void* read_in = null;
			void* write_in = null;
			void* read_out = null;
			void* write_out = null;
			void* read_err = null;
			void* write_err = null;
			this.open_pipe(out read_in, out write_in);
			try {
				this.open_pipe(out read_out, out write_out);
			} catch (GLib.Error e) {
				this.abandon(null, read_in, write_in, null, null, null, null, null, null);
				throw e;
			}
			try {
				this.open_pipe(out read_err, out write_err);
			} catch (GLib.Error e) {
				this.abandon(null, read_in, write_in, read_out, write_out, null, null, null, null);
				throw e;
			}
			if (!Win32.SetHandleInformation(write_in, Win32.HANDLE_FLAG_INHERIT, 0) ||
				!Win32.SetHandleInformation(read_out, Win32.HANDLE_FLAG_INHERIT, 0) ||
				!Win32.SetHandleInformation(read_err, Win32.HANDLE_FLAG_INHERIT, 0)) {
				var code = Win32.GetLastError();
				this.abandon(null, read_in, write_in, read_out, write_out, read_err, write_err, null, null);
				throw new GLib.IOError.FAILED("inherit %u".printf(code));
			}
			var job = Win32.CreateJobObjectW(null, null);
			if (job == null) {
				var code = Win32.GetLastError();
				this.abandon(null, read_in, write_in, read_out, write_out, read_err, write_err, null, null);
				throw new GLib.IOError.FAILED("job %u".printf(code));
			}
			var port = Win32.CreateIoCompletionPort(Win32.invalid_handle(), null, 0, 1);
			if (port == null) {
				var code = Win32.GetLastError();
				this.abandon(null, read_in, write_in, read_out, write_out, read_err, write_err, job, null);
				throw new GLib.IOError.FAILED("port %u".printf(code));
			}
			var assoc = Win32.JobCompletionPort() {
				key = job,
				port = port
			};
			if (!Win32.SetInformationJobObject(job,
				Win32.JobObjectAssociateCompletionPortInformation,
				&assoc, (uint32) sizeof(Win32.JobCompletionPort))) {
				var code = Win32.GetLastError();
				this.abandon(null, read_in, write_in, read_out, write_out, read_err, write_err, job, port);
				throw new GLib.IOError.FAILED("job port %u".printf(code));
			}
			void* token = null;
			var session = Win32.argus_active_session();
			if (session != (uint32) 0xFFFFFFFF) {
				void* user;
				if (Win32.WTSQueryUserToken(session, out user)) {
					void* dup;
					if (Win32.DuplicateTokenEx(user, Win32.MAXIMUM_ALLOWED, null,
						Win32.SecurityIdentification, Win32.TokenPrimary, out dup)) {
						token = dup;
					}
					Win32.CloseHandle(user);
				}
			}
			var si = Win32.StartupInfo() {
				cb = (uint32) sizeof(Win32.StartupInfo),
				flags = Win32.STARTF_USESTDHANDLES,
				stdin_handle = read_in,
				stdout_handle = write_out,
				stderr_handle = write_err
			};
			if (token != null) {
				si.desktop = Win32.g_utf8_to_utf16("winsta0\\default");
			}
			var info = Win32.ProcessInfo();
			var app = this.program_name(argv[0]);
			var line = new GLib.Array<uint16>();
			this.append_wide(line, this.command.to_utf16());
			uint16 zero = 0;
			line.append_val(zero);
			uint16[]? env = null;
			GLib.Array<uint16>? block = null;
			uint32 flags = Win32.CREATE_SUSPENDED;
			if (this.environment.length > 0) {
				block = this.environment_block();
				env = block.data;
				flags |= Win32.CREATE_UNICODE_ENVIRONMENT;
			}
			string16? cwd = null;
			if (this.cwd != "") {
				cwd = this.cwd.to_utf16();
			}
			var started = false;
			if (token != null) {
				started = Win32.CreateProcessAsUserW(token, app, line.data,
					null, null, true, flags, env, cwd, &si, out info);
			} else {
				started = Win32.CreateProcessW(app, line.data,
					null, null, true, flags, env, cwd, &si, out info);
			}
			if (token != null) {
				Win32.CloseHandle(token);
				token = null;
			}
			if (!started) {
				var code = Win32.GetLastError();
				this.abandon(null, read_in, write_in, read_out, write_out, read_err, write_err, job, port);
				throw new GLib.IOError.FAILED("start %u".printf(code));
			}
			Win32.CloseHandle(read_in);
			Win32.CloseHandle(write_out);
			Win32.CloseHandle(write_err);
			read_in = null;
			write_out = null;
			write_err = null;
			if (!Win32.AssignProcessToJobObject(job, info.process)) {
				var code = Win32.GetLastError();
				this.abandon(info.process, info.thread, write_in, read_out, read_err, job, port, null, null);
				throw new GLib.IOError.FAILED("assign %u".printf(code));
			}
			if (Win32.ResumeThread(info.thread) == Win32.INFINITE) {
				var code = Win32.GetLastError();
				this.abandon(info.process, info.thread, write_in, read_out, read_err, job, port, null, null);
				throw new GLib.IOError.FAILED("resume %u".printf(code));
			}
			Win32.CloseHandle(info.thread);
			stdin_fd = Win32.open_osfhandle(write_in, Win32.O_WRONLY | Win32.O_BINARY);
			if (stdin_fd < 0) {
				var code = Win32.GetLastError();
				this.abandon(info.process, write_in, read_out, read_err, job, port, null, null, null);
				throw new GLib.IOError.FAILED("stdin %u".printf(code));
			}
			stdout_fd = Win32.open_osfhandle(read_out, Win32.O_RDONLY | Win32.O_BINARY);
			if (stdout_fd < 0) {
				var code = Win32.GetLastError();
				Win32.close_fd(stdin_fd);
				stdin_fd = -1;
				this.abandon(info.process, read_out, read_err, job, port, null, null, null, null);
				throw new GLib.IOError.FAILED("stdout %u".printf(code));
			}
			stderr_fd = Win32.open_osfhandle(read_err, Win32.O_RDONLY | Win32.O_BINARY);
			if (stderr_fd < 0) {
				var code = Win32.GetLastError();
				Win32.close_fd(stdin_fd);
				Win32.close_fd(stdout_fd);
				stdin_fd = -1;
				stdout_fd = -1;
				this.abandon(info.process, read_err, job, port, null, null, null, null, null);
				throw new GLib.IOError.FAILED("stderr %u".printf(code));
			}
			var processes = new Gee.HashMap<uint32, JobProcess>();
			processes.set(info.pid, new JobProcess(info.process));
			this.job = job;
			this.job_port = port;
			this.job_processes = processes;
			this.live = info.process;
			this.job_done = false;
			this.job_code = 1;
			child = (GLib.Pid) info.process;
			GLib.debug("command %d pid %u", this.identifier, info.pid);
		}

		/**
		 * Program path for ''lpApplicationName''.
		 *
		 * A name with no directory is resolved through SearchPathW, which
		 * is the search {@link GLib.SpawnFlags.SEARCH_PATH} used to do.
		 * The command line itself is left unchanged.
		 *
		 * @param program first argument from ''GLib.Shell.parse_argv''
		 * @return UTF-16 path or the original name
		 */
		private string16 program_name(string program) throws GLib.Error
		{
			if (program.contains("\\") || program.contains("/")) {
				return program.to_utf16();
			}
			var found = Win32.g_utf8_to_utf16(string.nfill(259, ' '));
			var wrote = Win32.SearchPathW(null, program.to_utf16(),
				Win32.g_utf8_to_utf16(".exe"), 260, found, null);
			if (wrote == 0 || wrote >= 260) {
				return program.to_utf16();
			}
			return found;
		}

		/**
		 * Append the characters of a UTF-16 string, without its terminator.
		 *
		 * @param list buffer being built
		 * @param text wide string to copy
		 */
		private void append_wide(GLib.Array<uint16> list, string16 text)
		{
			var count = Win32.wide_length(text);
			for (uint64 i = 0; i < count; i++) {
				var unit = Win32.wide_at(text, i);
				list.append_val(unit);
			}
		}

		/**
		 * Environment block for CreateProcess.
		 *
		 * Entries are separated by a NUL, and the block ends with an
		 * extra NUL. The caller keeps the array alive until CreateProcess
		 * returns. The launch flag is CREATE_UNICODE_ENVIRONMENT.
		 *
		 * @return wide characters of the block
		 */
		private GLib.Array<uint16> environment_block() throws GLib.Error
		{
			var list = new GLib.Array<uint16>();
			foreach (var item in this.environment) {
				this.append_wide(list, item.to_utf16());
				uint16 zero = 0;
				list.append_val(zero);
			}
			uint16 end = 0;
			list.append_val(end);
			return list;
		}

		/**
		 * Create one inheritable pipe.
		 *
		 * The parent clears inherit on the end it keeps.
		 *
		 * @param read read end
		 * @param write write end
		 */
		private void open_pipe(out void* read, out void* write) throws GLib.Error
		{
			var sa = Win32.SecurityAttributes() {
				length = (uint32) sizeof(Win32.SecurityAttributes),
				inherit = true
			};
			if (!Win32.CreatePipe(out read, out write, &sa, 0)) {
				var code = Win32.GetLastError();
				read = null;
				write = null;
				throw new GLib.IOError.FAILED("pipe %u".printf(code));
			}
		}

		/**
		 * Close handles left over from a launch that did not finish.
		 *
		 * A non-null process is terminated first. Null handles are skipped.
		 */
		private void abandon(void* process, void* a, void* b, void* c, void* d,
			void* e, void* f, void* g, void* h)
		{
			if (process != null) {
				Win32.TerminateProcess(process, 1);
				Win32.CloseHandle(process);
			}
			if (a != null) {
				Win32.CloseHandle(a);
			}
			if (b != null) {
				Win32.CloseHandle(b);
			}
			if (c != null) {
				Win32.CloseHandle(c);
			}
			if (d != null) {
				Win32.CloseHandle(d);
			}
			if (e != null) {
				Win32.CloseHandle(e);
			}
			if (f != null) {
				Win32.CloseHandle(f);
			}
			if (g != null) {
				Win32.CloseHandle(g);
			}
			if (h != null) {
				Win32.CloseHandle(h);
			}
		}

		/**
		 * Read job messages until the port is empty or the job is empty.
		 *
		 * A new process is opened and kept. An exit stores that process's
		 * exit code and closes its handle. The stored code is the one
		 * ''Command.ended'' sends.
		 *
		 * @param wait_ms how long to wait for the first message
		 * @return true when the job has no active processes
		 */
		private bool drain_job(uint32 wait_ms)
		{
			if (this.job_done || this.job_port == null || this.job_processes == null) {
				return this.job_done;
			}
			var wait = wait_ms;
			while (true) {
				uint32 bytes = 0;
				uint64 key = 0;
				void* overlapped = null;
				if (!Win32.GetQueuedCompletionStatus(this.job_port, out bytes, out key,
					out overlapped, wait)) {
					if (Win32.GetLastError() == Win32.WAIT_TIMEOUT) {
						return false;
					}
					GLib.warning("job %u", Win32.GetLastError());
					this.job_done = true;
					return true;
				}
				wait = 0;
				var pid = (uint32) (size_t) overlapped;
				if (bytes == Win32.JOB_OBJECT_MSG_NEW_PROCESS &&
					!this.job_processes.has_key(pid)) {
					var handle = Win32.OpenProcess(Win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
					if (handle != null) {
						this.job_processes.set(pid, new JobProcess(handle));
						this.live = handle;
					}
				}
				if (bytes == Win32.JOB_OBJECT_MSG_EXIT_PROCESS ||
					bytes == Win32.JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS) {
					if (this.job_processes.has_key(pid)) {
						var handle = this.job_processes.get(pid).handle;
						uint32 code = 0;
						if (Win32.GetExitCodeProcess(handle, (void*) (&code))) {
							this.job_code = code;
						}
						if (this.live == handle) {
							this.live = null;
						}
						Win32.CloseHandle(handle);
						this.job_processes.unset(pid);
					}
					if (this.live == null) {
						foreach (var tracked in this.job_processes.values) {
							this.live = tracked.handle;
							break;
						}
					}
				}
				if (bytes == Win32.JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO) {
					this.job_done = true;
					this.live = null;
					return true;
				}
			}
		}

		/**
		 * Close the job, its port, and any process handles still held.
		 */
		private void close_job()
		{
			if (this.job_processes != null) {
				foreach (var tracked in this.job_processes.values) {
					Win32.CloseHandle(tracked.handle);
				}
				this.job_processes = null;
			}
			this.live = null;
			if (this.job != null) {
				Win32.CloseHandle(this.job);
				this.job = null;
			}
			if (this.job_port != null) {
				Win32.CloseHandle(this.job_port);
				this.job_port = null;
			}
		}

		/**
		 * Executable name and CPU time for a live process.
		 *
		 * CPU time is kernel plus user time. A number that stays at
		 * 0.0s is a process that has not run.
		 *
		 * @param child process handle from the job
		 * @return one line for ''Command.stderr''
		 */
		private string activity(GLib.Pid child)
		{
			var name = "process";
			var image = Win32.g_utf8_to_utf16(string.nfill(259, ' '));
			uint32 size = 260;
			if (Win32.QueryFullProcessImageNameW((void*) child, 0, image, ref size)) {
				try {
					var path = image.to_utf8();
					var slash = path.last_index_of("\\");
					if (slash >= 0 && slash + 1 < path.length) {
						name = path.substring(slash + 1);
					}
				} catch (GLib.ConvertError e) {
					GLib.warning("%s", e.message);
				}
			}
			var cpu = "0.0";
			Win32.FileTime created;
			Win32.FileTime finished;
			Win32.FileTime kernel;
			Win32.FileTime user;
			if (Win32.GetProcessTimes((void*) child, out created, out finished,
				out kernel, out user)) {
				uint64 ticks = ((uint64) kernel.high << 32) | kernel.low;
				ticks += ((uint64) user.high << 32) | user.low;
				cpu = "%.1f".printf(ticks / 10000000.0);
			}
			return name + " " + cpu + "s cpu\n";
		}

		/**
		 * Write text to this command's stdin.
		 *
		 * A missing handle is logged. The text is the follow-up from an
		 * ''agent.send'' notification. The handle stays open.
		 *
		 * @param text bytes for this command's stdin
		 */
		public void send(string text)
		{
			if (this.stdin_fd < 0) {
				GLib.warning("command %d is not running", this.identifier);
				return;
			}
			var channel = new GLib.IOChannel.win32_new_fd(this.stdin_fd);
			channel.set_close_on_unref(false);
			channel.set_buffered(false);
			try {
				channel.set_encoding(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				size_t wrote;
				channel.write_chars((char[]) text.data, out wrote);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				channel.flush();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
		}
	}
}
