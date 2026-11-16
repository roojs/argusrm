# Task stays Running when the child never starts

**Status:** ⏳ open — start check not approved. Connected tick is patched in the tree and not yet verified in the running controller.

**Pointer:** `docs/bug-fix-process.md`, `docs/rpc-commands.md`, [7.0-tasks.md](../plans/7.0-tasks.md), [2026-11-16-windows-uninstall-task-queue.md](2026-11-16-windows-uninstall-task-queue.md)

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
- ℹ️ `task_target.timeout` exists and [7.0-tasks.md](../plans/7.0-tasks.md) says it is unused. A silent `msiexec /qn` can run for a long time with an empty stdout, so “nothing was printed” does not mean the child is gone.
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

- 💩 **Start check when the agent socket opens.** For each target on that agent with `started > 0 AND ended = 0`, ask the agent if that identifier is in `Command.running`. No entry means the child is gone: call `fail_target` with a non-zero exit and a stderr line, then broadcast `event.task` `ended`. A live entry stays Running. Do not dispatch the command again. A partial `msiexec` must not be started twice.
- 💩 This needs an agent call, so it is a new RPC and stays here until that shape is approved.
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

## Next

- ⏳ 💩 Approve the reconnect start check and its RPC shape, then implement it. Until `ended` is set, task 1 on agent 11 stays Running.
- ✔️ Windows `spawn()` now sends `Command.stderr` and `Command.ended` with exit 127, matching Linux. That is in `agent/Win32/Command.vala` and is not in the agent that was restarted at 16:07. It does not close command 1, because that dispatch already returned and that process has exited.
- ⏳ 🔷 Relaunch the controller from `build/controller/argusrm-controller` and confirm the Connected tick on `DESKTOP-GITPJFF` while `ss` still shows the session to port 817.
