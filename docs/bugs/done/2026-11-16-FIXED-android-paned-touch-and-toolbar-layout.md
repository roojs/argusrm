# Android filter-bar spacer alignment and `Detail` tab touch reliability

**Status:** ✅ fixed and verified on `SM-S9380`

**Pointer:** `docs/bug-fix-process.md`, `controller/tab/Asset/SystemInfo.vala`, `controller/tab/Asset/DebPackages.vala`, `controller/tab/Asset/Machine/Users.vala`, `controller/tab/Tasks.vala`, `/home/alan/git/gtk-Knowles/docs-alan/bugs/2026-11-16-android-paned-touch-steal.md`

---

## Problem

- 🔷 **Filter-bar spacing on Android:** After collapsing `Gtk.SearchEntry` into a search icon button on Android, the remaining dropdowns/checks stay bunched to the left instead of aligning flush right.
- 🔷 **Unreliable touch on machine detail tabs:** Tapping the `Adw.ToggleGroup` tabs (`General`, `Users`, `Debian`, `Interfaces`) and the `System info` expander at the top of the machine detail pane on `SM-S9380` fails to switch tabs or toggle.

---

## Evidence

- ✔️ **Filter bars:** `SystemInfo.vala`, `DebPackages.vala`, and `Machine/Users.vala` pack `search_toggle` and the right-hand controls directly into a horizontal `Gtk.Box` without an expanding spacer between them (`Tasks.vala` placed its spacer after `date_button` instead of after `search_toggle`).
- ✔️ **Touch failure on `Detail` tabs (`SM-S9380`):**
  - `Adw.ToggleGroup` outside `Gtk.Paned` (`Asset/Software.vala`) switches on the first tap (`input tap 720 510`), whereas `Adw.ToggleGroup` inside `SystemInfo.vala`'s `Gtk.Paned` `end_child` (`y=1820..1920` px below separator at `y=1790` px) and `System info` (`y=1970` px) ignore taps completely.
  - `gtk/gtkpaned.c` attaches `pan_gesture` in `GTK_PHASE_CAPTURE` and immediately claims `GDK_TOUCH_BEGIN` anywhere within `±56` dp (`HANDLE_EXTRA_SIZE` 6 + `TOUCH_EXTRA_AREA_WIDTH` 50 = `210` px at `3.75x`) of the divider (`gtkpaned.c:865-943, 1511-1516`). Every widget within 56 dp of the `Gtk.Paned` divider (`Detail` tabs, `System info`, `Tasks` log header `Copy`/`Close`, and `Machine/Users` top rows) falls inside that dead zone.

---

## Root cause

1. ✔️ Filter bars on `#if ANDROID` lack a `hexpand = true` spacer after `search_toggle`.
2. ✔️ `Gtk.Paned` on touchscreens claims all `TOUCH_BEGIN` events within ±56 dp of its separator in `GTK_PHASE_CAPTURE`, preventing taps on `Detail` tabs (and adjacent buttons/expanders in `Tasks` and `Users`).

---

## Proposed fix

1. 🔷 Add `new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) { hexpand = true }` right after `search_toggle` on `#if ANDROID` in `SystemInfo.vala`, `DebPackages.vala`, `Machine/Users.vala`, and `Tasks.vala` (replacing the mid-bar spacer in `Tasks.vala`) so the right-hand controls align flush right.
2. 🔷 On `#if ANDROID`, replace `Gtk.Paned` in `SystemInfo.vala`, `Machine/Users.vala`, and `Tasks.vala` with a vertical `Gtk.Box` + `Gtk.Separator` so no `GtkPaned` capture gesture sits over the top of the lower pane (`Detail` tabs, `Tasks` log header buttons, `Users` list).
   - `SystemInfo.vala`: when `detail` is hidden, `this.overlay.vexpand = true`; when `detail` is shown, `this.overlay` gets `vexpand = false` and `height_request = 160` with `sep.visible = true` and `detail.vexpand = true`.
   - `Tasks.vala`: when `term_box` is hidden, `this.overlay.vexpand = true`; when `term_box` is shown, `this.overlay` gets `vexpand = false` and `height_request = 200` with `sep.visible = true` and `term_box.vexpand = true`.
   - `Machine/Users.vala`: vertical `Gtk.Box` with `groups_box` (`height_request = 160`), `Gtk.Separator`, and `this.overlay` (`vexpand = true`).

---

## Attempts / changelog

- ✔️ Documented root cause (`GtkPaned` `TOUCH_EXTRA_AREA_WIDTH = 50` + `HANDLE_EXTRA_SIZE = 6` claiming `GDK_TOUCH_BEGIN` in `GTK_PHASE_CAPTURE`) in both `argusrm` and `/home/alan/git/gtk-Knowles/docs-alan/bugs/2026-11-16-android-paned-touch-steal.md`.
- ✔️ Added `hexpand = true` spacers after `search_toggle` on `#if ANDROID` in `SystemInfo.vala`, `DebPackages.vala`, `Machine/Users.vala`, and `Tasks.vala`.
- ✔️ Replaced `Gtk.Paned` with vertical `Gtk.Box` + `Gtk.Separator` on `#if ANDROID` in `SystemInfo.vala`, `Machine/Users.vala`, and `Tasks.vala`.
- ✅ Verified on Linux (`ninja -C build`, `meson test -C build --print-errorlogs`) and `SM-S9380`: all filter bars align flush right, and tapping `Users`, `Debian`, and `Interfaces` tabs in `Machine/Detail.vala` switches on the first tap.
