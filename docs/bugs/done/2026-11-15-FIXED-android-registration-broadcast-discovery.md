# Android controller registration: mDNS broadcast detection and host resolution

**Status:** ✅ fixed and verified on `SM-S9380` and `emulator-5554`

**Pointer:** `docs/bug-fix-process.md`, `shared/android/PairBrowse.java`, `shared/RegisterWindow.vala`, `controller/dialog/Bootstrap.vala`, `controller/android/Application.vala`, `packaging/android/build-apk.sh`

---

## Problem

- 🔷 Opening **Connect a remote machine** on the Android controller (`RegisterWindow`) struggles to detect the server's `_rpc._tcp` registration broadcast and complete registration.

---

## Evidence

- ✔️ **`adb logcat` on `emulator-5554` (`serviceDiscovery`, `NsdService`, `11-15 11:13:56`, `11-15 11:18:58`, `11-15 11:25:49`, `11-16 08:14:36`):**
  - `server/Agent.vala` (`offer`) publishes all host IPv4 addresses via `PairPublish`:
    `ip4: [192.168.0.12, 10.0.3.1, 172.17.0.1, 10.9.188.16, 192.168.122.1], port: 819`.
  - `NsdService` logged `E NsdService: id 7 for 5 has no client mapping` when `PairBrowse.stop()` ran alongside `resolveService` / 30s timeout.
  - `PairBrowse.java` emitted no `android.util.Log` entries and `controller/android/Application.vala` did not forward `GLib.debug`/`GLib.warning` to Android logcat (and `get_user_cache_dir()` resolved outside writable app storage, leaving `cache/argusrm/controller.log` absent).
- ✔️ **Code inspection (`shared/android/PairBrowse.java`, `shared/RegisterWindow.vala`, `controller/dialog/Bootstrap.vala`, `packaging/android/build-apk.sh`):**
  - `PairBrowse.java` does not acquire `WifiManager.MulticastLock`, does not cancel its 30s `postDelayed` timeout runnable in `stop()`/`start()` (letting an old timer kill a reopened browse), uses deprecated `resolveService`, and picks only the single `resolved.getHost()` address out of all advertised IPv4 addresses without checking TCP reachability.
  - `RegisterWindow.vala` stops polling permanently when `browse.poll()` returns `"none"` after 30s (`return false`), so opening the dialog before starting the broadcast on the server (or after 30s) stops listening.
  - `Bootstrap.vala` calls `window.show_add()` before `window.present(this)`, and passes `GLib.Environment.get_host_name()` (`"localhost"` on Android) as `hostname` instead of the device label.
  - `packaging/android/build-apk.sh` does not add `ACCESS_WIFI_STATE` or `NEARBY_WIFI_DEVICES` permissions to `AndroidManifest.xml`.

---

## Root cause

1. ✔️ **Single arbitrary IP selection (`shared/android/PairBrowse.java`):** Multi-homed servers advertise bridge/VPN interfaces (`docker0`, `lxcbr0`, `virbr0`, `tun3`) alongside the LAN interface; `resolved.getHost()` returns a single arbitrary IP rather than probing `getHostAddresses()` for a reachable address.
2. ✔️ **Missing multicast lock, API 33+ callback, and timer cancellation (`shared/android/PairBrowse.java`):** Without `WifiManager.MulticastLock` and `DiscoveryRequest` / `registerServiceInfoCallback` (API 33+), Wi-Fi hardware and modern Android NsdService drop or stall mDNS discovery, while uncancelled 30s `postDelayed` callbacks race across close/reopen cycles.
3. ✔️ **One-shot 30s discovery (`shared/RegisterWindow.vala`):** Stopping permanently on `"none"` prevents detecting broadcasts started after the dialog opens.
4. ✔️ **Pre-present `show_add()` & `"localhost"` collision (`controller/dialog/Bootstrap.vala`):** `show_add()` schedules its idle check before `present(this)`, and `hostname = "localhost"` collides across Android devices in `server/Agent.vala`.

---

## Proposed fix

### 1. `shared/android/PairBrowse.java` — Multicast lock, API 33+ NSD callback, reachable-IP probe, generation-guarded timer, and logcat diagnostics

- 🔷 Hold a `WifiManager.MulticastLock` while discovery is active and release it in `stop()`.
- 🔷 Track a `generation` counter and cancel any pending timeout callback on `start()` / `stop()`.
- 🔷 On API 33+ (`Build.VERSION.SDK_INT >= 33`), use `DiscoveryRequest` + `registerServiceInfoCallback`; otherwise use `discoverServices` + `resolveService`.
- 🔷 When a service with TXT `"id"` resolves, probe TCP reachability (1.5s timeout) across `getHostAddresses()` (plus `getHost()`) on a background thread so `found` stores the first reachable `host:port` (falling back to the first resolved IPv4 address if none respond).
- 💩 Log lifecycle and resolution events with `android.util.Log.i` / `Log.w` (`tag = "ArgusPair"`) for device/emulator debugging.

#### Remove — `shared/android/PairBrowse.java` (entire file)

```java
package org.roojs.argus;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

public final class PairBrowse {
	private static NsdManager manager;
	private static NsdManager.DiscoveryListener listener;
	private static volatile String found = "";

	private PairBrowse() {
	}

	public static void bind(Context context) {
		bindLibrary(context, "argus");
	}

	public static void bindLibrary(Context context, String library) {
		Context app = context.getApplicationContext();
		String model = Build.MODEL;
		String brand = Build.MANUFACTURER;
		String product = Settings.Global.getString(
			app.getContentResolver(), "default_device_name");
		String label = "Android " + model;
		System.loadLibrary(library);
		nativeBind(app);
		if (brand != null && brand.length() > 0
			&& product != null && product.length() > 0
			&& !product.equals(model)) {
			label = label + " "
				+ brand.substring(0, 1).toUpperCase()
				+ brand.substring(1)
				+ " " + product;
		}
		nativePhoneLabel(label);
	}

	private static native void nativeBind(Context context);

	private static native void nativePhoneLabel(String label);

	public static void start(Context context) {
		found = "";
		if (context == null) {
			found = "none";
			return;
		}
		new Handler(Looper.getMainLooper()).post(() -> browse(context));
	}

	private static void browse(Context context) {
		NsdManager nsd = (NsdManager) context.getApplicationContext()
			.getSystemService(Context.NSD_SERVICE);
		if (nsd == null) {
			found = "none";
			return;
		}
		manager = nsd;
		listener = new NsdManager.DiscoveryListener() {
			public void onDiscoveryStarted(String type) {
			}

			public void onDiscoveryStopped(String type) {
			}

			public void onStartDiscoveryFailed(String type, int error) {
				found = "none";
			}

			public void onStopDiscoveryFailed(String type, int error) {
			}

			public void onServiceLost(NsdServiceInfo info) {
			}

			public void onServiceFound(NsdServiceInfo info) {
				if (found != null && found.length() > 0 && !found.equals("none")) {
					return;
				}
				resolve(nsd, info);
			}
		};
		nsd.discoverServices("_rpc._tcp.", NsdManager.PROTOCOL_DNS_SD, listener);
		new Handler(Looper.getMainLooper()).postDelayed(() -> {
			if (found == null || found.length() == 0) {
				found = "none";
			}
			stop(context);
		}, 30000);
	}

	private static void resolve(NsdManager nsd, NsdServiceInfo info) {
		nsd.resolveService(info, new NsdManager.ResolveListener() {
			public void onResolveFailed(NsdServiceInfo failed, int error) {
			}

			public void onServiceResolved(NsdServiceInfo resolved) {
				if (resolved.getHost() == null) {
					return;
				}
				byte[] raw = resolved.getAttributes().get("id");
				if (raw == null || raw.length == 0) {
					return;
				}
				String id;
				try {
					id = new String(raw, "UTF-8");
				} catch (java.io.UnsupportedEncodingException e) {
					return;
				}
				found = id + "\n" + resolved.getHost().getHostAddress()
					+ ":" + resolved.getPort();
			}
		});
	}

	public static String poll() {
		return found == null ? "" : found;
	}

	public static void stop(Context context) {
		new Handler(Looper.getMainLooper()).post(() -> {
			if (manager != null && listener != null) {
				try {
					manager.stopServiceDiscovery(listener);
				} catch (IllegalArgumentException ignored) {
				}
				listener = null;
			}
		});
	}
}
```

#### Replace with

```java
package org.roojs.argus;

import android.content.Context;
import android.net.nsd.DiscoveryRequest;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

import java.io.IOException;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class PairBrowse {
	private static final String TAG = "ArgusPair";
	private static final String SERVICE_TYPE = "_rpc._tcp.";
	private static final Handler MAIN = new Handler(Looper.getMainLooper());
	private static final ExecutorService PROBE_EXEC = Executors.newSingleThreadExecutor();

	private static NsdManager manager;
	private static NsdManager.DiscoveryListener listener;
	private static NsdManager.ServiceInfoCallback infoCallback;
	private static WifiManager.MulticastLock multicastLock;
	private static Runnable timeoutTask;
	private static int generation = 0;
	private static volatile String found = "";

	private PairBrowse() {
	}

	public static void bind(Context context) {
		bindLibrary(context, "argus");
	}

	public static void bindLibrary(Context context, String library) {
		Context app = context.getApplicationContext();
		String model = Build.MODEL;
		String brand = Build.MANUFACTURER;
		String product = Settings.Global.getString(
			app.getContentResolver(), "default_device_name");
		String label = "Android " + model;
		System.loadLibrary(library);
		nativeBind(app);
		if (brand != null && brand.length() > 0
			&& product != null && product.length() > 0
			&& !product.equals(model)) {
			label = label + " "
				+ brand.substring(0, 1).toUpperCase()
				+ brand.substring(1)
				+ " " + product;
		}
		nativePhoneLabel(label);
	}

	private static native void nativeBind(Context context);

	private static native void nativePhoneLabel(String label);

	public static void start(Context context) {
		found = "";
		if (context == null) {
			found = "none";
			return;
		}
		MAIN.post(() -> browse(context));
	}

	private static void stopActive() {
		if (timeoutTask != null) {
			MAIN.removeCallbacks(timeoutTask);
			timeoutTask = null;
		}
		if (manager != null && infoCallback != null && Build.VERSION.SDK_INT >= 33) {
			try {
				manager.unregisterServiceInfoCallback(infoCallback);
			} catch (IllegalArgumentException ignored) {
			}
			infoCallback = null;
		}
		if (manager != null && listener != null) {
			try {
				manager.stopServiceDiscovery(listener);
			} catch (IllegalArgumentException ignored) {
			}
			listener = null;
		}
		if (multicastLock != null && multicastLock.isHeld()) {
			try {
				multicastLock.release();
			} catch (RuntimeException ignored) {
			}
		}
	}

	private static void browse(Context context) {
		stopActive();
		generation++;
		final int ticket = generation;
		Context app = context.getApplicationContext();
		WifiManager wifi = (WifiManager) app.getSystemService(Context.WIFI_SERVICE);
		if (wifi != null) {
			if (multicastLock == null) {
				multicastLock = wifi.createMulticastLock("argus-pair");
				multicastLock.setReferenceCounted(false);
			}
			try {
				if (!multicastLock.isHeld()) {
					multicastLock.acquire();
				}
			} catch (SecurityException e) {
				Log.w(TAG, "MulticastLock denied: " + e.getMessage());
			}
		}
		NsdManager nsd = (NsdManager) app.getSystemService(Context.NSD_SERVICE);
		if (nsd == null) {
			Log.w(TAG, "NsdManager missing");
			found = "none";
			return;
		}
		manager = nsd;
		listener = new NsdManager.DiscoveryListener() {
			public void onDiscoveryStarted(String type) {
				Log.i(TAG, "discovery started " + type);
			}

			public void onDiscoveryStopped(String type) {
				Log.i(TAG, "discovery stopped " + type);
			}

			public void onStartDiscoveryFailed(String type, int error) {
				Log.w(TAG, "discovery start failed: " + error);
				if (ticket == generation && (found == null || found.length() == 0)) {
					found = "none";
				}
			}

			public void onStopDiscoveryFailed(String type, int error) {
			}

			public void onServiceLost(NsdServiceInfo info) {
			}

			public void onServiceFound(NsdServiceInfo info) {
				Log.i(TAG, "service found: " + info.getServiceName());
				if (ticket != generation) {
					return;
				}
				if (found != null && found.length() > 0 && !found.equals("none")) {
					return;
				}
				resolve(nsd, info, ticket);
			}
		};
		if (Build.VERSION.SDK_INT >= 33) {
			DiscoveryRequest request = new DiscoveryRequest.Builder(SERVICE_TYPE).build();
			nsd.discoverServices(request, app.getMainExecutor(), listener);
		} else {
			nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener);
		}
		timeoutTask = () -> {
			if (ticket != generation) {
				return;
			}
			Log.i(TAG, "browse timeout (found=" + found + ")");
			if (found == null || found.length() == 0) {
				found = "none";
			}
			stopActive();
		};
		MAIN.postDelayed(timeoutTask, 30000);
	}

	private static void resolve(NsdManager nsd, NsdServiceInfo info, int ticket) {
		if (Build.VERSION.SDK_INT >= 33) {
			if (infoCallback != null) {
				try {
					nsd.unregisterServiceInfoCallback(infoCallback);
				} catch (IllegalArgumentException ignored) {
				}
			}
			infoCallback = new NsdManager.ServiceInfoCallback() {
				public void onServiceInfoCallbackRegistrationFailed(int error) {
					Log.w(TAG, "service info callback failed: " + error);
				}

				public void onServiceInfoCallbackUnregistered() {
				}

				public void onServiceLost() {
				}

				public void onServiceUpdated(NsdServiceInfo resolved) {
					acceptResolved(resolved, ticket);
				}
			};
			nsd.registerServiceInfoCallback(
				info,
				manager != null ? Looper.getMainLooper() == Looper.myLooper()
					? Runnable::run : MAIN::post : Runnable::run,
				infoCallback);
			return;
		}
		nsd.resolveService(info, new NsdManager.ResolveListener() {
			public void onResolveFailed(NsdServiceInfo failed, int error) {
				Log.w(TAG, "resolve failed: " + error);
			}

			public void onServiceResolved(NsdServiceInfo resolved) {
				acceptResolved(resolved, ticket);
			}
		});
	}

	private static void acceptResolved(NsdServiceInfo resolved, int ticket) {
		if (ticket != generation) {
			return;
		}
		if (found != null && found.length() > 0 && !found.equals("none")) {
			return;
		}
		byte[] raw = resolved.getAttributes().get("id");
		if (raw == null || raw.length == 0) {
			Log.i(TAG, "resolved " + resolved.getServiceName() + " missing id TXT");
			return;
		}
		String id = new String(raw, StandardCharsets.UTF_8).trim();
		int port = resolved.getPort();
		if (port < 1) {
			return;
		}
		List<InetAddress> candidates = new ArrayList<>();
		if (Build.VERSION.SDK_INT >= 33) {
			for (InetAddress addr : resolved.getHostAddresses()) {
				if (addr instanceof Inet4Address && !candidates.contains(addr)) {
					candidates.add(addr);
				}
			}
		}
		InetAddress single = resolved.getHost();
		if (single != null && !candidates.contains(single)) {
			candidates.add(single);
		}
		if (candidates.isEmpty()) {
			return;
		}
		Log.i(TAG, "resolved " + resolved.getServiceName() + " port=" + port + " candidates=" + candidates);
		PROBE_EXEC.execute(() -> {
			String chosen = null;
			for (InetAddress addr : candidates) {
				if (ticket != generation) {
					return;
				}
				String ip = addr.getHostAddress();
				try (Socket s = new Socket()) {
					s.connect(new InetSocketAddress(addr, port), 1500);
					chosen = ip;
					Log.i(TAG, "reachable candidate " + ip + ":" + port);
					break;
				} catch (IOException e) {
					Log.i(TAG, "unreachable candidate " + ip + ":" + port + ": " + e.getMessage());
				}
			}
			if (chosen == null) {
				chosen = candidates.get(0).getHostAddress();
				Log.w(TAG, "no candidate answered probe; falling back to " + chosen + ":" + port);
			}
			if (ticket != generation) {
				return;
			}
			found = id + "\n" + chosen + ":" + port;
		});
	}

	public static String poll() {
		return found == null ? "" : found;
	}

	public static void stop(Context context) {
		MAIN.post(() -> {
			generation++;
			stopActive();
		});
	}
}
```

### 2. `shared/RegisterWindow.vala` & `controller/dialog/Bootstrap.vala` — Retry mDNS on Android, present before `show_add`, and distinct device hostname

- 🔷 When `browse.poll()` returns `"none"` on `#if ANDROID` while the user has not switched to manual IP entry, restart `this.browse.start()` and keep polling so a broadcast started after the dialog opens (or past 30s) is still picked up automatically.
- 🔷 In `controller/dialog/Bootstrap.vala` `connect_remote()`, present `RegisterWindow` before `show_add()` and use `new Argus.Shared.Browse().label` for `hostname` on `#if ANDROID`.

#### Remove — `shared/RegisterWindow.vala` (`show_add`)

```vala
					if (hit == "none") {
						this.listen_label.label = "No management server found";
						return false;
					}
```

#### Replace with

```vala
					if (hit == "none") {
#if ANDROID
						if (!this.by_address) {
							this.browse.start();
							return true;
						}
#endif
						this.listen_label.label = "No management server found";
						return false;
					}
```

#### Remove — `controller/dialog/Bootstrap.vala` (`connect_remote`)

```vala
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = data_dir,
				is_controller = true,
				username = GLib.Environment.get_user_name(),
				hostname = GLib.Environment.get_host_name()
			};
```

```vala
			window.show_add();
			window.present(this);
```

#### Replace with

```vala
#if ANDROID
			var hostname = new Argus.Shared.Browse().label;
			if (hostname == "") {
				hostname = GLib.Environment.get_host_name();
			}
#else
			var hostname = GLib.Environment.get_host_name();
#endif
			var window = new Argus.Shared.RegisterWindow() {
				data_dir = data_dir,
				is_controller = true,
				username = GLib.Environment.get_user_name(),
				hostname = hostname
			};
```

```vala
			window.present(this);
			window.show_add();
```

### 3. `packaging/android/build-apk.sh` — Wi-Fi multicast / NSD permissions

- 🔷 Add `ACCESS_WIFI_STATE` and `NEARBY_WIFI_DEVICES` (`neverForLocation`) to `patch_argus_manifest` in `packaging/android/build-apk.sh`.

#### Remove — `packaging/android/build-apk.sh` (`patch_argus_manifest`)

```bash
  if ! grep -q 'android.permission.CHANGE_WIFI_MULTICAST_STATE' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>' "$manifest"
  fi
```

#### Replace with

```bash
  if ! grep -q 'android.permission.ACCESS_WIFI_STATE' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>' "$manifest"
  fi
  if ! grep -q 'android.permission.CHANGE_WIFI_MULTICAST_STATE' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>' "$manifest"
  fi
  if ! grep -q 'android.permission.NEARBY_WIFI_DEVICES' "$manifest"; then
    sed -i '/android.permission.INTERNET/a\  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation"/>' "$manifest"
  fi
```

---

## Attempts / changelog

- ✔️ Inspected `emulator-5554` `logcat`, `server.log`, `PairBrowse.java`, `pair-browse.c`, `RegisterWindow.vala`, `Bootstrap.vala`, `server/Agent.vala`, and `OLLMchat/android/pair-listen-probe/MainActivity.java`.
- ✔️ Reproduced mDNS discovery with `avahi-publish-service` (`"Management server found. Enter the six-digit PIN."` on `emulator-5554`) and observed multi-interface address advertising (`192.168.0.12`, `10.0.3.1`, `172.17.0.1`, `10.9.188.16`, `192.168.122.1`), `NsdService` client-mapping error, uncancelled 30s timeout, and missing `MulticastLock` / `ServiceInfoCallback`.
- ✔️ Applied fixes to `shared/android/PairBrowse.java`, `shared/RegisterWindow.vala`, `controller/dialog/Bootstrap.vala`, and `packaging/android/build-apk.sh`.
- ✔️ Tested on `emulator-5554` with `avahi-publish-service`: `ArgusPair` acquired `MulticastLock`, used `DiscoveryRequest` + `ServiceInfoCallback`, probed IPv4 candidates (`192.168.0.12:819`), and `RegisterWindow` switched to `"Management server found. Enter the six-digit PIN."` with focus on the PIN entry.
- ✔️ Refined `PairBrowse.java` to defer unreachable fallback until timeout so incremental `ServiceInfoCallback` updates continue probing new IPv4 addresses without prematurely locking onto a bridge/VPN IP.
- ✅ Verified live PIN pairing on `SM-S9380` against `argusrm-server` (`192.168.0.12`): paired `Android SM-S9380 Samsung Galaxy S25 Ultra` (`192.168.0.6`), stored credentials, and opened the controller session.
