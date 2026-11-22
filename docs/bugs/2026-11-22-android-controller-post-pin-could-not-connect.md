# Android controller: PIN registers on server then Bootstrap shows “Could not connect”

**Status:** ⏳ fix applied; pending verify on `SM-S9380`

**Pointer:** `docs/bug-fix-process.md`, `controller/dialog/Bootstrap.vala`, `shared/SQT/Server.vala`, `shared/Register.vala`

---

## Problem

- 🔷 On **`SM-S9380`** (`org.roojs.argus` **0.1.3**), remote controller registration with a valid PIN succeeds on the management server, then the startup UI shows **Could not connect** instead of opening the main window.
- 🔷 **Expected:** Same as Linux desktop — brief **Server registered**, then TLS `RPC-Daemon.hello` and main window.
- 🔷 **Reproduce:** Connect a remote machine → enter PIN → wait for post-registration probe (~2s).

---

## Evidence

- ✔️ **Phone log** (`adb shell run-as org.roojs.argus cat …/files/etc/argusrm/controller.log`), failure at **2026-11-22 00:39:48** local (log timestamps):
  - `Register.vala:468: registering 192.168.0.16:819` — enrollment on registration port **819** succeeded.
  - TCP probes succeed (`GSocketClient: Connection successful!`).
  - `Client.vala:680: id=1 method=RPC-Daemon.hello`
  - `Client.vala:762: expected object type byte, got 0x0C`
  - `Client.vala:521: disconnect socket_path=tcp://192.168.0.16:817:817 pending=1`
  - `Client.vala:502: hello failed id=1: Client: disconnected`
- ✔️ **Saved credential** (`…/etc/argusrm/credentials/192.168.0.16.json` on device):
  - `port`: **817**
  - `addresses` (newline-separated `host:port` lines from `Agent.request_registration`):
    ```
    192.168.0.16:817
    10.0.3.1:817
    10.9.188.16:817
    192.168.122.1:817
    172.17.0.1:817
    ```
- ✔️ **Throwaway URL build** (reproduces log path without product code):
  ```text
  host = "192.168.0.16:817"   # value stored in Bootstrap.answered after probe
  port = 817
  → "tcp://" + host + ":" + str(port) == "tcp://192.168.0.16:817:817"
  ```
- ✔️ **Code** (`controller/dialog/Bootstrap.vala`):
  - `probe()` takes `hosts[this.address_index]` from `row.address_list()` — entries are **full lines** `ip:port` (`shared/SQT/Server.vala` adds `text`, not bare host).
  - On TCP success: `this.answered.set(row.name, host)` keeps the **full** `192.168.0.16:817` string.
  - `use()` builds `tcp://` + `host` + `:` + `server.port.to_string()` → **double port** when `host` already contains `:817`.
- ℹ️ **Not** the older Android runtime-dir failure: `argusrm-ca.pem` is present under `…/files/etc/argusrm/` (post-fix layout). UI subtitle here is RPC failure, not “Could not create the runtime directory”.
- ℹ️ **Package on device:** `org.roojs.argus` (not `org.roojs.ArgusController`). Config/log root: `/storage/emulated/0/Android/data/org.roojs.argus/files/etc/argusrm/`.

---

## Root cause

1. ✔️ **`Bootstrap.probe()` records `host:port` in `answered`, and `Bootstrap.use()` always appends `:` + `server.port`.** After remote registration, `addresses` are `host:817` lines; the successful probe stores e.g. `192.168.0.16:817`, producing RPC URL `tcp://192.168.0.16:817:817`. Hello reads non-RPC bytes (`0x0C`) and disconnects → Bootstrap **Could not connect**.
2. 🚫 Registration, mDNS, credential save, or Android TLS module load — ruled out by log (enrollment and TCP probe succeed; CA file written).

---

## Proposed fix

### 1. `controller/dialog/Bootstrap.vala` — store bare host from each address line in `probe()`

**Where:** `probe()` async success path (~lines 254–273).

#### Remove

```vala
				var host = hosts[this.address_index];
				this.address_index++;
				client.connect_to_host_async.begin(host, (uint16) row.port, null, (obj, res) => {
```

```vala
					this.answered.set(row.name, host);
```

#### Replace with

```vala
				var endpoint = hosts[this.address_index];
				this.address_index++;
				var connect_host = endpoint;
				var mark = endpoint.last_index_of(":");
				if (mark > 0) {
					connect_host = endpoint.substring(0, mark);
				}
				client.connect_to_host_async.begin(
					connect_host, (uint16) row.port, null, (obj, res) => {
```

```vala
					this.answered.set(row.name, connect_host);
```

(Probe already passes `row.port` to `connect_to_host_async`; only the hostname must be stripped to match `use()`.)

---

## Attempts / changelog

- ✔️ Pulled `controller.log` and credential JSON from `SM-S9380` via `adb` + `run-as org.roojs.argus`.
- ✔️ Confirmed malformed `socket_path` matches `Bootstrap.use()` string assembly.
- ✔️ Throwaway Python reproduces `tcp://192.168.0.16:817:817`.
- ✔️ Applied §1 in `controller/dialog/Bootstrap.vala` (`probe()` strips host before connect and `answered.set`).
- ✔️ `packaging/android/build-apk.sh` → `app-arm64-v8a-debug.apk`; `adb install -r` on `SM-S9380` (2026-11-22).

---

## Next

- ⏳ On phone: open Argus → **Retry** (saved server) or fresh PIN; expect `socket_path=tcp://192.168.0.16:817` in `controller.log` and main window.
- 💩 If Linux desktop remote registration still works today, capture whether `answered` / `last_host` on desktop avoids `host:port` lines (same `Bootstrap.vala` path — may be timing or older stored row shape).