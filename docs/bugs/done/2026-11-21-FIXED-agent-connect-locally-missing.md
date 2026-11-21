# Agent Gtk notice — **Connect locally** missing

**Status:** ✅ closed 2026-11-21 — merged into [2026-11-21-FIXED-agent-local-enroll-double-pkexec.md](2026-11-21-FIXED-agent-local-enroll-double-pkexec.md) (**R2**)

**Pointer:** [`shared/Register.vala`](../../../shared/Register.vala) `probe_local`

---

## Problem

**Connect locally** did not appear on the setup notice when `argusrm-server` was running but PIN registration (port 819) was not open.

## Fix

`probe_local()` probes management port **817** (`Argus.SOCKET_PORT`), not `REGISTER_PORT`.