# Debian package list kills the server

**Status:** ✔️ SQL fixed and covered by `server/tests/packages.vala` — not verified on device

**Pointer:** `docs/bug-fix-process.md`

---

## Problem

- 🔷 Opening Software and loading Debian packages kills `argusrm-server`.
- 🔷 The list should return the stored packages.
- 🔷 RPM packages and Windows programs use the same kind of query.

## Evidence

- ✔️ 17:15:07. `argusrm-server` pid 4045684 dumped core, signal 5 (TRAP).
- ✔️ The stack is `sq_query_selectPrepare` → `sq_query_selectQuery` → `argus_shared_os_query_deb_packages_list`.
- ✔️ `SQ.Query.selectPrepare` calls `GLib.error` when `prepare_v2` returns no statement. That aborts the process.
- ✔️ The same SQL against `/tmp/argus.sqlite` (7051 `deb_packages` rows): `DISTINCT aggregates must have exactly one argument`.
- ℹ️ The failing call is `GROUP_CONCAT(DISTINCT NULLIF(...), ', ')`. `DISTINCT` takes one argument. [5.8](../plans/5.8-assets-page.md) already uses `GROUP_CONCAT(DISTINCT logged_in_users.user)`, and the separator is a comma.
- ✔️ `RpmPackages.list` and `Programs.list` use the same two-argument form.

## Root cause

- ✔️ The aggregate list query does not prepare. `selectPrepare` treats that as fatal, so the server exits instead of answering the call.

## Proposed fix

- 🔷 Drop the separator argument. `GROUP_CONCAT(DISTINCT …)` keeps the default comma.
- 🔷 The same change on the RPM list and the Windows list.
- 🔷 A server test loads a few rows and calls each `list`. The old SQL aborts that test.

### `shared/OSQuery/DebPackages.vala`

#### Remove

```vala
						GROUP_CONCAT(DISTINCT NULLIF(arch, ''), ', ') AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(section, ''), ', ') AS section,
						GROUP_CONCAT(DISTINCT NULLIF(priority, ''), ', ') AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(source, ''), ', ') AS source,
						GROUP_CONCAT(DISTINCT NULLIF(maintainer, ''), ', ') AS maintainer,
```

#### Replace with

```vala
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(section, '')) AS section,
						GROUP_CONCAT(DISTINCT NULLIF(priority, '')) AS priority,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(maintainer, '')) AS maintainer,
```

### `shared/OSQuery/RpmPackages.vala`

#### Remove

```vala
						GROUP_CONCAT(DISTINCT NULLIF(arch, ''), ', ') AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(package_group, ''), ', ') AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(source, ''), ', ') AS source,
						GROUP_CONCAT(DISTINCT NULLIF(vendor, ''), ', ') AS vendor,
```

#### Replace with

```vala
						GROUP_CONCAT(DISTINCT NULLIF(arch, '')) AS arch,
						GROUP_CONCAT(DISTINCT NULLIF(package_group, '')) AS package_group,
						GROUP_CONCAT(DISTINCT NULLIF(source, '')) AS source,
						GROUP_CONCAT(DISTINCT NULLIF(vendor, '')) AS vendor,
```

### `shared/OSQuery/Programs.vala`

#### Remove

```vala
						GROUP_CONCAT(DISTINCT NULLIF(publisher, ''), ', ') AS publisher,
						GROUP_CONCAT(DISTINCT NULLIF(language, ''), ', ') AS language,
						GROUP_CONCAT(DISTINCT NULLIF(identifying_number, ''), ', ') AS identifying_number,
						GROUP_CONCAT(DISTINCT NULLIF(install_date, ''), ', ') AS install_date,
						GROUP_CONCAT(DISTINCT NULLIF(install_location, ''), ', ') AS install_location,
						GROUP_CONCAT(DISTINCT NULLIF(install_source, ''), ', ') AS install_source,
						GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, ''), ', ') AS uninstall_string,
```

#### Replace with

```vala
						GROUP_CONCAT(DISTINCT NULLIF(publisher, '')) AS publisher,
						GROUP_CONCAT(DISTINCT NULLIF(language, '')) AS language,
						GROUP_CONCAT(DISTINCT NULLIF(identifying_number, '')) AS identifying_number,
						GROUP_CONCAT(DISTINCT NULLIF(install_date, '')) AS install_date,
						GROUP_CONCAT(DISTINCT NULLIF(install_location, '')) AS install_location,
						GROUP_CONCAT(DISTINCT NULLIF(install_source, '')) AS install_source,
						GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string,
```

## Attempts

- ✔️ The three queries no longer pass a separator to `DISTINCT`.
- ✔️ `server/tests/packages.vala` calls `DebPackages.list`, `RpmPackages.list`, and `Programs.list` on a temporary database.

## Next

- 🔷 ⏳ Install with ninja and restart `argusrm-server`, then open Software. The Debian grid should fill. The server should stay up.
