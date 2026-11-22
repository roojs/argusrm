# Android controller: DebPackages.list drops TLS; Agent.list follows as “Client: disconnected”

**Status:** ⏳ diagnosed on `SM-S9380` + local server `192.168.0.16:817`; root cause open

**Pointer:** `docs/bug-fix-process.md`, `controller/android/Window.vala`, `OLLMchat/libocrpc/Client.vala`

---

## Problem

- 🔷 After the post-PIN connect fix, the Android controller opens and **SystemInfo** / startup lists work, but **Software → Debian packages** shows **Could not list Debian packages** / **Client: disconnected**, then **Machines** / tasks fail the same way.
- 🔷 **Expected:** Same RPC behaviour as desktop `argusrm-controller` on the same server.
- 🔷 **Reproduce:** Connect on phone → open aggregated Debian packages (Software).

---

## Evidence

- ✔️ **Phone** (`…/files/etc/argusrm/controller.log`, 2026-11-22 ~08:54 local):
  - `RPC-Daemon.hello` id=1 **ok**; `ScriptRepository.list`, `Distributable.list`, `SystemInfo.list` **ok**.
  - `DebPackages.list` id=5 → `expected object type byte, got 0x75` → `disconnect` → `DebPackages.list id=5: Client: disconnected`.
  - Reconnect `hello` id=6 → `root parse does not accept object arrays` → further `Agent.list` / `Task.all_targets` aborted (`pending=3` on hello id=7).
- ✔️ **Server** (`/var/log/argusrm/server.log`, same timestamps UTC+8):
  - `recv id=5 method=DebPackages.list` on phone TLS conn `0x5a31ef029980`.
  - ~360 ms later: `connection write error: … Connection reset by peer` (client closed mid-reply).
  - **No** server process exit; handler continues. Repeated `type id '0' is invalid` on **`Task.all_targets`** from a **second** controller TLS session `0x5a31efee1cd0` (desktop).
- ✔️ **Desktop controller** (`~/.cache/argusrm/controller.log`):
  - `DebPackages.list` id=21 at `08:54:29` → `replied id=21` ~1.5 s later on **same server**.
- ✔️ **ocrpc lineage (rules out “old distro vs new pixie”):**
  - `/lib/x86_64-linux-gnu/libocrpc.so` is the same file as `/home/alan/gitlive/OLLMchat/build/libocrpc/libocrpc.so` (`md5` `709c4df9…`, built 2026-11-21).
  - OLLMchat `HEAD` = `7bbe43a4` (`v1.4.15`).
  - Pixie `release.pins` `ocrpc` entry `resolved` = `7bbe43a4db2257fef85c582a24eba5ca024fc803` (same commit as live server build).
- 🚫 **Withdrawn:** dpkg **1.4.14** package label vs pixie **1.4.15** `.pc` Version — misleading here; server uses the live OLLMchat build, not an unrelated distro library.

---

## Root cause

1. ✔️ **Not a server crash.** The phone closes TLS while decoding the `DebPackages.list` reply; the server only logs **reset by peer**.
2. ✔️ **Primary failure:** bin decoder on the phone rejects wire data (`expected object type byte, got 0x75`) while handling the `DebPackages.list` reply. `SystemInfo.list` on the same session succeeds; desktop `DebPackages.list` on the same server succeeds ~1.5 s later.
3. ⏳ **Open — why Android-only on a large reply:** same Argus **0.1.36** Vala, same OLLMchat **7bbe43a4** on both ends. Possibilities to prove next: TLS/read chunk boundary in `Client.on_read` / `poll_drain_readable`, property stream desync inside the array payload, or interference from a second desktop controller TLS session on the same server (desktop was also calling `Task.all_targets` / `Agent.list` on conn `0x5a31efee1cd0`).
4. ✔️ **Follow-on UI errors:** after the first decode disconnect, `controller/android/Window.vala` `check_connection()` calls `rpc.connect.begin(hello)` every ~30 s; those hellos also hit `0x0C` / `root parse does not accept object arrays`, so Machines/Tasks show **Client: disconnected** even when the underlying bug is the first `DebPackages.list` parse failure.

---

## Proposed fix

### 1. Prove the first desync (before any product change)

- ⏳ Re-test phone **DebPackages** with **no desktop controller** connected (single TLS session on :817).
- ⏳ **Host throwaway:** `build/tests/argus-list-probe HOST PORT SERVER_NAME` (`tests/list-probe.vala`; PEMs via `Argus.Controller.SQT.Server.load_certificates` / libsecret). If host passes, compare with phone log on the same server (single TLS session on :817, desktop controller off).

### 2. Reconnect after decode disconnect

- ⏳ **OLLMchat (upstream):** `OLLMchat/docs/bugs/2026-11-22-client-disconnect-idempotent.md`
- ⏳ **Argusrm offline UX:** `docs/bugs/2026-11-22-android-controller-offline-reconnect.md` (APK rebuild pending)

---

## Attempts / changelog

- ✔️ Pulled phone `controller.log` and correlated with `/var/log/argusrm/server.log` and desktop `controller.log`.
- ✔️ Confirmed `DebPackages.list` succeeds on desktop, fails on phone, same server.

---

## Next

- ⏳ Bump host server to ocrpc **1.4.15** (or pin Android to **1.4.14**), rebuild/reinstall, retry Debian packages on `SM-S9380`.
- ⏳ If aligned versions still fail, capture a short hexdump of the first `DebPackages.list` reply frame (throwaway probe, not product change).