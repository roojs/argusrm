# Android connection fails with "Could not create the runtime directory" & RegisterWindow 10s close lacks countdown

**Status:** ✔️ applied and verified on `SM-S9380` — awaiting user verification (`✅`)

**Pointer:** `docs/bug-fix-process.md`, `controller/dialog/Bootstrap.vala`, `controller/android/Application.vala`, `shared/RegisterWindow.vala`

---

## Problem

- 🔷 After entering the registration PIN on `SM-S9380`:
  1. `RegisterWindow` displays `"Registration succeeded. This window will close in 10 seconds."` for a full 10 seconds with no visible countdown or progress.
  2. When it closes, `Bootstrap` displays `"Could not connect"` / `"Could not create the runtime directory"`.
- 🔷 **Expected:**
  - `Bootstrap` saves the CA certificate to a writable directory on Android and opens the controller main window immediately after registration succeeds.
  - When `RegisterWindow` uses its 10-second auto-close timer (agent registration), it ticks down `"10 seconds"` → `"9 seconds"` → … → `"1 second"` so the user sees it is alive; when used by the controller (`is_controller == true`), `Bootstrap` takes over immediately upon `certificate_received` instead of leaving `RegisterWindow` sitting on top for 10 seconds.

---

## Evidence

- ✔️ **`Could not create the runtime directory` (`controller/dialog/Bootstrap.vala:946-954`):**
  - `Bootstrap.use()` calls `GLib.Environment.get_user_runtime_dir()`, creates that directory with `0700`, and writes `argusrm-ca.pem` there for `GLib.TlsFileDatabase.@new(ca_path)`.
  - On Android, `gdk/android/gdkandroidruntime.c` (`277-281`) calls `g_set_user_dirs()` for `XDG_CONFIG_DIRS`, `XDG_DATA_DIRS`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME`, leaving `XDG_RUNTIME_DIR`, `XDG_CACHE_HOME`, and `HOME` unset.
  - GLib's `g_get_user_runtime_dir()` (`glib/gutils.c:2140-2175`) falls back to `g_build_user_cache_dir()` → `g_build_home_dir()` + `/.cache` → `/.cache`, which fails `mkdir` on Android's read-only root filesystem and throws `"Could not create the runtime directory"`.
  - Similarly, `controller/android/Application.vala:75` calls `GLib.Environment.get_user_cache_dir()` for `controller.log`, hitting the same `/.cache` fallback.
- ✔️ **10-second static close message (`shared/RegisterWindow.vala:731-747` & `controller/dialog/Bootstrap.vala:876-892`):**
  - `RegisterWindow.registration_succeeded()` sets static text `"Registration succeeded. This window will close in 10 seconds."` and calls `GLib.Timeout.add_seconds(10, ...)` without updating the seconds each second.
  - That 10-second delay was added for the **Agent** (`agent/linux/Application.vala:376,453` and `agent/Win32/tray/Tray.vala`) so the user can read confirmation while the background agent restarts.
  - For the **Controller** (`Bootstrap.connect_remote()` sets `is_controller = true`), `certificate_received` calls `Bootstrap.finish_registration(window.issued)` which changes `Bootstrap` underneath to `"Server registered"` and probes after 2s to call `Bootstrap.use()` (which normally closes `Bootstrap` and `RegisterWindow` together). Because `Bootstrap.use()` failed on `"Could not create the runtime directory"`, `Bootstrap` stayed open behind `RegisterWindow`, leaving `RegisterWindow` frozen on `"This window will close in 10 seconds."` for all 10 seconds.

---

## Root cause

1. ✔️ `Bootstrap.use()` writes `argusrm-ca.pem` to `GLib.Environment.get_user_runtime_dir()`, which is unconfigured (`/.cache`) on Android instead of `GLib.Environment.get_user_config_dir()` (which `gdkandroidruntime.c` sets to `<ext_files_dir>/etc` and where `argusrm` already writes `connections.json`, `credentials/`, and `certs/`).
2. ✔️ `RegisterWindow.registration_succeeded()` schedules a single 10-second timeout without updating the countdown label, and `Bootstrap.connect_remote()` leaves `RegisterWindow` open over `Bootstrap` even though `Bootstrap` immediately takes over the registration flow on `certificate_received`.

---

## Proposed fix

### 1. `controller/dialog/Bootstrap.vala` — use `argusrm` config dir on Android for `argusrm-ca.pem` and close `RegisterWindow` on `certificate_received`

**Where:** `connect_remote()` (`876-892`) and `use()` (`946-950`).

#### Remove (`connect_remote`)

```vala
				this.finish_registration(window.issued);
			});
```

#### Replace with

```vala
				this.finish_registration(window.issued);
				window.close();
			});
```

#### Remove (`use`)

```vala
				var dir = GLib.Environment.get_user_runtime_dir();
				if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
					throw new GLib.FileError.FAILED(
						"Could not create the runtime directory");
				}
```

#### Replace with

```vala
#if ANDROID
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(), "argusrm");
#else
				var dir = GLib.Environment.get_user_runtime_dir();
#endif
				if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
					throw new GLib.FileError.FAILED(
						"Could not create the runtime directory");
				}
```

### 2. `controller/android/Application.vala` — log to `get_user_config_dir()` instead of `get_user_cache_dir()`

**Where:** `Application()` constructor (`74-76`).

#### Remove

```vala
					var log_dir = GLib.Path.build_filename(
						GLib.Environment.get_user_cache_dir(), "argusrm");
```

#### Replace with

```vala
					var log_dir = GLib.Path.build_filename(
						GLib.Environment.get_user_config_dir(), "argusrm");
```

### 3. `shared/RegisterWindow.vala` — live 1-second countdown in `registration_succeeded()` (skipped for controller)

**Where:** fields (`74-77`) and `registration_succeeded()` (`731-747`).

#### Add — field after `private uint close_id = 0;`

```vala
		private int close_remaining = 0;
```

#### Remove (`registration_succeeded`)

```vala
		private void registration_succeeded()
		{
			this.pin_box.visible = false;
			this.offer_box.visible = false;
			this.address_box.visible = false;
			this.certificate_received();
			if (!this.registering) {
				return;
			}
			this.listen_label.label =
				"Registration succeeded. This window will close in 10 seconds.";
			this.close_id = GLib.Timeout.add_seconds(10, () => {
				this.close_id = 0;
				this.close();
				return false;
			});
		}
```

#### Replace with

```vala
		private void registration_succeeded()
		{
			this.pin_box.visible = false;
			this.offer_box.visible = false;
			this.address_box.visible = false;
			this.certificate_received();
			if (!this.registering || this.is_controller) {
				return;
			}
			this.close_remaining = 10;
			this.listen_label.label =
				"Registration succeeded. This window will close in 10 seconds.";
			this.close_id = GLib.Timeout.add_seconds(1, () => {
				this.close_remaining--;
				if (this.close_remaining <= 0) {
					this.close_id = 0;
					this.close();
					return false;
				}
				var marker = this.listen_label.label.index_of("This window will close in ");
				var prefix = marker >= 0 ?
					this.listen_label.label.substring(0, marker) :
					"Registration succeeded. ";
				var unit = this.close_remaining == 1 ? " second." : " seconds.";
				this.listen_label.label = prefix + "This window will close in " +
					this.close_remaining.to_string() + unit;
				return true;
			});
		}
```

---

## Attempts / changelog

- ✔️ Documented root cause and proposed fix.
- ✔️ Applied changes to `controller/dialog/Bootstrap.vala`, `controller/android/Application.vala`, and `shared/RegisterWindow.vala`.
- ✔️ Verified on Linux (`ninja -C build`, `meson test -C build --print-errorlogs`, `ninja -C build valadoc`) and installed on `SM-S9380`: no `"Could not create the runtime directory"` error; `Bootstrap.use()` connected to `192.168.0.12` cleanly.
- ⏳ 🔷 Awaiting user verification of the live `10 -> 1` countdown on agent registration and end-to-end PIN registration on `SM-S9380`.
