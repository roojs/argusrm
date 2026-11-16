# Storage tab drops the mounts reply

**Status:** ✔️ controller registers `Mounts` and `Uptime` — restart the installed controller to see the grid

**Pointer:** `docs/bug-fix-process.md`, [2026-11-16-FIXED-machine-additional-osquery-data.md](done/2026-11-16-FIXED-machine-additional-osquery-data.md), [`controller/Application.vala`](../../controller/Application.vala), [`shared/OSQuery/Mounts.vala`](../../shared/OSQuery/Mounts.vala)

---

## Problem

- 🔷 **Expected:** Storage shows the machine's osquery `mounts` rows.
- 🔷 **Actual:** the grid stays empty. Opening Storage on a machine that has rows drops the controller's RPC connection.

---

## Evidence

- ✔️ Agent log `/var/log/argusrm/agent.log` at 15:48:21: `SELECT * FROM mounts 88 rows` then `mounts sent`.
- ✔️ Server log `/var/log/argusrm/server.log`: `OSQuery.sync` at that time, then `Mounts.list` at 15:58:55, 15:59:07, 15:59:16, and 15:59:23.
- ✔️ Controller log `~/.cache/argusrm/controller.log`:
  - 15:59:07 and 15:59:23: `Unrecognized type alias: Mounts`, then `disconnect` on `Mounts.list`.
  - The two `Mounts.list` replies that did not name the alias returned in about 2ms (empty list, no type token).
- ✔️ `/tmp/argus-mounts-alias`: a reply whose element alias is `Mounts` throws `Unrecognized type alias: Mounts` until `OLLMrpc.Bin.register("Mounts", …)`. After that, the row decodes.
- ℹ️ The same controller startup registers the other machine row types and skips `Mounts` and `Uptime`. `Uptime.list` in this session returned no alias, so that hole did not disconnect today.

---

## Root cause

- ✔️ The server registers `Mounts` and writes that alias on a non-empty `Mounts.list` reply. The controller never calls `Mounts.rpc_register()`, so decode throws, `Client` disconnects, and `Store.Mounts` never installs the rows.

---

## Fix

#### Replace — `controller/Application.vala` and `controller/android/Application.vala`

```vala
Argus.Shared.OSQuery.CpuInfo.rpc_register();
Argus.Shared.OSQuery.Uptime.rpc_register();
Argus.Shared.OSQuery.Mounts.rpc_register();
Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
```

- ✔️ Applied in both files.
- ⏳ Installed `/usr/bin/argusrm-controller` is still the build from before this change. Restart it after install.
