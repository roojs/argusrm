# Android controller: offline state does not recover automatically

**Status:** ✅ closed 2026-11-24 (parked; APK verify deferred)

**Pointer:** `docs/bug-fix-process.md`, `controller/android/Window.vala`, `controller/Window.vala`

---

## Problem

- 🔷 On **SM-S9380**, after TLS/RPC drops (e.g. `DebPackages.list` decode disconnect), the drawer title shows **Offline** and tabs keep failing with **Client: disconnected**. There is no obvious way to resume except killing the app or re-registering.
- 🔷 **Expected:** Same as desktop — automatic `RPC-Daemon.hello` reconnect on a timer, then lists work again without manual re-bootstrap.

---

## Evidence

- ✔️ `controller/android/Window.vala` already had `check_connection()` (1 s timer, 30 s backoff, `hello` on drop) — same shape as desktop `controller/Window.vala`.
- ✔️ User report (2026-11-22): offline feels permanent; reconnect not visible.
- ℹ️ Follow-on parse failures on auto-`hello` from first `DebPackages.list` decode — archived `docs/bugs/done/2026-11-22-CLOSED-android-debpackages-disconnect.md`.

---

## Root cause

1. ✔️ **UX:** Only the sidebar title changes to **Offline**; no “reconnecting” state and **30 s** wait between attempts on mobile.
2. ✔️ **Transport:** idempotent `Client.disconnect()` is in shipped Pixie **ocrpc**; Argus only needs a rebuild against the current pin and on-device verify.

---

## Proposed fix

### 1. `controller/android/Window.vala` (argusrm) — ✔️ applied

- Call `rpc.disconnect()` immediately before each auto-reconnect `connect.begin(hello)`.
- Backoff **5 s** (was 30 s) between failed attempts.
- Title **Reconnecting…** while `reconnecting` is true.
- **Tap** the offline title to force an immediate retry (`next_reconnect = 0`, `was_connected = true`).

### 2. `controller/Window.vala` (argusrm) — ✔️ applied

- Call `rpc.disconnect()` before auto-reconnect `hello` (desktop; still **30 s** backoff).

---

## Attempts / changelog

- ✔️ §1–2 in argusrm tree (2026-11-22).
- ⏳ Rebuild/install Android APK (`packaging/android/build-apk.sh`, `adb install -r`) and verify on `SM-S9380`.
- ⏳ Rebuild/install APK with current pixie ocrpc pin and verify reconnect on `SM-S9380`.

---

## Next

- Install fresh APK; induce disconnect (e.g. open Debian packages); confirm title cycles **Offline** / **Reconnecting…** and connection returns within ~5 s once server is reachable.
- `scripts/android/pull-controller-log.sh` after repro.