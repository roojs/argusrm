# `Command.run` reaches the server; the controller never prints it

**Status:** ✔️ FIXED — `command.ref()` in the hello callback; `controller-command` prints `ok hello`

**Reproduction:** `ninja -C build controller/argus-controller-command && ./build/controller/argus-controller-command`

ℹ️ `controller/tests/command.vala` plus product `controller/Command.vala`.
ℹ️ Local command with no extra ref: `stdout: ` exit 1. Client still emits `controller.stdout` / `controller.ended`.
ℹ️ Same local plus `command.ref()`: `ok hello`.
ℹ️ Live 12:26: agent `command 1`, server `Command.stdout` / `ended`, `1-1.stdout` 29163 bytes. Controller stayed on `Connecting...`.
ℹ️ Library `TlsClient` watch skip is installed. That is not this hang.

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**.

ℹ️ Parent: [2.4-DONE-listen.md](../../plans/done/2.4-DONE-listen.md).
ℹ️ Library hunk: `/home/alan/gitlive/OLLMchat/docs/bugs/done/2026-11-04-FIXED-tlsclient-watch-timeout.md`.

---

## Problem

- 🔷 `sudo argus-controller --agent 1 --command "ls -l /home/alan"` prints `Connecting to the local Argus server...` and waits until Ctrl+C.
- 🔷 Expected: the listing, then exit.
- 🔷 The Gtk session-bus warning is the controller `GLib.Application` as root. It is not this hang.

---

## Evidence

- ✔️ Server `/var/log/argusrm/server.log`:
  - `recv id=1 method=RPC-Daemon.hello`
  - `recv id=2 method=Command.run`
  - `run 1793783586236460 on agent 1`
- ✔️ Agent `/var/log/argusrm/agent.log` after the debug restart:
  - `Listen.vala:64: watching app socket`
  - osquery tables sent, `osquery 0`
  - no `agent.run`
- 💩 `TlsClient.watch` watches the raw TCP fd. `GSocket` / TLS can hold the bytes so that fd never looks readable.
- 💩 Osquery `call`s from a worker thread. Each `call` removes the watch and `Idle.add`s it back.
- ✔️ `sync-lag` 12:07 library: 200 ms gap → `locked`. Tight loop → `ok` at 0 ms.
- ✔️ `sync-lag` 12:20 local copy: 200 ms gap → `call 1` 1 ms, `call 2–4` 0 ms, `ok`.
- ✔️ `argus-agent-watch` 12:20 local copy: `ok during ls -l /home/alan after true`.
- ✔️ 12:23 A/B on the same local file:
  - Skip present: `call 1–4` 0–1 ms, `ok`. `watch`: `ok during ls -l /home/alan after true`.
  - Skip removed: `call 1 9862 ms`, `slow`, exit 1.
  - Skip restored: `call 1` 3 ms, then 1/0/0, `ok`. `watch` still `ok`.

---

## Root cause

- ✔️ `command_line` hello callback constructs `Command`, calls `run()`, and returns.
- ✔️ Vala connects `rpc.notification` with `g_signal_connect_object`. Collecting the command drops that handler.
- ✔️ Client still emits `controller.stdout` / `controller.ended`. Nothing prints them.
- ✔️ An extra `ref()` keeps the command until process exit. The CLI exits after `ended`.

---

## Debug added

- ✔️ `agent/Listen.vala` `start` logs `watching app socket`.
- ✔️ `agent/Listen.vala` `notification` logs the method.
- ℹ️ Do not launch `argus-agent`. That is the dialog. The service is already root.
- 🔷 Install with meson, then restart systemd:

```
ninja -C build install
sudo systemctl restart argusrm-server.service
sudo systemctl restart argusrm-agent.service
sudo argus-controller --agent 1 --command "ls -l /home/alan"
```

---

## Attempts / changelog

- ✔️ `Listen.start` watch is in the running binary. Still no command on the agent.
- ✔️ `watching app socket` is in the agent log. No method log after it.

---

## Next

- ✔️ `controller-command` with `command.ref()` prints `ok hello`.
- ✔️ `command.ref()` applied in `controller/Application.vala`.
- ✔️ 17:33: restarting the server dropped the agent TLS link.
  - Agent: `TlsClient.vala:266: TLS connection closed unexpectedly`
  - Server `Command.run`: `unknown agent`
  - That means no running app-socket connection with `agent_id == 1`.
- ✔️ 17:34: agent up, `watching app socket`, osquery `0`.
  - Server: `run command 1 on agent 1`.
  - No `agent.run` on the agent.
  - 10s later: `TlsClient.vala:266: Socket I/O timed out`.
- 💩 App-socket `SslConnection` had `live_handles = true`. The agent `TlsClient` does not.
  - The command object can go out as a live handle. The agent then waits for more bytes.
- ✔️ Remove `live_handles` on that TLS connection. Unix controller socket stays live.
- ✔️ After osquery, `Idle.add` calls `watch` again.
- ✔️ 17:37: `ninja -C build install`, server then agent, then `--command`.
  - `Initialize.vala:78: watching app socket` after `osquery 0`.
  - Server: `run command 1 on agent 1`.
  - No `agent.run`. `TlsClient.vala:266: Socket I/O timed out` 10s later.
- 💩 Dropping `live_handles` and calling `watch` again did not deliver the notification.
- ✔️ Local `Argus.Agent.TlsClient`. `watch` is a 50ms timeout. A would-block or timed-out parse keeps the source.
- ✔️ Loopback: `ninja -C build agent/argus-agent-watch` then `./build/agent/argus-agent-watch`. Watch, worker `call`, then `agent.run`. No systemd.
- ✔️ That binary printed `ok agent.run` and exited 0.
- ✔️ Library proposal uses that `watch`. Argus keeps the local class only until `ocrpc` has the hunk.
- ✔️ Upstream applied and installed. Argus dropped `Argus.Agent.TlsClient` and uses the library again.
- ✔️ 17:52 live: `Command.run` during osquery. No `agent.run` on the agent. The first loopback only proved `TlsClient`, not {@link Listen}.
- ✔️ Real loopback: four `OSQuery.sync` calls, `agent.run` with an `Argus.Command` during the first `call`, and another after the last.
  - `new Listen(link).start()` never ran the command.
  - `g_signal_connect_object` drops the handler when `Listen` is collected.
- ✔️ `Application` keeps `this.commands`. Test printed `ok during ls -l /home/alan after true`.
- ✔️ Folded `Listen` into `Application.notification`.
- ✔️ 10:51 live: agent watches, four osquery tables each take ~10s (`OSQuery.sync` then `backupDB()`), then `osquery 0`.
  - `sudo argus-controller --agent 1 --command` still prints `Connecting to the local Argus server...` and waits.
- ✔️ The 10s is `TlsClient.watch` holding `mutex` for `GSocket.timeout`. Not `backupDB()`.
  - `watch` should set `timeout` to 0. `call` restores it.
- 💩 The old loopback stubbed `Command` and used a lambda, not {@link Application.notification}.
  - It never spawned, never sent `Command.stdout` / `Command.ended`, and never ran the controller.
- ✔️ `meson test agent-command` — standalone `agent/tests/command.vala` plus `linux/Command.vala`.
  - `Application.notification` switch, real spawn, delayed first `OSQuery.sync`.
  - Both `agent.run`s produce stdout and `Command.ended`.
- ✔️ `controller-command` — standalone `controller/tests/command.vala` plus `Command.vala`.
  - Unix hello, `Command.run`, `controller.stdout` / `controller.ended`. `ok hello`.

---

## Proposed fix

- ✔️ `ref()` the command in the hello callback. Process exits after `ended`.
- 🚫 No `Application` field. No `order`.
- 🚫 Do not change {@link Argus.Controller.Command.run} identifier filter.

### `controller/Application.vala` — `command_line` hello callback

**Why:** Proven on `controller/tests/command.vala`. No extra ref → empty stdout. `command.ref()` → `ok hello`.

**Where:** `--command` branch after hello.

**Depends on:** `./build/controller/argus-controller-command` prints `ok hello`.

#### Replace with — ref the command, then connect and run

```vala
				var command = new Command(this);
				command.ref();
				command.stdout.connect((text) => {
					this.cli.print("%s", text);
				});
				command.stderr.connect((text) => {
					this.cli.printerr("%s", text);
				});
				command.ended.connect(() => {
					this.code = 0;
					this.loop.quit();
				});
				command.run();
```

---

## LLM efforts

- ✔️ 11:17: `agent-command` passed once (`ok during during after after`) and hung under `meson test`.
  - `controller-command` printed `stdout:` and exited 1.
  - Production `Application.vala` was not edited for those runs.
- ✔️ 11:20: `Idle.add` around `command.run` in `agent/tests/command.vala`.
  - Four direct runs plus `meson test agent-command` printed `ok during during after after`.
- ✔️ Same idle copied to `Application.notification`.
- ✔️ 11:57 live: `ninja -C build install`, restart server then agent,
  `--command`. Agent `agent.run` at 11:58:35. Still no `command 1`
  two minutes later. `/var/log/argusrm/commands/2026/11/05/` has
  only the 10:53 listing.
- ✔️ `agent-command` with `Idle.add` plus `ran_in_handler` printed
  `command did not run in the handler` and exited 1.
- ✔️ Same test with `command.run` in the handler.
- ✔️ Live-shaped gate: four syncs, then `watch`, then `agent.run`.
  Prints `notif agent.run` / `ran 1`, then hangs in
  `Command.stdout` `call()`. Watchdog:
  `Command.stdout still blocked after agent.run`.
- ✔️ `Idle.add` removed from `Application.notification`. The remaining FAIL is `TlsClient.watch`.
- ✔️ `agent/tests/sync-lag.vala`: four immediate `OSQuery.sync` replies after `watch`.
  - No 200 ms gap: `call 1–4` 0 ms, `ok`.
  - 200 ms gap: no `call` line, `locked`, exit 1 at 12 s.
- ✔️ 12:20 local `TlsClient` `watch` skips `parse` when not readable.
  - `sync-lag`: `ok` at 0–1 ms.
  - `watch`: `ok during ls -l /home/alan after true`.
- ✔️ Local class is test-only. Agent uses the library again.
- ✔️ 12:23 A/B: that skip is the only local change that matters.
  - Without it: `call 1 9862 ms` (`GSocket.timeout`). Same 10s as live `OSQuery.sync` and `Command.stdout`.
  - With it: `ok` at 0–3 ms. Both `agent.run`s still arrive.
- ✔️ 12:26 live after library install: agent `command 1`, server `Command.stdout` / `ended`. Controller `Connecting...`.
- ✔️ `controller-command` without a held `order`: Client emits `controller.stdout` / `controller.ended`. `got_stdout` stays empty. 5/5 exit 1.
- ✔️ Extra handler that read `order.identifier` kept the object. 5/5 `ok hello`. Extra handler that only printed the method: 5/5 empty stdout.
- ✔️ Test `Command` copy with `printerr` in the handler: `run ident 1`, `peer Command.run`, `reply ok`, `peer sent stdout`. No `cmd` line. Handler was gone.
- ✔️ Product `Command.vala` plus `app.order`: `ok hello` 5/5.
- ✔️ Same hold applied to `controller/Application.vala`.
- ✔️ Dropped the `order` field. `command.ref()` instead. Process exits after `ended`.
