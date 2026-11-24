# Android startup crash on SM-S9380 (`pthread_create` / `PTHREAD_INHERIT_SCHED`)

**Status:** ✅ closed 2026-11-24 — build issue; GLib `.pixie` with `pthread-restrictions.patch` fixes launch on `SM-S9380`.

**Pointer:** `docs/bug-fix-process.md`, `.android-tools/gtk-android-builder/prepare/wraps/glib/pthread-restrictions.patch`, `android/pixiewood-wraps/glib/glib.wrap`, `packaging/android/build-apk.sh`

---

## Problem

- 🔷 Opening `org.roojs.argus` on physical Samsung `SM-S9380` (Android 17 `pa3q:17/CP2A.260605.016`) crashes immediately on launch before any GTK window renders.
- 🔷 **Expected:** `org.roojs.argus` starts GTK (`RuntimeApplication.onCreate()` -> `startRuntime()`), shows the Argus Remote Manager bootstrap backdrop (`ArgusApplication`), and opens the **Connect a remote machine** flow cleanly, just as on `emulator-5554`.
- 🔷 **Actual:** `RuntimeApplication.onCreate()` aborts in GLib `g_system_thread_new("GTK Thread")` with `Operation not permitted`:
  - `W libc    : pthread_create sched_setscheduler(1073741825, {1}) call failed: Operation not permitted`
  - `F GLib    : file ../subprojects/glib/glib/gthread-posix.c: line 774 (g_system_thread_new): error 'Operation not permitted' during 'pthread_create'`

---

## Evidence

- ✔️ Both `org.roojs.ollmchat.androidpoc` and `org.gtk.entrypopuptest` crash identically on `SM-S9380` with the same `gthread-posix.c: line 774` `Operation not permitted` abort.
- ✔️ `logcat` on `SM-S9380` shows `PkgPredictorService-IpmAtlasController` manipulating the app main thread scheduling policy at launch (`1073741825` = `0x40000001` = `SCHED_FIFO | SCHED_RESET_ON_FORK`, priority `1`).
- ✔️ `.pixiewood/pixie/lib/arm64-v8a/libglib-2.0.so` (from `https://github.com/roojs/pixiewood-pkgs/releases/download/1.261109/glib-arm-v31-2.90.1.pixie`, GLib `2.90.1` commit `e05063ccc6c8f222465a1080927f4c14349f3de6`) runs `glib/gthread-posix.c`:
  - `pthread_attr_setinheritsched (&attr, PTHREAD_INHERIT_SCHED);` before `pthread_create(...)`.
  - On Bionic, `pthread_attr_init` defaults to `PTHREAD_EXPLICIT_SCHED` (`0`), whereas `PTHREAD_INHERIT_SCHED` (`1`) copies `0x40000001` from the boosted Android UI thread and calls `sched_setscheduler(child, 0x40000001, {1})`, which fails with `EPERM` because `RLIMIT_RTPRIO == 0`.
- ✔️ `.android-tools/gtk-android-builder/prepare/wraps/glib/pthread-restrictions.patch` already exists to comment out `pthread_attr_setstacksize` and `pthread_attr_setinheritsched (&attr, PTHREAD_INHERIT_SCHED)` in `glib/gthread-posix.c`, but `OLLMchat`'s `android/pixiewood-wraps/glib/glib.wrap` (and `pixiewood-pkgs`'s GLib build) only listed `diff_files=glib/hack.patch`.
- 🚫 **Ruled out:** calling `sched_setscheduler(0, SCHED_OTHER, &sp)` in `ArgusApplication.onCreate()` before `super.onCreate()` still crashed with `sched_setscheduler(1073741825, {1}) call failed: Operation not permitted`.
- 🚫 **Ruled out:** calling `RuntimeApplication.startRuntime()` from a Java `new Thread()` (`SCHED_OTHER`) fails immediately with `java.lang.IllegalStateException: RuntimeApplication.startRuntime called on non-main thread. This is forbidden!`.
- ✔️ **Device verification:** Cross-compiled GLib `2.90.1` (`e05063ccc6c8f222465a1080927f4c14349f3de6`) in `/tmp/glib-2.90.1` with both `hack.patch` and `pthread-restrictions.patch`, replaced `libglib-2.0.so` in the APK, installed on `SM-S9380`, and launched `org.roojs.argus`:
  - Process stayed alive (`pid 13816`), `GLib-GIO` loaded `GTlsBackendOpenssl`, GTK rendered `Argus Remote Manager 0.1.19` + **Connect a remote machine**, tapping it opened `Connect to management server 0.1.19`, and `ArgusPair: discovery started _rpc._tcp.` logged cleanly.

---

## Root cause

- ✔️ `libglib-2.0.so` in `roojs/pixiewood-pkgs` (`glib-arm-v31-2.90.1.pixie`) is built without `pthread-restrictions.patch`, so `g_system_thread_new` forces `PTHREAD_INHERIT_SCHED` when creating `"GTK Thread"` (and any GLib thread spawned from a boosted UI thread). When Samsung One UI / Android 17 `PkgPredictorService` boosts the UI thread to `SCHED_FIFO | SCHED_RESET_ON_FORK`, `pthread_create` tries to inherit `SCHED_FIFO` under `RLIMIT_RTPRIO == 0` and fails with `EPERM`.

---

## Proposed fix

- 🔷 **Root-cause fix (`roojs/pixiewood-pkgs` & `../OLLMchat`):**
  - ⏳ Update `glib` wrap in `roojs/pixiewood-pkgs` (and `../OLLMchat/android/pixiewood-wraps/glib/`) to include `gtk-android-builder`'s `pthread-restrictions.patch` alongside `hack.patch` and publish a rebuilt `glib` `.pixie` package (fixes `argusrm`, `OLLMchat`, and all other Pixiewood apps).
  - ⏳ In `argusrm`, refresh `.pixiewood/pixie` (`PIXIEWOOD_REFRESH_SUBPROJECTS=1 bash packaging/android/build-apk.sh`) once the rebuilt Pixie GLib is published and verify clean launch on `SM-S9380`. No local GLib override or workaround in `argusrm`.

---

## Attempts / changelog

- ✔️ Tested `nativePrepareMainThread()` calling `sched_setscheduler(0, SCHED_OTHER, &sp)` in `controller/android/android-gio-tls.c` — still crashed with `sched_setscheduler(1073741825, {1})`. Reverted cleanly.
- ✔️ Tested spawning `SystemFilesystem.writeResources` + `startRuntime()` on `new Thread()` in `ArgusApplication.java` — aborted with `IllegalStateException: RuntimeApplication.startRuntime called on non-main thread`. Reverted cleanly.
- ✔️ Cross-compiled GLib `2.90.1` (`e05063ccc6c8f222465a1080927f4c14349f3de6`) with `hack.patch` + `pthread-restrictions.patch`, packaged into `app-arm64-v8a-debug.apk`, installed on `SM-S9380`, and verified launch + GTK UI + `ArgusPair` mDNS startup.
- ✔️ Removed the temporary `/tmp/glib-2.90.1` build, `.pixiewood/android/app/build`, and manual `jniLibs/arm64-v8a/libglib-2.0.so` override so `argusrm` stays strictly on Pixie packages.

---

## Next

- ✔️ User (2026-11-24): confirmed — pthread inherit-sched crash was a Pixiewood GLib build gap, not argusrm product code; closed.
