# `Command.run` reaches the server; the agent never runs it

**Status:** ⏳ `Application.notification` on the process; no `Listen` class

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**.

ℹ️ Parent: [2.4-listen.md](../plans/2.4-listen.md).
ℹ️ Library hunk: `/home/alan/gitlive/OLLMchat/docs/bugs/2026-11-04-tlsclient-watch-timeout.md`.

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

---

## Root cause

- ✔️ `Listen.start` ran. `TlsClient.watch` did not deliver `agent.run`.
- ✔️ `watch` polls the raw TCP fd. The bytes are TLS application data.

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

- ✔️ Library watch patch is installed. This tree only rebuilds and restarts the agent.
- ⏳ Install the new `argus-agent`, then `sudo systemctl restart argusrm-agent.service`.
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
- ✔️ Local `Argus.Agent.TlsClient`. `watch` is a 50ms timeout. A
  would-block or timed-out parse keeps the source.
- ✔️ Loopback: `ninja -C build agent/argus-agent-watch` then
  `./build/agent/argus-agent-watch`. Watch, worker `call`, then
  `agent.run`. No systemd.
- ✔️ That binary printed `ok agent.run` and exited 0.
- ✔️ Library proposal uses that `watch`. Argus keeps the local
  class only until `ocrpc` has the hunk.
- ✔️ Upstream applied and installed. Argus dropped
  `Argus.Agent.TlsClient` and uses the library again.
- ✔️ 17:52 live: `Command.run` during osquery. No `agent.run` on
  the agent. The first loopback only proved `TlsClient`, not
  {@link Listen}.
- ✔️ Real loopback: four `OSQuery.sync` calls, `agent.run` with
  an `Argus.Command` during the first `call`, and another after
  the last. `new Listen(link).start()` never ran the command.
  `g_signal_connect_object` drops the handler when `Listen` is
  collected.
- ✔️ `Application` keeps `this.commands`. Test printed
  `ok during ls -l /home/alan after true`.
