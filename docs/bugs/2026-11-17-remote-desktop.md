# Remote desktop from the machine General tab

**Status:** ⏳ critical — Phases 1–5 are in the tree. The controller compiled. None of this is verified on a machine. Phase 6 is the session tabs. Phase 6.5 is Force and the Disconnect notice. Phase 7 waits until Windows works.

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md`, archived plan [5.12-MOVED-remote-desktop.md](../plans/done/5.12-MOVED-remote-desktop.md), missing `relay.status`, server broadcast abort, Windows cert wipe), [`controller/tab/Asset/Machine/General.vala`](../../controller/tab/Asset/Machine/General.vala), [`agent/Win32/Service.vala`](../../agent/Win32/Service.vala), [`server/Net/Download.vala`](../../server/Net/Download.vala)

---

## Problem

- 🔷 Scripted Windows uninstalls are not a reliable way to finish the job. A task can start on the signed-in desktop and still be a window nobody is there to click. The person has to be at that desktop.
- 🔷 **Expected:** on the General tab of a Windows machine, a button with a screen picture. Touch and hold starts visual remote control of that machine. Argus turns Windows Remote Desktop on, and tunnels those protocol bytes to a viewer on the controller.
- 🔷 **Actual:** no button, the agent does not enable Remote Desktop, and there is no product tunnel. The only path onto the machine is a task command.

---

## After "Told the server this controller wants to take control."

Windows PC (`snappr-win`), 5:07pm. Lines before that sentence are left out. ✔️ means this run reached that line. A blank flag means it did not. The desktop was on screen. Windows then closed the session that came from this PC. Tries 2 and 3 waited and got no new sign-in.

| Step | This run |
| --- | --- |
| Told the server this controller wants to take control. | ✔️ |
| Turning Remote Desktop on. | |
| Waiting for Remote Desktop to be turned on. | |
| Remote Desktop is on. | |
| Connecting to Windows Remote Desktop on the machine. | ✔️ |
| The machine started the Remote Desktop connection. | ✔️ |
| The machine is joining the server. | ✔️ |
| The machine joined the server. | ✔️ |
| The server is waiting for this controller. | ✔️ |
| The server is holding the desktop until this controller joins. | ✔️ |
| This controller is joining the desktop. | |
| This controller joined the desktop. | ✔️ |
| The machine is about to send the desktop. | ✔️ |
| Drawing the desktop in this window. | |
| The machine is sending the desktop to the server. | ✔️ |
| The desktop data is coming through. | ✔️ |
| The desktop is on screen. | ✔️ then it closed. **Critical. Stops here.** "The machine could not send the desktop." Trying 1, 2, and 3. Windows closed the session from this PC. Tries 2 and 3 got no new sign-in. |

## Why this left the plan

- 🔷 [5.12](../plans/done/5.12-MOVED-remote-desktop.md) was feasibility only, and it waited. It is this bug because the uninstall work still leaves machines that need a person on the desktop.
- ℹ️ 2026-11-17-FIXED-windows-command-session-job.md starts the command on the signed-in desktop and waits for the process tree. That does not click a wizard. The Illustrator run in that log is the case: the launcher exited, and `Set-up.exe` sat on a lock.
- ℹ️ 2026-11-16-FIXED-windows-uninstall-task-queue.md rewrites `msiexec /I` to a silent `/X … /qn /norestart`. An uninstaller that is not `msiexec`, or that ignores the quiet flags, still opens a window on a desktop the controller cannot see.

---

## Evidence

- ✔️ The General tab is `controller/tab/Asset/Machine/General.vala`, inside `controller/tab/Asset/Machine/Detail.vala`. General is a vertical list of expanders. It has no search and no bar of its own. Users, Windows programs, Storage, and the package tabs put a search field in a bar at the top of the page. `Detail` has the tab toggles. The window header bar is the title only.
- ✔️ The controller is GTK 4 and libadwaita. `controller/meson.build`.
- ✔️ The Windows agent is the service in `agent/Win32/Service.vala`. It already holds a TLS session to the server. Nothing in the tree sets `fDenyTSConnections`, starts `TermService`, or speaks Remote Desktop.
- ℹ️ The download socket is the precedent for a second listen: the same client certificate, and a transfer there does not clog the app socket. `server/Net/Download.vala`.
- ℹ️ `Application.open_connection` keeps one `TlsClient`, and `watch` reads frames for the life of it.

---

## Root cause

- ✔️ There is no remote-desktop path. A task command cannot stand in for one when the work is a window on that machine.

---

## Phases

- ✔️ **Phase 1 — Relay proof.** Framed RPC carried a FreeRDP session. Test binaries only.
- ✔️ **Phase 2 — Second connection, same port.** No other port and no other listener. The server registers `Relay.join` and `Relay.write`. The proof still uses the test listen.
- ✔️ **Phase 3 — Enable Windows Remote Desktop.** Edition check, logged-in check, and the tray balloon are in. The button is Phase 5.
- ✔️ **Phase 4 — Start the flow.** In the tree. Not verified on a machine. The agent streams. The server tells the controller. Bytes are dropped until the controller connects, then forwarded from the start of a connection. A late controller gets a new connection from the first byte.
- 🔷 ⏳ **Phase 5 — Viewer.** A touch and hold of the screen button on General opens the RDP page in this window.
- 🔷 ⏳ **Phase 6 — Session tabs.** The selected tab is the live feed. The X on a tab disconnects it.
- 🔷 ⏳ **Phase 6.5 — Takeover edges.** Force. The tray asks before Remote Desktop is turned on, and the controller is told so the page is not blank. The tray names who has the screen and can disconnect.
- 💩 ⏳ **Phase 7 — Linux desktops.** After Windows works. GNOME Remote Desktop and xrdp speak this protocol.

Phase 2 adds no port and no listener.

---

## Phase 1 — Relay proof

- ✔️ `meson test -C build rdp-relay` passed. The desk log contains `ACTIVATED` and the test prints `ok rdp relay activated`. Needs `freerdp3`, `freerdp-server3`, `winpr3`, and `sdl-freerdp3`.
- ✔️ The path is `Argus.Agent.Rdp.Desk` (FreeRDP listener on `127.0.0.1`) ← `Argus.Agent.Rdp.Tunnel` (dials that port, joins as `agent`) ← `Argus.Server.Rdp.Relay` (`Relay.write` chunks become `relay.data`) ← `Argus.Controller.Rdp.Viewer` (joins as `view`, accepts sdl-freerdp3 on a loopback port).
- ✔️ Those classes are compiled into `argus-rdp-desk` and `argus-rdp-relay-test` from the top-level `meson.build`. They are not linked into the agent, the server, or the controller.
- ✔️ The bytes are framed `ay` chunks on `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`. `Relay.join` and `Relay.write` exist only inside the test process. They are not in `docs/rpc-commands.md`.
- ℹ️ The stand-in desk turns NLA off and accepts any logon, so the Linux listener can finish without a Windows account. Phase 3 does not copy that. Network Level Authentication stays on for TermService.
- ℹ️ sdl-freerdp3 ran with `+auth-only`. It did not open a window. `ACTIVATED` is FreeRDP finishing the connection sequence, not a person looking at a desktop.
- ✔️ 2026-11-18: the same listen also answers `App.ping` on the first connection while the second connection streams. After `joined view` the log still has `app pong`, then `ACTIVATED`. `meson test -C build rdp-relay` prints `ok app rpc during stream`.
- 🚫 A hand-rolled C Gio TLS splice. The probe is Vala and uses the existing RPC types.
- 🚫 sdl-freerdp3 inside a GTK 4 widget. It is a separate SDL window. Phase 5 paints with `libfreerdp-client`.

---

## Phase 2 — Second connection, same port

- 🔷 The desktop is another connection to the port that is already listening. No other port. No other listener.
- 🔷 The first connection stays the app session. It is not switched to raw bytes. The desktop bytes are not `agent.run`.
- 🔷 An RPC on the second connection turns streaming on. The bytes are the Remote Desktop protocol, not a second remote-desktop product.
- ✔️ One listen, one port. The first connection calls `App.ping` and does not join the stream. The agent and the viewer open further connections to that same port and `Relay.join` turns streaming on. `App.ping` still replies after `joined view`, and the desk reaches `ACTIVATED`.
- ℹ️ The listen in the test is the same shape as `server/Net/SslListen.vala`: one `SocketService`, TLS, a client certificate, then `OLLMrpc.Transport.Connection`. The product class is not the one that accepted these connections.
- 🚫 Another listen, or any new port. The download socket stays an HTTPS GET. `server/Net/Download.vala`.
- ℹ️ The agent still dials out. The machine does not accept a new inbound port for this.
- ℹ️ Streaming off is not dropping the desktop. A tab that is not selected keeps the Windows session and drops the bytes. Phase 6.
- ℹ️ Phase 2 does not start the stream. The test opens the agent connection itself. Phase 4 is signed off. Phase 6.5 builds it.
- 🔷 A new or changed `Request.add_class` method is written into `docs/rpc-commands.md` in the same change.
- ✔️ The fences are applied. The server calls `Rdp.Relay.rpc_register()` and compiles `Relay.vala`. `listen()` stays the test's listen. The server does not call it.

---

## Phase 3 — Enable Windows Remote Desktop

- 🔷 Show the button only when `supports_rdp()` is true. If it is false, show nothing. The button is Phase 5. It is not built.
- ✔️ The agent does not change Windows when `supports_rdp()` is false.
- ℹ️ The Windows name is `os_version.name`, for example `Microsoft Windows 11 Pro`. No name yet means no.
- ✔️ After startup the Windows agent sets `fDenyTSConnections` to `0`, sets `UserAuthentication` to `1`, and starts `TermService`. The firewall group is left closed.
- 🔷 Leave the Windows password prompt on. Argus does not store the password.
- ✔️ Nobody is logged in: an active Windows session is absent, so Remote Desktop is turned on. No tray question.
- ℹ️ Someone is logged in: the tray ask is held until Phase 6.5. Until then the agent turns Remote Desktop on without asking.
- ℹ️ The tray reads the last keyboard or mouse time. Half an hour idle allows Remote Desktop without asking. More recent input shows a balloon. A click allows it. Ignoring the balloon leaves it off. That ask is Phase 6.5.
- ℹ️ The service cannot read that time. It runs in session 0. The tray runs in the signed-in session.
- 🔷 Sign in as the person already logged in. A different account logs them off.
- ℹ️ Force, and the tray notice that names who has the screen, are Phase 6.5.
- ℹ️ A machine that is really asleep has to wake before any of this.
- 🚫 Do not patch Windows to invent a second screen, or to turn this on for Home.

---

## Phase 4 — Start the flow

- 🔷 The controller starts this when the operator touches and holds the screen button on that machine's General tab. Phase 5 draws the button.
- 🔷 The agent opens the second connection and starts streaming once Remote Desktop is on.
- 🔷 The server tells the controller that this machine's stream has started. That notification is not the desktop bytes.
- 🔷 Until that controller connects, the server drops the stream bytes.
- 🔷 When the controller connects, the server forwards both ways.
- ℹ️ Windows sends nothing until it receives the viewer's opening bytes. The controller's first bytes are the start of the connection.
- 🔷 A controller that arrives after a stream is already going does not join the middle. The agent closes that connection to Windows and opens a new one. Forwarding starts at the first byte of the new connection.
- 🚫 The server does not read Remote Desktop messages to find a cut point. The cut is a new connection.
- ℹ️ Force and the tray notice stay in Phase 6.5.
- ✔️ In the tree. `server/Rdp/Relay.vala`, `server/Rdp/Seat.vala`, `agent/Application.vala`, `agent/Win32/Service.vala`, `agent/Rdp/Tunnel.vala`, `controller/store/MachineGeneral.vala`.
- ℹ️ Not in `meson test -C build rdp-relay`. That test starts the agent and the viewer itself. `Relay.listen` stays the test listen.
- 🔷 Phase 5's screen button calls `MachineGeneral.start_desktop`. It does not draw the button.

---

## Phase 5 — Viewer

- 🔷 FreeRDP is the viewer. It asks for the Windows password. No drive redirection.
- 🔷 Clipboard sharing can wait. It is not required to see and control the desktop.
- 🔷 Audio is not part of this bug.
- 🔷 The starter is on the General tab of one Windows machine. A button with a screen picture. Touch and hold starts the flow and switches this window to the RDP page, with that machine's tab selected. A second machine adds a tab.
- 🔷 A short press does not start it.
- 🔷 The button is shown only when that machine's `OsVersion.supports_rdp()` is true. Unknown and Home show nothing.
- 🔷 The RDP row sits under Assets on the left. It shows while a session tab exists, and it goes when the last tab is gone. `controller/TabList.vala` lists Assets above Distributables.
- 🔷 On Android the viewer is that same RDP page.
- 🔷 The screen button sits at the top of the General page, in the bar where the other machine tabs put search. General has no search. The bar belongs to that page. Not in the window header. Not on the detail tab switcher.
- 🚫 A text button labeled Connect to desktop.
- 🚫 The starter on the machine list, or on Agents.
- ℹ️ A desktop inside the controller window links `libfreerdp-client` and paints into GTK. The localhost port the viewer already listens on is the socket FreeRDP reads. `Viewer.run` stays the test. This phase does not change it.
- 🚫 A separate viewer window.
- ℹ️ The X, the key, and a quiet tab are Phase 6. This phase adds the tab and shows the selected picture. An unselected tab stays connected. `Rdp.drop` removes a tab and hides the row when none remain. Phase 6's X calls `drop`, and that phase is what tells the agent to let go of the Windows session.
- ℹ️ The hold is `HoldButton`. That is two seconds. `short_click` is not connected.
- 💩 The Windows certificate is accepted. FreeRDP dials `127.0.0.1`, so the certificate name will not match that host.
- 💩 An empty hostname uses `computer_name` for the tab.
- 💩 The picture uses 1280×720 when the page has no size yet.
- ℹ️ The controller links `freerdp3` and `winpr3` on every host, including Android. The test's optional dependency stays optional.

```
web-03, General
+------------------------------------------------------------------+
| [ General | Users | Windows programs | Interfaces | Storage ]    |
+------------------------------------------------------------------+
| [screen]                                                         |
|  Computer                                                        |
|  hostname            web-03                                      |
|  operating system    Microsoft Windows 11 Pro                    |
+------------------------------------------------------------------+
 touch and hold [screen] starts the flow
```

```
+------------------+------------------------------------------------------+
| Argus RM         | web-03 - Argus RM                                    |
+------------------+------------------------------------------------------+
| Dashboard        |                                                      |
| Assets           |                                                      |
| RDP              |                                                      |
| Distributables   |              web-03 desktop                          |
| Tasks            |                                                      |
| Monitoring       |                                                      |
| Scripts          |                                                      |
| Repositories     |                                                      |
|                  |                                                      |
|                  +------------------------------------------------------+
|                  | [ web-03  x ] [ db-01  x ]                      [key]|
| Agents           |                                                      |
| Settings         |                                                      |
+------------------+------------------------------------------------------+
```

Edits are **Remove** / **Replace with** / **Add** from the tree. Verify the surrounding lines before applying.

### 1. `controller/store/MachineGeneral.vala` — `desktop` and `hostname`

**Why:** The button is shown only when this machine's `OsVersion.supports_rdp()` is true. The tab title is the hostname. An empty hostname uses `computer_name`.

**Where:** the `loaded_agent` field, the agent change at the start of `load`, and `load_section` after an empty row list returns.

**Depends on:** none.

#### Remove

```vala
		private int loaded_agent = -1;
```

#### Replace with

```vala
		public int loaded_agent { get; private set; default = -1; }
		public bool desktop { get; private set; default = false; }
		public string hostname { get; private set; default = ""; }
```

#### Remove

```vala
			if (agent_id != this.loaded_agent && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<KeyValue>();
			}
```

#### Replace with

```vala
			if (agent_id != this.loaded_agent) {
				this.desktop = false;
				this.hostname = "";
				if (this.items_store.size > 0) {
					this.items = new Gee.ArrayList<KeyValue>();
				}
			}
```

#### Add — in `load_section`, after the empty-row return, before the column loop

An `os_version` row sets `desktop`. A `system_info` row sets `hostname`.

```vala
			if (source == "os_version") {
				var version = (Argus.Shared.OSQuery.OsVersion) rows.get(0);
				this.desktop = version.supports_rdp();
			}
			if (source == "system_info") {
				var info = (Argus.Shared.OSQuery.SystemInfo) rows.get(0);
				this.hostname = info.hostname;
				if (this.hostname == "") {
					this.hostname = info.computer_name;
				}
			}
```

### 2. `controller/tab/Asset/Machine/General.vala` — the screen button

**Why:** Touch and hold calls `start_desktop` and opens the RDP page. A short press does not. The button sits in the page bar, and it is shown only when `desktop` is true.

**Where:** a field for the window, the start of the constructor, and the bar appended before the list.

**Depends on:** ### 1 and ### 4.

#### Add — field, after `list`

```vala
		private Argus.Controller.Window window;
```

#### Add — first line of the constructor body, after `Object(...)`

```vala
			this.window = window;
```

#### Remove

```vala
			this.append(overlay);
```

#### Replace with

```vala
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 4,
				visible = false
			};
			var screen = new Argus.Controller.Widget.HoldButton() {
				icon_name = "video-display-symbolic",
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER
			};
			screen.confirmed.connect(() => {
				var agent_id = this.store.loaded_agent;
				var name = this.store.hostname;
				this.window.open_desktop(agent_id, name);
				this.store.start_desktop();
			});
			bar.append(screen);
			this.store.notify["desktop"].connect(() => {
				bar.visible = this.store.desktop;
			});
			this.append(bar);
			this.append(overlay);
```

### 3. `controller/TabList.vala` — the RDP row

**Why:** The row sits under Assets while a session tab exists, and it goes when the last tab is gone. Selecting it shows the RDP page. Hiding it while it is selected returns to Assets.

**Where:** `places` keeps the list that is local today. `show_rdp` and `hide_rdp` are new methods before the class closing brace.

**Depends on:** none.

#### Remove

```vala
			var list = new Gtk.ListBox() {
```

#### Replace with

```vala
			this.places = new Gtk.ListBox() {
```

#### Add — immediately after that initializer's `};`

The rest of the constructor keeps the name `list`.

```vala
			var list = this.places;
```

#### Add — fields, next to `titles`

```vala
		private Gtk.ListBox places;
		private Gtk.ListBoxRow? rdp_row;
```

#### Add — `show_rdp` and `hide_rdp`, before the class closing brace

`show_rdp` inserts the row after Assets and selects it. `hide_rdp` removes it. Phase 6's last X is what calls `hide_rdp`.

```vala
		/**
		 * Show RDP under Assets and select it.
		 *
		 * A row that is already there is only selected.
		 */
		public void show_rdp()
		{
			if (this.rdp_row != null) {
				this.places.select_row(this.rdp_row);
				return;
			}
			var row = new Gtk.ListBoxRow();
			row.child = new Gtk.Label("RDP") {
				xalign = 0,
				margin_top = 6,
				margin_bottom = 6,
				margin_start = 12,
				margin_end = 12
			};
			row.name = "rdp";
			this.places.insert(row, 2);
			this.rdp_row = row;
			this.places.select_row(row);
		}

		/**
		 * Remove the RDP row.
		 *
		 * When that row was selected, Assets is selected.
		 */
		public void hide_rdp()
		{
			if (this.rdp_row == null) {
				return;
			}
			var selected = this.places.get_selected_row() == this.rdp_row;
			var row = this.rdp_row;
			this.rdp_row = null;
			this.places.remove(row);
			if (!selected) {
				return;
			}
			this.places.select_row(this.places.get_row_at_index(1));
		}
```

### 4. `controller/Window.vala` — the page and the host

**Why:** The hold switches this window to the RDP page. The second connection dials the host that answered. The page is added once, named `rdp`.

**Where:** `host`, `tabs`, `pages`, and `rdp` are fields. The constructor stores the host and the two locals. `open_desktop` is a new method after `check_connection`.

**Depends on:** ### 3 and ### 7.

#### Add — fields, after `issued`

```vala
		public string host { get; set; default = ""; }
		private TabList tabs;
		private Gtk.Stack pages;
		private Tab.Rdp rdp;
```

#### Remove

```vala
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued
		) {
			this.app = app;
			this.connection = connection;
			this.issued = issued;
```

#### Replace with

```vala
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued,
			string host
		) {
			this.app = app;
			this.connection = connection;
			this.issued = issued;
			this.host = host;
```

#### Remove

```vala
			var tabs = new TabList();
```

#### Replace with

```vala
			this.tabs = new TabList();
			var tabs = this.tabs;
```

#### Remove

```vala
			var pages = new Gtk.Stack() {
```

#### Replace with

```vala
			this.pages = new Gtk.Stack() {
```

#### Add — immediately after that initializer's `};`

```vala
			var pages = this.pages;
```

#### Add — after `pages.add_named(new Tab.Settings(this), "settings");`

```vala
			this.rdp = new Tab.Rdp(this);
			pages.add_named(this.rdp, "rdp");
```

#### Add — after `check_connection`, before the class closing brace

```vala
		/**
		 * Open this machine on the RDP page.
		 *
		 * A machine that already has a tab is selected.
		 * A new machine adds a tab. The sidebar row is shown.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 * @param name tab title, the hostname
		 */
		public void open_desktop(int agent_id, string name)
		{
			this.rdp.open(agent_id, name);
			this.tabs.show_rdp();
		}
```

### 5. `controller/android/Window.vala` — the same page

**Why:** Android uses this same RDP page. `open` is where the desktop window's constructor builds the pages.

**Where:** the same fields. `open` gains `host`. The page is added in `open`, and `open_desktop` matches ### 4.

**Depends on:** ### 4.

#### Add — fields, after `issued`

```vala
		public string host { get; set; default = ""; }
		private TabList tabs;
		private Gtk.Stack pages;
		private Tab.Rdp rdp;
```

#### Remove

```vala
		public void open(
			Connection connection,
			Argus.Shared.Registration.Data issued
		) {
```

#### Replace with

```vala
		public void open(
			Connection connection,
			Argus.Shared.Registration.Data issued,
			string host
		) {
```

#### Add — in `open`, after `this.issued = issued;`

```vala
			this.host = host;
```

#### Remove

```vala
			var tabs = new TabList();
```

#### Replace with

```vala
			this.tabs = new TabList();
			var tabs = this.tabs;
```

#### Remove

```vala
			var pages = new Gtk.Stack() {
```

#### Replace with

```vala
			this.pages = new Gtk.Stack() {
```

#### Add — immediately after that initializer's `};`

```vala
			var pages = this.pages;
```

#### Add — after `pages.add_named(new Tab.Settings(this), "settings");`

```vala
			this.rdp = new Tab.Rdp(this);
			pages.add_named(this.rdp, "rdp");
```

#### Add — `open_desktop`, the same method as ### 4, before the class closing brace

### 6. `controller/dialog/Bootstrap.vala` — pass the host that answered

**Why:** `use` already has that host. The window needs it for the second connection.

**Where:** the two places that open the window, inside the connect callback in `use`.

**Depends on:** ### 4 and ### 5.

#### Remove

```vala
				app.window.open(connection, issued);
```

#### Replace with

```vala
				app.window.open(connection, issued, host);
```

#### Remove

```vala
				var window = new Window(app, connection, issued);
```

#### Replace with

```vala
				var window = new Window(app, connection, issued, host);
```

### 7. `controller/tab/Rdp.vala` — the page

**Why:** One page holds every machine's picture. The selected tab is the picture in front. A second machine adds a tab. `relay.ready` starts that machine's FreeRDP. `drop` removes a tab and hides the row when none remain. Phase 6's X calls `drop`.

**Where:** new file. The copyright comment is the one on `controller/Rdp/Viewer.vala`.

**Depends on:** ### 4 and ### 9.

#### Add — new file `controller/tab/Rdp.vala`

```vala
namespace Argus.Controller.Tab
{
	/**
	 * Remote desktops for this window.
	 *
	 * One tab per machine. The selected tab is the picture
	 * in front. {@link Argus.Controller.Rdp.Screen} paints it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * rdp.open(4, "web-03");
	 * }}}
	 */
	public class Rdp : Gtk.Box
	{
		private Argus.Controller.Window window;
		private Gtk.Stack pictures;
		private Adw.ToggleGroup group;
		private Gee.HashMap<int, Argus.Controller.Rdp.Screen> screens;

		/**
		 * Build the picture stack and the tab bar.
		 *
		 * @param window the window this page belongs to
		 */
		public Rdp(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.screens = new Gee.HashMap<int, Argus.Controller.Rdp.Screen>();
			this.pictures = new Gtk.Stack() {
				hexpand = true,
				vexpand = true
			};
			this.group = new Adw.ToggleGroup() {
				orientation = Gtk.Orientation.HORIZONTAL,
				hexpand = true
			};
			this.group.notify["active-name"].connect(() => {
				var name = this.group.active_name;
				if (name == null || name == "") {
					return;
				}
				this.pictures.visible_child_name = name;
			});
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				css_classes = { "machines-filter" },
				margin_start = 12,
				margin_end = 12,
				margin_top = 4,
				margin_bottom = 8
			};
			bar.append(this.group);
			this.append(this.pictures);
			this.append(bar);
			this.window.app.rpc.notification.connect((notification) => {
				if (notification.method != "relay.ready" || notification.args.size < 1) {
					return;
				}
				var agent_id = notification.args.get(0).get_int();
				if (!this.screens.has_key(agent_id)) {
					return;
				}
				var screen = this.screens.get(agent_id);
				if (screen.started) {
					return;
				}
				screen.started = true;
				screen.begin();
			});
		}

		/**
		 * Select this machine, or add its tab.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 * @param name tab title
		 */
		public void open(int agent_id, string name)
		{
			var key = agent_id.to_string();
			if (this.screens.has_key(agent_id)) {
				this.group.active_name = key;
				return;
			}
			var screen = new Argus.Controller.Rdp.Screen(this.window, agent_id);
			this.screens.set(agent_id, screen);
			this.pictures.add_named(screen.picture, key);
			this.group.add(new Adw.Toggle() {
				name = key,
				label = name
			});
			this.group.active_name = key;
		}

		/**
		 * Remove one machine's tab.
		 *
		 * The local picture stops. The last tab hides the RDP row.
		 * Phase 6's X calls this. Letting go of the Windows session
		 * is that phase.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void drop(int agent_id)
		{
			if (!this.screens.has_key(agent_id)) {
				return;
			}
			var screen = this.screens.get(agent_id);
			this.screens.unset(agent_id);
			screen.stop();
			var key = agent_id.to_string();
			var child = this.pictures.get_child_by_name(key);
			if (child != null) {
				this.pictures.remove(child);
			}
			var toggle = this.group.get_toggle_by_name(key);
			if (toggle != null) {
				this.group.remove(toggle);
			}
			if (this.screens.size > 0) {
				return;
			}
			this.window.tabs_hide_rdp();
		}
	}
}
```

`Window.tabs_hide_rdp` is the one-line call, on both window classes, next to `open_desktop`:

```vala
		/**
		 * Hide the RDP row. {@link Tab.Rdp.drop} calls this
		 * when the last tab is gone.
		 */
		public void tabs_hide_rdp()
		{
			this.tabs.hide_rdp();
		}
```

### 8. `controller/Rdp/Viewer.vala` — `serve`

**Why:** The product listens on loopback and splices that socket to `Relay.view`. `run` stays the test. This path does not exit the process. `watch` runs on the caller, which is the GTK thread. `view` is the thread. Each call that throws has its own try.

**Where:** `view_port`, `rpc`, and `plain` are fields. `serve` is a new method after `carry`. `view` is the next method.

**Depends on:** none.

#### Add — fields, after the class opening

```vala
		public uint16 view_port { get; private set; }
		private OLLMrpc.Transport.TlsClient rpc;
		private GLib.SocketConnection? plain;
```

#### Add — after `carry`, the product splice

`plain` is null until FreeRDP connects. `relay.data` before that is dropped. Windows sends nothing until it has the client's opening bytes.

```vala
		/**
		 * Listen on loopback and carry that socket to one agent.
		 *
		 * {@link view_port} is set before this returns. FreeRDP
		 * connects there. ''Relay.view'' is the join. ''run'' is
		 * the test and is not this method.
		 *
		 * @param host server that answered
		 * @param port server port
		 * @param certificate this controller's certificate
		 * @param database the server CA
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void serve(
			string host,
			uint16 port,
			GLib.TlsCertificate certificate,
			GLib.TlsDatabase database,
			int agent_id
		) throws GLib.Error
		{
			var listener = new GLib.SocketListener();
			var where = new GLib.InetSocketAddress(
				new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0);
			GLib.SocketAddress? bound = null;
			listener.add_address(
				where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, out bound);
			this.view_port = ((GLib.InetSocketAddress) bound).get_port();
			this.rpc = new OLLMrpc.Transport.TlsClient(host, port) {
				tls_certificate = certificate,
				tls_database = database
			};
			this.rpc.timeout = 5;
			this.rpc.notification.connect((notif) => {
				if (notif.method != "relay.data" || notif.args.size < 1 || this.plain == null) {
					return;
				}
				var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
				unowned uint8[] data = blob.get_data();
				if (data == null) {
					return;
				}
				size_t off = 0;
				while (off < data.length) {
					try {
						off += this.plain.output_stream.write(data[off:data.length]);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						return;
					}
				}
			});
			this.rpc.watch();
			new GLib.Thread<int>("view", () => {
				this.view(listener, agent_id);
				return 0;
			});
		}

		/**
		 * Join one agent and copy until that socket closes.
		 *
		 * This is the view thread. ''Relay.view'', the accept,
		 * the read, and ''Relay.write'' each have their own try.
		 *
		 * @param listener the loopback listen
		 * @param agent_id ''agent.id'' of the machine
		 */
		private void view(GLib.SocketListener listener, int agent_id)
		{
			OLLMrpc.Response joined;
			try {
				joined = this.rpc.call(new OLLMrpc.Request() {
					method = "Relay.view",
					args = OLLMrpc.args("i", agent_id)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			if (joined.error != null) {
				GLib.warning("%s", joined.error.message);
				return;
			}
			try {
				this.plain = listener.accept(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			try {
				this.plain.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			var buf = new uint8[16384];
			while (true) {
				ssize_t n = 0;
				try {
					n = this.plain.input_stream.read(buf);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				if (n <= 0) {
					return;
				}
				var chunk = new uint8[n];
				GLib.Memory.copy((uint8[]) chunk, buf, n);
				var held = GLib.Value(typeof(GLib.Bytes));
				held.set_boxed(new GLib.Bytes(chunk));
				var request = new OLLMrpc.Request() {
					method = "Relay.write"
				};
				request.args.add(held);
				OLLMrpc.Response response;
				try {
					response = this.rpc.call(request);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return;
				}
				if (response.error != null) {
					GLib.warning("%s", response.error.message);
					return;
				}
			}
		}
```

### 9. `controller/Rdp/Screen.vala` — paint with FreeRDP

**Why:** FreeRDP connects to the loopback port and asks for the Windows user and password. Drive redirection, clipboard, and audio stay off. The GDI buffer is copied onto the picture. The Windows certificate is accepted because the dial is `127.0.0.1`.

**Where:** new file. The copyright comment is the one on `controller/Rdp/Viewer.vala`.

**Depends on:** ### 8 and ### 10.

#### Add — new file `controller/Rdp/Screen.vala`

```vala
namespace Argus.Controller.Rdp
{
	/**
	 * One machine's picture.
	 *
	 * FreeRDP dials the loopback port {@link Viewer} is reading.
	 * {@link begin} runs after ''relay.ready''. The password
	 * dialog is FreeRDP's authenticate callback.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var screen = new Argus.Controller.Rdp.Screen(window, 4);
	 * screen.begin();
	 * }}}
	 */
	public class Screen : GLib.Object
	{
		/**
		 * The picture for this machine.
		 */
		public Gtk.Picture picture { get; private set; }
		/**
		 * True after ''relay.ready'' has started this picture.
		 */
		public bool started = false;
		private static Gee.ArrayList<Screen> live = new Gee.ArrayList<Screen>();
		private Argus.Controller.Window window;
		private int agent_id;
		private FreeRDP.Instance? instance;
		private string user = "";
		private string pass = "";

		/**
		 * @param window the window that owns the certificate
		 * @param agent_id ''agent.id'' of the machine
		 */
		public Screen(Argus.Controller.Window window, int agent_id)
		{
			this.window = window;
			this.agent_id = agent_id;
			this.picture = new Gtk.Picture() {
				hexpand = true,
				vexpand = true,
				can_shrink = true,
				content_fit = Gtk.ContentFit.CONTAIN
			};
		}

		/**
		 * Open the splice and run FreeRDP on its own thread.
		 */
		public void begin()
		{
			var pem = this.window.issued.client_certificate + "\n" + this.window.issued.private_key;
			GLib.TlsCertificate certificate;
			GLib.TlsDatabase trust;
			try {
				certificate = new GLib.TlsCertificate.from_pem(pem, pem.length);
#if ANDROID
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(), "argusrm");
#else
				var dir = GLib.Environment.get_user_runtime_dir();
#endif
				trust = GLib.TlsFileDatabase.new(
					GLib.Path.build_filename(dir, "argusrm-ca.pem"));
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			var viewer = new Viewer();
			try {
				viewer.serve(
					this.window.host,
					(uint16) this.window.connection.port,
					certificate,
					trust,
					this.agent_id);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return;
			}
			this.instance = new FreeRDP.Instance();
			if (!this.instance.context_new()) {
				GLib.warning("desktop context");
				return;
			}
			this.instance.PostConnect = Screen.connected;
			this.instance.Authenticate = Screen.authenticate;
			this.instance.VerifyCertificateEx = Screen.verify;
			Screen.live.add(this);
			unowned FreeRDP.Settings settings = this.instance.context.settings;
			settings.set_string(FreeRDP.SettingsString.ServerHostname, "127.0.0.1");
			settings.set_uint32(FreeRDP.SettingsUint32.ServerPort, viewer.view_port);
			var width = this.picture.get_width();
			var height = this.picture.get_height();
			if (width < 64) {
				width = 1280;
			}
			if (height < 64) {
				height = 720;
			}
			settings.set_uint32(FreeRDP.SettingsUint32.DesktopWidth, width);
			settings.set_uint32(FreeRDP.SettingsUint32.DesktopHeight, height);
			settings.set_uint32(FreeRDP.SettingsUint32.ColorDepth, 32);
			settings.set_bool(FreeRDP.SettingsBool.RedirectDrives, false);
			settings.set_bool(FreeRDP.SettingsBool.AudioPlayback, false);
			settings.set_bool(FreeRDP.SettingsBool.RedirectClipboard, false);
			new GLib.Thread<int>("screen", () => {
				if (!this.instance.connect()) {
					GLib.warning("desktop connect failed");
					return 0;
				}
				while (!this.instance.shall_disconnect()) {
					if (!FreeRDP.check_event_handles(this.instance.context)) {
						break;
					}
					this.publish();
				}
				return 0;
			});
		}

		/**
		 * Stop this picture. {@link Argus.Controller.Tab.Rdp.drop}
		 * calls this.
		 */
		public void stop()
		{
			Screen.live.remove(this);
			if (this.instance == null) {
				return;
			}
			this.instance.disconnect();
			FreeRDP.gdi_free(this.instance);
			this.instance.context_free();
			this.instance = null;
		}

		private void publish()
		{
			unowned FreeRDP.Gdi? gdi = this.instance.context.gdi;
			if (gdi == null || gdi.width < 1 || gdi.height < 1) {
				return;
			}
			var width = gdi.width;
			var height = gdi.height;
			var stride = (int) gdi.stride;
			var size = stride * height;
			var copy = new uint8[size];
			GLib.Memory.copy((void*) copy, gdi.primary_buffer, size);
			var bytes = new GLib.Bytes(copy);
			GLib.Idle.add(() => {
				var texture = new Gdk.MemoryTexture(
					width, height, Gdk.MemoryFormat.B8G8R8A8, bytes, (uint) stride);
				this.picture.set_paintable(texture);
				return false;
			});
		}

		/**
		 * Ask for the Windows user and password.
		 *
		 * The FreeRDP thread waits. The dialog runs on the GTK thread.
		 *
		 * @return true when both fields are filled
		 */
		private bool prompt()
		{
			var user_entry = new Gtk.Entry() {
				placeholder_text = "User"
			};
			var pass_entry = new Gtk.PasswordEntry();
			var form = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
			form.append(user_entry);
			form.append(pass_entry);
			var dialog = new Adw.AlertDialog("Windows sign-in", null);
			dialog.extra_child = form;
			dialog.add_response("cancel", "Cancel");
			dialog.add_response("ok", "Sign in");
			dialog.default_response = "ok";
			dialog.close_response = "cancel";
			bool ok = false;
			bool done = false;
			var mutex = GLib.Mutex();
			var cond = GLib.Cond();
			GLib.Idle.add(() => {
				dialog.response.connect((response) => {
					mutex.lock();
					if (response == "ok") {
						this.user = user_entry.text;
						this.pass = pass_entry.text;
						ok = this.user != "" && this.pass != "";
					}
					done = true;
					cond.signal();
					mutex.unlock();
				});
				dialog.present(this.picture);
				return false;
			});
			mutex.lock();
			while (!done) {
				cond.wait(mutex);
			}
			mutex.unlock();
			return ok;
		}

		private static Screen? find(FreeRDP.Instance instance)
		{
			foreach (var screen in Screen.live) {
				if (screen.instance == instance) {
					return screen;
				}
			}
			return null;
		}

		private static bool connected(FreeRDP.Instance instance)
		{
			return FreeRDP.gdi_init(instance, FreeRDP.PIXEL_FORMAT_BGRA32);
		}

		private static bool authenticate(
			FreeRDP.Instance instance,
			out string username,
			out string password,
			out string domain)
		{
			username = "";
			password = "";
			domain = "";
			var screen = Screen.find(instance);
			if (screen == null || !screen.prompt()) {
				return false;
			}
			username = screen.user;
			password = screen.pass;
			return true;
		}

		private static uint32 verify(
			FreeRDP.Instance instance,
			string host,
			uint16 port,
			string common_name,
			string subject,
			string issuer,
			string fingerprint,
			uint32 flags)
		{
			return 1;
		}
	}
}
```

### 10. `server/vapi/freerdp.vapi` — the client

**Why:** The vapi is the server listener. The picture needs the client, the GDI buffer, and the authenticate callback. Names are the FreeRDP 3 calls. A header that disagrees is fixed here before the picture is built.

**Where:** more settings keys, `set_string`, and the client types before the `WinPr` namespace.

**Depends on:** none.

#### Add — on `SettingsBool`, after `NSCodec`

```vala
		RedirectDrives,
		AudioPlayback,
		RedirectClipboard,
```

#### Add — on `SettingsUint32`, after `ColorDepth`

```vala
		ServerPort,
		DesktopWidth,
		DesktopHeight,
```

#### Add — after the `SettingsUint32` enum

```vala
	[CCode (cprefix = "FreeRDP_", has_type_id = false, cheader_filename = "freerdp/settings_keys.h")]
	public enum SettingsString
	{
		ServerHostname,
		Username,
		Password,
		Domain
	}
```

#### Add — on `Settings`, after `set_pointer`

```vala
		[CCode (cname = "freerdp_settings_set_string")]
		public bool set_string (SettingsString key, string value);
```

#### Add — on `Context`, after `settings`

```vala
		public unowned Instance instance;
		public unowned Gdi? gdi;
```

#### Add — before the `WinPr` namespace

```vala
	[CCode (cname = "PIXEL_FORMAT_BGRA32", cheader_filename = "freerdp/codec/color.h")]
	public const uint32 PIXEL_FORMAT_BGRA32;

	[Compact]
	[CCode (cname = "rdpGdi", cheader_filename = "freerdp/gdi/gdi.h")]
	public class Gdi
	{
		public int width;
		public int height;
		public uint32 stride;
		public void *primary_buffer;
	}

	[CCode (has_target = false, cname = "pPostConnect")]
	public delegate bool PostConnect (Instance instance);

	[CCode (has_target = false, cname = "pAuthenticate")]
	public delegate bool Authenticate (
		Instance instance,
		[CCode (type = "char**")] out string username,
		[CCode (type = "char**")] out string password,
		[CCode (type = "char**")] out string domain);

	[CCode (has_target = false, cname = "pVerifyCertificateEx")]
	public delegate uint32 VerifyCertificateEx (
		Instance instance,
		string host,
		uint16 port,
		string common_name,
		string subject,
		string issuer,
		string fingerprint,
		uint32 flags);

	[Compact]
	[CCode (cname = "freerdp", free_function = "freerdp_free", cheader_filename = "freerdp/freerdp.h")]
	public class Instance
	{
		[CCode (cname = "freerdp_new")]
		public Instance ();

		public unowned Context context;
		public PostConnect PostConnect;
		public Authenticate Authenticate;
		public VerifyCertificateEx VerifyCertificateEx;

		[CCode (cname = "freerdp_context_new")]
		public bool context_new ();

		[CCode (cname = "freerdp_context_free")]
		public void context_free ();

		[CCode (cname = "freerdp_connect")]
		public bool connect ();

		[CCode (cname = "freerdp_disconnect")]
		public bool disconnect ();

		[CCode (cname = "freerdp_shall_disconnect")]
		public bool shall_disconnect ();
	}

	[CCode (cname = "freerdp_check_event_handles")]
	public bool check_event_handles (Context context);

	[CCode (cname = "gdi_init", cheader_filename = "freerdp/gdi/gdi.h")]
	public bool gdi_init (Instance instance, uint32 format);

	[CCode (cname = "gdi_free", cheader_filename = "freerdp/gdi/gdi.h")]
	public void gdi_free (Instance instance);
```

### 11. `controller/meson.build` and `docs/meson.build` — compile the picture

**Why:** `Viewer.vala` is only in the test binary today. The controller compiles it, the picture, and the page, and links FreeRDP.

**Where:** `deps` and `controller_vala_args` in `controller/meson.build`, the `sources` list, and the same files plus `--pkg=freerdp` in `docs/meson.build`.

**Depends on:** ### 9.

#### Add — `controller/meson.build`, after `deps += shared_dep`

```meson
dependency('freerdp3')
dependency('winpr3')
pkgconfig = find_program('pkg-config')
freerdp_cflags = run_command(pkgconfig, '--cflags', 'freerdp3', check: true).stdout().split()
freerdp_libs = run_command(pkgconfig, '--libs', 'freerdp3', check: true).stdout().split()
winpr_cflags = run_command(pkgconfig, '--cflags', 'winpr3', check: true).stdout().split()
winpr_libs = run_command(pkgconfig, '--libs', 'winpr3', check: true).stdout().split()
deps += declare_dependency(
	compile_args: freerdp_cflags + winpr_cflags,
	link_args: freerdp_libs + winpr_libs,
)
controller_vala_args += [
	'--vapidir', meson.project_source_root() / 'server' / 'vapi',
	'--pkg', 'freerdp',
]
```

#### Add — `controller/meson.build`, in `sources`, after `'TabList.vala',`

```meson
	'Rdp/Viewer.vala',
	'Rdp/Screen.vala',
	'tab/Rdp.vala',
```

#### Add — `docs/meson.build`, after `'../controller/TabList.vala',`

```meson
  '../controller/Rdp/Viewer.vala',
  '../controller/Rdp/Screen.vala',
  '../controller/tab/Rdp.vala',
```

#### Add — `docs/meson.build`, in the valadoc `command`, after `'--pkg=libadwaita-1',`

```meson
    '--pkg=freerdp',
```

---

## Phase 6 — Session tabs

- 🔷 The page is the desktop of the selected tab. The bottom bar is the session tabs and a key button.
- 🔷 The selected tab is the live feed. The agent sends for that session and the server forwards it.
- 🔷 A tab that is not selected gets no live feed. The agent keeps that Windows session and drops the bytes.
- 🔷 Selecting a quiet tab starts its feed. The tab that was showing goes quiet.
- 🔷 The X on a tab disconnects that session and removes the tab. The agent lets go of that RDP session. The last X removes the RDP row.
- 🔷 The key button sends keys into the desktop that is showing.
- 🚫 A list of RDP connections.
- 🚫 A frame bar with Send keys, Close connection, and an X that leaves the desktop running. The window header stays the title.

---

## Phase 6.5 — Takeover edges

- ℹ️ The stream is in the tree. This phase does not repeat it.
- ⏳ 🔷 When someone is at the keyboard, the tray asks before Remote Desktop is turned on. Half an hour idle allows it without asking. A click allows it. Ignoring the balloon leaves it off.
- ⏳ 🔷 The server tells the controller that this desktop is waiting for that authorization. The RDP page says so. It does not stay blank.
- ⏳ 🔷 Force is off unless the operator turns it on.
- ⏳ 🔷 The tray names who from Argus has the screen, and offers Disconnect.
- ℹ️ While a connection is up the PC screen is locked. Signing in at the PC disconnects the remote side. Windows does that. It does not say the Argus name.

---

## Phase 7 — Linux desktops

- 💩 ⏳ After Windows works. GNOME Remote Desktop and xrdp speak this protocol, so the same stream could reach them. Nothing in Phases 2–6 turns a Linux service on.

---

## Attempts / changelog

- ✔️ 2026-11-17: First probe was a C Gio TLS splice under `/tmp`. Rejected. The proof has to be Vala and has to use `OLLMrpc.Transport.TlsClient` and `OLLMrpc.Transport.Connection`.
- ✔️ 2026-11-17: The probe moved into the repo test tree. `server/vapi/freerdp.vapi` replaced the C desk. `server/tests/rdp-desk.c` is gone.
- ✔️ 2026-11-17: The desk, the tunnel, the relay, and the viewer are separate classes. `server/tests/rdp-relay.vala` only starts them and waits for `ACTIVATED`. `meson test -C build rdp-relay` passed.
- ✔️ 2026-11-17: "The Android controller does not get this button" was an inference. It is removed. Android shows the viewer in the same window, with navigation back to the main page.
- ✔️ 2026-11-17: The spec is split into phases. Each phase holds the requirements for that slice.
- ✔️ 2026-11-18: A second listen was an assumption, not a result. The design is another connection to the port already listening. Phase 5 is the parked desktop: the X stops streaming, Close connection drops the session, and **RDP connections** under Assets opens it again.
- ✔️ 2026-11-18: `App.ping` on the first connection kept replying after the second connection joined the stream. The test prints `ok app rpc during stream`.
- ✔️ 2026-11-18: The controller message starts the flow. The server notifies the agent, and that notification is what makes the agent open the second connection. This is Phase 4, before the viewer. The test does not do it.
- ✔️ 2026-11-18: `SslListen.by_id` is the connection for one agent id. `Command.dispatch`, `Agent.list`, `Agent.remove`, and the task list use it. `broadcast` still walks `connections` because that send goes to every connection.
- ✔️ 2026-11-18: Phase 2 fences now include the `join()` and `write()` bodies. `write()` in that fence does not use a ternary. The fences are not applied.
- ✔️ 2026-11-18: Phase 2 fences are applied. `Application.command_line` calls `Rdp.Relay.rpc_register()`. `Relay.join` and `Relay.write` are in `docs/rpc-commands.md`. `listen()` is still only the test.
- ✔️ 2026-11-18: Phase 2 fences are removed from this bug. Phase 3 proposes `OsVersion.supports_rdp()`. Unknown and Home are not offered. A client edition has no supported second session. The service is not changed.
- ✔️ 2026-11-18: Connect when nobody is logged in, or when the screen is locked or idle, as that same user. If someone is at the PC, the tray asks first. Force is off unless the operator turns it on. A different account logs them off.
- ✔️ 2026-11-18: The tray names who has the screen and can disconnect. The person at the locked PC gets the screen back by signing in. Windows does that itself.
- ✔️ 2026-11-18: `OsVersion.supports_rdp()` is in. After startup the Windows agent turns Remote Desktop on only when that is true, and leaves the password prompt on. Home and an unknown name do nothing. The button and the tray ask are not built.
- ✔️ 2026-11-18: An active Windows session means someone is logged in. The tray asks before Remote Desktop is turned on. Allow turns it on. No leaves it off. Nobody logged in skips the question. Force, Disconnect, and the connection are not built. Lock versus a person at the keyboard is not detected.
- ✔️ 2026-11-18: The tray allows Remote Desktop without asking when the keyboard and mouse have been idle for half an hour. The service cannot see that time.
- ✔️ 2026-11-18: When the agent streams, the server tells the controller and drops the bytes until the controller connects. A late controller gets a new connection from the first byte. The server does not parse Remote Desktop.
- ✔️ 2026-11-18: The tray ask is a balloon, the same call Snappr uses. A click allows Remote Desktop. Ignoring the balloon leaves it off.
- 🔷 2026-11-18: Phase 4 rules are signed off. The stream is not built. Building it, Force, and the Disconnect notice are Phase 6.5.
- ✔️ 2026-11-18: Those rules had been marked ✅. ✅ is work verified on a machine. The stream is not built, so the rules stay 🔷. The viewer is one RDP page under Assets. Session tabs sit on the bottom bar. The selected tab is the live feed. The X on a tab disconnects it.
- 🔷 2026-11-18: The starter is a screen button on the General tab of a Windows machine. Touch and hold starts the flow. A short press does not.
- 🔷 2026-11-18: Phase 4's stream proposal is in this bug. `Relay.start` asks the agent. The agent dials Windows on `127.0.0.1:3389` once Remote Desktop is on. Bytes are dropped until `Relay.view`. A late view waits for `Relay.fresh` after `relay.cut`. The screen button is still Phase 5.
- 🔷 2026-11-18: The desktop thread is the `while`. `Tunnel.handle_stream` reads one chunk. `buf` is a property, allocated in that thread. `MachineGeneral.start_desktop` is the controller ask.
- ✔️ 2026-11-18: Phase 4 is in the tree. `Relay.start` asks the agent. The Windows agent dials `127.0.0.1:3389` once Remote Desktop is on. The screen button is still Phase 5.
- ✔️ 2026-11-18: The relay and the tunnel have one body. A connection that is not a server connection stays the single test pair. The service opens the second connection and passes it to the tunnel.
- ✔️ 2026-11-18: `Seat` is its own class. It remembers the ask, answers `relay.ready`, attaches a view, holds a late view, releases that view, and forwards one chunk. `Relay` still checks the controller and finds the agent connection.
- ✔️ 2026-11-18: `relay.cut` with no tunnel opens the stream. An open tunnel is closed so the read dials Windows again. That sits in the notification. `Service.tunnel` is visible to it.
- 🔷 2026-11-18: The screen button sits at the top of General, where the other machine tabs put their search field. General has no search.
- ✔️ 2026-11-18: Phase 4's proposed code is removed. The stream is in the tree. Phase 5's proposed code is the screen button, the RDP page, and the FreeRDP picture.
- ✔️ 2026-11-18: Phase 5 is in the tree. The screen button, `controller/tab/Rdp.vala`, `Viewer.serve` / `Viewer.view`, and `controller/Rdp/Screen.vala` match the proposal. `freerdp3` and `winpr3` are linked from `controller/meson.build`. The `controller_vala_args +=` sits after that list is assigned.
- ✔️ 2026-11-18: `ninja -C build controller/argusrm-controller` linked. Meson must not pass `--pkg freerdp3` or `--pkg winpr3` to valac. Those packages have no vapi. The link uses `pkg-config --cflags` and `--libs`, and valac uses `--pkg freerdp`. `context.settings` and `context.gdi` are `unowned`. `gdi` is nullable.
- ✔️ 2026-11-18: `server.log` at 18:06: `Relay.start` from the controller, then `no handler for 'Relay'`. The running `argusrm-server` started 17 Nov 17:38. The binary on disk is 18 Nov 18:04. The desktop never left the controller.
- ✔️ 2026-11-18: After the server restart, `Relay.start` at 18:16 has no handler error. The Windows agent exe is still 17 Nov 17:29, 1175091 bytes. Its log at 18:16:11 is `name-ref token 21 alias mismatch`. `ArgusAgent-0.1.27-Setup.exe` is in `C:\msys64\tmp\argusrm\dist-windows` and is not installed.
- ✔️ 2026-11-18: After installing 0.1.27, `argus-agent.exe` and `argus-tray.exe` are 18:24, 1198463 bytes. At 18:30:10 the server received `Relay.start` and the agent logged `relay.start`. There is no `AgentService.allow`, no `Relay.join`, and no `relay.ready`. Windows 10 Pro, `fDenyTSConnections` is 0, and TermService is running. The picture waits for `relay.ready`.
- ✔️ 2026-11-19: The tray ask is what stopped that stream. `initialize` turns Remote Desktop on without sending `agent.desktop`. The ask, and telling the controller that the page is waiting for authorization, are Phase 6.5.
- ✔️ 2026-11-19: `meson test -C build rdp-seat` passes. A TLS listener accepts controller, agent, and view connections. `Seat.joined` sends `relay.ready 42` to the controller. `Seat.attach` + `Seat.forward` sends `relay.data 5` to the view. This is the notification flow without `SslConnection` or the database.
- ✔️ 2026-11-19: After 0.1.29, the server received `Relay.start` at 12:14:23 with no `name-ref` error. The agent log has no `relay.start`. The agent dropped at 12:14:09 and reconnected at 12:14:26 — three seconds after `Relay.start`. `by_id.get` returned null, the server replied "unknown agent", and the controller showed a grey screen. The agent was not connected when the button was pressed. That gap is not the tick-on Waiting case; see 2026-11-19-CLOSED-desktop-status-and-reconnect.md.
- ✔️ 2026-11-19: `MachineGeneral.start_desktop` only caught `GLib.Error` (transport), not `response.error`. Every other `call.end` in the controller checks `response.error`. The call now returns false on that error, the notice uses `failed`, and the desktop page opens only after a successful reply.
- ✔️ 2026-11-19: The click at 12:14 failed because the machine was not connected. The server called that `unknown agent`, so the notice did not say what was wrong. `Relay.start` now replies `The machine is not connected.` The notice heading is the hostname and the body is that sentence. The desktop page says `Waiting for Remote Desktop on <name>.` until `relay.ready`, and a FreeRDP failure replaces that sentence. `meson test -C build rdp-start` requires the new sentence.

- ✔️ 2026-11-19: After 0.1.28, `Relay.start` at 11:52:31 and the agent log `name-ref token 21 alias mismatch`. The server had restarted at 11:52:15. The agent called `open` on the same client, so the old name table stayed. `/tmp/argus-nameref` prints `stale name-ref token 1 alias mismatch` and `fresh relay.start`. A dropped connection is now a new client.
- ✔️ 2026-11-26: Throwaway on `snappr-win`, not in the tree. Wintun 0.14 adapter `ArgusWintun0` at `10.200.0.2/32`. This process owned `10.200.0.1` and injected IPv4 TCP to `10.200.0.2:3389`. Windows listed that connection established from `10.200.0.1:51422`. TermService answered the opening request with the same 19 bytes a normal socket got, selected protocol Network Level Authentication. The session from `192.168.88.132:51982` stayed established. No logon was sent. The adapter, the driver, and `C:\Users\Alan\argus-wintun-probe` were removed.

## Next

- ⏳ 🔷 Phase 5 is not verified on a machine. The Windows agent installer for that try is 0.1.29. Phase 6 is the session tabs.
- ⏳ 🔷 Phase 6.5 is the tray ask, the controller notice while that ask is open, Force, and the tray notice that names who has the screen.
- ⏳ 💩 The proof listen is still `Relay.listen`. Phase 2 does not move it into `SslListen`.
- ⏳ The virtual adapter is `2026-11-26-FEATURE-windows-rdp-virtual-adapter.md`.

## LLM notes

- 🚫 Do not patch `termsrv.dll` to add a session, or to unlock Remote Desktop on Windows Home.
- 🚫 Do not turn Network Level Authentication off.
- 🚫 Do not put the desktop bytes on `agent.run` or the command log files.
- 🚫 Do not switch `Application.connection` to raw bytes. The desktop is a second connection to the same port.
- 🚫 Do not add a listener, and do not open another port.
- 🚫 Do not add drive redirection.
- 🚫 Do not put the button in the window header bar.
- 🚫 Do not start the flow from a short press, or from a button labeled Connect to desktop.
- 🚫 Do not put the starter on the machine list or on Agents.
- 🚫 Do not hide the button on Android.
- 🚫 Do not open the viewer in another window.
- 🚫 Do not add an RDP connections list.
- ℹ️ 2026-11-26 throwaway was `/tmp/argus-wintun-probe.c`, copied to `snappr-win` and deleted after the run. The 4-byte frame in the sketch is not an IP packet. The probe built IPv4 and TCP. The export is `WintunGetAdapterLUID`. Send with `WintunAllocateSendPacket`, then `WintunSendPacket`.
- ℹ️ The inbound Remote Desktop firewall rules were already enabled on that PC. This run did not test a closed firewall group.
- 🚫 Do not treat the negotiation answer as a desktop that stayed on screen. No credentials were sent.
- ℹ️ 2026-11-26: The virtual adapter is its own report, `2026-11-26-FEATURE-windows-rdp-virtual-adapter.md`.
