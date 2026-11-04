# OSQuery.sync aborts the agent daemon

**Status:** ✔️ empty-array abort gone (`osquery 0`); await table debug on device

**Pointer:** `docs/bug-fix-process.md`. `docs/guide-to-writing-plans.md` — **Checklist for plans**. Proposed Vala must follow `docs/coding-standards.md`.

ℹ️ Related: `docs/bugs/2026-11-04-osquery-not-sent.md` got the rows onto the wire. This log is why the service then dies.
ℹ️ Library report: `/home/alan/gitlive/OLLMchat/docs/bugs/2026-11-04-empty-arraylist-tlsclient-encode.md`.
ℹ️ `docs/bugs/done` in OLLMchat `2026-11-02-FIXED-tls-one-shot-rpc.md` — libocrpc is not edited from this tree.

---

## Problem

- 🔷 After the Linux service starts and begins `OSQuery.sync`, it is not left running.
- 🔷 Agent log:
  - `syncing osquery rows`
  - `oll_mrpc_transport_connection_get_live_handles: assertion 'self != NULL' failed` (twice)
- 🔷 Server log:
  - two `OSQuery.sync` on one connection
  - `disk backup requested` after each
  - `TLS connection closed unexpectedly`
  - the same pair about five seconds later on a new connection
- ℹ️ `argusrm-agent.service` is `Restart=on-failure` / `RestartSec=5s`.

---

## Evidence

- ✔️ Path fix in `docs/bugs/2026-11-04-osquery-not-sent.md` works.
  - `Initialize.vala:179` runs.
  - The server receives `OSQuery.sync`.
- ℹ️ `agent/OSQuery/Initialize.vala` posts `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses` in that order.
  - An empty array is required. See `docs/rpc-commands.md`.
- ✔️ On this machine `osqueryi --json` returns rows for `system_info` and `interface_addresses`.
  - `cpu_info` and `logged_in_users` return `[]`.
  - The service is root, so `cpu_info` can still have rows there.
- ✔️ The abort is `OLLMrpc.Bin.StreamValue.write` calling `list.get(0)` on an empty `Gee.ArrayList`.
  - libgee `ArrayList.get` is `g_assert`. That kills `--service`.
- ✔️ The critical is the same write reading `ctx.connection.live_handles`.
  - `TlsClient` has no `Transport.Connection`.
- ℹ️ Agent log is opened with `"w"`, so each restart keeps only the last start.
  - No `osquery %d` line after the two criticals.

---

## Root cause

- ✔️ This is a libocrpc encoder bug, not an Argus skip or a dummy connection.
  - Argus has no other way to write a `Request` `o` argument that is an `ArrayList`.
  - Skipping empty tables would leave stale server rows.
- ℹ️ Full justification and fences are in the OLLMchat log.

---

## Proposed fix

- 🔷 Do not edit libocrpc from this tree.
- 🔷 `✔️` OLLMchat applied empty object arrays: count `0`, no list type.
- 🔷 Rebuild Argus against the installed `ocrpc`.
- 🔷 Empty `OSQuery.sync` arrays stay `[]`.
- 🚫 Do not invent a row type for an empty table.
- 🚫 Do not skip empty tables.
- 🚫 Do not add a dummy `Transport.Connection` on the agent `TlsClient`.

---

## Attempts / changelog

- 🔷 User: the daemon is not running after the criticals and the TLS close.
- 🔷 User: library edits need a library bug and a justification. Do not patch libocrpc from Argus.
- ✔️ Premature generic `sync_table<T>` in the agent was reverted. It does not help until `StreamValue` can write `[]`.
- 🔷 User: the array fix is in libocrpc.
- 🔷 User: that `ocrpc` is installed.
- ✔️ `meson compile -C /home/alan/gitlive/argusrm/build` succeeded against it.
- ✔️ Service log `osquery 0` after `syncing osquery rows`. The empty-array abort is gone.
- 🔷 Debug each table: the SELECT, the row count, and whether `OSQuery.sync` sent.

---

## Next

- 🔷 `✔️` `/home/alan/gitlive/OLLMchat/docs/bugs/2026-11-04-empty-arraylist-tlsclient-encode.md` applied.
- 🔷 `✔️` Installed `ocrpc`. Rebuilt `argus-agent`. Service ran `osquery 0`.
- 🔷 `⏳` Confirm the four tables in the debug file: query, row count, sent.
