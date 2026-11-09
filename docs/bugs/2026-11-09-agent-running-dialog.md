# Agent running dialog

**Status:** ✔️ code updated. Not installed. Not user-verified.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 A normal desktop launch asks to run as admin, then Polkit succeeds.
- 🔷 The next window title is `Argus`, and the header says `Argus agent is running`.
- 🔷 This is the Argus Remote Manager agent window. The header is the title only. The running or connected state belongs in the body.
- 🔷 The body then shows a D-Bus error.
- 🔷 System D-Bus stays. The GTK window asks the running service, over the system bus, whether it is connected to the management server.
- 🔷 The controller does not show the machine as connected.

## Evidence

- ✔️ `argusrm-agent.service` is active as `/usr/bin/argusrm-agent --service` since 15:18:06. The process is still that pid.
- ✔️ `/var/log/argusrm/agent.log` stops at `SELECT * FROM cpu_info`. There is no `osquery` result line after that.
- ✔️ `system_info` logged `Error sending data: Connection reset by peer`. The next `TlsClient.call` sets the socket blocking and waits in `parse`. That wait is not limited to would-block, so the main thread never returns from `command_line`.
- ✔️ `Bus.own_name` for `org.roojs.ArgusAgent` is started in that same `command_line`, before `OSQuery.Initialize.start`. The name callback needs the main loop. The loop never runs, so the name is never requested.
- ✔️ `busctl --system call org.freedesktop.DBus ... ListNames` does not include `org.roojs.ArgusAgent`.
- ✔️ The window catch sets the body to that error: `The name org.roojs.ArgusAgent was not provided by any .service files`.
- ✔️ `shared/Notice.vala` assigned the status heading to `this.title`, so the header repeated `Argus agent is running`.
- ✔️ `/usr/share/dbus-1/system.conf` has `<deny own="*"/>`. Root does not get a blanket allow. `org.roojs.ArgusAgent.conf` allows root to own the name, and its mtime is 2026-11-03. `dbus.service` has been up since 2026-10-09, so that file is not loaded.
- ✔️ A non-root `Bus.own_name` on the system bus reaches the bus and then loses the name. The callback path works. The service never gets that far.
- ℹ️ The session-bus warning is separate. `GApplication` still opens the session bus. Polkit runs this program as root, and that bus closes the connection. Status does not use the session bus.

## Root cause

- ✔️ The header title is the status sentence.
- ✔️ The service never owns `org.roojs.ArgusAgent`, because osquery sync blocks `command_line` on the dead server socket before the main loop can finish the name request.
- ✔️ After that request can run, the system bus still needs the ownership policy loaded. The file is on disk and the running dbus daemon has not read it.

## Proposed fix

- 🔷 Header title is `Argus Remote Management Agent`. The status sentence stays in the body.
- 🔷 Not connected offers Configure, which opens registration.
- 🚫 Stopping the remaining table sends after the first failure. All four tables stay in the one run.
- 🔷 Ship `org.roojs.ArgusAgent.conf` with the agent package. Reload the system bus once so the running daemon allows the name.

### `agent/linux/Application.vala` — window name

{@link Argus.Shared.Notice} stays `Argus Remote Manager` for the controller. The agent dialog sets its own title.

#### Add

```vala
			GLib.Environment.set_application_name("Argus Remote Management Agent");
			notice.title = "Argus Remote Management Agent";
```

### `agent/OSQuery/Initialize.vala` — failed send

The four `code += this.sync_table` calls stay. A thrown send sets `Application.connection_down`.

#### Remove

```vala
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
```

#### Replace with

```vala
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
```

## Attempts

- ✔️ The service log, system bus name list, and a same-process `Bus.own_name` probe.
- 🚫 Private session bus. Polkit starts the same program as root.
- 🚫 Editing `TlsClient` from this tree. The blocking read is in `libocrpc`.

## Next

- ⏳ Install the new `argusrm-agent` and `argusrm-agent-gtk`.
- ⏳ `systemctl reload dbus`, then restart `argusrm-agent`. The daemon has not loaded the ownership policy.
- ⏳ Open the agent as a normal user. The header says Argus Remote Management Agent. Not connected offers Configure. The controller stays disconnected until this machine is registered again against the current server CA.
