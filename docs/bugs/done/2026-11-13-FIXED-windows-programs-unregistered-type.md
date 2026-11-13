# Agent `Package.send` fails with `Unregistered class type schema: ArgusAgentOSQueryPrograms`

**Status:** ✅ fixed (`0.1.19`); verified on `snappr-win` and controller

**Pointer:** `docs/bug-fix-process.md`. Prior bug: [2026-11-13-FIXED-windows-missing-gspawn-helper.md](2026-11-13-FIXED-windows-missing-gspawn-helper.md).

---

## Problem

- 🔷 On `0.1.18` (`snappr-win`), `osqueryi.exe` installs and delivers `system_info`, `cpu_info`, `logged_in_users`, `interface_addresses`, and `os_version` to the server, but `Programs` fails to serialize and is never sent.
- 🔷 Same pattern affects `DebPackages` and `RpmPackages` through `Argus.Agent.OSQuery.Package`.

## Evidence

- ✔️ `snappr-win` (`0.1.18` `C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache\argusrm\agent.log`):
  - `14:43:39.150` `system_info sent`
  - `14:43:39.653` `cpu_info sent`
  - `14:43:39.826` `logged_in_users sent`
  - `14:43:40.204` `interface_addresses sent`
  - `14:43:40.565` `os_version sent`
  - `14:43:41.131970: G_LOG_LEVEL_WARNING : Package.vala:72: Unregistered class type schema: ArgusAgentOSQueryPrograms`
  - `14:43:41.131970: G_LOG_LEVEL_DEBUG : Execute.vala:168: osquery -32603`
- ✔️ `agent/OSQuery/Programs.vala`, `DebPackages.vala`, `RpmPackages.vala` define subclasses `Argus.Agent.OSQuery.*` extending `Argus.Shared.OSQuery.*` and implementing `Argus.Agent.OSQuery.Package`.
- ✔️ `shared/OSQuery/Programs.vala` (`DebPackages.vala`, `RpmPackages.vala`) registers `"Programs"` -> `typeof(Argus.Shared.OSQuery.Programs)` on `OLLMrpc.Bin`, not `typeof(Argus.Agent.OSQuery.Programs)`.
- ✔️ `agent/OSQuery/Package.vala:51-52` calls `application.osquery.select(this.get_type(), ...)` (using the `Argus.Agent.OSQuery.*` subclass type), whereas `agent/OSQuery/Execute.vala:181` (`sync_table()`) uses `OLLMrpc.Bin.alias_to_gtype.get(class_name)` (the registered `Argus.Shared.OSQuery.*` type).

## Root cause

- ✔️ `Argus.Agent.OSQuery.Package.send()` instantiates rows using `this.get_type()` (`ArgusAgentOSQueryPrograms` / `DebPackages` / `RpmPackages`) instead of the wire-registered `GType` (`OLLMrpc.Bin.alias_to_gtype.get(this.rpc_name())`), so `OLLMrpc.Bin.Stream.write_reg_gtype()` throws `Unregistered class type schema`.

## Proposed fix

- 🔷 Use `OLLMrpc.Bin.alias_to_gtype.get(this.rpc_name())` in `agent/OSQuery/Package.vala` (`send()`), matching `agent/OSQuery/Execute.vala` (`sync_table()`).
- 🚫 Do not register separate `ArgusAgentOSQuery*` wire aliases; the server expects `Programs`, `DebPackages`, and `RpmPackages`.

### 1. `agent/OSQuery/Package.vala` — select with the registered `GType`

**Why:** `OLLMrpc.Bin` serializes rows by looking up their runtime `GType` in `gtype_to_alias`.

**Where:** `send()`, lines 51–52.

**Depends on:** none.

#### Remove

```vala
			application.osquery.select(
				this.get_type(), "SELECT * FROM " + this.table_name(), fresh);
```

#### Replace with

```vala
			application.osquery.select(OLLMrpc.Bin.alias_to_gtype.get(this.rpc_name()),
				"SELECT * FROM " + this.table_name(), fresh);
```

## Attempts / changelog

- ℹ️ 2026-11-13: Diagnosed from `snappr-win` `0.1.18` `agent.log`, `/var/log/argusrm/server.log`, `agent/OSQuery/Package.vala`, and `OLLMchat/libocrpc/Bin/Stream.vala`.
- ✔️ 2026-11-13: Applied `### 1` to `agent/OSQuery/Package.vala`, bumped version to `0.1.19` in `CHANGELOG.md` and `meson.build`, and rebuilt `ArgusAgent-0.1.19-Setup.exe` on `snappr-win`.
- ✅ 2026-11-13: Verified on `snappr-win` (`0.1.19`): `agent.log` logged `Execute.vala:168: osquery 0`, `/var/log/argusrm/server.log` received `OSQuery.sync` (`Programs`) at `14:59:31.141`, and `Programs.list` served rows cleanly with user confirming Windows programs are working.

## Next

- ✅ Closed.
