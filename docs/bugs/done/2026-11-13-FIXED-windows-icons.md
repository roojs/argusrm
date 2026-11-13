# Windows icons missing approved bird icon

**Status:** ✅ closed 2026-11-13. `packaging/windows/argusrm.ico`, `argusrm.rc`, meson resource compilation, and NSIS / shortcut / uninstall icon wiring are in the tree.

## Problem

- 🔷 The Windows tray icon, the desktop app window icon, and the Windows installer/shortcut icons do not use the approved `argusrm.svg` bird icon.
- 🔷 Expected: `argus-tray.exe`, its GTK4/Adwaita windows (`RegisterWindow`, `Notice`), the Start Menu shortcut, the installer, and `argusrm-controller.exe` (when built for Windows) display the `argusrm.svg` bird icon.
- 🔷 Actual: Windows falls back to the default `IDI_APPLICATION` (`32512`) system icon for the tray and windows, and the NSIS installer uses the default NSIS icon.

## Evidence

- ✔️ `agent/Win32/tray/Tray.vala` `load_icon()` searches the executable module for `"IDI_APP_ICON"` and then resource `1` before falling back to system icon `32512` (`IDI_APPLICATION`).
- ✔️ `agent/meson.build` does not compile any `.rc` or `.ico` resource into `argus-agent.exe` (which `scripts/ci/windows-package-nsis.sh` copies to `argus-tray.exe`).
- ✔️ `controller/meson.build` compiles `pixmaps/argus-icons.gresource.xml` for GTK `IconTheme` on Linux, but does not compile a Windows `.rc`/`.ico` resource for `argusrm-controller.exe`.
- ✔️ `packaging/windows/argusrm-agent.nsi` and `scripts/ci/windows-package-nsis.sh` do not set `MUI_ICON`, `MUI_UNICON`, or `DisplayIcon`, and no `.ico` file existed in `packaging/windows/`.
- ✔️ Tested in `/tmp/` with `rsvg-convert`, `magick`, `icotool`, `x86_64-w64-mingw32-windres`, `x86_64-w64-mingw32-objcopy --subsystem windows`, and Meson `windows.compile_resources`: `1 ICON "argusrm.ico"` embeds the 32-bit RGBA multi-size `.ico` into `.rsrc` as resource `1` and survives `objcopy --subsystem windows`.

## Root cause

- ✔️ No `.ico` file was generated from `argusrm.svg`, no `.rc` resource script was compiled into the Windows executables, and the NSIS packaging scripts did not configure an installer or uninstaller icon. Without resource `1` in the executable, `Tray.load_icon()`, GTK4's Win32 `RegisterGdkClass`, Windows Explorer, and Start Menu shortcuts all fall back to the default Windows application icon.

## Proposed fix

- 🔷 Generate `packaging/windows/argusrm.ico` from `argusrm.svg` with 32-bit RGBA sizes `16, 24, 32, 48, 64, 128, 256` centered on a square transparent canvas.
- 🔷 Add `packaging/windows/argusrm.rc` with resource `1 ICON "argusrm.ico"`, so `Tray.load_icon()` resource `1`, GTK4 Win32 `MAKEINTRESOURCE(1)`, Explorer, and Start Menu shortcuts all resolve the approved bird icon.

### 1. `packaging/windows/argusrm.rc`

#### Add

```rc
1 ICON "argusrm.ico"
```

### 2. `agent/meson.build`

#### Add

```meson
	win_mod = import('windows')
	sources += win_mod.compile_resources(
		files('../packaging/windows/argusrm.rc'),
		include_directories: include_directories('../packaging/windows'),
	)
```

### 3. `controller/meson.build`

#### Add

```meson
if host_machine.system() == 'windows'
	win_mod = import('windows')
	sources += win_mod.compile_resources(
		files('../packaging/windows/argusrm.rc'),
		include_directories: include_directories('../packaging/windows'),
	)
endif
```

### 4. `packaging/windows/argusrm-agent.nsi`

#### Remove

```nsi
RequestExecutionLevel admin
Unicode true

!insertmacro MUI_PAGE_WELCOME
```

#### Replace with

```nsi
RequestExecutionLevel admin
Unicode true

!ifndef MUI_ICON
  !define MUI_ICON "packaging\windows\argusrm.ico"
!endif
!ifndef MUI_UNICON
  !define MUI_UNICON "${MUI_ICON}"
!endif

!insertmacro MUI_PAGE_WELCOME
```

#### Remove

```nsi
  CreateShortCut "$SMPROGRAMS\Argus RM\Argus Agent.lnk" \
    "$INSTDIR\argus-tray.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
```

#### Replace with

```nsi
  CreateShortCut "$SMPROGRAMS\Argus RM\Argus Agent.lnk" \
    "$INSTDIR\argus-tray.exe" "" "$INSTDIR\argus-tray.exe" 0

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\argus-tray.exe"
```

### 5. `scripts/ci/windows-package-nsis.sh`

#### Remove

```bash
exe="${build_dir}/agent/argus-agent.exe"

[[ -f "${exe}" ]] || {
	echo "missing ${exe}" >&2
	exit 1
}
```

#### Replace with

```bash
exe="${build_dir}/agent/argus-agent.exe"
icon="${ROOT}/packaging/windows/argusrm.ico"

[[ -f "${exe}" ]] || {
	echo "missing ${exe}" >&2
	exit 1
}
[[ -f "${icon}" ]] || {
	echo "missing ${icon}" >&2
	exit 1
}
```

#### Remove

```bash
makensis \
	-DINST_SRC="$(cygpath -aw "${stage}")" \
	-DPRODUCT_VERSION="${version}" \
	-DOUTFILE="$(cygpath -aw "${out_dir}/${out_name}")" \
	packaging/windows/argusrm-agent.nsi
```

#### Replace with

```bash
win_icon="$(cygpath -aw "${icon}")"

makensis \
	-DINST_SRC="$(cygpath -aw "${stage}")" \
	-DPRODUCT_VERSION="${version}" \
	-DOUTFILE="$(cygpath -aw "${out_dir}/${out_name}")" \
	-DMUI_ICON="${win_icon}" \
	-DMUI_UNICON="${win_icon}" \
	packaging/windows/argusrm-agent.nsi
```

## Attempts / changelog

- ✔️ Generated `packaging/windows/argusrm.ico` from `argusrm.svg`.
- ✔️ Created `packaging/windows/argusrm.rc` and wired it into `agent/meson.build` and `controller/meson.build`.
- ✔️ Updated `packaging/windows/argusrm-agent.nsi` and `scripts/ci/windows-package-nsis.sh` for installer/uninstaller/shortcut/uninstall-entry icons.
- ✅ 2026-11-13: User closed as fixed.

## Next

- ✅ Closed. `argusrm.ico`, `argusrm.rc`, meson resource compilation, and NSIS icon wiring are in the tree.
