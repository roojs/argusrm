# Task stays Running when the child never starts

**Status:** closed 2026-11-17 — a spawn that throws sends exit 127, `Task.agent_boot` ends a target whose child is gone, and a live child reports `running`. In the tree since `0.1.20`–`0.1.23`. The Windows agent that has this is the NSIS setup test in 2026-11-17-FIXED-windows-command-session-job.md.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [7.0-tasks.md](../../plans/7.0-tasks.md)

---

## Problem

- 🔷 Uninstalling Adobe Illustrator on the Windows machine (`DESKTOP-GITPJFF`, agent 11, `192.168.88.244`) queued a task that the Tasks pane showed as Running. The output pane stayed black. Restarting the Windows agent updated Last connected and left the Connected tick blank.
- 🔷 **Expected:** a task is Running only while the agent still has that child. If the child never starts, or the agent process comes back without it, the target ends as failed and the machine can take another task. The Connected tick shows while the app socket is open.
- 🔷 **Actual:** the server set `started` when it wrote `agent.run`. No stdout, stderr, stdin, or exit ever arrived. After the agent restart the child was gone and the row was still Running. `Task.run` treats every `started > 0 AND ended = 0` target as occupying that agent, so agent 11 takes no further task. The Connected tick stayed blank even though the new socket was up.

---

## Evidence

- ✔️ `/var/log/argusrm/server.log` on 2026-11-16:
  - `15:49:15.798` `Command.vala:235: run command 1 on agent 11`
  - `15:49:15.798` `Task.vala:788: task 1 target 11 started 1`
  - `15:49:15.817` `Connection.vala:377: Unexpected early end-of-stream`
  - No `Command.stdout`, `Command.stderr`, `Command.stdin`, or `Command.ended` for that identifier after the dispatch.
- ✔️ `/var/log/argusrm/commands/2026/11/16/` had no `{agent}-{identifier}.stdout`, `.stderr`, or `.stdin` file. `Task.logs` at `15:49:20` therefore returned three empty strings, and the terminal pane stayed black.
- ✔️ On `snappr-win` before the restart, `argus-agent.exe` pid 292 had `CreationDate=20261116123545` (12:35, before the dispatch). `wmic` children of pid 292 returned none. `tasklist` for `msiexec.exe` returned none.
- ✔️ After the service restart, `argus-agent.exe` pid 31568 had `CreationDate=20261116160719`. It still had no child process, and `msiexec.exe` was still absent. The in-memory `Command.running` map does not survive the process, and nothing re-sent command 1 (`Task.run` only selects `started = 0`).
- ✔️ The new socket did connect:
  - `16:07:20.028` `hello argus-agent 1` on `conn=0x593ad6bc8a70`, then six `OSQuery.sync` calls through `16:07:24`. No close of that connection is in the log after the hello.
  - `ss` showed `ESTAB` from `192.168.88.244:64821` to `192.168.88.132:817`.
  - `SslListen` writes `agent.last_connected` on that handshake, which is why Last connected moved. `Agent.connected` is not a column. `Agent.list` sets it from sockets with `connection.running && connection.user.id >= 1`.
- ✔️ `controller/tab/Base.vala` `tick-connected` set `icon_name` once from the value at bind time, then bound only `visible` to `connected`. The machines grid had already bound that row while the service was down (`Agent.list` at `16:07:19`, before the hello), so the icon was null. When `connected` later became true, the image was shown with no icon. `display-last` is a real property binding, so the time updated.
- ✔️ `agent/Win32/Command.vala` `spawn()` on `GLib.Error` logs a warning and returns. It does not send `Command.stderr` or `Command.ended`. `agent/linux/Command.vala` does send both and finishes with exit 127.
- ℹ️ `task_target.timeout` exists and [7.0-tasks.md](../../plans/7.0-tasks.md) says it is unused. A silent `msiexec /qn` can run for a long time with an empty stdout, so “nothing was printed” does not mean the child is gone.
- ℹ️ The agent keeps the pid only in `Command.running` and a `GLib.debug` line. The server never receives it.

---

## Root cause

- ✔️ `server/SQT/Task.vala` `run()` sets `target.started` and `target.identifier` as soon as `Command.dispatch` writes `agent.run`. That is before the agent has a child. A socket that closes in the next few milliseconds, a Windows spawn that throws, or an agent restart all leave `ended = 0`.
- ✔️ `server/Net/SslListen.vala` on a known agent only releases targets with `started = 0`. It never asks the new process whether an already-started identifier is still in `Command.running`.
- ✔️ The Connected tick did not follow `connected` after the first bind. That is separate from the open task row.

---

## Ruled out

- 🚫 Do not close this on a silence timer. `task_target.timeout` is a wall-clock limit for a child that did start. Illustrator’s `/qn` uninstall is a quiet process, and an empty pane is normal for it.
- 🚫 Do not store the pid on the server for this failure. pid 292 never had a child, and pid 31568 is a new process. Reattaching a pid after an agent crash is a later case, where the child outlives the agent.

---

## Proposed fix

- 🔷 **After OSQuery startup sync, close this agent's open tasks.** `Execute.send_startup()` is that point on Linux and Windows. This process has no child yet, so the agent calls `Task.agent_boot` with no arguments. Every target with `started > 0 AND ended = 0` for this agent is ended with exit 127 and the stderr line `agent started and this task was not running`, and `event.task` `ended` is broadcast. Do not dispatch that command again. `Command.ended` cannot do this. It requires the in-memory `Command.agents` entry from the original dispatch, which is gone after a server restart.
- 🔷 A freshly started agent has no pid for those tasks. The server was never sent one. The cleanup does not read `Command.running` and does not look up a stored pid.

#### Add — `server/SQT/Task.vala` (`rpc_register`, the `add_class` list)

```vala
				"logs", "i",
				"agent_boot", ""
```

#### Add — `server/SQT/Task.vala` (method `agent_boot`, after `logs`)

```vala
		/**
		 * End this agent's tasks that are still marked started.
		 *
		 * The agent calls this at the end of startup sync. This process
		 * has no child yet. Each target with
		 * {@link Argus.Shared.SQT.TaskTarget.started} set and
		 * {@link Argus.Shared.SQT.TaskTarget.ended} still 0 is closed
		 * with exit 127. The same command is not sent again.
		 *
		 * @param request inbound RPC from the agent
		 */
		public void agent_boot(OLLMrpc.Request request)
		{
			var caller = request.connection as Net.SslConnection;
			if (caller == null || caller.user == null || caller.user.id < 1 ||
				caller.user.is_controller) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("agent only")
				});
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("agent_id", (int) caller.user.id);
			Argus.Shared.SQT.TaskTarget.query(this.app.db).selectWhere(
				"WHERE agent_id = $agent_id AND started > 0 AND ended = 0 " +
					"AND is_cancelled = 0",
				binds, null, rows);
			var now = new GLib.DateTime.now_utc().to_unix();
			var text = "agent started and this task was not running\n";
			var ended_any = false;
			foreach (var target in rows) {
				if (target.log_dir != "" && target.identifier > 0) {
					var name = caller.user.id.to_string() + "-" +
						target.identifier.to_string() + ".stderr";
					var path = GLib.Path.build_filename(target.log_dir, name);
					var stream = GLib.FileStream.open(path, "a");
					if (stream != null) {
						stream.puts(text);
						stream.flush();
					}
				}
				var controller = target.is_watched ?
					Argus.Server.Command.watcher((int) target.id) : null;
				if (controller != null && controller.running) {
					controller.write(new OLLMrpc.Notification() {
						method = "controller.stderr",
						args = OLLMrpc.args("is", target.identifier, text)
					});
					controller.write(new OLLMrpc.Notification() {
						method = "controller.ended",
						args = OLLMrpc.args("i", target.identifier)
					});
				}
				// Exit 127: this agent booted and the task had no child.
				// The Tasks grid shows Failed, and the output footer shows this exit.
				target.ended = now;
				target.success = 127;
				Argus.Shared.SQT.TaskTarget.query(this.app.db).updateById(target);
				this.complete_task((int) target.task_id, now);
				ended_any = true;
				GLib.debug("task %s target %s ended 127",
					target.task_id.to_string(), target.agent_id.to_string());
			}
			if (ended_any) {
				this.app.db.backupDB();
				this.app.broadcast(new OLLMrpc.Notification() {
					method = "event.task",
					action = "ended"
				});
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
			if (ended_any) {
				this.app.scheduler.reschedule();
			}
		}
```

#### Add — `agent/OSQuery/Execute.vala` (end of `send_startup`)

```vala
			GLib.debug("osquery %d", code);
			var connection = this.application.connection;
			if (connection == null) {
				return;
			}
			try {
				var response = connection.call(new OLLMrpc.Request() {
					method = "Task.agent_boot"
				});
				if (response.error != null) {
					GLib.warning("task agent_boot %s", response.error.message);
				}
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
			}
```
- 💩 Reporting the pid to the server is a later case, for a child that outlives the agent process. `Command.stdin` sends the command line only. `agent/Win32/Command.vala` logs `command %d pid %d` and does not put that pid on the wire.
- ✔️ **Windows spawn failure reports the exit,** the same way Linux already does. A throw in `spawn()` is a child that did not start. This is in `agent/Win32/Command.vala`.

#### Remove — `agent/Win32/Command.vala` (`spawn()`, the `GLib.Error` catch)

```vala
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
```

#### Replace with — `agent/Win32/Command.vala` (`spawn()`, the `GLib.Error` catch)

```vala
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
```

- ✔️ **Connected tick** is already edited in `controller/tab/Base.vala`. The `tick-connected` binding now sets `icon_name` and `visible` on each `connected` change. The controller process that was open during this run is `/usr/bin/argusrm-controller` (pid 3623486). The tick appears after that process is replaced with `build/controller/argusrm-controller`.

---

## Attempts / changelog

- ✔️ `server/Command.vala`, `agent/linux/Command.vala`, `agent/Win32/Command.vala`, `controller/tab/Tasks.vala`: a spawned child sends `Command.stdin` with the command line. `agent/tests/command.vala` expects `printf listing` on that call. That shows the command after a child exists. It does not close a target whose child never existed. Not in the installed server or the Windows agent from 12:35 / 16:07.
- ✔️ `controller/tab/Base.vala` `tick-connected` binding, as above. `ninja -C build controller/argusrm-controller` succeeded after that edit.
- ✔️ `agent/Win32/Command.vala` `spawn()` sends `Command.stderr` and `Command.ended` (exit 127) when `spawn_async_with_pipes` throws.

## 2026-11-17 12:55, command 3

- ✔️ Server process restarted at 12:54:41 (`/var/log/argusrm/server.log` starts there). `12:55:08` `run command 3 on agent 11`, then `task 3 target 11 started 3`.
- ✔️ The agent's first `OSQuery.sync` on that connection is `12:55:14`. `Task.agent_boot` is `12:55:21`. No `Command.stdin`, `Command.stdout`, `Command.stderr`, or `Command.ended` after the dispatch. No `task … ended 127` line, and no database backup after `agent_boot`, so the query matched no row.
- ✔️ `/var/log/argusrm/commands/2026/11/17/` has `11-2.stdin` and `11-2.stderr` from 12:12 (the quoted-path failure). No `11-3` file.
- ✔️ On `DESKTOP-GITPJFF`, `argus-agent.exe` pid 24564 started 12:53:22 and has no child. Its threads all started at 12:53:22–23. No `Uninstaller.exe`. `Set-up.exe` pids 20872 and 13648 started 2026-10-29 12:17, session 0, parent 6816 is gone. That is not command 3.

## 2026-11-17 running line

- ✔️ `agent/Win32/Command.vala` polls the process handle. A silent child sends `Command.stderr` `running` every five seconds. When the handle is signaled, the loop ends and `Command.ended` carries the process exit code.
- ✔️ `Task.agent_boot` loads `started > 0 AND ended = 0 AND is_cancelled = 0` with {@link SQ.Query.select} and keeps the caller's agent id in Vala. It logs `agent_boot caller N running M`.

## Next

- ✔️ `Task.agent_boot`, the exit 127 spawn failure, the running line, and the Connected tick binding are in the tree. The Windows agent check is the NSIS setup test.
