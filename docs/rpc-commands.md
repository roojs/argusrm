# RPC commands

Reference for the calls the agent sends, and the library calls those depend on.

A call name is `Class.method`. The letters in `OLLMrpc.args` are the argument types.

- `s` string
- `o` object
- `ay` bytes
- `as` string array
- `b` bool, `i` int, `x` int64, `t` uint64

ℹ️ The full letter list is `OLLMrpc.args` in `libocrpc/namespace.vala`.

---

## Direction

- 🔷 A normal call is the client calling a method on the server. The server replies.
- 🔷 Remote command execution is the other way. The server sends a client notification to the connected agent. See [2.0 Phase 4](plans/2.0-agent.md).

---

## Calls the agent sends

The server handler for `OSQuery.sync` is `server/OSQuery.vala`. The download socket is not an RPC call. See [Downloads](#downloads).

### `Agent.request_registration`

- Socket: the app socket. The client certificate does not exist yet.
- Direction: agent calls the server.
- Arguments `ssssbss`: the pin, certificate request PEM, requester, OS family, controller flag, username, and hostname.
  - Windows sends `windows`. Android sends `android`.
  - Linux reads `/etc/os-release` before the call, through `GLib.Environment.get_os_info` for `ID` and `ID_LIKE`. Debian and Ubuntu send `debian`. Fedora, RHEL, CentOS, and SUSE send `rpm`.
  - When that file does not decide, `dpkg` on `PATH` sends `debian` and `rpm` on `PATH` sends `rpm`.
- Reply `retval`: a string array.
  - Index 0 is the client certificate PEM.
  - Index 1 is the CA PEM.
  - Index 2 is the download socket `host:port`. The agent writes that as `download`.
  - Index 3 is the download URL path, including the extension. The agent writes that as `download-path`. The server chooses it from the OS family.
  - Later entries are listen addresses.
- ℹ️ The method is `server/Agent.vala`. The agent calls it from `shared/Register.vala`.

### `Registration.certificate`

- Socket: the Unix socket.
- Direction: privileged controller calls the server.
- Arguments `s`: the controller user's operating-system login name.
- The server requires Unix peer uid `0`.
- Reply `retval` `o`: `Argus.Shared.Registration.Data`.
  - It contains the private key, client certificate, CA certificate, server name, addresses, and TLS port.
  - The server stores a pending controller row with `status = 0`.
- ℹ️ The method is `server/Registration.vala`.

### `Agent.list`

- Socket: the Unix socket.
- Direction: controller calls the server.
- Arguments: none.
- Reply `retval` `o`: an array of `Argus.Shared.Agent` rows, at most twenty.
- 💩 The controller prints `id` and `requester`.

### `OSQuery.sync`

- Socket: the app socket. The client certificate is already on that connection. That certificate selects `agent.id`. The snapshot is stored against it.
- Direction: agent calls the server.
- 🔷 One call per table. The arguments are the table name and the array of row objects.
- Arguments `so`: the table name, then the array.
- Tables the agent sends: `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`.
- An empty array is sent too.
- The row objects are `Argus.Shared.OSQuery`. The property name is the column name.
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `InterfaceAddresses`.
- ℹ️ Linux and Windows call it from `agent/OSQuery/Initialize.vala`. Android compiles `agent/android/OSQuery/Initialize.vala` and does not query.

---

## Downloads

Not an RPC call. [1.1](plans/1.1-implementation.md).

- 🔷 The download socket only listens for download requests.
- 🔷 The agent fetches with a standard HTTP GET over TLS.
- 🔷 The GET is authenticated with the client certificate. The server allows or refuses that certificate.
- 🔷 The URL is `https://` plus the download socket and the URL path from registration.
- 🔷 The saved basename is that path's last segment.
- 🚫 `Download.get` is not this fetch.
- ℹ️ `OLLMrpc.Transport.HttpClient` posts an RPC body. It is not this GET.

---

## Notifications

The server sends these. The agent listens. [2.0 Phase 4](plans/2.0-agent.md).

- 🔷 The connected agent has a class that listens for notifications.
- 🔷 The command class deals with the command notifications.
- 🔷 Every notification has a method. The listener switches on it.
- 💩 `Application.notification` in `agent/Application.vala`. Method `agent.run` runs an `Argus.Command`. Method `agent.send` follows up on one. Any other method returns. After `open_link` the process connects `TlsClient.notification` and calls `TlsClient.watch`. [2.4-DONE-listen.md](plans/done/2.4-DONE-listen.md).

- 🔷 A notification is for one connection. There are two deliveries.
  - A broadcast notification goes to every connection.
  - A client notification goes to one connection.
- 🔷 The run data goes to the agent as a client notification.
- 🚫 Signals and `RPC-Live-Subscribe` are not these calls. Bubble is not these calls.
- ℹ️ Both deliveries are one `OLLMrpc.Notification`. It has no matching response id.
  - `Connection.write` sends it to that connection.
  - `Listen.broadcast` sends it to every connection.
  - Nothing on the notification marks which delivery it is. The call that writes it does.
- ℹ️ `libocrpc/Notification.vala`, `libocrpc/Transport/Connection.vala`, `libocrpc/Transport/Listen.vala`.

### Argus command

- 🔷 The notification name says the agent receives it. That name is not the object.
- 🔷 The object set on the notification is an Argus command. Not an RPC method. Not what the agent sends.
- 🔷 On the server it is `Argus.Server.Command`. The server makes it.
- 🔷 On the agent it is `Argus.Agent.Command`. The agent executes it.
- 🔷 The two classes do not have to be the same. The server command maps to the agent command.
- 🔷 Down the wire the object is called `Argus.Command`.
- 🔷 The run data is the identifier, the command, the environment variables, and the current working directory.
- 🔷 That set has to run the command on Windows and on Linux.
- ℹ️ `g_spawn_async` takes `working_directory`, `argv`, and `envp`. `CreateProcess` takes `lpCurrentDirectory`, `lpCommandLine`, and `lpEnvironment`.
- 🔷 `Argus.Agent.Command` is a Linux class and a Windows class. They monitor the sockets differently. One class wrapped in ifdefs would be overwhelming.
- 🚫 A base class is not the split.
- 💩 `agent/linux/Command.vala`, `agent/Win32/Command.vala`, and `agent/android/Command.vala` are all `Argus.Agent.Command`. The build compiles one of them. Each registers the bin alias `Argus.Command`. Linux runs `sh -c` and watches stdout and stderr with `IOChannel.add_watch`. Windows runs `cmd.exe /c` and waits with `IOChannel.win32_poll`. Stdin, stdout, and stderr stay open on those two. An empty `cwd` or an empty `environment` inherits the agent process. The Android `run` does not spawn. It sends `Command.stdout` with an empty chunk.
- 💩 Properties on both: `identifier` `i`, `command` `s`, `environment` `as`, `cwd` `s`.
- 💩 Each environment entry is `NAME=value`. `cwd` is the current working directory.
- 💩 The `agent.run` notification `args` hold that one object. The bin alias is `Argus.Command`.

### `agent.run`

- 🔷 Every notification has a method. `agent.run` starts the command.
- 💩 Arguments: one `Argus.Command`. `Task.run` sends it.

### `agent.send`

- 🔷 A later notification can follow up on a running command. The method is `agent.send`, and it has an id.
- 💩 The id is the command `identifier` int. Arguments `is`: identifier, then the text. `Command.send` writes that text to the command's stdin. Android logs and does not write.
- 💩 `Notification.id` is an int. It is not this id.

## Server, after those calls

The agent does not do this. The handler is `server/Command.vala`.

- 🔷 Argus appends each `Command.stdout` chunk to a file.
- 💩 Argus appends each `Command.stderr` chunk to the stderr file.
- 💩 `Command.send` appends its text to the stdin file.
- 💩 `Task.run` stores `localstatedir/log/argusrm/commands/yyyy/mm/dd/` from the day the command starts. The default is `/var/log/argusrm`. Later stdin, stdout, and stderr append in that directory. The file is `{agent.id}-{identifier}` plus `.stdin`, `.stdout`, or `.stderr`. An identifier less than `1` is refused.
- 🔷 Argus then sends a client notification on the controller that set `task_target.is_watched`, when that connection is still up. An unwatched target does not send one.
- 🔷 A controller that initialized an install can watch that install.
- 🔷 The type name says the controller receives it.
- 💩 `Connection.running` is that check. The notification method is `controller.stdout` or `controller.stderr`. Arguments are `is`: identifier, then that chunk.
- 💩 The agent calls `Command.ended` when the child is dead. Arguments `ii`: identifier, then the exit code. The server stores that code on the task target and writes `controller.ended`.

### `Command.run`

- 🔷 The controller does not call this. `--command` creates a task, adds the agent, and approves it. [7.1 Phase 1.5](plans/7.1-tasks-implementation.md).
- 🔷 `Task.run` sends `agent.run` with one `Argus.Command`.

### `Command.send`

- 🔷 The controller calls this on the server. The server then sends the `send` notification to the agent that accepted that `run`.
- 💩 Arguments `is`: identifier, then the text. The same callers as `Command.run`.

### `controller.stdout`

- 🔷 Notification on the controller connection that initialized the run, when that connection is still up.
- 💩 Argus sends this after each `Command.stdout`. Arguments `is`: identifier, then that stdout chunk.

### `controller.stderr`

- 🔷 Notification on the controller connection that initialized the run, when that connection is still up.
- 💩 Argus sends this after each `Command.stderr`. Arguments `is`: identifier, then that stderr chunk.

### `controller.ended`

- 🔷 Notification on the controller connection that initialized the run, when that connection is still up.
- 💩 Argus sends this after `Command.ended`. Arguments `i`: identifier.

---

## Calls the agent sends for a run

The agent sends these on the app socket from `Command.run`. They are RPC calls.

### `Command.stdout`

- 🔷 The agent sends this as stdout arrives.
- 🔷 Each call is the next stdout chunk. The command is not resent.
- 💩 Arguments `is`: identifier, chunk.

### `Command.stderr`

- 🔷 The agent sends this as stderr arrives.
- 🔷 Each call is the next stderr chunk. The command is not resent.
- 💩 Arguments `is`: identifier, chunk.

### `Command.ended`

- 🔷 The agent sends this when the child is dead.
- 💩 Arguments `ii`: identifier, then the exit code.

---

## Tasks

Controller calls for the script library and tasks. Defined in [7.1](plans/7.1-tasks-implementation.md).

- `ScriptRepository.clone` `o`, `pull` `i`, `remove` `i`, `list` — in the tree. Clone uses libgit2 (`Ggit`). The row is written after the checkout succeeds.
- `Script.create` `ss`, `update` `is`, `read` `i`, `list` `i`, `enable` `ii`, `disable` `ii`, `agents` `i`
- `Task.create` `o`, `update` `o`, `list`, `target` `iv`, `watch` `i`, `approve` `ib`, `duplicate` `i`, `targets` `i`
