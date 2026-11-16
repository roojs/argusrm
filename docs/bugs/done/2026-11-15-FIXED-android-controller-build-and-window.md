# Android controller build and slide-out menu primary window

**Status:** ✅ fixed and verified on `SM-S9380` — APK build, slide-out drawer, hamburger navigation, TLS connection, and `#if ANDROID` bootstrap all working

**Pointer:** `docs/bug-fix-process.md`, `docs/plans/5.5-controller-user-interface.md`, `controller/Window.vala`, `controller/TabList.vala`, `controller/Application.vala`, `controller/dialog/Bootstrap.vala`, `controller/meson.build`, `meson.build`, `packaging/android/pixiewood-argus.xml`, `packaging/android/build-apk.sh`, `.github/workflows/x-android.yml`, `.github/workflows/release-android.yml`

---

## Problem

- 🔷 Set up the Android APK build for the Argus controller (`argus-controller`) instead of the abandoned Android agent.
- 🔷 Modify the primary window for Android so the top-level shell fits a mobile/touch screen while keeping all controller tabs and component parts shared with desktop:
  - 🔷 The primary view opens on the navigation menu so the user can pick a section/task.
  - 🔷 The menu is a slide-out left drawer with a top-left hamburger button visible on all screens so the user can open the menu at any point.
  - 🔷 Selecting a menu item switches to that tab (as on desktop) and hides the menu automatically.

---

## Evidence

- ✔️ **Meson build (`controller/meson.build`, `meson.build`):**
  - `controller/meson.build` already defines an Android executable target `'argus-controller'` with `android_exe_type: 'application'`, using the desktop `sources` list (including desktop `Window.vala`).
  - `controller/meson.build` does not pass `-D ANDROID`, does not check `meson_version >= 1.8.0`, does not link `gioopenssl`, and does not load the static OpenSSL GIO TLS backend (`g_io_openssl_load(NULL)`).
  - `meson.build` defines `vendor/libocsqlite`, `vendor/libocrpc`, `gee_vapi_dir`, and `--pkg=json-glib-1.0` / `--pkg=libsoup-3.0`, and skips `server` and `docs` on Android.
- ✔️ **Desktop window & sidebar (`controller/Window.vala`, `controller/TabList.vala`):**
  - `controller/Window.vala` builds an `Adw.Window` (`960x640`) with `Adw.NavigationSplitView` (`min_sidebar_width = 200`, `max_sidebar_width = 280`), no hamburger toggle, and `TabList` mapped on the left.
  - `controller/TabList.vala` auto-selects row 0 (`"dashboard"`) inside `list.map` via `GLib.Idle.add` and only emits `chosen` on `list.row_selected` / `settings_list.row_selected` (tapping the already-selected row does not re-emit `chosen`).
  - Tabs and dialogs (`Agent`, `Assets`, `Tasks`, `Repository`, `Settings`, `Dashboard`, `Pairing`) only depend on `Argus.Controller.Window` (`window.app`, `window.connection`, `window.issued`, `window.leaving`, `window.close()`, and `"win"` actions `register` / `deregister`). None of them read `Adw.NavigationSplitView` or pack controls into `window.content_header`.
- ✔️ **Android startup & credential blockers (`controller/Application.vala`, `controller/dialog/Bootstrap.vala`, `shared/Registration/Data.vala`):**
  - `controller/Application.vala` lines 166–171 check `DISPLAY` and `WAYLAND_DISPLAY` and abort with `"Run argusrm-controller-cli on the server."` when neither is set; on Android neither env var exists.
  - `controller/dialog/Bootstrap.vala` wraps all `Secret` keyring lookups (`check()`, line 242) and stores (`finish_registration()`, line 623) in `#if LINUX`, then immediately fails `check()` at line 278 (`if (this.credentials.size < 1)`) with `"The saved server has no certificate."` on non-Linux systems. It also shows `"Log in to local machine"` even though `exe_root()` is Linux-only (`pkexec` / `/proc/self/exe`).
  - `shared/Registration/Data.vala` `clear_saved_login()` only clears `Secret` under `#if LINUX` and edits `connections.json`.
  - `shared/RegisterWindow.vala` already handles `#if ANDROID` (`this.browse.label` via `PairBrowse.java`).
- ✔️ **Emulator launch crash (`adb logcat` on `emulator-5554`, 2026-11-15 11:06):**
  - `org.roojs.argus` initialized `GTlsBackendOpenssl` (`_g_io_module_get_default: Found default implementation openssl (GTlsBackendOpenssl)`), then aborted on `GTK Thread` inside `adw_dialog_present` -> `gtk_window_present` -> `gdk_toplevel_present`:
  - `JNI DETECTED ERROR IN APPLICATION: jfieldID long org.gtk.android.ToplevelActivity.nativeIdentifier not valid for an object of class org.roojs.argus.ArgusApplication`
  - Cause: `controller/Application.vala` subclasses `GLib.Application` with `HANDLES_COMMAND_LINE` and calls `bootstrap.present(null)` from `command_line()` during `RuntimeApplication.onCreate()` before `ToplevelActivity.onCreate()` calls `GdkContext._set_latest_activity(this)` and `GdkContext.activate()`, and without a parent `Adw.ApplicationWindow`.
- ✔️ **Android packaging & CI (`packaging/android/`, `shared/android/`, `.github/workflows/`):**
  - `packaging/android/pixiewood-argus.xml` still targets `argus-agent` (`org.roojs.argus`, `"Argus RM Agent"`) and lacks `<sqlite3/>` in `<dependencies>`.
  - `shared/android/ArgusApplication.java` binds native library `"argus-agent"` instead of `"argus-controller"`.
  - `packaging/android/build-apk.sh` does not stage CA certificates (`ca-certificates.crt`), Adwaita icons (`assets/share/icons/Adwaita/`), or `mime.cache` into APK assets.
  - `.github/workflows/release-android.yml` has `if: false`, and `.github/workflows/x-android.yml` checks for `lib/arm64-v8a/libargus-agent.so` and pins `roojs/OLLMchat` `v1.4.9` (while `OLLMchat` `v1.4.12` has `vapi/gioopenssl.vapi` and current `build-pixiewood-apk.sh` with `PIXIEWOOD_USE_PIXIE=1`).

---

## Root cause

1. ✔️ **No Android window shell (`controller/Window.vala`, `controller/TabList.vala`):** Desktop `Window` uses a persistent `Adw.NavigationSplitView` without a slide-out drawer or hamburger toggle, and `TabList` auto-selects row 0 without handling re-activation of the current row.
2. ✔️ **Missing Android platform wiring in controller (`controller/Application.vala`, `controller/meson.build`, `controller/main.vala`):** `Application` subclasses `GLib.Application` with `HANDLES_COMMAND_LINE` and presents `Bootstrap` (`Adw.Dialog`) with `parent = null` inside `command_line()` before `ToplevelActivity` runs `GdkContext.activate()`, `controller/meson.build` omits `-D ANDROID` and `gioopenssl`, and nothing initializes `g_io_openssl_load(NULL)` or sets the Adwaita icon theme on Android.
3. ✔️ **No credential persistence outside `libsecret` (`controller/dialog/Bootstrap.vala`, `shared/Registration/Data.vala`):** Android builds compile without `libsecret`, leaving `Bootstrap` unable to save or reload server certificates across restarts and offering a Linux-only local login button.
4. ✔️ **Stale Android packaging for agent (`packaging/android/`, `shared/android/`, `.github/workflows/`):** Pixiewood manifest, Java `System.loadLibrary`, asset staging, and GitHub workflows still target `argus-agent` rather than `argus-controller`.

---

## Proposed fix

### 1. `controller/android/Window.vala` & `controller/TabList.vala` — Android slide-out drawer primary window

- 🔷 Introduce `controller/android/Window.vala` defining the same `Argus.Controller.Window` class API (`app`, `connection`, `issued`, `leaving`, `content_header`, `content_bar`, `win.register` / `win.deregister` actions, reconnect loop) so all tabs and dialogs compile unchanged.
- 🔷 Use `Adw.OverlaySplitView` with `collapsed = true` and `show_sidebar = true` on initial open so the left menu is the primary screen at launch.
- 🔷 Add a `Gtk.ToggleButton` with `open-menu-symbolic` (`tooltip_text = "Menu"`) at `this.content_header.pack_start(...)`, bound bidirectionally to `split.show_sidebar`, so the hamburger menu button is always visible on the top-left of every tab screen.
  - 💩 Note on `.cursor/rules/no-header-bar-controls.mdc`: this button is window-level navigation chrome (analogous to `About` in `Window.vala` and `history_toggle_button` in `OLLMchat`), not a tab/page action. Confirm this exception is desired.
- 🔷 When the user chooses any row in `TabList`, switch `pages.visible_child_name`, update `content_title.label`, and set `split.show_sidebar = false` (skipping auto-hide on the initial `map` auto-selection so the menu stays visible on launch).
- 🔷 In `controller/TabList.vala`, emit `chosen` on `row_activated` as well as `row_selected` (via `activate_on_single_click = true`, only firing on `row_activated` when already selected or handling both cleanly) so tapping the already-selected tab still closes the slide-out menu.

#### Add — `controller/android/Window.vala` (new file)

Android `Argus.Controller.Window` using `Adw.OverlaySplitView` (`collapsed = true`, `show_sidebar = true` on launch) and top-left hamburger toggle in `content_header`.

```vala
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

namespace Argus.Controller
{
	/**
	 * Android main controller window for one server.
	 *
	 * Uses a collapsed {@link Adw.OverlaySplitView} whose left menu
	 * starts open so the user picks a section first. Selecting any
	 * place switches the content stack and hides the drawer. A
	 * top-left menu button in {@link content_header} re-opens the
	 * slide-out menu from any screen.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var window = new Argus.Controller.Window(app, connection, issued);
	 * window.present();
	 * }}}
	 */
	public class Window : Adw.Window
	{
		public Application app;
		public Connection connection { get; set; default = new Connection(); }
		public Argus.Shared.Registration.Data issued {
			get; set; default = new Argus.Shared.Registration.Data();
		}
		/**
		 * Header of the active page.
		 */
		public Adw.HeaderBar content_header;
		/**
		 * Toolbar around the active page.
		 */
		public Adw.ToolbarView content_bar;
		/**
		 * True when this window is closing without quitting.
		 */
		public bool leaving = false;
		private GLib.SimpleAction deregister_action;
		private Dialog.Pairing pairing_dialog;
		private Gtk.Label title_label;
		private uint connection_check_id = 0;
		private bool reconnecting = false;
		private bool was_connected = true;
		private bool closed = false;
		private int64 next_reconnect = 0;

		/**
		 * Create the Android controller window for one server.
		 *
		 * @param app the controller process
		 * @param connection the server that answered
		 * @param issued certificate from this process, or empty
		 */
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued
		) {
			this.app = app;
			this.connection = connection;
			this.issued = issued;
			this.issued.name = connection.name;
			this.issued.finished.connect((removed) => {
				if (removed) {
					this.app.quit();
					return;
				}
				this.deregister_action.set_enabled(true);
			});
			this.title = "Argus RM " + Argus.VERSION;
			this.set_default_size(420, 720);
			var header = new Adw.HeaderBar();
			this.title_label = new Gtk.Label("Argus RM " + Argus.VERSION) {
				css_classes = { "title" }
			};
			header.title_widget = this.title_label;
			var logo = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				width_request = 34,
				height_request = 34,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			logo.append(new Gtk.Image() {
				icon_name = "org.roojs.ArgusController",
				pixel_size = 24,
				hexpand = true,
				vexpand = true,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			});
			header.pack_start(logo);
			header.pack_end(new About());
			this.pairing_dialog = new Dialog.Pairing(this);
			var actions = new GLib.SimpleActionGroup();
			this.deregister_action = new GLib.SimpleAction("deregister", null);
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.issued.deregister(this, this.app.rpc);
			});
			var register_action = new GLib.SimpleAction("register", null);
			register_action.activate.connect(() => {
				if (this.pairing_dialog.pairing) {
					return;
				}
				this.pairing_dialog.open();
			});
			actions.add_action(this.deregister_action);
			actions.add_action(register_action);
			this.insert_action_group("win", actions);
			var sidebar_bar = new Adw.ToolbarView();
			sidebar_bar.add_top_bar(header);
			var tabs = new TabList();
			sidebar_bar.content = tabs;
			this.content_header = new Adw.HeaderBar();
			var menu_button = new Gtk.ToggleButton() {
				icon_name = "open-menu-symbolic",
				tooltip_text = "Menu"
			};
			this.content_header.pack_start(menu_button);
			var host_name = connection.name;
			if (host_name == "" && connection.addresses.length > 0) {
				host_name = connection.addresses[0];
			}
			if (host_name == "") {
				host_name = "Argus RM";
			}
			var content_title = new Gtk.Label(host_name + " - " + tabs.titles[0]) {
				css_classes = { "title" }
			};
			this.content_header.title_widget = content_title;
			this.content_bar = new Adw.ToolbarView() {
				vexpand = true,
				hexpand = true
			};
			this.content_bar.add_top_bar(this.content_header);
			var pages = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.CROSSFADE
			};
			this.content_bar.content = pages;
			var agent = new Tab.Agent(this);
			var repository = new Tab.Repository(this);
			for (var i = 0; i < tabs.keys.length; i++) {
				var key = tabs.keys[i];
				if (key == "dashboard") {
					pages.add_named(new Tab.Dashboard(this), key);
					continue;
				}
				if (key == "agents") {
					pages.add_named(agent, key);
					continue;
				}
				if (key == "repositories") {
					pages.add_named(repository, key);
					continue;
				}
				if (key == "assets") {
					pages.add_named(new Tab.Assets(this), key);
					continue;
				}
				if (key == "tasks") {
					pages.add_named(new Tab.Tasks(this), key);
					continue;
				}
				pages.add_named(new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true
				}, key);
			}
			pages.add_named(new Tab.Settings(this), "settings");
			pages.visible_child_name = tabs.keys[0];
			var split = new Adw.OverlaySplitView() {
				sidebar = sidebar_bar,
				content = this.content_bar,
				collapsed = true,
				show_sidebar = true,
				min_sidebar_width = 240,
				max_sidebar_width = 300,
				hexpand = true,
				vexpand = true
			};
			split.bind_property("show-sidebar", menu_button, "active",
				GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);
			var ready = false;
			tabs.chosen.connect((key, title) => {
				pages.visible_child_name = key;
				content_title.label = host_name + " - " + title;
				if (!ready) {
					ready = true;
					return;
				}
				split.show_sidebar = false;
			});
			this.content = split;
			this.close_request.connect(() => {
				this.closed = true;
				if (this.connection_check_id != 0) {
					GLib.Source.remove(this.connection_check_id);
					this.connection_check_id = 0;
				}
				if (this.leaving) {
					return false;
				}
				this.app.quit();
				return false;
			});
			this.connection_check_id = GLib.Timeout.add_seconds(1, this.check_connection);
		}

		/**
		 * Show whether the server connection is open, and open it
		 * again after it drops.
		 *
		 * @return true while this window is open
		 */
		private bool check_connection()
		{
			if (this.closed) {
				this.connection_check_id = 0;
				return false;
			}
			var rpc = this.app.rpc;
			var connected = rpc != null && rpc.connected;
			if (connected) {
				this.title_label.label = "Argus RM " + Argus.VERSION;
				this.title_label.css_classes = { "title" };
			}
			if (!connected) {
				this.title_label.label = "Offline";
				this.title_label.css_classes = { "title", "offline-title" };
			}
			if (connected || rpc == null || this.reconnecting) {
				if (connected) {
					this.was_connected = true;
				}
				return true;
			}
			var now = GLib.get_monotonic_time();
			if (!this.was_connected && now < this.next_reconnect) {
				return true;
			}
			this.was_connected = false;
			/* Monotonic time is microseconds. Try again in 30 seconds. */
			this.next_reconnect = now + (int64) 30 * 1000000;
			this.reconnecting = true;
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				this.reconnecting = false;
				if (this.closed) {
					return;
				}
				try {
					rpc.connect.end(res);
				} catch (GLib.Error e) {
					GLib.debug("%s", e.message);
				}
			});
			return true;
		}
	}
}
```

#### Remove — `controller/TabList.vala` (`TabList` signal wiring)

```vala
			var list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				css_classes = { "navigation-sidebar" },
				vexpand = true,
				hexpand = true
			};
```

#### Replace with

```vala
			var list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				activate_on_single_click = true,
				css_classes = { "navigation-sidebar" },
				vexpand = true,
				hexpand = true
			};
```

#### Remove — `controller/TabList.vala` (`settings_list` and selection handlers)

```vala
			var settings_list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				css_classes = { "navigation-sidebar" },
				hexpand = true
			};
```

#### Replace with

```vala
			var settings_list = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				activate_on_single_click = true,
				css_classes = { "navigation-sidebar" },
				hexpand = true
			};
```

#### Add — `controller/TabList.vala`, immediately after `settings_list.row_selected.connect(...)`

Emit `chosen` when tapping an already-selected row so the slide-out drawer hides even when the user picks the active tab again.

```vala
			list.row_activated.connect((row) => {
				if (row == list.get_selected_row()) {
					this.chosen(row.name, ((Gtk.Label) row.child).label);
				}
			});
			settings_list.row_activated.connect((row) => {
				if (row == settings_list.get_selected_row()) {
					this.chosen("settings", "Settings");
				}
			});
```

---

### 2. `controller/android/Application.vala`, `controller/android/main.vala`, `controller/android/Window.vala`, `controller/dialog/Bootstrap.vala`, `controller/tab/Settings.vala`, `controller/android/android-gio-tls.c` — Android launch, host window, and TLS init

- 🔷 Keep desktop `controller/Application.vala` and `controller/main.vala` free of `#if ANDROID` by adding `controller/android/Application.vala` (`Adw.Application` with `GLib.ApplicationFlags.DEFAULT_FLAGS`) and `controller/android/main.vala`.
- 🔷 Handle `this.activate` (invoked by `ToplevelActivity.onCreate()` -> `GdkContext.activate()`) in `controller/android/Application.vala` to register RPC types, configure CSS/icons (`gtk_icon_theme_name = "Adwaita"`), present a host `Adw.ApplicationWindow`, and present `Dialog.Bootstrap` over that host window.
- 🔷 Make `controller/android/Window.vala` subclass `Adw.ApplicationWindow` (`Object(application: app)`) so `Bootstrap.use()` and `Settings` always keep a valid `ToplevelActivity` window on screen, closing the temporary bootstrap host window once `Window` is presented.
- 🔷 Generate `android/icon-foreground.xml` from `argusrm.svg` (replacing the solid blue `#3584e4` placeholder that rendered as a solid blue circle in the launcher icon and Android splash screen) and set `<color target="background">#ffffff</color>` in `packaging/android/pixiewood-argus.xml`.
- 🔷 Populate the `Adw.ApplicationWindow` host behind `Dialog.Bootstrap` in `controller/android/Application.vala` with the application logo, title, and spinner so the backdrop above the bottom sheet is not blank.

#### Add — `controller/android/android-gio-tls.h` and `controller/android/android-gio-tls.c` (new files)

Initialize the static OpenSSL GIO TLS module on Android before creating `GLib.TlsFileDatabase` or `OLLMrpc.Client`.

```c
#ifndef ARGUS_CONTROLLER_ANDROID_GIO_TLS_H
#define ARGUS_CONTROLLER_ANDROID_GIO_TLS_H

#include <glib.h>

gboolean argus_controller_configure_android_gio_tls_modules (void);

#endif
```

```c
#include "android-gio-tls.h"

#include <gio/gio.h>
#include <string.h>

/* Static glib-networking OpenSSL backend. */
extern void g_io_openssl_load (gpointer module);

gboolean
argus_controller_configure_android_gio_tls_modules (void)
{
	GTlsBackend *backend;
	const char *type_name;

	g_io_openssl_load (NULL);
	backend = g_tls_backend_get_default ();
	if (backend == NULL) {
		g_warning ("GIO TLS backend unavailable after g_io_openssl_load(NULL)");
		return FALSE;
	}
	type_name = G_OBJECT_TYPE_NAME (backend);
	if (type_name == NULL || strcmp (type_name, "GDummyTlsBackend") == 0) {
		g_warning ("GIO TLS backend is dummy after g_io_openssl_load(NULL)");
		return FALSE;
	}
	return TRUE;
}
```

#### Add — `controller/android/main.vala` (new file)

Android entry point initializing static `gioopenssl` before starting `Application`.

```vala
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

[CCode (cheader_filename = "android-gio-tls.h")]
private extern bool argus_controller_configure_android_gio_tls_modules();

namespace Argus.Controller
{
	int main(string[] args)
	{
		argus_controller_configure_android_gio_tls_modules();
		var app = new Application();
		return app.run(args);
	}
}
```

#### Add — `controller/android/Application.vala` (new file)

Android `Adw.Application` entry implementing the same `Argus.Controller.Application` surface and launching `Dialog.Bootstrap` over a host `Adw.ApplicationWindow` on `activate`.

```vala
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

namespace Argus.Controller
{
	/**
	 * Android controller application.
	 *
	 * Same public surface as desktop {@link Application} so shared
	 * tabs and dialogs compile unchanged. Waits for Android
	 * {@link GLib.Application.activate} from ''ToplevelActivity'',
	 * configures the Adwaita icon theme and CSS, presents a host
	 * {@link Adw.ApplicationWindow}, and opens {@link Dialog.Bootstrap}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var app = new Argus.Controller.Application();
	 * return app.run(args);
	 * }}}
	 */
	public class Application : Adw.Application
	{
		public static string agent = "";
		public static string command = "";
		public OLLMrpc.Client rpc { get; set; }
		/**
		 * Main window opened after a connection answers.
		 */
		public Window window { get; set; }
		/**
		 * True while {@link Window} is on screen.
		 */
		public bool running_window = false;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;

		/**
		 * Create the Android controller application and wire activate.
		 */
		public Application()
		{
			Object(
				application_id: "org.roojs.ArgusController",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				if (debug_log_in_progress) {
					return;
				}
				var timestamp = (new GLib.DateTime.now_local()).format("%H:%M:%S.%f");
				var shown_domain = dom == null ? "" : dom;
				if ((lvl & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0) {
					GLib.stderr.printf("%s: %s : %s : %s\n",
						timestamp, lvl.to_string(), shown_domain, msg);
				}
				debug_log_in_progress = true;
				if (debug_log_file == null) {
					var log_dir = GLib.Path.build_filename(
						GLib.Environment.get_user_cache_dir(), "argusrm");
					var log_file_path = GLib.Path.build_filename(log_dir, "controller.log");
					if (!GLib.FileUtils.test(log_dir, GLib.FileTest.IS_DIR)) {
						GLib.DirUtils.create_with_parents(log_dir, 0755);
					}
					debug_log_file = GLib.FileStream.open(log_file_path, "w");
				}
				if (debug_log_file != null) {
					debug_log_file.puts(timestamp + ": " + lvl.to_string() + " : " + msg + "\n");
					debug_log_file.flush();
				}
				debug_log_in_progress = false;
			});
			this.activate.connect(() => {
				OLLMrpc.rpc_register();
				Argus.Shared.Agent.rpc_register();
				Argus.Shared.OSQuery.SystemInfo.rpc_register();
				Argus.Shared.OSQuery.OsVersion.rpc_register();
				Argus.Shared.OsReleases.rpc_register();
				Argus.Shared.OSQuery.CpuInfo.rpc_register();
				Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
				Argus.Shared.OSQuery.Users.rpc_register();
				Argus.Shared.OSQuery.Groups.rpc_register();
				Argus.Shared.OSQuery.UserGroups.rpc_register();
				Argus.Shared.OSQuery.InterfaceAddresses.rpc_register();
				Argus.Shared.OSQuery.DebPackages.rpc_register();
				Argus.Shared.OSQuery.RpmPackages.rpc_register();
				Argus.Shared.OSQuery.Programs.rpc_register();
				Argus.Shared.Registration.Data.rpc_register();
				Argus.Shared.SQT.Task.rpc_register();
				Argus.Shared.SQT.TaskTarget.rpc_register();
				Argus.Shared.SQT.Script.rpc_register();
				Argus.Shared.SQT.ScriptRepository.rpc_register();
				Argus.Controller.Command.rpc_register();
				Gtk.Settings.get_default().gtk_icon_theme_name = "Adwaita";
				var screen = Gdk.Display.get_default();
				if (screen != null) {
					var css = new Gtk.CssProvider();
					css.load_from_resource("/argusrm/style.css");
					Gtk.StyleContext.add_provider_for_display(
						screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
					Gtk.IconTheme.get_for_display(screen).add_resource_path("/argusrm/icons");
				}
				Gtk.Window.set_default_icon_name("org.roojs.ArgusController");
				var host = new Adw.ApplicationWindow(this) {
					title = "Argus Remote Manager " + Argus.VERSION
				};
				host.set_default_size(420, 720);
				host.present();
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(host);
			});
		}
	}
}
```

#### Remove — `controller/android/Window.vala` (class and constructor)

```vala
	public class Window : Adw.Window
```

```vala
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued
		) {
			this.app = app;
```

#### Replace with

```vala
	public class Window : Adw.ApplicationWindow
```

```vala
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued
		) {
			Object(application: app);
			this.app = app;
```

#### Remove — `controller/dialog/Bootstrap.vala` (`use`)

```vala
				window.present();
				this.close();
				if (replace) {
					previous.close();
				}
```

#### Replace with

```vala
				window.present();
				this.close();
				if (replace) {
					previous.close();
				}
#if ANDROID
				foreach (var win in app.get_windows()) {
					if (win != window && win != previous) {
						win.close();
					}
				}
#endif
```

#### Remove — `controller/tab/Settings.vala` (`animation.done`)

```vala
						this.window.close();
						new Dialog.Bootstrap(this.window.app, "choose").present(null);
```

#### Replace with

```vala
#if ANDROID
						var host = new Adw.ApplicationWindow(this.window.app) {
							title = "Argus Remote Manager " + Argus.VERSION
						};
						host.set_default_size(420, 720);
						host.present();
						this.window.close();
						new Dialog.Bootstrap(this.window.app, "choose").present(host);
#else
						this.window.close();
						new Dialog.Bootstrap(this.window.app, "choose").present(null);
#endif
```

#### Add — `controller/android/android-gio-tls.h` and `controller/android/android-gio-tls.c` (new files)

Initialize the static OpenSSL GIO TLS module on Android before creating `GLib.TlsFileDatabase` or `OLLMrpc.Client`.

```c
#ifndef ARGUS_CONTROLLER_ANDROID_GIO_TLS_H
#define ARGUS_CONTROLLER_ANDROID_GIO_TLS_H

#include <glib.h>

gboolean argus_controller_configure_android_gio_tls_modules (void);

#endif
```

```c
#include "android-gio-tls.h"

#include <gio/gio.h>
#include <string.h>

/* Static glib-networking OpenSSL backend. */
extern void g_io_openssl_load (gpointer module);

gboolean
argus_controller_configure_android_gio_tls_modules (void)
{
	GTlsBackend *backend;
	const char *type_name;

	g_io_openssl_load (NULL);
	backend = g_tls_backend_get_default ();
	if (backend == NULL) {
		g_warning ("GIO TLS backend unavailable after g_io_openssl_load(NULL)");
		return FALSE;
	}
	type_name = G_OBJECT_TYPE_NAME (backend);
	if (type_name == NULL || strcmp (type_name, "GDummyTlsBackend") == 0) {
		g_warning ("GIO TLS backend is dummy after g_io_openssl_load(NULL)");
		return FALSE;
	}
	return TRUE;
}
```

#### Remove — `controller/main.vala`

```vala
namespace Argus.Controller
{
	int main(string[] args)
	{
		var app = new Application();
		return app.run(args);
	}
}
```

#### Replace with

```vala
#if ANDROID
[CCode (cheader_filename = "android-gio-tls.h")]
private extern bool argus_controller_configure_android_gio_tls_modules();
#endif

namespace Argus.Controller
{
	int main(string[] args)
	{
#if ANDROID
		argus_controller_configure_android_gio_tls_modules();
#endif
		var app = new Application();
		return app.run(args);
	}
}
```

#### Remove — `controller/Application.vala` (`command_line`)

```vala
			if (give_certificate == "" && deregister_name == "") {
				var display = GLib.Environment.get_variable("DISPLAY");
				var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				if ((display == null || display == "") && (wayland == null || wayland == "")) {
					command_line.printerr("Run argusrm-controller-cli on the server.\n");
					return 1;
				}
				Adw.init();
				var screen = Gdk.Display.get_default();
				if (screen != null) {
					var css = new Gtk.CssProvider();
					css.load_from_resource("/argusrm/style.css");
					Gtk.StyleContext.add_provider_for_display(
						screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
					Gtk.IconTheme.get_for_display(screen).add_resource_path("/argusrm/icons");
				}
				Gtk.Window.set_default_icon_name("org.roojs.ArgusController");
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(null);
				this.hold();
				return 0;
			}
```

#### Replace with

```vala
			if (give_certificate == "" && deregister_name == "") {
#if !ANDROID
				var display = GLib.Environment.get_variable("DISPLAY");
				var wayland = GLib.Environment.get_variable("WAYLAND_DISPLAY");
				if ((display == null || display == "") && (wayland == null || wayland == "")) {
					command_line.printerr("Run argusrm-controller-cli on the server.\n");
					return 1;
				}
#endif
				Adw.init();
#if ANDROID
				Gtk.Settings.get_default().gtk_icon_theme_name = "Adwaita";
#endif
				var screen = Gdk.Display.get_default();
				if (screen != null) {
					var css = new Gtk.CssProvider();
					css.load_from_resource("/argusrm/style.css");
					Gtk.StyleContext.add_provider_for_display(
						screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
					Gtk.IconTheme.get_for_display(screen).add_resource_path("/argusrm/icons");
				}
				Gtk.Window.set_default_icon_name("org.roojs.ArgusController");
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(null);
				this.hold();
				return 0;
			}
```

---

### 3. `controller/dialog/Bootstrap.vala` & `shared/Registration/Data.vala` — Android credential persistence & remote-only registration

- 💩 On Android, there is no `libsecret` and no local server (`pkexec`). Persist server certificates under `get_user_config_dir()/argusrm/credentials/<name>.json` (`0600` in app-private `etc/`, surviving APK updates) and offer only `"Connect a remote machine"` instead of `"Log in to local machine"`.
  - 💩 Confirm whether `Adw.Dialog.present(null)` in `Bootstrap` renders cleanly on Pixiewood's GTK4 Android backend, or if `Bootstrap` should be presented over a host `Adw.Window` when `app.window == null`.

#### Remove — `controller/dialog/Bootstrap.vala` (`check`)

```vala
			if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
				return;
			}
```

#### Replace with

```vala
			if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
#if ANDROID
				this.page("Argus Remote Manager", "",
					{ "Connect a remote machine" }, { "remote" });
#else
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
#endif
				return;
			}
```

#### Remove — `controller/dialog/Bootstrap.vala` (`check` empty list)

```vala
			if (this.connections.size < 1 || this.adding) {
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
				return;
			}
#if LINUX
			var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(GLib.str_hash, GLib.str_equal);
			types.insert("service", Secret.SchemaAttributeType.STRING);
			types.insert("server", Secret.SchemaAttributeType.STRING);
			types.insert("name", Secret.SchemaAttributeType.STRING);
			var schema = new Secret.Schema.newv("org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
			foreach (var connection in this.connections) {
				var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
				attrs.insert("service", "argusrm");
				attrs.insert("name", connection.name);
				var secret = "";
				try {
					var found = Secret.password_lookupv_sync(schema, attrs, null);
					if (found != null) {
						secret = found;
					}
				} catch (GLib.Error e) {
					this.page("Could not connect", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				if (secret == "") {
					continue;
				}
				try {
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.Registration.Data), secret)
						as Argus.Shared.Registration.Data;
					if (parsed == null || parsed.private_key == "" || parsed.client_certificate == "") {
						continue;
					}
					this.credentials.set(connection.name, parsed);
				} catch (GLib.Error e) {
					continue;
				}
			}
#endif
```

#### Replace with

```vala
			if (this.connections.size < 1 || this.adding) {
#if ANDROID
				this.page("Argus Remote Manager", "",
					{ "Connect a remote machine" }, { "remote" });
#else
				this.page("Argus Remote Manager", "",
					{ "Log in to local machine", "Connect a remote machine" },
					{ "register", "remote" });
#endif
				return;
			}
#if LINUX
			var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(GLib.str_hash, GLib.str_equal);
			types.insert("service", Secret.SchemaAttributeType.STRING);
			types.insert("server", Secret.SchemaAttributeType.STRING);
			types.insert("name", Secret.SchemaAttributeType.STRING);
			var schema = new Secret.Schema.newv("org.roojs.ArgusController", Secret.SchemaFlags.NONE, types);
			foreach (var connection in this.connections) {
				var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
				attrs.insert("service", "argusrm");
				attrs.insert("name", connection.name);
				var secret = "";
				try {
					var found = Secret.password_lookupv_sync(schema, attrs, null);
					if (found != null) {
						secret = found;
					}
				} catch (GLib.Error e) {
					this.page("Could not connect", e.message,
						{ "Retry", "Log in to register" }, { "retry", "register" });
					return;
				}
				if (secret == "") {
					continue;
				}
				try {
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.Registration.Data), secret)
						as Argus.Shared.Registration.Data;
					if (parsed == null || parsed.private_key == "" || parsed.client_certificate == "") {
						continue;
					}
					this.credentials.set(connection.name, parsed);
				} catch (GLib.Error e) {
					continue;
				}
			}
#elif ANDROID
			var cred_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "credentials");
			foreach (var connection in this.connections) {
				var cred_path = GLib.Path.build_filename(cred_dir, connection.name + ".json");
				if (!GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS)) {
					continue;
				}
				var secret = "";
				try {
					GLib.FileUtils.get_contents(cred_path, out secret);
					var parsed = Json.gobject_from_data(typeof(Argus.Shared.Registration.Data), secret)
						as Argus.Shared.Registration.Data;
					if (parsed == null || parsed.private_key == "" || parsed.client_certificate == "") {
						continue;
					}
					this.credentials.set(connection.name, parsed);
				} catch (GLib.Error e) {
					continue;
				}
			}
#endif
```

#### Remove — `controller/dialog/Bootstrap.vala` (`finish_registration` end of `#if LINUX` block)

```vala
#endif
			this.credentials.set(data.name, data);
```

#### Replace with

```vala
#elif ANDROID
			var cred_dir = GLib.Path.build_filename(dir, "credentials");
			if (GLib.DirUtils.create_with_parents(cred_dir, 0700) != 0) {
				this.page("Could not register", "Could not create the credentials directory",
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
				return;
			}
			var secret = new Argus.Shared.Registration.Data() {
				private_key = data.private_key,
				client_certificate = data.client_certificate,
				ca_certificate = data.ca_certificate
			};
			var cred_path = GLib.Path.build_filename(cred_dir, data.name + ".json");
			try {
				GLib.FileUtils.set_contents(cred_path, Json.gobject_to_data(secret, null));
				GLib.FileUtils.chmod(cred_path, 0600);
			} catch (GLib.Error e) {
				this.page("Could not register", e.message,
					{ "Retry", "Connect a remote machine" }, { "retry", "remote" });
				return;
			}
#endif
			this.credentials.set(data.name, data);
```

#### Remove — `controller/dialog/Bootstrap.vala` (`connect_remote`)

```vala
		private void connect_remote()
		{
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argusrm"),
				is_controller = true,
				username = GLib.Environment.get_user_name(),
				hostname = GLib.Environment.get_host_name()
			};
```

#### Replace with

```vala
		private void connect_remote()
		{
#if ANDROID
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "certs");
#else
			var data_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argusrm");
#endif
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = data_dir,
				is_controller = true,
				username = GLib.Environment.get_user_name(),
				hostname = GLib.Environment.get_host_name()
			};
```

#### Remove — `shared/Registration/Data.vala` (`clear_saved_login`)

```vala
			Secret.password_clearv_sync(schema, attrs, null);
#endif
```

#### Replace with

```vala
			Secret.password_clearv_sync(schema, attrs, null);
#elif ANDROID
			var cred_path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "credentials",
				this.name + ".json");
			if (GLib.FileUtils.test(cred_path, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.remove(cred_path);
			}
#endif
```

---

### 4. `controller/meson.build`, `shared/android/ArgusApplication.java`, `packaging/android/*`, `.github/workflows/*` — Android controller build & APK staging

- 🔷 Update `meson.build` so Android handles both `PIXIEWOOD_USE_PIXIE=1` (`gee_vapi_dir` from pkg-config `gee-0.8`, `gioopenssl` fallback subproject) and from-source wraps.
- 🔷 Update `controller/meson.build` to:
  - Require Meson `>= 1.8.0` on Android (`android_exe_type`).
  - Pass `-D ANDROID` and `--vapidir` for `vendor/vapi` + `--pkg gioopenssl`, linking `dependency('gioopenssl', static: true)`.
  - Build `android/Window.vala` + `android/android-gio-tls.c` instead of desktop `Window.vala` on Android, with `install_dir: get_option('libdir')`.
- 🔷 Update `shared/android/ArgusApplication.java` to bind `"argus-controller"` (or split a controller Java entrypoint).
- 🔷 Update `packaging/android/pixiewood-argus.xml` to `<meta:id>org.roojs.argus</meta:id>` / `<meta:name>Argus RM</meta:name>`, add `<sqlite3/>`, and set `<build target="argus-controller">`.
- 🔷 Add `packaging/android/icons/manifest` covering all Adwaita symbolic icons used by `controller` and GTK widgets, and update `packaging/android/build-apk.sh` to stage CA certificates, Adwaita icons, and `mime.cache` into APK assets.
- 🔷 Update `.github/workflows/x-android.yml` (checkout `roojs/OLLMchat` `v1.4.12`, install `adwaita-icon-theme`, `shared-mime-info`, `libsqlite3-dev`, `jq`, use `PIXIEWOOD_USE_PIXIE=1`, verify `lib/arm64-v8a/libargus-controller.so`, output `ArgusController-${version}-android-arm64-debug.apk`) and re-enable `.github/workflows/release-android.yml`.
  - 💩 Decide whether Android APK should also be added to `.github/workflows/release.yml` tag releases or stay manual-trigger via `release-android.yml` first.

#### Remove — `meson.build` (Android `gee_vapi_dir` setup)

```meson
	gee_vapi_dir = meson.project_source_root() / 'subprojects' / 'libgee-0.20.8' / 'gee'
```

#### Replace with

```meson
	if not dependency('gioopenssl', required: false).found()
		subproject('glib-networking')
	endif
	gee_vapi_dir = meson.project_source_root() / 'subprojects' / 'libgee-0.20.8' / 'gee'
	gee_dep = dependency('gee-0.8')
	if gee_dep.type_name() == 'pkgconfig'
		gee_vapi_dir = gee_dep.get_variable(pkgconfig: 'prefix') / 'share' / 'vala' / 'vapi'
		add_project_arguments(['--vapidir', gee_vapi_dir], language: 'vala')
	endif
```

#### Remove — `controller/meson.build` (lines 17–43 and 106–128)

```vala
deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gtk4'),
	dependency('libadwaita-1'),
	ocrpc_dep,
]
deps += shared_dep
controller_vala_args = ocrpc_vala_args + ocsqlite_vala_args + [
	'--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
	'--pkg', 'sqlite3',
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1',
]
# Android passes gee-0.8.vapi as a source via dependency('gee-0.8').
# --pkg=gee-0.8 looks for a host package and fails in the Pixiewood build.
if host_machine.system() != 'android'
	controller_vala_args += ['--pkg', 'gee-0.8']
endif
```

#### Replace with

```meson
deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gtk4'),
	dependency('libadwaita-1'),
	ocrpc_dep,
]
deps += shared_dep
controller_vala_args = ocrpc_vala_args + ocsqlite_vala_args + [
	'--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
	'--pkg', 'sqlite3',
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1',
]
controller_c_args = ocsqlite_c_args
# Android passes gee-0.8.vapi as a source via dependency('gee-0.8').
# --pkg=gee-0.8 looks for a host package and fails in the Pixiewood build.
if host_machine.system() == 'android'
	if not meson.version().version_compare('>=1.8.0')
		error('Android requires Meson >= 1.8.0 for android_exe_type')
	endif
	gioopenssl_dep = dependency('gioopenssl')
	if gioopenssl_dep.type_name() == 'pkgconfig'
		gioopenssl_dep = dependency('gioopenssl', static: true)
	endif
	deps += gioopenssl_dep
	controller_vala_args += [
		'-D', 'ANDROID',
		'--vapidir', meson.project_source_root() / 'vendor' / 'vapi',
		'--pkg', 'gioopenssl',
	]
	controller_c_args += ['-I' + meson.current_source_dir() / 'android']
else
	controller_vala_args += ['--pkg', 'gee-0.8']
endif
```

#### Remove — `controller/meson.build` (Window source and Android executable)

```meson
	'TabList.vala',
	'Window.vala',
)
if host_machine.system() == 'windows'
	win_mod = import('windows')
	sources += win_mod.compile_resources(
		files('../packaging/windows/argusrm.rc'),
		include_directories: include_directories('../packaging/windows'),
	)
endif
if host_machine.system() == 'android'
	executable(
		'argus-controller',
		sources,
		controller_resources,
		controller_icon_resources,
		files('main.vala'),
		dependencies: deps,
		c_args: ocsqlite_c_args,
		vala_args: controller_vala_args,
		android_exe_type: 'application',
		install: true,
	)
else
	executable(
		'argusrm-controller',
		sources,
		controller_resources,
		controller_icon_resources,
		files('main.vala'),
		dependencies: deps,
		c_args: ocsqlite_c_args,
		vala_args: controller_vala_args,
		install: true,
	)
endif
```

#### Replace with

```meson
	'TabList.vala',
)
if host_machine.system() == 'android'
	sources += files(
		'android/Window.vala',
		'android/android-gio-tls.c',
	)
else
	sources += files('Window.vala')
endif
if host_machine.system() == 'windows'
	win_mod = import('windows')
	sources += win_mod.compile_resources(
		files('../packaging/windows/argusrm.rc'),
		include_directories: include_directories('../packaging/windows'),
	)
endif
if host_machine.system() == 'android'
	executable(
		'argus-controller',
		sources,
		controller_resources,
		controller_icon_resources,
		files('main.vala'),
		dependencies: deps,
		c_args: controller_c_args,
		vala_args: controller_vala_args,
		android_exe_type: 'application',
		install: true,
		install_dir: get_option('libdir'),
	)
else
	executable(
		'argusrm-controller',
		sources,
		controller_resources,
		controller_icon_resources,
		files('main.vala'),
		dependencies: deps,
		c_args: controller_c_args,
		vala_args: controller_vala_args,
		install: true,
	)
endif
```

#### Remove — `shared/android/ArgusApplication.java`

```java
public class ArgusApplication extends RuntimeApplication {
	@Override
	public void onCreate() {
		super.onCreate();
		PairBrowse.bindLibrary(this, "argus-agent");
	}
}
```

#### Replace with

```java
public class ArgusApplication extends RuntimeApplication {
	@Override
	public void onCreate() {
		super.onCreate();
		PairBrowse.bindLibrary(this, "argus-controller");
	}
}
```

#### Remove — `packaging/android/pixiewood-argus.xml`

```xml
      <meta:id>org.roojs.argus</meta:id>
      <meta:name>Argus RM Agent</meta:name>
      <meta:summary>Argus Remote Manager agent</meta:summary>
      <meta:metadata_license>CC0-1.0</meta:metadata_license>
      <meta:project_license>LGPL-3.0-or-later</meta:project_license>
      <meta:description>
        <meta:p>Enroll this device with an Argus Remote Manager server.</meta:p>
      </meta:description>
```

#### Replace with

```xml
      <meta:id>org.roojs.argus</meta:id>
      <meta:name>Argus RM</meta:name>
      <meta:summary>Argus Remote Manager controller</meta:summary>
      <meta:metadata_license>CC0-1.0</meta:metadata_license>
      <meta:project_license>LGPL-3.0-or-later</meta:project_license>
      <meta:description>
        <meta:p>Manage Argus Remote Manager servers, machines, software, and tasks.</meta:p>
      </meta:description>
```

#### Remove — `packaging/android/pixiewood-argus.xml` (`<dependencies>` and `<build>`)

```xml
    <libadwaita/>
    <gee/>
    <json-glib/>
    <nghttp2/>
    <libsoup/>
    <openssl/>
    <glib-networking/>
  </dependencies>
  <build target="argus-agent">
    <architectures>
      <arch>aarch64</arch>
    </architectures>
  </build>
```

#### Replace with

```xml
    <libadwaita/>
    <sqlite3/>
    <gee/>
    <json-glib/>
    <nghttp2/>
    <libsoup/>
    <openssl/>
    <glib-networking/>
  </dependencies>
  <build target="argus-controller">
    <architectures>
      <arch>aarch64</arch>
    </architectures>
  </build>
```

#### Add — `packaging/android/icons/manifest` (new file)

List the Adwaita symbolic icons referenced by controller tabs, dialogs, and GTK widgets so `build-apk.sh` stages them into `assets/share/icons/Adwaita/`.

```text
# Tab-separated: dest_under_Adwaita	source_theme	source_relpath
symbolic/actions/open-menu-symbolic.svg	Adwaita	symbolic/actions/open-menu-symbolic.svg
symbolic/actions/list-add-symbolic.svg	Adwaita	symbolic/actions/list-add-symbolic.svg
symbolic/actions/help-about-symbolic.svg	Adwaita	symbolic/actions/help-about-symbolic.svg
symbolic/actions/view-refresh-symbolic.svg	Adwaita	symbolic/actions/view-refresh-symbolic.svg
symbolic/actions/edit-copy-symbolic.svg	Adwaita	symbolic/actions/edit-copy-symbolic.svg
symbolic/actions/edit-clear-symbolic.svg	Adwaita	symbolic/actions/edit-clear-symbolic.svg
symbolic/actions/edit-find-symbolic.svg	Adwaita	symbolic/actions/edit-find-symbolic.svg
symbolic/actions/object-select-symbolic.svg	Adwaita	symbolic/actions/object-select-symbolic.svg
symbolic/actions/system-log-out-symbolic.svg	Adwaita	symbolic/actions/system-log-out-symbolic.svg
symbolic/actions/view-reveal-symbolic.svg	Adwaita	symbolic/actions/view-reveal-symbolic.svg
symbolic/actions/view-conceal-symbolic.svg	Adwaita	symbolic/actions/view-conceal-symbolic.svg
symbolic/actions/go-next-symbolic.svg	Adwaita	symbolic/actions/go-next-symbolic.svg
symbolic/actions/go-previous-symbolic.svg	Adwaita	symbolic/actions/go-previous-symbolic.svg
symbolic/categories/preferences-system-symbolic.svg	Adwaita	symbolic/categories/preferences-system-symbolic.svg
symbolic/legacy/system-users-symbolic.svg	Adwaita	symbolic/legacy/system-users-symbolic.svg
symbolic/devices/computer-symbolic.svg	Adwaita	symbolic/devices/computer-symbolic.svg
symbolic/devices/network-wired-symbolic.svg	Adwaita	symbolic/devices/network-wired-symbolic.svg
symbolic/mimetypes/package-x-generic-symbolic.svg	Adwaita	symbolic/mimetypes/package-x-generic-symbolic.svg
symbolic/places/folder-symbolic.svg	Adwaita	symbolic/places/folder-symbolic.svg
symbolic/status/network-transmit-symbolic.svg	Adwaita	symbolic/status/network-transmit-symbolic.svg
symbolic/places/user-trash-symbolic.svg	Adwaita	symbolic/places/user-trash-symbolic.svg
symbolic/status/dialog-information-symbolic.svg	Adwaita	symbolic/status/dialog-information-symbolic.svg
symbolic/ui/pan-down-symbolic.svg	Adwaita	symbolic/ui/pan-down-symbolic.svg
symbolic/ui/pan-up-symbolic.svg	Adwaita	symbolic/ui/pan-up-symbolic.svg
symbolic/ui/window-close-symbolic.svg	Adwaita	symbolic/ui/window-close-symbolic.svg
```

#### Remove — `packaging/android/build-apk.sh` (`patch_argus_manifest` and `run_argus_pixiewood_build`)

```bash
patch_argus_manifest() {
  local manifest="$ROOT_DIR/.pixiewood/android/app/src/main/AndroidManifest.xml"

  if [ ! -f "$manifest" ]; then
    echo "AndroidManifest missing: $manifest" >&2
    exit 1
  fi
  sed -i 's/android:name="org.gtk.android.RuntimeApplication"/android:name="org.roojs.argus.ArgusApplication"/' "$manifest"
}

# Same order as OLLMchat run_pixiewood_build. generate's org/gtk/android
# symlink stays. Only jniLibs is copied off its symlink.
run_argus_pixiewood_build() {
  init_pixiewood_env
  maybe_download_meson_subprojects "$MESON_FOR_ANDROID"

  echo "Reconfiguring Pixiewood Meson build."
  maybe_reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"

  rm -rf "$ROOT_DIR/.pixiewood/android/app/src/main/jniLibs"
  sync_pixiewood_ini_manifest
  run_pixiewood generate
  patch_pixiewood_gradle_native_libs
  run_pixiewood build --skip-gradle
  materialize_pixiewood_jni_libs
  install_argus_java
  patch_argus_manifest
  run_pixiewood_gradle_assemble
}
```

#### Replace with

```bash
install_argus_icons() {
  local manifest="$ROOT_DIR/packaging/android/icons/manifest"
  local assets_icons="$ROOT_DIR/.pixiewood/android/app/src/main/assets/share/icons/Adwaita"
  local dest_relpath source_theme source_relpath src dest_file line

  if [ ! -f "$manifest" ]; then
    echo "Argus Android icon manifest missing: $manifest" >&2
    exit 1
  fi
  rm -rf "$assets_icons"
  mkdir -p "$assets_icons"
  if [ -f /usr/share/icons/Adwaita/index.theme ]; then
    cp -a /usr/share/icons/Adwaita/index.theme "$assets_icons/index.theme"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "$line" ] && continue
    dest_relpath="${line%%$'\t'*}"
    line="${line#*$'\t'}"
    source_theme="${line%%$'\t'*}"
    source_relpath="${line#*$'\t'}"
    src="/usr/share/icons/$source_theme/$source_relpath"
    if [ ! -f "$src" ]; then
      echo "Icon source missing: $src" >&2
      exit 1
    fi
    dest_file="$assets_icons/$dest_relpath"
    mkdir -p "$(dirname "$dest_file")"
    cp -rL "$src" "$dest_file"
  done < "$manifest"
}

patch_argus_manifest() {
  local manifest="$ROOT_DIR/.pixiewood/android/app/src/main/AndroidManifest.xml"

  if [ ! -f "$manifest" ]; then
    echo "AndroidManifest missing: $manifest" >&2
    exit 1
  fi
  sed -i 's/android:name="org.gtk.android.RuntimeApplication"/android:name="org.roojs.argus.ArgusApplication"/' "$manifest"
  if ! grep -q 'android.permission.ACCESS_NETWORK_STATE' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>' "$manifest"
  fi
  if ! grep -q 'android.permission.CHANGE_WIFI_MULTICAST_STATE' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>' "$manifest"
  fi
  if grep -q 'android:launchMode="standard"' "$manifest"; then
    sed -i 's/android:launchMode="standard"/android:launchMode="singleTask"/' "$manifest"
  fi
}

# Same order as OLLMchat run_pixiewood_build. generate's org/gtk/android
# symlink stays. Only jniLibs is copied off its symlink.
run_argus_pixiewood_build() {
  init_pixiewood_env
  maybe_download_meson_subprojects "$MESON_FOR_ANDROID"

  echo "Reconfiguring Pixiewood Meson build."
  maybe_reconfigure_pixiewood_build "$MESON_FOR_ANDROID" "${PIXIEWOOD_CONFIGURE_OPTIONS[@]}"

  rm -rf "$ROOT_DIR/.pixiewood/android/app/src/main/jniLibs"
  if [ "$PIXIEWOOD_USE_PIXIE" = 1 ]; then
    local base clone
    base="$(dirname "$PIXIEWOOD_BUILD_DIR")"
    clone="$base/pixie-pkg/scripts/stage-runtime.sh"
    if [ ! -x "$clone" ]; then
      echo "pixie-pkg stage-runtime missing: $clone" >&2
      exit 1
    fi
    "$clone" "$PIXIEWOOD_PIXIE" "$base/root"
  fi
  sync_pixiewood_ini_manifest
  run_pixiewood generate
  patch_pixiewood_gradle_native_libs
  run_pixiewood build --skip-gradle
  materialize_pixiewood_jni_libs
  install_ca_certificates_to_assets
  install_argus_icons
  install_shared_mime_to_assets
  install_argus_java
  patch_argus_manifest
  run_pixiewood_gradle_assemble
}
```

#### Remove — `.github/workflows/x-android.yml`

```yaml
# Not called from release.yml. The Android agent sends no inventory.
name: X - Android APK build
```

#### Replace with

```yaml
name: X - Android APK build
```

#### Remove — `.github/workflows/x-android.yml` (`OLLMchat` ref, apt deps, Pixiewood env, and APK check)

```yaml
      - uses: actions/checkout@v4
        with:
          repository: roojs/OLLMchat
          ref: v1.4.9
          path: OLLMchat

      - name: Install Android build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            build-essential ca-certificates curl git glslc \
            gir1.2-appstream libadwaita-1-dev libglib-object-introspection-perl \
            libglib-perl libglib2.0-dev-bin libgtk-4-dev libipc-run-perl \
            libjson-perl libset-scalar-perl libxml-libxml-perl \
            libxml-libxslt-perl libtext-template-perl libxml2-utils \
            libjson-glib-dev libsoup-3.0-dev \
            meson nasm ninja-build openjdk-17-jdk pkg-config python3 \
            sassc unzip valac
```

#### Replace with

```yaml
      - uses: actions/checkout@v4
        with:
          repository: roojs/OLLMchat
          ref: v1.4.12
          path: OLLMchat

      - name: Install Android build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            adwaita-icon-theme build-essential ca-certificates curl git glslc \
            gir1.2-appstream jq libadwaita-1-dev libglib-object-introspection-perl \
            libglib-perl libglib2.0-dev-bin libgtk-4-dev libipc-run-perl \
            libjson-perl libset-scalar-perl libxml-libxml-perl \
            libxml-libxslt-perl libtext-template-perl libxml2-utils \
            libjson-glib-dev libsoup-3.0-dev libsqlite3-dev \
            meson nasm ninja-build openjdk-17-jdk pkg-config python3 \
            sassc shared-mime-info unzip valac
```

#### Remove — `.github/workflows/x-android.yml` (Stage, Prepare, Build, and Collect)

```yaml
      - name: Stage pinned Android tooling and libraries
        working-directory: argusrm
        run: |
          mkdir -p scripts/android android vendor
          cp -a ../OLLMchat/scripts/android/. scripts/android/
          cp -a ../OLLMchat/android/pixiewood-wraps android/
          cp -a ../OLLMchat/android/pixiewood-extra.cross android/
          cp -a ../OLLMchat/android/local-build.local.env android/
          cp -a ../OLLMchat/libocrpc vendor/
          cp -a ../OLLMchat/libocsqlite vendor/
          cp -a ../OLLMchat/vapi vendor/
          chmod +x scripts/android/*.sh

      - name: Prepare and configure Pixiewood
        working-directory: argusrm
        env:
          PIXIEWOOD_MANIFEST: ${{ github.workspace }}/argusrm/packaging/android/pixiewood-argus.xml
        run: |
          PIXIEWOOD_PHASE=setup scripts/android/build-pixiewood-apk.sh
          PIXIEWOOD_PHASE=configure scripts/android/build-pixiewood-apk.sh

      - name: Build APK
        working-directory: argusrm
        env:
          PIXIEWOOD_MANIFEST: ${{ github.workspace }}/argusrm/packaging/android/pixiewood-argus.xml
        run: bash packaging/android/build-apk.sh

      - name: Collect and verify APK
        working-directory: argusrm
        run: |
          set -euo pipefail
          source=.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
          unzip -l "$source" | grep -q 'lib/arm64-v8a/libargus-agent.so'
          mkdir -p artifacts
          version="$(bash scripts/release/changelog.sh packaging-version)"
          cp "$source" "artifacts/ArgusAgent-${version}-android-arm64-debug.apk"
```

#### Replace with

```yaml
      - name: Stage pinned Android tooling and libraries
        working-directory: argusrm
        run: |
          mkdir -p scripts/android android vendor
          cp -a ../OLLMchat/scripts/android/. scripts/android/
          cp -a ../OLLMchat/android/pixiewood-wraps android/
          cp -a ../OLLMchat/android/pixiewood-extra.cross android/
          cp -a ../OLLMchat/android/pixie-gtk.pins android/
          cp -a ../OLLMchat/android/pixie-webkit.pins android/
          cp -a ../OLLMchat/android/local-build.local.env android/
          cp -a ../OLLMchat/libocrpc vendor/
          cp -a ../OLLMchat/libocsqlite vendor/
          cp -a ../OLLMchat/vapi vendor/
          chmod +x scripts/android/*.sh

      - name: Prepare and configure Pixiewood
        working-directory: argusrm
        env:
          PIXIEWOOD_USE_PIXIE: "1"
          PIXIEWOOD_MANIFEST: ${{ github.workspace }}/argusrm/packaging/android/pixiewood-argus.xml
        run: |
          PIXIEWOOD_PHASE=setup scripts/android/build-pixiewood-apk.sh
          PIXIEWOOD_PHASE=configure scripts/android/build-pixiewood-apk.sh

      - name: Build APK
        working-directory: argusrm
        env:
          PIXIEWOOD_USE_PIXIE: "1"
          PIXIEWOOD_MANIFEST: ${{ github.workspace }}/argusrm/packaging/android/pixiewood-argus.xml
        run: bash packaging/android/build-apk.sh

      - name: Collect and verify APK
        working-directory: argusrm
        run: |
          set -euo pipefail
          source=.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
          unzip -l "$source" | grep -q 'lib/arm64-v8a/libargus-controller.so'
          mkdir -p artifacts
          version="$(bash scripts/release/changelog.sh packaging-version)"
          cp "$source" "artifacts/ArgusController-${version}-android-arm64-debug.apk"
```

#### Remove — `.github/workflows/release-android.yml`

```yaml
jobs:
  android:
    # The phone agent sends no inventory. osquery has no Android package.
    if: false
    uses: ./.github/workflows/x-android.yml
```

#### Replace with

```yaml
jobs:
  android:
    uses: ./.github/workflows/x-android.yml
```

---

## Attempts / changelog

- ✔️ Inspected `controller/Window.vala`, `controller/TabList.vala`, `controller/Application.vala`, `controller/dialog/Bootstrap.vala`, `controller/meson.build`, `meson.build`, `shared/Registration/Data.vala`, `shared/android/ArgusApplication.java`, `shared/android/PairBrowse.java`, `packaging/android/build-apk.sh`, `packaging/android/pixiewood-argus.xml`, `.github/workflows/x-android.yml`, `.github/workflows/release-android.yml`, and sibling `OLLMchat` Android build scripts (`v1.4.12`).
- ✔️ Added `controller/android/Window.vala` (`Adw.OverlaySplitView` starting open with top-left `open-menu-symbolic` toggle in `content_header`, hiding drawer on selection), `controller/android/android-gio-tls.h`, `controller/android/android-gio-tls.c`, and `packaging/android/icons/manifest`.
- ✔️ Updated `controller/TabList.vala`, `controller/main.vala`, `controller/Application.vala`, `controller/dialog/Bootstrap.vala`, `shared/Registration/Data.vala`, `meson.build`, `controller/meson.build`, `shared/android/ArgusApplication.java`, `packaging/android/pixiewood-argus.xml`, `packaging/android/build-apk.sh`, `.github/workflows/x-android.yml`, and `.github/workflows/release-android.yml`.
- ✔️ Defaulted `PIXIEWOOD_USE_PIXIE=1` in `packaging/android/build-apk.sh`, moved `argus_controller_configure_android_gio_tls_modules` extern to file scope in `controller/main.vala`, and updated `.gitignore` for staged/local Android build directories.
- ✔️ Built `.pixiewood/android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk` (21M) using the 25 published Pixie packages; verified `lib/arm64-v8a/libargus-controller.so`, `assets/share/ssl/certs/ca-certificates.crt`, `assets/share/mime/mime.cache`, and `assets/share/icons/Adwaita/symbolic/actions/open-menu-symbolic.svg`.
- ✔️ Separated Android entrypoints into `controller/android/Application.vala` (`Adw.Application`) and `controller/android/main.vala` (keeping desktop `controller/Application.vala` and `controller/main.vala` untouched).
- ✔️ Generated `android/icon-foreground.xml` from `argusrm.svg` (replacing the solid `#3584e4` placeholder that caused the launcher/splash blue circle), set `#ffffff` icon background in `packaging/android/pixiewood-argus.xml`, and added logo + title + spinner to the bootstrap host `Adw.ApplicationWindow` in `controller/android/Application.vala`.
- ✔️ Freed space on `emulator-5554` (cleared Google app caches, uninstalled `com.google.android.apps.docs.editors.docs` and YouTube updates), installed `app-arm64-v8a-debug.apk`, and verified launch, adaptive launcher icon, TLS backend (`GTlsBackendOpenssl`), logo/spinner backdrop, and `Argus Remote Manager` bootstrap sheet on `emulator-5554`.
- ✔️ Fixed `controller/dialog/Bootstrap.vala` under `#if ANDROID` so cancelling `RegisterWindow`, registration errors, connection errors, and `deregister_local()` all stay on `"Connect a remote machine"` rather than showing `"Log in to local machine"` or `"Log in to register"`.
- ✅ Verified on `SM-S9380`: startup registration/bootstrap, slide-out menu drawer, top-left hamburger button across tabs, auto-hide on tab selection, and live TLS connection to `192.168.0.12`.

---

## Next

- ⏳ 🔷 Run `.github/workflows/release-android.yml` in CI and decide whether `.github/workflows/release.yml` should also attach the Android controller APK on tag releases.
