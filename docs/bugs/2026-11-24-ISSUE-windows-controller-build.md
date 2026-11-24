# Windows controller build — certificate storage blocker

**Status:** ⏳

### User decisions required

- 💩 Confirm scope for v1: ship a controller that registers with PIN and manages the fleet, or also require FreeRDP remote desktop on the same Windows laptop (today `controller/meson.build` omits FreeRDP when `host_machine.system() == 'windows'`).

### User reported

- 🔷 Field rollout today assumes a phone (Android controller) or carrying installers machine-by-machine. A **Windows laptop running the controller** is the simpler on-site workflow: install agents, read the PIN on one console machine, complete pin sync without juggling a phone through the firewall.
- 🔷 Alternatives (VPN tablet, shouting the PIN across the room) are workable but awkward. **Windows controller packaging is treated as critical** for bulk Windows agent deployment.
- 🔷 The Windows path must **not** leave client TLS material in **cleartext on disk** where another local user (or a casual file browse) can copy PEMs and impersonate the controller — same intent as **libsecret** on Linux, not Android-style credential JSON.
- 🚫 **Blocker:** Linux stores controller client TLS material in **libsecret** (`org.roojs.ArgusController`). There is **no Windows equivalent** wired into the controller yet.

### Success scenario

- Installer or portable build installs **`argusrm-controller`** (GTK) on Windows 10/11.
- Operator runs bootstrap, pairs to the management server (PIN / browse), and **survives restart** with saved credentials.
- Operator registers Windows agents (tray installer + PIN) from the same laptop without an Android device or VPN-only workaround.
- Saved controller PEMs on Windows are **opaque to other users** (Credential Manager or DPAPI), not plain `.json` under the profile.

### Current behavior (code)

- [`controller/meson.build`](../../controller/meson.build) line 35: *"The Windows installer is the agent. FreeRDP is the controller picture."* — **no Windows controller target** in CI/packaging (agent has [`packaging/windows/argusrm-agent.nsi`](../../packaging/windows/argusrm-agent.nsi)).
- [`controller/SQT/Server.vala`](../../controller/SQT/Server.vala):
  - **Linux:** `Secret.password_*` with schema `org.roojs.ArgusController`; JSON blob via `Json.gobject_to_data` / `from_data`.
  - **Android:** `%config%/argusrm/credentials/{name}.json` (`0600`).
  - **Else:** `load_certificates`, `store_certificates`, and `clear_registration` throw *"controller certificates are not supported on this platform"*.
- [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala): registration finish and `check()` credential paths are **`#if LINUX`** (libsecret) with the same non-Linux gap Android work closed via credential files — **Windows would hit the same wall** until `Server` (+ any Bootstrap stores) gain a `WINDOWS` branch.
- **Agent precedent (not shared with controller today):** [`agent/SQT/Server.vala`](../../agent/SQT/Server.vala) keeps PEMs on disk under `data_dir` and on Win32 calls `OLLMrpc.Transport.Cert.ensure()` after write — service-oriented paths, not the per-user controller keyring model.

### Scope beyond the blocker (not exhaustive)

| Area | Linux / Android today | Windows gap |
|------|------------------------|-------------|
| Credential PEMs | libsecret or JSON file (Android) | **DPAPI / Credential Manager — primary blocker** |
| Meson / `-D WINDOWS` | N/A | No `controller` Vala pkg graph for mingw |
| Remote desktop viewer | FreeRDP linked | Explicitly skipped on `windows` host |
| Local registration / pkexec | Linux Bootstrap | N/A on Windows (remote PIN only) |
| Packaging | APK / `.deb` | No controller NSIS |

### Proposed fix (phased)

#### Phase W-C0 — Credential backend (blocker)

Implement `load_certificates` / `store_certificates` / `clear_registration` for Windows in [`controller/SQT/Server.vala`](../../controller/SQT/Server.vala).

- Persist the same **logical payload** as Linux (serialized `Server` JSON with PEM fields) but only inside a **user-scoped secret store** — Win32 **Credential Manager** and/or **DPAPI** (`CryptProtectData` / `CryptUnprotectData`), via a small C shim + vapi. One secret per saved server name (mirror libsecret lookup keys: `service=argusrm`, `name=`).
- **🚫 Rejected:** cleartext credential JSON under `%LOCALAPPDATA%` / config dir (Android parity). ACLs on a PEM file are not an acceptable substitute for libsecret on this ticket.
- Prove read/write/round-trip in a throwaway before product; threat model: other **interactive users** on the machine must not be able to harvest controller client certs from the filesystem.
- Align [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala) and any remaining `Secret` call sites with the Windows backend (no `#elif` file-store path for Windows).

#### Phase W-C1 — Build & ship

- `controller/meson.build`: `-D WINDOWS`, mingw deps (gtk4, libadwaita, sqlite, …), optional FreeRDP decision from user.
- Reuse agent icon `.rc` pattern from packaging tree; NSIS or zip distinct from agent installer.
- CI compile smoke (`valac -C -D WINDOWS` / meson cross) once W-C0 lands.

#### Phase W-C2 — Verify

- Register controller → restart app → connect without re-PIN.
- Register a Windows agent from that controller; confirm fleet grids load.

### Debugging

#### Current debug output

None.

#### Debug code added (remove when complete)

None.

### LLM

- ⏳ Phase W-C0 — implement DPAPI/CM backend (design settled: **no** cleartext JSON).
- 🚫 User 2026-11-24: credential JSON under user config is **out of scope** — defeats the purpose of libsecret-equivalent storage.
- ℹ️ `docs/bug-fix-process.md`
- ℹ️ [`controller/meson.build`](../../controller/meson.build)
- ℹ️ [`controller/SQT/Server.vala`](../../controller/SQT/Server.vala)
- ℹ️ [`controller/dialog/Bootstrap.vala`](../../controller/dialog/Bootstrap.vala)
- ℹ️ [`shared/RegisterWindow.vala`](../../shared/RegisterWindow.vala)
- ℹ️ [`agent/SQT/Server.vala`](../../agent/SQT/Server.vala)