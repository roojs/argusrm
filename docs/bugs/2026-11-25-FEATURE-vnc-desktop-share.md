# Is a VNC library enough to share the signed-in desktop?

**Status:** ⏳

### User decisions required

- 💩 LibVNCServer is GPL and Argus is LGPL. Ship it as its own helper exe in the installer, or link it into `argus-tray` and accept that binary becoming GPL.

### User reported

- 🔷 The old desktop approach is thrown out. This report is only whether VNC is feasible.
- 🔷 Can a library share the desktop as it is, or does a VNC service have to be installed?
- 🔷 A library that is part of the installer is the preferred shape.

### Success scenario

- A library we build into the installer shares the desktop the person is already signed in to.
- No separate VNC product is installed.
- A viewer on the same PC still shows that desktop after a minute.
- The Windows service process is not the process that captures the screen.

### Current behavior

- What you said
  - The report was about the old desktop path.
  - It should only say whether VNC is feasible.
- Tool calls
  - `pkg-config --exists libvncserver` on this Linux box — the library is not installed here.
- Observable product outcome
  - The tree has no VNC code and no VNC dependency.
  - No throwaway has shared a Windows desktop yet.

### Codebase observed behavior

- [`agent/windows/Service.vala`](../../agent/windows/Service.vala) is the Windows service, in session 0. It starts `argus-tray.exe` in the signed-in session.
- [`meson.build`](../../meson.build) does not look up a VNC library.

### Debugging

#### Current debug output

None yet.

#### Debug code added (remove when complete)

None.

### Proposed fix

Feasibility, before any product code.

- A separate VNC service does not have to be installed.
- LibVNCServer is a library. It serves a pixel buffer over VNC. It does not grab the Windows desktop by itself.
- The program that links it copies the signed-in desktop into that buffer. That is ordinary Windows capture in the same program.
- That program cannot be the service. Session 0 cannot see the signed-in desktop.
- `argus-tray` already runs in the signed-in session, so the library can live there, or in a small helper the installer starts the same way.
- Either one is part of the installer. TightVNC, UltraVNC, and TigerVNC as their own Windows service are not required.
- The library is not on this Linux box, and it has not been built for the Windows PC yet. Phase 1 is that proof.

### Phase 1 — Prove the library on the Windows PC

- Why
  - The answer above is from the library's shape and from where the tray runs. It is not yet a picture on that PC.
- Where
  - A throwaway started in the signed-in session. Not the service. Not the product.
- Steps
  - Build LibVNCServer into the throwaway.
  - Copy the signed-in desktop into its buffer.
  - Listen on `127.0.0.1` only.
  - Open a VNC viewer on that port and leave it up for a minute.
- Done when
  - The viewer shows the desktop that is already on the screen, and no VNC service was installed.

### LLM

- ℹ️ LibVNCServer is GPL-2.0-or-later. Argus sources carry the LGPL header. A helper process keeps the GPL on the helper. Linking the library into `argus-tray` covers the tray as well.
- 🚫 Installing TightVNC, UltraVNC, or TigerVNC as a Windows service.
- 🚫 Capturing the desktop inside the service process.
- ℹ️ Nobody signed in: the tray is not running, so there is no signed-in desktop to share.
- ⏳ Phase 1 has not been built.
