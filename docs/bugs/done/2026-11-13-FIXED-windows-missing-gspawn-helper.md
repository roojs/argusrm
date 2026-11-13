# Windows agent fails to launch `osquery.msi` and subprocesses (`gspawn-win64-helper` missing)

**Status:** ✅ fixed (`0.1.18`); verified on `snappr-win` (`osquery.msi` installed and `osqueryi.exe` ran); follow-up `Programs` upload fix closed in [2026-11-13-FIXED-windows-programs-unregistered-type.md](2026-11-13-FIXED-windows-programs-unregistered-type.md)

**Pointer:** `docs/bug-fix-process.md`. Prior bug: [2026-11-13-FIXED-windows-no-packages.md](2026-11-13-FIXED-windows-no-packages.md).

---

## Current situation & problem

- 🔷 On `0.1.17` (`snappr-win`), the Windows agent service (`argus-agent.exe`) starts, connects to the management server, connects to `argus-tray.exe` over `OLLMrpc` (`127.0.0.1:4142`), and downloads `/osquery/osquery.msi` into `C:\Windows\Temp\osquery.msi`.
- 🔷 `OSQuery.Initialize` then fails to execute `msiexec.exe` with `Failed to execute helper program (No such file or directory)`, so `osqueryi.exe` is never installed, no osquery tables (`system_info`, `os_version`, `programs`) are sent, and the controller's Software -> Windows tab stays empty.
- 🔷 All Windows `GLib.Subprocess` / `GLib.Process.spawn_async_with_pipes` callers (`Initialize.vala` installer, `Execute.vala` `osqueryi.exe`, and `Win32/Command.vala` `cmd.exe`) are affected.

## Evidence

- ✔️ `snappr-win` (`0.1.17` installed and running at `14:29:31`):
  - `C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache\argusrm\agent.log`:
    - `14:29:31.998` `Application.vala:268: watching the server connection`
    - `14:29:32.012` `Service.vala:97: local hello argus-tray 1`
    - `14:29:32.016` `Download.vala:106: fetching /osquery/osquery.msi` -> wrote `C:\Windows\Temp\osquery.msi` (`20,815,872` bytes)
    - `14:29:34.350` `G_LOG_LEVEL_WARNING : Initialize.vala:138: Failed to execute helper program (No such file or directory)`
  - `C:\Windows\System32\msiexec.exe` exists; `C:\Program Files\osquery\` does not exist.
  - `C:\Program Files\Argus\` contains `libglib-2.0-0.dll`, `argus-agent.exe`, `argus-tray.exe`, and `gio\modules\libgiognutls.dll`, but does **not** contain `gspawn-win64-helper.exe` or `gspawn-win64-helper-console.exe`.
  - `C:\msys64\ucrt64\bin\` contains both `gspawn-win64-helper.exe` (`30,569` bytes) and `gspawn-win64-helper-console.exe` (`29,942` bytes), and `strings /ucrt64/bin/libglib-2.0-0.dll` references both helper filenames from `gspawn-win32.c`.
  - `ldd /ucrt64/bin/gspawn-win64-helper.exe` and `gspawn-win64-helper-console.exe` show only Windows system DLLs plus `libglib-2.0-0.dll`, `libintl-8.dll`, `libiconv-2.dll`, and `libpcre2-8-0.dll` (all already staged by `scripts/ci/copy-windows-runtime.sh`).
- ✔️ `snappr-win` (`0.1.18` installed and running at `14:43:38`):
  - `C:\Program Files\osquery` now exists (`Nov 13 14:41`).
  - `agent.log` confirms `osqueryi.exe` ran and delivered `system_info` (1), `cpu_info` (1), `logged_in_users` (1), `interface_addresses` (17), and `os_version` (1) to `/var/log/argusrm/server.log` (`14:43:39`–`14:43:40`).

## Root cause

- ✔️ `scripts/ci/copy-windows-runtime.sh` copies DLLs found by `ldd` and `gio/modules/libgiognutls.dll` into `dist-windows/Argus/`, omitting GLib's out-of-process spawn helpers (`gspawn-win64-helper.exe` and `gspawn-win64-helper-console.exe`). Because `libglib-2.0-0.dll` (`gspawn-win32.c`) locates those helper executables beside `libglib-2.0-0.dll` / `argus-agent.exe` whenever `GLib.Subprocess` or `GLib.Process.spawn_async_with_pipes` runs, every subprocess launch on an installed machine fails with `Failed to execute helper program (No such file or directory)`.

## Proposed fix

- 🔷 Copy `gspawn-win64-helper.exe` and `gspawn-win64-helper-console.exe` from `${MSYSTEM_PREFIX:-/ucrt64}/bin/` into `${out}` in `scripts/ci/copy-windows-runtime.sh`.
- 🚫 Do not replace `GLib.Subprocess` / `GLib.Process.spawn_async_with_pipes` across `Initialize.vala`, `Execute.vala`, and `Win32/Command.vala` with Win32 `CreateProcessW` workarounds when the missing GLib runtime helpers are the cause.

### 1. `scripts/ci/copy-windows-runtime.sh` — copy GLib `gspawn` helper executables

**Why:** GLib on Windows spawns subprocesses through `gspawn-win64-helper.exe` and `gspawn-win64-helper-console.exe` next to `libglib-2.0-0.dll`.

**Where:** `scripts/ci/copy-windows-runtime.sh`, at the end of the script after copying `libgiognutls.dll`.

**Depends on:** none.

#### Add — copy both `gspawn-win64-helper` executables into `${out}`

```bash
cp -f "${MSYSTEM_PREFIX:-/ucrt64}/bin/gspawn-win64-helper.exe" "${out}/"
cp -f "${MSYSTEM_PREFIX:-/ucrt64}/bin/gspawn-win64-helper-console.exe" "${out}/"
```

## Attempts / changelog

- ℹ️ 2026-11-13: Diagnosed on `snappr-win` (`0.1.17`) from `agent.log`, `server.log`, `C:\Program Files\Argus\`, `C:\Windows\Temp\osquery.msi`, and `ldd` on `/ucrt64/bin/gspawn-win64-helper*.exe`. Split out from [2026-11-13-FIXED-windows-no-packages.md](2026-11-13-FIXED-windows-no-packages.md).
- ✔️ 2026-11-13: Applied `### 1` to `scripts/ci/copy-windows-runtime.sh`, bumped version to `0.1.18` in `CHANGELOG.md` and `meson.build`, and rebuilt `ArgusAgent-0.1.18-Setup.exe` on `snappr-win`.
- ✅ 2026-11-13: Verified on `snappr-win` (`0.1.18` and `0.1.19`): `C:\Program Files\osquery` is installed and `osqueryi.exe` synced `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, `os_version`, and `programs` to the server. Follow-up `Programs` serialization fix closed in [2026-11-13-FIXED-windows-programs-unregistered-type.md](2026-11-13-FIXED-windows-programs-unregistered-type.md).

## Next

- ✅ Closed.
