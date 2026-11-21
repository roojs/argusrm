# Local registration — docs and polkit

**Status:** ⏳ open

**Depends on:** [done/2026-11-21-FIXED-local-agent-registration-certificate.md](done/2026-11-21-FIXED-local-agent-registration-certificate.md) (R1–R5 fenced in product).

**Goal:** Document same-host agent enrollment and allow pkexec for `argusrm-server --give-me-a-certificate`.

---

## R6 — Agent headless local (`docs/setup.md`)

### Replace — §3.2 Register a local server

Document same-host flow: `sudo argusrm-server --give-me-a-certificate agent` then agent persists JSON + starts. Keep §3.3 remote PIN unchanged.

---

## R7 — Polkit (Linux)

Allow pkexec **`argusrm-server`** with **`--give-me-a-certificate agent|controller`** (server policy).

---

## Order

1. R7 (polkit) so Gtk Bootstrap and agent **Connect locally** can use pkexec without a full root shell.
2. R6 (`docs/setup.md`).
3. Agent integration test sibling (`--give-me-a-certificate agent`, save, TLS hello) — optional follow-up in this bug or a separate test doc.