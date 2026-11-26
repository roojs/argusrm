# Is a VNC library enough to share the desktop that is already on screen?

**Status:** 📦 archived 2026-11-26 — VNC path parked (LibVNCServer GPL / licensing). Active remote desktop work: 2026-11-17-remote-desktop.md only.

### User decisions required

None.

### User reported

- 🔷 The old desktop approach is thrown out. This report is only whether VNC is feasible.
- 🔷 Can a library share the desktop as it is, or does a VNC service have to be installed?
- 🔷 A library that is part of the installer is the preferred shape.
- 🔷 Update the report with what the throwaway actually showed.
- 🔷 Clear up whether we see the desktop that is already active, or whether a new session is required.
- 🔷 Name the libraries and check their licenses.
- 🔷 The next thought is some basic code in the tray.
- 🔷 Linking the library into the agent pollutes it, and that is not a big deal.
- 🔷 The FreeRDP library can act as a server, so the built-in Windows one is not required.
- 🔷 FreeRDP shadow is not worth more work. The listener came up and no picture was served.
- 🔷 The tray does little besides the icon and the registration window, so the tray can be the GPL program.

### Success scenario

- The tray, already running in the signed-in session, shares the desktop that session is showing.
- No new Windows session is created.
- No separate VNC product is installed.
- A viewer still shows that desktop after a minute.

### Current behavior

- What you said
  - The throwaway left it unclear whether the active desktop can be viewed, or whether a new session is required.
  - The libraries and their licenses need to be checked before any tray code.
- Tool calls
  - Throwaway on `snappr-win`: LibVNCServer 0.9.15, Windows `BitBlt`, listen `127.0.0.1:5910`.
  - `COPYING` and `README.md` in that LibVNCServer tree. `zlib.h`, `png.h`, `jpeglib.h`, `pthread.h` on that machine. The Argus service file header.
- Observable product outcome
  - The tree still has no VNC code.
  - The throwaway is not the product. It has exited.

### Codebase observed behavior

- [`agent/windows/Service.vala`](../../agent/windows/Service.vala) is the Windows service, in session 0. It starts `argus-tray.exe` in the signed-in session.
- [`agent/windows/main.vala`](../../agent/windows/main.vala) runs the tray when the exe name is `argus-tray.exe`, and runs the service otherwise.
- [`scripts/ci/windows-package-nsis.sh`](../../scripts/ci/windows-package-nsis.sh) copies the agent exe to `argus-tray.exe`. They are one build.
- [`meson.build`](../../meson.build) does not look up a VNC library.

### Debugging

#### Current debug output

- Throwaway on `snappr-win`, 25 Nov. One exe. No VNC product installed. The exe is gone. The one-shot helper that started it was deleted. `sc query ArgusVncProbe` then said it was not installed.
  ```text
  session 1
  attached
  screen 1024 768
  bound 127.0.0.1 5910
  view 1024 768 nonzero 786374
  ```
  - The viewer stayed connected for a minute. 786374 of 786432 pixels were not black.
  - The picture was the lock screen already on the console: the dock at sunset, 5:58, Wednesday, November 25.
  - A connection to `192.168.88.244:5910` from this Linux machine was refused.
  - `qwinsta` showed the console connected and no username.

- Throwaway on `snappr-win`, 25 Nov. FreeRDP 3.14.0 `freerdp-shadow-cli`. No product code. The one-shot helper was deleted. `sc query ArgusShadowProbe` then said it was not installed.
  ```text
  session 5
  started 13648 session 5
  GetDesktopSharedRect width: 1920 height: 1200
  width: 0 height: 0
  Listening on [127.0.0.1]:3391
  freerdp_connect: 0
  ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED
  ```
  - The process ran in the signed-in session. That session stayed Active. Nobody was logged off.
  - It listened on `127.0.0.1:3391`. Port 3389 was not dialed.
  - Windows Desktop Sharing reported the desktop as 1920 by 1200, then the library dialed that sharing endpoint on this PC, port 40000.
  - The security handshake on that dial failed. The size it would have served stayed 0 by 0. No picture was saved.
  - The screen-copy path in this version is turned off. Turning it on does not compile.

#### Debug code added (remove when complete)

None.

### Proposed fix

The tray is the GPL program. LibVNCServer links into a tray executable of its own. `argus-agent.exe` stays LGPL and does not link that library.

- The active screen
  - The program copied the screen that Windows was already showing.
  - It did not create a session, did not log anyone in, and did not replace that screen.
  - LibVNCServer only sent the pixels the program put in its buffer. Windows `BitBlt` took those pixels.
  - The capture program has to run in the Windows session that owns the screen. The SSH shell was session 0 and could not see it. The program was started in session 1, which is the console that was on screen.
  - Nobody was signed in, so the screen was the lock screen. A signed-in desktop full of programs was not up, and this run did not capture one.
  - The same copy, run in the signed-in session, is that session's desktop. The tray already runs there. That is the place for the basic code. It is not a second session.
- Libraries the throwaway linked
  - LibVNCServer 0.9.15. This is the VNC library. `COPYING` is GPL version 2. `README.md` says version 2 or any later version, and says linking LibVNCServer makes the program GPL.
  - Windows GDI (`BitBlt`). This copied the screen. It is not a third-party library.
  - zlib 1.3.2. The zlib license. Permission for any purpose, including commercial.
  - libpng 1.6.58. The libpng license.
  - libjpeg-turbo, via `jpeglib.h`. The Independent JPEG Group terms, not GPL.
  - winpthreads, the header shipped with the mingw compiler. MIT-style grant.
  - zlib, libpng, libjpeg-turbo, and winpthreads were pulled in for compressed encodings and the compiler's thread library. They are not what copied the screen.
  - Argus sources, including [`agent/windows/Service.vala`](../../agent/windows/Service.vala), are LGPL-3.
  - gtk-vnc was not used.
- Other libraries
  - FreeRDP shadow, `freerdp-shadow3`. Apache-2.0. It opens its own Remote Desktop listener. On Windows the picture is not copied by the library. The backend that builds asks Windows Desktop Sharing for the session, then dials that endpoint itself. Tried on this PC. The listener came up. The picture did not.
  - neatvnc. ISC license. A VNC server library. Its own page says it is for the Linux desktop stack (GBM, libdrm). No Windows build.
  - TightVNC, UltraVNC, TigerVNC. GPL programs you install. Not libraries to put in the tray.
  - No extra library. The throwaway already copied the screen with `BitBlt`. The bytes the viewer read are a small protocol. That sender can be ours. Nothing GPL is required for that.
- Not required
  - The built-in Windows Remote Desktop service. That is the server that disconnects.
  - A TightVNC, UltraVNC, or TigerVNC Windows service.
  - A new Windows session.

### ✔️ Phase 1 — Prove the library on the Windows PC

- Done when
  - A viewer showed the screen that was already up, for a minute, and no VNC service was installed.
- Result
  - Met for the lock screen that was on the console.
  - Not met for a signed-in desktop, because nobody was signed in.

### Phase 2 — Basic capture in the tray

- Why
  - The tray already runs in the signed-in session, and that process is the icon and the registration window.
- Where
  - A tray executable built on its own. Not a copy of `argus-agent.exe`. Not the service.
- What
  - That executable links LibVNCServer and copies the screen with `BitBlt`. It is GPL.
  - The service starts it in the signed-in session, as it starts the tray now.
  - `argus-agent.exe` does not link LibVNCServer.
- Not in this report yet
  - Keyboard and mouse.
  - The controller page.
  - Carrying the bytes to the server.

### LLM

- ℹ️ Throwaway tree was `C:\Users\alan\argus-vnc-probe` on `snappr-win`. LibVNCServer tag `LibVNCServer-0.9.15`. It is not part of this repo.
- ℹ️ Shadow throwaway was `C:\Users\alan\argus-shadow-probe` on `snappr-win`. FreeRDP tag `3.14.0`. It is not part of this repo.
- ℹ️ LibVNCServer `README.md` "Commercial Use" and the FAQ: linking is derivative work under the GPL. Internal-only use does not by itself remove that.
- 🚫 Linking LibVNCServer into `argus-agent.exe`. The tray file is a copy of that binary today, so the tray has to be its own build.
- 🚫 Installing TightVNC, UltraVNC, or TigerVNC as a Windows service.
- 🚫 Capturing the desktop inside the service process.
- 🚫 Treating VNC as a new Windows logon. The throwaway did not do that.
