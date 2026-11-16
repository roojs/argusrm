# Android `singleTask` destroys app when `Bootstrap` or `Settings` opens a second `Window`

**Status:** ✅ fixed and verified on `SM-S9380`

**Pointer:** `docs/bug-fix-process.md`, `controller/android/Application.vala`, `controller/android/Window.vala`, `controller/dialog/Bootstrap.vala`, `controller/tab/Settings.vala`, `packaging/android/build-apk.sh`

---

## Problem

- 🔷 Once `Bootstrap.use()` succeeds in connecting to the saved server on `SM-S9380` and opens the main `Window`, the app closes immediately instead of showing the main controller window.
- 🔷 **Expected:** `Bootstrap` closes and the main Android `Window` (`Adw.OverlaySplitView` drawer + tabs) appears on screen; disconnecting from `Settings` returns to `Bootstrap` on the same activity.
- 🔷 **Actual:** `Bootstrap.use()` calls `window.present()` on a second `Adw.ApplicationWindow` and closes the initial `host` window. Because `AndroidManifest.xml` uses `android:launchMode="singleTask"`, Android refuses to spawn a second `ToplevelActivity` (`result code=3`), and closing `host` finishes the only `ToplevelActivity` in the task.

---

## Evidence

- ✔️ `logcat` on `SM-S9380` (`pid 19786`) right after `Bootstrap.use()` succeeded:
  - `D Gdk     : Spawning activity for toplevel: (transient 0x0)`
  - `I ActivityTaskManager: START u0 {flg=0x18000000 xflg=0x4 cmp=org.roojs.argus/org.gtk.android.ToplevelActivity (has extras)} with LAUNCH_SINGLE_TASK from uid 10031 (org.roojs.argus) ... result code=3`
  - `D WindowManagerShell: onActivityRestartAttempt: topActivity=ComponentInfo{org.roojs.argus/org.gtk.android.ToplevelActivity}, wasVisible=true`
  - `D Gdk     : AndroidSurface: hide called 0xb400006f97943610 [GdkAndroidToplevel] (1 0)`
  - Followed immediately by `Transition type=CLOSE` destroying `org.roojs.argus/org.gtk.android.ToplevelActivity`.
- ✔️ `packaging/android/build-apk.sh:102-104` sets `android:launchMode="singleTask"` so switching away and returning resumes the existing `ToplevelActivity` rather than cold-restarting GTK.
- ✔️ `controller/android/Application.vala:139` creates a throwaway `host = new Adw.ApplicationWindow(this)` and calls `host.present()`, then `controller/dialog/Bootstrap.vala:1011-1019` creates a second `new Window(...)`, calls `window.present()`, and closes `host`. `controller/tab/Settings.vala:184-190` does the same in reverse on disconnect.

---

## Root cause

- ✔️ Under `android:launchMode="singleTask"`, the Android app can only own one `ToplevelActivity` (`Adw.ApplicationWindow`) at a time. Opening a new `Window` while closing the first `host` window fails to create a second `ToplevelActivity` (`START_RETURN_INTENT_TO_CALLER` / `result code=3`) and closes the active `ToplevelActivity`.

---

## Proposed fix

Keep **one** `Argus.Controller.Window` (`Adw.ApplicationWindow`) on Android for the entire app lifetime, starting with the Argus logo/spinner backdrop and swapping its `content` when opening a server or returning to `Bootstrap` on disconnect.

### 1. `controller/android/Application.vala` — create `this.window = new Window(this)` as the single window

**Where:** `Application()` `activate` callback (`119-147`).

#### Remove

```vala
				var host_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 16) {
					margin_top = 48,
					margin_bottom = 48,
					margin_start = 24,
					margin_end = 24,
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.START
				};
				host_box.append(new Gtk.Image() {
					icon_name = "org.roojs.ArgusController",
					pixel_size = 160
				});
				host_box.append(new Gtk.Label("Argus Remote Manager") {
					css_classes = { "title-2" }
				});
				host_box.append(new Adw.Spinner() {
					width_request = 32,
					height_request = 32,
					halign = Gtk.Align.CENTER
				});
				var host = new Adw.ApplicationWindow(this) {
					title = "Argus Remote Manager " + Argus.VERSION,
					content = host_box
				};
				host.set_default_size(420, 720);
				host.present();
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(host);
```

#### Replace with

```vala
				this.window = new Window(this);
				this.window.present();
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(this.window);
```

### 2. `controller/android/Window.vala` — initialize with backdrop and swap content in `open()` / `unload()`

**Where:** `Window` constructor (`65-228`).

#### Remove

```vala
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
			Object(application: app);
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
```

And the rest of the constructor body (`header` … `connection_check_id`), replacing with:

#### Replace with

- `public Window(Application app)` sets `this.app = app`, `this.title = "Argus Remote Manager " + Argus.VERSION`, `this.set_default_size(420, 720)`, wires `this.close_request`, and calls `this.unload()` to display the logo/spinner backdrop.
- `public void unload()` stops `this.connection_check_id`, resets `this.title`, `this.title_label`, `this.reconnecting`, `this.was_connected`, and sets `this.content` to the logo/spinner backdrop.
- `public void open(Connection connection, Argus.Shared.Registration.Data issued)` stops any prior `this.connection_check_id`, assigns `this.connection` and `this.issued`, builds the `Adw.OverlaySplitView` + tabs into `this.content`, and starts `this.connection_check_id`.

### 3. `controller/dialog/Bootstrap.vala` & `controller/tab/Settings.vala` — reuse `app.window` on `#if ANDROID`

**Where:** `controller/dialog/Bootstrap.vala` (`use()`, `997-1020`) and `controller/tab/Settings.vala` (`animation.done`, `180-195`).

#### Remove (`controller/dialog/Bootstrap.vala`)

```vala
				var app = this.app;
				var previous = app.window;
				var replace = app.running_window;
				if (replace) {
					app.rpc.disconnect();
					previous.leaving = true;
				}
				/* The agent page connects notifications while the window is built. */
				app.rpc = rpc;
				var window = new Window(app, connection, issued);
				app.running_window = true;
				app.window = window;
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

#### Replace with

```vala
				var app = this.app;
				var replace = app.running_window;
				if (replace) {
					app.rpc.disconnect();
				}
				/* The agent page connects notifications while the window is built. */
				app.rpc = rpc;
#if ANDROID
				app.running_window = true;
				app.window.open(connection, issued);
				this.close();
#else
				var previous = app.window;
				if (replace) {
					previous.leaving = true;
				}
				var window = new Window(app, connection, issued);
				app.running_window = true;
				app.window = window;
				window.present();
				this.close();
				if (replace) {
					previous.close();
				}
#endif
```

#### Remove (`controller/tab/Settings.vala`)

```vala
						this.window.app.running_window = false;
						this.window.leaving = true;
						this.window.app.rpc.disconnect();
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

#### Replace with

```vala
						this.window.app.running_window = false;
						this.window.app.rpc.disconnect();
#if ANDROID
						this.window.unload();
						new Dialog.Bootstrap(this.window.app, "choose").present(this.window);
#else
						this.window.leaving = true;
						this.window.close();
						new Dialog.Bootstrap(this.window.app, "choose").present(null);
#endif
```

---

## Attempts / changelog

- ✔️ Documented root cause and proposed fix.
- ✔️ Applied changes to `controller/android/Application.vala`, `controller/android/Window.vala`, `controller/dialog/Bootstrap.vala`, and `controller/tab/Settings.vala`.
- ✅ Verified on `SM-S9380`: `Bootstrap` connected to `192.168.0.12` and switched seamlessly to the main `Adw.OverlaySplitView` drawer (`Argus RM 0.1.19`) without `singleTask` killing the activity; tapping `Agent / Controllers` auto-hid the drawer and showed the top-left hamburger button and `192.168.0.12 - Agent / Controllers`.
