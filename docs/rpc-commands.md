# RPC commands

Reference for the calls the agent sends, and the library calls those depend on.

A registered call, or a notification the server sends, belongs in this file. Add it in the same change that adds the call.

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

- Socket: the registration socket. The client certificate does not exist yet. The app socket stays on its certificate check.
- Direction: agent calls the server.
- Arguments `ssssbss`: the pin, certificate request PEM, requester, OS family, controller flag, username, and hostname.
  - Windows sends `windows`. Android sends `android`.
  - Linux reads `/etc/os-release` before the call, through `GLib.Environment.get_os_info` for `ID` and `ID_LIKE`. Debian and Ubuntu send `debian`. Fedora, RHEL, CentOS, and SUSE send `rpm`.
  - When that file does not decide, `dpkg` on `PATH` sends `debian` and `rpm` on `PATH` sends `rpm`.
- Reply `retval`: a string array.
  - Index 0 is the client certificate PEM.
  - Index 1 is the CA PEM.
  - Index 2 is the download URL path, including the extension. The agent writes that as `download-path`. The server chooses it from the OS family.
  - Later entries are app-socket listen addresses. The client stores that port as `server`, not the registration port it dialed.
  - The download address is not in the reply. The agent writes `download` as the host it connected to and `Argus.DOWNLOAD_PORT`.
- A controller that already has an active row for that username and hostname is refused with `This machine is already registered.`
- ℹ️ The method is `server/Agent.vala`. The agent calls it from `shared/Register.vala`.
- A matching pin broadcasts `event.pair` with action `done`. A rejected pin broadcasts `event.pair` with action `rejected`.

### `Agent.offer`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments: none.
- Opens the registration socket and publishes that port. The app socket stays as it is.
- Reply `retval` `as`: index 0 is the six digits. Index 1 is the public IPv4 address, or empty when that lookup fails.
- The number lasts sixty seconds, until `Agent.request_registration` accepts it, or until this connection closes.
- A caller that is not a controller is `controller only`.
- The registration socket failing to bind is `registration socket did not bind`.
- ℹ️ The method is `server/Agent.vala`. The controller calls it from `controller/dialog/Pairing.vala` and `controller/cli/Pin.vala`.

### `AgentService.hello` / `AgentService.status` / `AgentService.register`

- Socket: loopback `tcp://127.0.0.1:4142` (`OLLMrpc.Transport.TcpListen` inside the Windows service).
- Direction: `argus-tray.exe` calls `argus-agent.exe`.
- `AgentService.hello` `is`: protocol version, client name. Reply `msg`: `ok`.
- `AgentService.status`: no arguments. Reply `retval` `as`: `["1"|"0" registered, "1"|"0" connected, tip]`.
- `AgentService.register` `ss`: six-digit PIN, `host:port` (or empty to use browse). Reply `retval` `i`: `0` on success or `OLLMrpc.RpcErrorCode`.
- ℹ️ The handlers are in `agent/Win32/Service.vala`, called from `agent/Win32/tray/Tray.vala`.

### `Registration.certificate`

- Socket: the Unix socket.
- Direction: privileged controller calls the server.
- Arguments `s`: the controller user's operating-system login name.
- The server requires Unix peer uid `0`.
- An active controller row for the same login and hostname is refused with `This machine is already registered.`
- Reply `retval` `o`: `Argus.Shared.Registration.Data`.
  - It contains the private key, client certificate, CA certificate, server name, addresses, and TLS port.
  - The server stores a pending controller row with `status = 0`.
- ℹ️ The method is `server/Registration.vala`.

### `Registration.deregister`

- Socket: the Unix socket, or the app socket.
- Direction: controller calls the server.
- Arguments `s`: a SHA256 fingerprint, or a username on the Unix socket.
- On the app socket the string must be that connection's certificate fingerprint. The matching controller row is deleted. A missing row is still success.
- On the Unix socket the peer uid must be `0`. Sixty four lowercase hex digits delete that fingerprint. Anything else is a username, and only rows with a blank `ip` or `127.0.0.1` are deleted.
- An empty string is `fingerprint is required`. A Unix caller that is not root is `root is required`. A TLS fingerprint that is not the peer certificate is `fingerprint is required`.
- ℹ️ The method is `server/Registration.vala`.

### `RPC-Daemon.hello`

- Socket: the Unix socket.
- Direction: controller calls the server. This is the first call on that socket.
- Arguments `is`: the protocol number, then the client name. The controller sends `1` and `argus-controller`.
- Reply `msg`: `ok`. There is no return value.
- ℹ️ The method is `server/Daemon.vala`.

### `Agent.list`

- Socket: the Unix socket.
- Direction: controller calls the server.
- Arguments: none.
- Reply `retval` `o`: an array of `Argus.Shared.Agent` rows, at most twenty.
- `status` is `1` when the machine is registered, and `0` while a controller registration is still pending.
- `created` is the unix time the row was registered.
- `last_connected` is the unix time of the latest app-socket session. `0` means it has never connected.
- `connected` is true while that machine's app socket is open. It is not a database column.
- 💩 The command line prints `id` and `requester`.

### `Agent.remove`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent.id`.
- Deletes that row, writes `agent.removed` on its app socket, closes that socket, and refreshes the address allowlist.
- An unknown id is `unknown machine`. A caller that is not a controller is `controller only`.

### `OSQuery.sync`

- Socket: the app socket. The client certificate is already on that connection. That certificate selects `agent.id`. The snapshot is stored against it.
- Direction: agent calls the server.
- 🔷 One call per table. The arguments are the table name and the array of row objects.
- Arguments `so`: the table name, then the array.
- Tables: `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, and `os_version`, then one package class, plus `package_updates` on Linux (`APT` / `DNF`) from `PackageMonitor.send_pending`.
- The package class follows `os_version.package_manager`. APT sends `DebPackages`. DNF sends `RpmPackages`. WIN sends `Programs`. Any other value sends no package class.
- A row left out of a standard table snapshot gets `deleted_dt`. For `PackageUpdates`, existing names keep their `since` time, new names are inserted, and names left out are deleted.
- The machine tables are posted even when the array is empty. After the first package send, an empty package query is not posted. An empty `PackageUpdates` list is posted when `UpdatesAvailable.check` succeeds with no updates.
- The row objects are `Argus.Shared.OSQuery`. The property name is the column name.
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `InterfaceAddresses`, `OsVersion`, `DebPackages`, `RpmPackages`, `Programs`, `PackageUpdates`.
- Reply `msg`: `ok`. An unknown name, a name that is not a row class, or a row the apply rejects is an error.
- ℹ️ `Execute.send_startup` posts the machine tables, then `Execute.send_packages`. A later package change posts `Execute.send_packages` again. `Initialize` installs `osqueryi` and does not query.

### `SystemInfo.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `b`: true includes that host's `os_version` and the distinct logged-in users on the row. false is `system_info` only.
- Reply `retval` `o`: an array of `SystemInfo` rows. One row per host that has sent `system_info` and whose `agent_id` is still in `agent`.
- `os_version` and `logged_in_users` in that reply are included only when their `agent_id` is in `agent`.
- Startup deletes `system_info` rows whose `agent_id` is not in `agent`.
- With the flag, the row also carries `logged-in-users`, `operating_system` (`name` and `version`), `major`, `minor`, `patch`, `build`, `platform`, `platform_like`, `codename`, `arch`, `os_updated`, `os_status`, and `reboot_required`. `os_updated` and `os_status` come from `os_releases` (`1` up to date, `2` update available, `0` EOL, `-1` unchecked or unmatched). `logged-in-users` is `GROUP_CONCAT(DISTINCT logged_in_users.user)`. A host with no `os_version` row, or no session, stays in the list and those fields are empty.
- `logged-in-users` is not a column of `system_info`. The list reads rows already stored. It does not ask the agent.
- `major`, `minor`, and `patch` are text here, so a missing row stays blank. They are not columns of `system_info`.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/SystemInfo.vala`. `Store.SystemInfo` calls it. [5.8](plans/5.8-assets-page.md).

### `DebPackages.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `ii`: `agent_id`, `since`. `agent_id` zero is every agent, one row per package name. Greater than zero is that agent's stored rows, and the added-up columns are not filled. `since` zero leaves out a row whose `deleted_dt` is set. A later `since` returns every stored row whose `added_dt`, `updated_dt`, or `deleted_dt` is after that time, including a deleted row. That reply is not the added-up list.
- Reply `retval` `o`: an array of `DebPackages` rows. A host whose `agent_id` is not in `agent` is left out.
- When `since` is zero, the reply fills `update_since` from `package_updates` (`0` when no update is waiting). When `agent_id` and `since` are zero, the reply also fills `arch`, `section`, `priority`, `source`, `maintainer`, `min_version`, `max_version`, `max_size`, and `installed`. Those are not stored columns. `min_version` and `max_version` are the minimum and maximum of `version`, a hyphen, and `revision`. An empty revision leaves the trailing hyphen.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/DebPackages.vala`. `Store.DebPackages` calls it. The columns are `columns/deb_packages.csv`. [5.9](plans/5.9-assets-software.md).

### `RpmPackages.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `ii`: `agent_id`, `since`. `agent_id` zero is every agent, one row per package name. Greater than zero is that agent's stored rows, and the added-up columns are not filled. `since` zero leaves out a row whose `deleted_dt` is set. A later `since` returns every stored row whose `added_dt`, `updated_dt`, or `deleted_dt` is after that time, including a deleted row. That reply is not the added-up list.
- Reply `retval` `o`: an array of `RpmPackages` rows. A host whose `agent_id` is not in `agent` is left out.
- When `since` is zero, the reply fills `update_since` from `package_updates` (`0` when no update is waiting). When `agent_id` and `since` are zero, the reply also fills `arch`, `package_group`, `source`, `vendor`, `min_version`, `max_version`, `max_size`, and `installed`. Those are not stored columns. `min_version` and `max_version` are the minimum and maximum of `epoch`, a colon, `version`, a hyphen, and `release`.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/RpmPackages.vala`. `Store.RpmPackages` calls it. The columns are `columns/rpm_packages.csv`. [5.9](plans/5.9-assets-software.md).

### `Programs.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `ii`: `agent_id`, `since`. `agent_id` zero is every agent, one row per program name. Greater than zero is that agent's stored rows, and the added-up columns are not filled. `since` zero leaves out a row whose `deleted_dt` is set. A later `since` returns every stored row whose `added_dt`, `updated_dt`, or `deleted_dt` is after that time, including a deleted row. That reply is not the added-up list.
- Reply `retval` `o`: an array of `Programs` rows. A host whose `agent_id` is not in `agent` is left out.
- When `agent_id` and `since` are zero, the reply fills `publisher`, `language`, `identifying_number`, `install_date`, `install_location`, `install_source`, `uninstall_string`, `min_version`, `max_version`, `installed`, and `uninstall_count`. The added columns are not stored. `uninstall_count` is how many of those machines have an uninstall string.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/Programs.vala`. `Store.Programs` calls it. The columns are `columns/programs.csv`. [5.9](plans/5.9-assets-software.md).

---

## Downloads

Not an RPC call. [1.1](plans/1.1-implementation.md).

- 🔷 The download socket only listens for download requests.
- 🔷 The agent fetches with a standard HTTP GET over TLS.
- 🔷 The GET is authenticated with the client certificate. The server allows or refuses that certificate.
- 🔷 The URL is `https://` plus the registration host, `Argus.DOWNLOAD_PORT`, and the URL path from registration.
- 🔷 The saved basename is that path's last segment.
- 🚫 `Download.get` is not this fetch.
- ℹ️ `OLLMrpc.Transport.HttpClient` posts an RPC body. It is not this GET.

---

## Notifications

The server sends these. The agent listens. [2.0 Phase 4](plans/2.0-agent.md).

- 🔷 The connected agent has a class that listens for notifications.
- 🔷 The command class deals with the command notifications.
- 🔷 Every notification has a method. The listener switches on it.
- 💩 `Application.notification` in `agent/Application.vala`. Method `agent.run` runs an `Argus.Command`. Method `agent.send` follows up on one. Method `agent.removed` deletes the stored certificate. Any other method returns. After `open_connection` the process connects `TlsClient.notification` and calls `TlsClient.watch`. [2.4-DONE-listen.md](plans/done/2.4-DONE-listen.md).

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

### `event.pair`

- 🔷 Broadcast. `Agent.request_registration` sends it.
- 💩 Action `done` means the pin was accepted. Action `rejected` means the pin was refused.
- ℹ️ The pairing dialog and `argusrm-controller --pin` listen for it. The agent page reloads on `done`.

### `event.agent`

- 🔷 Broadcast. The app socket sends it.
- 💩 Action `connected` is a known certificate joining. Action `disconnected` is that socket stopping.
- ℹ️ The agent page reloads on either action.

### `agent.removed`

- 🔷 Client notification on the machine `Agent.remove` is deleting.
- 💩 No arguments. The agent deletes its stored `client.pem`. The server then closes that socket.

### `agent.run`

- 🔷 Every notification has a method. `agent.run` starts the command.
- 💩 Arguments: one `Argus.Command`. `Task.run` sends it.

### `agent.send`

- 🔷 A later notification can follow up on a running command. The method is `agent.send`, and it has an id.
- 💩 The id is the command `identifier` int. Arguments `is`: identifier, then the text. `Command.send` writes that text to the command's stdin. Android logs and does not write.
- 💩 `Notification.id` is an int. It is not this id.

### `agent.status`

- 🔷 Broadcast from `AgentService` over loopback TCP (`127.0.0.1:4142`) to connected `argus-tray.exe` clients.
- 💩 Arguments `bbs`: `registered`, `connected`, `tip`.

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
