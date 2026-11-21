# Local registration certificate — remainder (review before code)

**Status:** ⏳ open

**Rule:** Only apply edits that match a **Remove** / **Replace with** / **Add** fenced block below. No comment-only or “like X” hints in product code.

**Parent (closed):** [done/2026-11-21-FIXED-local-agent-registration-certificate.md](done/2026-11-21-FIXED-local-agent-registration-certificate.md) — R1–R5 fences landed.

**Related:** [2026-11-21-local-registration-docs-polkit.md](2026-11-21-local-registration-docs-polkit.md) (R6/R7), [2026-11-21-agent-gtk-notice.md](2026-11-21-agent-gtk-notice.md) (wire `enroll_local_certificate`).

---

## Why this bug exists

The parent bug had a **comment-only** line for agent download fields (no `vala` fence). R3 **did** fence `download` / `download_path` in `docs/rpc-commands.md`, but the server agent branch does not set them yet — doc/code drift.

`server/meson.build` may contain `-D LINUX` for `issue_local_certificate` `#if LINUX`; that was **not** in a parent fence (confirm keep or revert below).

---

## A1 — Agent `Registration.certificate` reply: download socket

**Where:** [`server/Registration.vala`](../../server/Registration.vala), agent branch (`!is_controller`), after `firewall.apply`, before `request.reply`.

### Add

```vala
					this.app.download_listen.listen();
					data.download = this.app.download;
```

**Review:** Same as PIN registration after a non-controller row is committed (`Agent.request_registration`).

---

## A2 — Agent reply: `download_path`

**Where:** same branch, immediately after A1.

### Add

```vala
					data.download_path = "/osquery/osquery.deb";
```

**Review:** Parent comment said “debian path”. Co-located managed agent on the server host only; RPM/MSI need a separate proposal if required.

---

## A3 — `server/meson.build` Linux compile define

**Where:** [`server/meson.build`](../../server/meson.build) `server_vala_args`.

### Add (if keeping current tree behaviour)

```meson
	'-D', 'LINUX',
```

**Review:** Without this, `server/Application.vala` `#if LINUX` in `issue_local_certificate` falls through to “Linux only” error on Linux builds. Reject this block and replace `issue_local_certificate` root check with an unfenced POSIX path if you prefer no `-D LINUX` on server.

---

## A4 — `docs/rpc-commands.md` (optional: match tree until A1–A2)

If A1–A2 are **not** approved yet, revert the agent download bullet to avoid promising fields the server does not set.

### Replace — `Registration.certificate` reply bullet

```markdown
- Reply `retval` `o`: `Argus.Shared.SQT.Server` (PEM fields, `addresses`).
```

**Review:** Apply **either** A1–A2 **or** A4, not both.