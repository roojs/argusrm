# Assets lists the same machine more than once

**Status:** ✅ closed 2026-11-11. A machine with no agent row is left out of the list, and startup deletes that `system_info` row.

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 The Assets machine list shows the same computer more than once.
- 🔷 Operating system and logged-in users do not show on those rows the way the stored host should.
- 🔷 One physical machine should be one `system_info` row, with its `os_version` and logins.

## Evidence

- ✔️ Read `/var/lib/argusrm/argus.sqlite` on 2026-11-11. No copy was needed.
- ✔️ `agent` has two rows. `id` 4 is the controller (`is_controller` 1, hostname `alan-office-desktop`). `id` 5 is the agent (`is_controller` 0, ip `192.168.88.132`). `sqlite_sequence.agent` is 5, so ids 1, 2, and 3 were used and then deleted.
- ✔️ `system_info` has three rows, all the same machine.

  - `id` 1, `agent_id` 1, hostname `alan-office-desktop.roojs.com`, uuid `4c4c4544-0033-4610-8039-b4c04f425132`
  - `id` 2, `agent_id` 3, same hostname and uuid
  - `id` 3, `agent_id` 5, same hostname and uuid

- ✔️ `cpu_info` has the same three `agent_id` values, one row each, same CPU.
- ✔️ `interface_addresses` has 12 rows for agent 1, 10 for agent 3, and 10 for agent 5.
- ✔️ `os_version` has one row, and it is agent 5 only (`Ubuntu 25.04`). The join in `SystemInfo.list` therefore leaves operating system blank on the two leftover rows. It does not multiply rows. Each `system_info` id joins 0 or 1 `os_version` row.
- ✔️ `logged_in_users` has 0 rows. The Logged in users cell is blank on every machine, including the live agent. Startup does post that table (`agent/OSQuery/Initialize.vala`).
- ✔️ `deb_packages` exists only for agent 5 (7051 rows).
- ✔️ `SystemInfo.list` selects every `system_info` row. It does not require a live `agent` row.
- ✔️ `Agent.remove` deletes the `agent` row only (`server/Agent.vala`). It does not delete `system_info`, `cpu_info`, `interface_addresses`, `os_version`, `logged_in_users`, `deb_packages`, `rpm_packages`, or `programs`.
- ℹ️ The same agent-only delete is in `Registration.deregister`, the pending-controller replace in `Registration`, and the expired-pending delete in `shared/Agent.vala`. Those paths are controllers or status 0. They are not what left agents 1 and 3.
- ℹ️ Empty `logged_in_users` is a separate miss. It does not create the extra `system_info` rows.

## Root cause

- ✔️ Removing a machine deletes `agent` and leaves the osquery snapshots under the old `agent_id`.
- ✔️ The next registration of that machine inserts a new `agent` id and a new `system_info` row. The old snapshots stay. Assets lists all of them.
- ✔️ `os_version` was stored only for the current id, so the leftover rows look like the same computer with its operating system missing.

## Proposed fix

- 🔷 `SystemInfo.init_db` deletes `system_info` rows whose `agent_id` is not in `agent`. That runs on server startup, after `agent` is created.
- 🔷 `SystemInfo.list` keeps a row only when `system_info.agent_id` is in `agent`. The same check applies to the joined `os_version` row and the `logged_in_users` names.
- 🚫 Do not delete the other snapshot tables in this change. `cpu_info` and `interface_addresses` for agents 1 and 3 stay until a later prune.
- 🚫 Logged-in users staying empty is not this fix.

## Attempts

- ✔️ Counted the live database. Did not change it.
- ✔️ The delete and the list filter are in `shared/OSQuery/SystemInfo.vala`. `docs/rpc-commands.md` names the omitted rows.
- ✔️ A read of the live database with that filter returned one row: agent 5, `alan-office-desktop.roojs.com`.

## Next

- ✅ Closed. The list omits a `system_info` row whose agent is gone, and startup deletes it.
- ℹ️ The copies already stored for agents 1 and 3 are removed when this server build starts.
