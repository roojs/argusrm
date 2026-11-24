# Linux agent Gtk setup notice

**Status:** ✅ closed 2026-11-21 — Phase 1 notice rules, loopback `probe_local`, Phase 4 actions landed; **Connect locally** → [`LocalRegistration`](../../../agent/linux/LocalRegistration.vala).

**Pointer:** `docs/bug-fix-process.md`, [`agent/linux/Application.vala`](../../../agent/linux/Application.vala), [`agent/linux/LocalRegistration.vala`](../../../agent/linux/LocalRegistration.vala), [`shared/RegisterWindow.vala`](../../../shared/RegisterWindow.vala)

**Polkit / docs:** 2026-11-21-FIXED-local-registration-docs-polkit.md — ✔️ server Polkit + `docs/setup.md` §3.2.

**Spec archive:** 2026-11-21-archived-agent-gtk-setup-notice-proposal.md — Phase 1–4 Vala fences and behaviour tables (do not reopen for new work; add a new bug with fences).

---

## What shipped

- ✔️ Setup **Notice** follows saved `server` row + link state (not `client.pem` alone); **Close**/**Restart** rules match the proposal tables.
- ✔️ **Retry** / **Reconfigure** / service **Restart** via `ServiceManager`; no duplicate management hello on the Gtk path.
- ✔️ **Connect locally** when loopback management port is up → `LocalRegistration` (see double-pkexec fix log).

---

## Archive

Do not extend this file. Gtk notice regressions or new actions need a **new** `docs/bugs/…` entry.