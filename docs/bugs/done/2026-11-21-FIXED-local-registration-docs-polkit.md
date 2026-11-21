# Local registration — docs and polkit

**Status:** ✅ closed 2026-11-21 — R6 (`docs/setup.md` §3.2) and R7 (`org.roojs.ArgusServer.register` polkit policy).

**Depends on:** [2026-11-21-FIXED-local-agent-registration-certificate.md](2026-11-21-FIXED-local-agent-registration-certificate.md) (R1–R5 fenced in product).

---

## Closure

| Item | ✔️ in tree |
| --- | --- |
| **R6** | `docs/setup.md` §3.2 — same-host `sudo argusrm-server --give-me-a-certificate agent`, desktop **Connect locally**, headless service path; §3.3 remote PIN unchanged |
| **R7** | `server/linux/org.roojs.ArgusServer.register.policy.in` → installed `org.roojs.ArgusServer.register.policy` (debian `argusrm-server.install`, `packaging/rpm/argusrm.spec`); `docs/packaging.md` |

**Optional follow-up (not this bug):** agent integration test sibling (`--give-me-a-certificate agent`, save, TLS hello).

---

## R6 — Agent headless local (`docs/setup.md`)

### Replace — §3.2 Register a local server

Document same-host flow: `sudo argusrm-server --give-me-a-certificate agent` then agent persists JSON + starts. Keep §3.3 remote PIN unchanged.

---

## R7 — Polkit (Linux)

Allow pkexec **`argusrm-server`** with **`--give-me-a-certificate agent|controller`** (server policy).

---

## Order (historical)

1. R7 (polkit) so Gtk Bootstrap and agent **Connect locally** can use pkexec without a full root shell.
2. R6 (`docs/setup.md`).
3. Agent integration test sibling — optional; see closure table above.