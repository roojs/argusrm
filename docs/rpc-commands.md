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

The server handler for `OSQuery.sync` is not in this tree. The download socket is not an RPC call. See [Downloads](#downloads).

### `ClientCert.request_registration`

- Socket: the app socket. The client certificate does not exist yet.
- Direction: agent calls the server.
- Arguments `ssss`: the pin, the certificate request PEM, the requester, the OS family.
  - Windows sends `windows`. Android sends `android`.
  - Linux reads `/etc/os-release` before the call, through `GLib.Environment.get_os_info` for `ID` and `ID_LIKE`. Debian and Ubuntu send `debian`. Fedora, RHEL, CentOS, and SUSE send `rpm`.
  - When that file does not decide, `dpkg` on `PATH` sends `debian` and `rpm` on `PATH` sends `rpm`.
- Reply `retval`: a string array.
  - Index 0 is the client certificate PEM.
  - Index 1 is the CA PEM.
  - Index 2 is the download socket `host:port`. The agent writes that as `download`.
  - Index 3 is the download URL path, including the extension. The agent writes that as `download-path`. The server chooses it from the OS family.
  - Later entries are listen addresses.
- ℹ️ The method is `ollmfilesd/ClientCert.vala`. The agent calls it from `shared/Register.vala`.

### `OSQuery.sync`

- Socket: the app socket. The client certificate is already on that connection.
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

Not an RPC call. [1.0 Sockets](plans/1.0-overview.md).

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
- 💩 `Argus.Agent.Listen` in `agent/Listen.vala`. Method `run` runs an `Argus.Command`. Method `send` follows up on one. Any other method returns. `start` does not pull one yet: `TlsClient.call` only returns a `Response`.

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
- 💩 `agent/linux/Command.vala`, `agent/Win32/Command.vala`, and `agent/android/Command.vala` are all `Argus.Agent.Command`. The build compiles one of them. Each registers the bin alias `Argus.Command`. Linux runs `sh -c` and watches stdout and stderr with `IOChannel.add_watch`. Windows runs `cmd.exe /c` and waits with `IOChannel.win32_poll`. Stdin, stdout, and stderr stay open on those two. An empty `cwd` or an empty `environment` inherits the agent process. The Android `run` does not spawn. It sends `Command.started` with an empty initial output.
- 💩 Properties on both: `identifier` `s`, `command` `s`, `environment` `as`, `cwd` `s`.
- 💩 Each environment entry is `NAME=value`. `cwd` is the current working directory.
- 💩 The `run` notification `args` hold that one object. The bin alias is `Argus.Command`.

### `run`

- 🔷 Every notification has a method. This one starts the command.
- 💩 Arguments: one `Argus.Command`. `Command.run` takes it.

### `send`

- 🔷 A later notification can follow up on a running command. It has a `send` method and an id.
- 💩 The id is the command `identifier` string. Arguments `ss`: identifier, then the text. `Command.send` writes that text to the command's stdin. Android logs and does not write.
- 💩 `Notification.id` is an int. It is not this id.

## Server, after those calls

The agent does not do this. The server is not in this tree.

- 🔷 Argus writes the `Command.started` output to a file.
- 💩 Argus appends each `Command.output` chunk to that file.
- 🔷 Argus then sends a client notification on the controller connection that initialized the run, when that connection is still up.
- 🔷 A controller that initialized an install can watch that install.
- 🔷 The type name says the controller receives it.
- 💩 How the server learns that the process exited was not named.

### `Argus.Controller.CommandStarted`

- 🔷 Object on the notification to the controller. The type name says the controller receives it.
- 🔷 Sent when that controller initialized the run and the connection is still up.
- 🔷 A controller that initialized an install can watch that install.
- 💩 Argus sends this after it has received `Command.started`. The agent does not send this object.
- 💩 Properties: `identifier` `s`, `text` `s`. `text` is the initial output.

### `Argus.Controller.CommandOutput`

- 🔷 Object on the notification to the controller. The type name says the controller receives it.
- 💩 Argus sends this after each `Command.output`. The agent does not send this object.
- 💩 Properties: `identifier` `s`, `text` `s`. `text` is that chunk.

---

## Calls the agent sends for a run

The agent sends these on the app socket from `Command.run`. They are RPC calls.

### `Command.started`

- 🔷 The agent sends this after the process has started.
- 🔷 It says the command started and includes the initial output.
- 💩 Arguments `ss`: identifier, initial output. Sent from `agent/linux/Command.vala` and `agent/Win32/Command.vala`.

### `Command.output`

- 🔷 The agent sends this as output arrives.
- 🔷 Each call is the next chunk.
- 💩 Arguments `ss`: identifier, chunk. Sent from the same `Command.run`.
