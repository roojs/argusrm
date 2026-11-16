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
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class PairBrowse {
	private static final String TAG = "ArgusPair";
	private static final String SERVICE_TYPE = "_rpc._tcp.";
	private static final Handler MAIN = new Handler(Looper.getMainLooper());
	private static final ExecutorService PROBE_EXEC = Executors.newSingleThreadExecutor();

	private static NsdManager manager;
	private static NsdManager.DiscoveryListener listener;
	private static final List<NsdManager.ServiceInfoCallback> infoCallbacks = new ArrayList<>();
	private static WifiManager.MulticastLock multicastLock;
	private static Runnable timeoutTask;
	private static int generation = 0;
	private static volatile String found = "";
	private static volatile String fallbackFound = "";
	private static final Set<String> probed = new HashSet<>();

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
		fallbackFound = "";
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
		if (manager != null && Build.VERSION.SDK_INT >= 33) {
			for (NsdManager.ServiceInfoCallback cb : infoCallbacks) {
				try {
					manager.unregisterServiceInfoCallback(cb);
				} catch (IllegalArgumentException ignored) {
				}
			}
			infoCallbacks.clear();
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
		probed.clear();
		fallbackFound = "";
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
				resolve(nsd, app, info, ticket);
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
				if (fallbackFound != null && fallbackFound.length() > 0) {
					Log.w(TAG, "timeout fallback to " + fallbackFound.replace('\n', ' '));
					found = fallbackFound;
				} else {
					found = "none";
				}
			}
			stopActive();
		};
		MAIN.postDelayed(timeoutTask, 30000);
	}

	private static void resolve(NsdManager nsd, Context app, NsdServiceInfo info, int ticket) {
		if (Build.VERSION.SDK_INT >= 33) {
			NsdManager.ServiceInfoCallback cb = new NsdManager.ServiceInfoCallback() {
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
			infoCallbacks.add(cb);
			nsd.registerServiceInfoCallback(info, app.getMainExecutor(), cb);
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
		if (single != null && !single.isLinkLocalAddress() && !candidates.contains(single)) {
			if (single instanceof Inet4Address) {
				candidates.add(single);
			}
		}
		if (candidates.isEmpty()) {
			return;
		}
		List<InetAddress> fresh = new ArrayList<>();
		for (InetAddress addr : candidates) {
			String key = addr.getHostAddress() + ":" + port;
			if (!probed.contains(key)) {
				probed.add(key);
				fresh.add(addr);
			}
		}
		if (fresh.isEmpty()) {
			return;
		}
		Log.i(TAG, "resolved " + resolved.getServiceName() + " port=" + port + " probing=" + fresh);
		PROBE_EXEC.execute(() -> {
			for (InetAddress addr : fresh) {
				if (ticket != generation || (found != null && found.length() > 0 && !found.equals("none"))) {
					return;
				}
				String ip = addr.getHostAddress();
				if (fallbackFound == null || fallbackFound.length() == 0) {
					fallbackFound = id + "\n" + ip + ":" + port;
				}
				try (Socket s = new Socket()) {
					s.connect(new InetSocketAddress(addr, port), 1500);
					Log.i(TAG, "reachable candidate " + ip + ":" + port);
					if (ticket == generation) {
						found = id + "\n" + ip + ":" + port;
					}
					return;
				} catch (IOException e) {
					Log.i(TAG, "unreachable candidate " + ip + ":" + port + ": " + e.getMessage());
				}
			}
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
