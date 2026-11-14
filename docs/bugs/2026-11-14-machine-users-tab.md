# Machine Users tab shows only logged-in sessions instead of all system users

**Status:** ✔️ applied; ✔️ fixed missing `server/OSQuery.rpc_register` for `Users`/`Groups`/`UserGroups` (`no handler` / `Unrecognized type alias`); awaiting reinstall + live UI verification

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, `docs/plans/7.2-tasks-ui-and-signing.md`, `docs/rpc-commands.md`, [2026-11-13-FIXED-machines-detail-pane.md](done/2026-11-13-FIXED-machines-detail-pane.md), [2026-11-14-FIXED-logged-in-users-empty-linux.md](done/2026-11-14-FIXED-logged-in-users-empty-linux.md), [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md)

---

## Problem

- 🔷 Per-machine `Users` tab lists only `logged_in_users` sessions.
- 🔷 Expected (confirmed):
  - 🔷 Replace that tab with all osquery `users`, plus `groups` / `user_groups` in the same change.
  - 🔷 Horizontal split: groups left + `Clear`, users right filtered by selected group name.
  - 🔷 Tick (`object-select-symbolic`) when the account has an active login (`logged_in_users_time != 0`).
  - 🔷 `Added` / `Modified` from `added_dt` / `updated_dt`.
  - 🔷 Default filter: `uid >= 1000 && uid != 65534`; search + show system users.
  - 🔷 `SystemInfo.list` logged-in subquery: `AND logged_in_users.deleted_dt = 0`.
- 🔷 Actual: only `logged_in_users` synced/wired; `tick` bind empty; no groups pane.

---

## Evidence / root cause

- ✔️ No `users` / `groups` / `user_groups` sync, tables, or list RPCs.
- ✔️ `Detail` wires `"users"` to `LoggedInUsers`.
- ✔️ Join naming: FK-style when the link reads (`gid_groupname`); table-name prefix when the link is a weak UI label (`logged_in_users_time`).
- 🚫 Unapproved draft was removed from the tree. Do not re-apply it.

---

## Design (approved decisions baked into fences below)

### Stored tables (original columns)

#### `users`

```
id, agent_id, uid, gid, uid_signed, gid_signed, username, description,
directory, shell, uuid, added_dt, updated_dt, deleted_dt
```

#### `groups`

```
id, agent_id, gid, gid_signed, groupname, added_dt, updated_dt, deleted_dt
```

#### `user_groups`

```
id, agent_id, uid, gid, added_dt, updated_dt, deleted_dt
```

### Joined / derived on list (non-stored)

| Property | On | Meaning |
| --- | --- | --- |
| `gid_groupname` | `Users` | Primary group name (`groups.groupname` where `groups.gid = users.gid`) |
| `logged_in_users_time` | `Users` | `MAX(logged_in_users.time)` for live sessions of this username; tick when non-zero |
| `groups_groupnames` | `Users` | `GROUP_CONCAT` of member group names via `user_groups` (for display + group filter) |
| `member_count` | `Groups` | `COUNT(DISTINCT user_groups.uid)` of live members |

- 🚫 No `logged_in_users_tty` / `logged_in_users_host` (not wanted).
- 🚫 No `user_groups_gids` (not useful; filter uses `groups_groupnames`).
- 🚫 No bare `tty` / `host` / `gids` / `group_names` / `logged_in`.
- 🔷 Column CSVs: `users.csv` and `groups.csv` (no `_machine` suffix — per-machine only).

### Apply order after approval

1. Shared rows + `SystemInfo.list` fix + rpc-commands + mesons + registrations + Execute sync.
2. `Tab.Base` tick / BOOLEAN / date tooltip.
3. Controller stores, filter, CSVs, gresource, Groups + Users tabs, Detail wiring.
4. Drop unused controller `LoggedInUsers` tab/store/CSV.
5. Server test inserts + list calls.
6. Probe joins outside product, then build/test.

---

## Proposed fix (verbatim — review before apply)

### 1. `shared/OSQuery/Users.vala` — new row + `Users.list`

**Why:** Persist osquery `users` and list live rows with joined primary group, login time, and member group names.

#### Add — new file `shared/OSQuery/Users.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Shared.OSQuery
{
	/**
	 * One ''users'' row.
	 *
	 * Account list from osquery. Joined fields on {@link list} are not
	 * columns of ''users''.
	 */
	public class Users : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Users>(db, agent_id, rows, "users",
				{ "uid", "username", "uuid" });
		}

		public override string table_name() { return "users"; }

		public override string rpc_name() { return "Users"; }

		/**
		 * Create ''users''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Users.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS users (
					id          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id    INTEGER NOT NULL,
					uid         INTEGER NOT NULL DEFAULT 0,
					gid         INTEGER NOT NULL DEFAULT 0,
					uid_signed  INTEGER NOT NULL DEFAULT 0,
					gid_signed  INTEGER NOT NULL DEFAULT 0,
					username    TEXT NOT NULL DEFAULT '',
					description TEXT NOT NULL DEFAULT '',
					directory   TEXT NOT NULL DEFAULT '',
					shell       TEXT NOT NULL DEFAULT '',
					uuid        TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("users create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "users");
		}

		/**
		 * Register this row and ''Users.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Users", typeof(Users));
			OLLMrpc.Request.add_class(
				"Users", typeof(Users),
				"list", "i"
			);
		}

		/**
		 * Stored ''users'' rows for one agent, with joined fields.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''agent_id'' is not in ''agent'' or
		 * whose ''deleted_dt'' is set is absent. Joined fields:
		 * {@link gid_groupname}, {@link logged_in_users_time},
		 * {@link groups_groupnames}. A caller that is not a controller
		 * is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Users>();
			if (agent_id > 0) {
				var query = new SQ.Query<Users>(Users.db, "users");
				var columns = string.joinv(", ", query.getColsExcept(null, "users."));
				query.selectQuery(@"
					SELECT
						$(columns),
						COALESCE((
							SELECT
								groups.groupname
							FROM
								groups
							WHERE
								groups.agent_id = users.agent_id
							AND
								groups.gid = users.gid
							AND
								groups.deleted_dt = 0
							LIMIT
								1
						), '') AS gid_groupname,
						COALESCE((
							SELECT
								MAX(logged_in_users.time)
							FROM
								logged_in_users
							WHERE
								logged_in_users.agent_id = users.agent_id
							AND
								logged_in_users.user = users.username
							AND
								logged_in_users.deleted_dt = 0
						), 0) AS logged_in_users_time,
						COALESCE((
							SELECT
								GROUP_CONCAT(DISTINCT groups.groupname)
							FROM
								user_groups
							INNER JOIN
								groups
							ON
								groups.agent_id = user_groups.agent_id
							AND
								groups.gid = user_groups.gid
							AND
								groups.deleted_dt = 0
							WHERE
								user_groups.agent_id = users.agent_id
							AND
								user_groups.uid = users.uid
							AND
								user_groups.deleted_dt = 0
						), '') AS groups_groupnames
					FROM
						users
					WHERE
						users.agent_id = $(agent_id)
					AND
						users.deleted_dt = 0
					AND
						users.agent_id IN (SELECT id FROM agent)
					ORDER BY
						users.uid,
						users.username
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public int64 uid { get; set; default = 0; }
		public int64 gid { get; set; default = 0; }
		public int64 uid_signed { get; set; default = 0; }
		public int64 gid_signed { get; set; default = 0; }
		public string username { get; set; default = ""; }
		public string description { get; set; default = ""; }
		public string directory { get; set; default = ""; }
		public string shell { get; set; default = ""; }
		public string uuid { get; set; default = ""; }

		/*
		 * Joined / derived. Not columns of users.
		 */
		public string gid_groupname { get; set; default = ""; }
		public int64 logged_in_users_time { get; set; default = 0; }
		public string groups_groupnames { get; set; default = ""; }
	}
}
```

---

### 2. `shared/OSQuery/Groups.vala` — new row + `Groups.list`

**Why:** Persist osquery `groups` and list live rows with `member_count`.

#### Add — new file `shared/OSQuery/Groups.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Shared.OSQuery
{
	/**
	 * One ''groups'' row.
	 *
	 * Group list from osquery. {@link member_count} on {@link list} is
	 * not a column of ''groups''.
	 */
	public class Groups : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Groups>(db, agent_id, rows, "groups",
				{ "gid", "groupname" });
		}

		public override string table_name() { return "groups"; }

		public override string rpc_name() { return "Groups"; }

		/**
		 * Create ''groups''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Groups.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS groups (
					id         INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id   INTEGER NOT NULL,
					gid        INTEGER NOT NULL DEFAULT 0,
					gid_signed INTEGER NOT NULL DEFAULT 0,
					groupname  TEXT NOT NULL DEFAULT ''
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("groups create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "groups");
		}

		/**
		 * Register this row and ''Groups.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Groups", typeof(Groups));
			OLLMrpc.Request.add_class(
				"Groups", typeof(Groups),
				"list", "i"
			);
		}

		/**
		 * Stored ''groups'' rows for one agent, with {@link member_count}.
		 *
		 * A controller calls this. An ''agent_id'' less than one returns
		 * an empty list. A row whose ''agent_id'' is not in ''agent'' or
		 * whose ''deleted_dt'' is set is absent. A caller that is not a
		 * controller is refused.
		 *
		 * @param request inbound RPC from a controller
		 * @param agent_id selected machine agent id
		 */
		public void list(OLLMrpc.Request request, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Groups>();
			if (agent_id > 0) {
				var query = new SQ.Query<Groups>(Groups.db, "groups");
				var columns = string.joinv(", ", query.getColsExcept(null, "groups."));
				query.selectQuery(@"
					SELECT
						$(columns),
						COALESCE((
							SELECT
								COUNT(DISTINCT user_groups.uid)
							FROM
								user_groups
							INNER JOIN
								users
							ON
								users.agent_id = user_groups.agent_id
							AND
								users.uid = user_groups.uid
							AND
								users.deleted_dt = 0
							WHERE
								user_groups.agent_id = groups.agent_id
							AND
								user_groups.gid = groups.gid
							AND
								user_groups.deleted_dt = 0
						), 0) AS member_count
					FROM
						groups
					WHERE
						groups.agent_id = $(agent_id)
					AND
						groups.deleted_dt = 0
					AND
						groups.agent_id IN (SELECT id FROM agent)
					ORDER BY
						groups.gid,
						groups.groupname
					", rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public int64 gid { get; set; default = 0; }
		public int64 gid_signed { get; set; default = 0; }
		public string groupname { get; set; default = ""; }

		/*
		 * Derived. Not a column of groups.
		 */
		public int64 member_count { get; set; default = 0; }
	}
}
```

---

### 3. `shared/OSQuery/UserGroups.vala` — membership sync only

**Why:** Persist osquery `user_groups` for joins. No list RPC.

#### Add — new file `shared/OSQuery/UserGroups.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Shared.OSQuery
{
	/**
	 * One ''user_groups'' row.
	 *
	 * Membership pairs from osquery. Used by {@link Users.list} and
	 * {@link Groups.list}. No list RPC.
	 */
	public class UserGroups : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<UserGroups>(db, agent_id, rows, "user_groups",
				{ "uid", "gid" });
		}

		public override string table_name() { return "user_groups"; }

		public override string rpc_name() { return "UserGroups"; }

		/**
		 * Create ''user_groups''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			UserGroups.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS user_groups (
					id       INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id INTEGER NOT NULL,
					uid      INTEGER NOT NULL DEFAULT 0,
					gid      INTEGER NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("user_groups create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "user_groups");
		}

		/**
		 * Register this row for ''OSQuery.sync''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("UserGroups", typeof(UserGroups));
		}

		public int64 uid { get; set; default = 0; }
		public int64 gid { get; set; default = 0; }
	}
}
```

---

### 4. `shared/OSQuery/namespace.vala` — init new tables

**Why:** Create `users` / `groups` / `user_groups` with the other osquery tables.

#### Keep

```vala
		CpuInfo.init_db(db);
		LoggedInUsers.init_db(db);
		InterfaceAddresses.init_db(db);
```

#### Add — after `LoggedInUsers.init_db(db);`

```vala
		Users.init_db(db);
		Groups.init_db(db);
		UserGroups.init_db(db);
```

---

### 5. `shared/OSQuery/SystemInfo.vala` — live logins only

**Why:** Logged-out sessions must not appear in the Machines grid.

#### Keep

```vala
						COALESCE((
							SELECT GROUP_CONCAT(DISTINCT logged_in_users.user)
							FROM logged_in_users
							WHERE logged_in_users.agent_id = system_info.agent_id
							AND logged_in_users.agent_id IN (SELECT id FROM agent)
							AND logged_in_users.user != ''
						), '') as logged_in_users
```

#### Remove

```vala
							AND logged_in_users.user != ''
```

#### Replace with

```vala
							AND logged_in_users.user != ''
							AND logged_in_users.deleted_dt = 0
```

---

### 6. `shared/meson.build` — compile new rows

#### Keep

```meson
	'OSQuery/CpuInfo.vala',
	'OSQuery/LoggedInUsers.vala',
	'OSQuery/InterfaceAddresses.vala',
```

#### Add — after `LoggedInUsers.vala`

```meson
	'OSQuery/Users.vala',
	'OSQuery/Groups.vala',
	'OSQuery/UserGroups.vala',
```

---

### 7. `agent/OSQuery/Execute.vala` — sync at startup

**Why:** Agents must post `users` / `groups` / `user_groups` snapshots.

#### Keep

```vala
#else
			code += this.sync_table("logged_in_users", "LoggedInUsers");
#endif
			code += this.sync_table("interface_addresses", "InterfaceAddresses");
```

#### Add — after the `#endif` that ends the logged_in_users sync, before `interface_addresses`

```vala
			code += this.sync_table("users", "Users");
			code += this.sync_table("groups", "Groups");
			code += this.sync_table("user_groups", "UserGroups");
```

---

### 8. `agent/Application.vala` — Bin register

#### Keep

```vala
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
			Argus.Shared.OSQuery.InterfaceAddresses.rpc_register();
```

#### Add — after `LoggedInUsers.rpc_register();`

```vala
			Argus.Shared.OSQuery.Users.rpc_register();
			Argus.Shared.OSQuery.Groups.rpc_register();
			Argus.Shared.OSQuery.UserGroups.rpc_register();
```

---

### 9. `server/Application.vala` — dispatch register

#### Keep

```vala
			OLLMrpc.Request.register("LoggedInUsers", new Argus.Shared.OSQuery.LoggedInUsers());
			OLLMrpc.Request.register("InterfaceAddresses", new Argus.Shared.OSQuery.InterfaceAddresses());
```

#### Add — after `LoggedInUsers` register

```vala
			OLLMrpc.Request.register("Users", new Argus.Shared.OSQuery.Users());
			OLLMrpc.Request.register("Groups", new Argus.Shared.OSQuery.Groups());
			OLLMrpc.Request.register("UserGroups", new Argus.Shared.OSQuery.UserGroups());
```

### 9b. `server/OSQuery.vala` — `rpc_register` (required for list + sync)

**Why:** `Request.register` alone is not enough. `Users.rpc_register()` / `Groups.rpc_register()` / `UserGroups.rpc_register()` run `Bin.register` and `Request.add_class` so `Users.list` / `Groups.list` dispatch and `OSQuery.sync` aliases work. Missed on first apply; live failure was `no handler for 'Users'/'Groups'` and `Unrecognized type alias: Users`.

#### Keep

```vala
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
			Argus.Shared.OSQuery.InterfaceAddresses.rpc_register();
```

#### Add — after `LoggedInUsers.rpc_register();`

```vala
			Argus.Shared.OSQuery.Users.rpc_register();
			Argus.Shared.OSQuery.Groups.rpc_register();
			Argus.Shared.OSQuery.UserGroups.rpc_register();
```

---

### 10. `controller/Application.vala` — Bin register

#### Keep

```vala
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
			Argus.Shared.OSQuery.InterfaceAddresses.rpc_register();
```

#### Add — after `LoggedInUsers.rpc_register();`

```vala
			Argus.Shared.OSQuery.Users.rpc_register();
			Argus.Shared.OSQuery.Groups.rpc_register();
			Argus.Shared.OSQuery.UserGroups.rpc_register();
```

---

### 11. `docs/rpc-commands.md` — document list RPCs + sync names

**Why:** New `Request.add_class` methods and sync table names.

#### Add — after the `LoggedInUsers.list` section (before `InterfaceAddresses.list`)

```markdown
### `Users.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent_id`.
- Reply `retval` `o`: an array of `Users` rows (`deleted_dt = 0`) for that `agent_id` when `agent_id` is in `agent`, ordered by `uid, username`. Stored columns are the osquery `users` fields plus audit timestamps. Joined (not stored): `gid_groupname` (primary `groups.groupname`), `logged_in_users_time` (`MAX` of live `logged_in_users.time` for that username), `groups_groupnames` (`GROUP_CONCAT` of member `groups.groupname` via live `user_groups`). An `agent_id` less than one returns an empty array.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/Users.vala`. `Store.Users` calls it. The columns are `columns/users.csv`.

### `Groups.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent_id`.
- Reply `retval` `o`: an array of `Groups` rows (`deleted_dt = 0`) for that `agent_id` when `agent_id` is in `agent`, ordered by `gid, groupname`. Stored columns are the osquery `groups` fields plus audit timestamps. Derived (not stored): `member_count` (`COUNT(DISTINCT user_groups.uid)` for live memberships of live users). An `agent_id` less than one returns an empty array.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/Groups.vala`. `Store.Groups` calls it. The columns are `columns/groups.csv`.
```

#### Keep — `OSQuery.sync` wire aliases line in `docs/rpc-commands.md`

```markdown
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `InterfaceAddresses`, `OsVersion`, `DebPackages`, `RpmPackages`, `Programs`, `PackageUpdates`.
```

#### Remove

```markdown
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `InterfaceAddresses`, `OsVersion`, `DebPackages`, `RpmPackages`, `Programs`, `PackageUpdates`.
```

#### Replace with

```markdown
- Wire aliases: `SystemInfo`, `CpuInfo`, `LoggedInUsers`, `Users`, `Groups`, `UserGroups`, `InterfaceAddresses`, `OsVersion`, `DebPackages`, `RpmPackages`, `Programs`, `PackageUpdates`.
```

---

Also note after apply: update the stale `Store.LoggedInUsers` pointer under `LoggedInUsers.list` only if that bullet still claims a controller store (shared list remains; controller store is removed).

#### Keep — `LoggedInUsers.list` info bullet

```markdown
- ℹ️ The method is `shared/OSQuery/LoggedInUsers.vala`. `Store.LoggedInUsers` calls it.
```

#### Remove

```markdown
- ℹ️ The method is `shared/OSQuery/LoggedInUsers.vala`. `Store.LoggedInUsers` calls it.
```

#### Replace with

```markdown
- ℹ️ The method is `shared/OSQuery/LoggedInUsers.vala`. Used by `SystemInfo.list` and `Users.list` joins; no dedicated controller tab after the Users change.
```

---

### 12. `controller/tab/Base.vala` — `tick`, `BOOLEAN`, date tooltip

**Why:** Logged-in tick column; safe property extract for bool; full datetime on date hover.

#### Part 1 — property extract: support `BOOLEAN`

#### Keep

```vala
				switch (prop.value_type) {
					case GLib.Type.INT:
						shown = value.get_int().to_string();
						break;

					case GLib.Type.INT64:
						shown = value.get_int64().to_string();
						break;

					default:
						shown = value.get_string();
						break;
				}
```

#### Remove

```vala
					case GLib.Type.INT64:
						shown = value.get_int64().to_string();
						break;

					default:
						shown = value.get_string();
						break;
```

#### Replace with

```vala
					case GLib.Type.INT64:
						shown = value.get_int64().to_string();
						break;

					case GLib.Type.BOOLEAN:
						shown = value.get_boolean() ? "1" : "0";
						break;

					default:
						shown = value.get_string();
						break;
```

#### Part 2 — `date` tooltip

#### Keep

```vala
					case "date":
						var stamp = (int64) 0;
						if (prop.value_type == GLib.Type.INT64) {
							stamp = value.get_int64();
						}
						if (prop.value_type == GLib.Type.INT) {
							stamp = (int64) value.get_int();
						}
						var date_text = "";
						if (stamp > 0) {
							var when = new GLib.DateTime.from_unix_local(stamp);
							if (when != null) {
								var formatted = when.format("%Y-%m-%d");
								date_text = formatted != null ? formatted : "";
							}
						}
						((Gtk.Label) item.child).label = date_text;
						break;
```

#### Remove

```vala
						((Gtk.Label) item.child).label = date_text;
						break;
```

#### Replace with

```vala
						var date_label = (Gtk.Label) item.child;
						date_label.label = date_text;
						date_label.tooltip_text = null;
						if (stamp > 0) {
							var tip_when = new GLib.DateTime.from_unix_local(stamp);
							if (tip_when != null) {
								date_label.tooltip_text = tip_when.format("%Y-%m-%d %H:%M:%S");
							}
						}
						break;
```

#### Part 3 — `tick` bind

#### Keep

```vala
					case "tick":
						break;
```

#### Remove

```vala
					case "tick":
						break;
```

#### Replace with

```vala
					case "tick":
						var tick_image = (Gtk.Image) item.child;
						var ticked = false;
						if (prop.value_type == GLib.Type.BOOLEAN) {
							ticked = value.get_boolean();
						}
						if (prop.value_type == GLib.Type.INT) {
							ticked = value.get_int() != 0;
						}
						if (prop.value_type == GLib.Type.INT64) {
							ticked = value.get_int64() != 0;
						}
						tick_image.icon_name = ticked ? "object-select-symbolic" : null;
						tick_image.visible = ticked;
						break;
```

---

### 13. `controller/store/Users.vala` — new store

#### Add — new file `controller/store/Users.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Store
{
	/**
	 * ''users'' rows for one agent on the open server.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.OSQuery.Users}.
	 * {@link items} is the backing list. {@link load} calls ''Users.list''.
	 * A newer {@link load} drops a reply that is still waiting. An empty
	 * list is omitted on the wire, so an unset return is no rows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Users(app);
	 * store.load(1);
	 * }}}
	 */
	public class Users : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.OSQuery.Users> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.OSQuery.Users>();
		}
		private int epoch = 0;
		private int loaded_agent = -1;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.OSQuery.Users> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * True while the list call is in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * The list call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * @param app the controller process
		 */
		public Users(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.OSQuery.Users);
		}

		/**
		 * Number of rows in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Row at ''position''.
		 *
		 * @param position zero-based index
		 * @return the row, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''Users.list'' for ''agent_id'' and apply it to {@link items}.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<Argus.Shared.OSQuery.Users>();
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Users.list",
				args = OLLMrpc.args("i", agent_id)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list users", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list users", response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.Users>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.Users>) response.retval.get_object();
				}
				this.items = listed;
				this.busy = false;
			});
		}
	}
}
```

---

### 14. `controller/store/Groups.vala` — new store

#### Add — new file `controller/store/Groups.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Store
{
	/**
	 * ''groups'' rows for one agent on the open server.
	 *
	 * A {@link GLib.ListModel} of {@link Argus.Shared.OSQuery.Groups}.
	 * {@link items} is the backing list. {@link load} calls
	 * ''Groups.list''. A newer {@link load} drops a reply that is still
	 * waiting. An empty list is omitted on the wire, so an unset return
	 * is no rows.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var store = new Argus.Controller.Store.Groups(app);
	 * store.load(1);
	 * }}}
	 */
	public class Groups : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.OSQuery.Groups> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.OSQuery.Groups>();
		}
		private int epoch = 0;
		private int loaded_agent = -1;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.OSQuery.Groups> items {
			get {
				return this.items_store;
			}
			private set {
				if (this.items_store == value) {
					return;
				}
				var removed = (uint) this.items_store.size;
				this.items_store = value;
				this.items_changed(0, removed, (uint) value.size);
			}
		}

		/**
		 * True while the list call is in flight.
		 */
		public bool busy { get; private set; default = false; }

		/**
		 * The list call failed.
		 *
		 * @param heading short title for the notice
		 * @param message server or transport text
		 */
		public signal void failed(string heading, string message);

		/**
		 * @param app the controller process
		 */
		public Groups(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Item type for {@link GLib.ListModel}.
		 */
		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.OSQuery.Groups);
		}

		/**
		 * Number of rows in this list.
		 */
		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		/**
		 * Row at ''position''.
		 *
		 * @param position zero-based index
		 * @return the row, or null when ''position'' is past the end
		 */
		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''Groups.list'' for ''agent_id'' and apply it to {@link items}.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			if (this.busy && agent_id == this.loaded_agent) {
				return;
			}
			this.busy = true;
			if (agent_id != this.loaded_agent && this.items_store.size > 0) {
				this.items = new Gee.ArrayList<Argus.Shared.OSQuery.Groups>();
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Groups.list",
				args = OLLMrpc.args("i", agent_id)
			}, (obj, res) => {
				if (epoch != this.epoch) {
					return;
				}
				OLLMrpc.Response response;
				try {
					response = this.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					this.busy = false;
					this.failed("Could not list groups", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not list groups", response.error.message);
					return;
				}
				var listed = new Gee.ArrayList<Argus.Shared.OSQuery.Groups>();
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					listed = (Gee.ArrayList<Argus.Shared.OSQuery.Groups>) response.retval.get_object();
				}
				this.items = listed;
				this.busy = false;
			});
		}
	}
}
```

---

### 15. `controller/filter/Users.vala` — search / system / group

#### Add — new file `controller/filter/Users.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Filters
{
	/**
	 * Local filter for the per-machine users grid.
	 *
	 * Search, show-system, and the selected group name are properties
	 * here. A change to one of them refilters the grid.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var filter = new Argus.Controller.Filters.Users();
	 * var rows = new Gtk.FilterListModel(store, filter);
	 * }}}
	 */
	public class Users : Gtk.Filter
	{
		/**
		 * Text in the search entry.
		 */
		public string search { get; set; default = ""; }
		/**
		 * True shows accounts with ''uid < 1000'' and ''nobody''.
		 */
		public bool show_system { get; set; default = false; }
		/**
		 * Selected group name. Empty means every user. Otherwise the
		 * row must list that name in {@link Argus.Shared.OSQuery.Users.groups_groupnames}.
		 */
		public string group_name { get; set; default = ""; }

		/**
		 * Refilter when a setting changes.
		 */
		construct
		{
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		/**
		 * Whether this row stays on the grid.
		 *
		 * @param item a ''users'' row
		 * @return true when the row passes these settings
		 */
		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.Users) item;
			if (!this.show_system) {
				if (row.uid < 1000 || row.uid == 65534) {
					return false;
				}
			}
			var group = this.group_name.strip();
			if (group != "") {
				var hit = false;
				foreach (var part in row.groups_groupnames.split(",")) {
					if (part.strip() != group) {
						continue;
					}
					hit = true;
					break;
				}
				if (!hit) {
					return false;
				}
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			if (row.username.down().contains(query)) {
				return true;
			}
			if (row.description.down().contains(query)) {
				return true;
			}
			if (row.directory.down().contains(query)) {
				return true;
			}
			if (row.shell.down().contains(query)) {
				return true;
			}
			if (row.gid_groupname.down().contains(query)) {
				return true;
			}
			return row.groups_groupnames.down().contains(query);
		}

		/**
		 * Skip matching when nothing is filtering.
		 */
		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" && this.show_system && this.group_name.strip() == "") {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
```

---

### 16. `controller/resources/columns/users.csv` — new

#### Add — new file `controller/resources/columns/users.csv`

```csv
Column header | Database name [JSON] | Visible | Width | Format | Sort

User,username,ON,160,text,ON
Logged in,logged-in-users-time,ON,80,tick,ON
UID,uid,ON,80,number,ON
Primary group,gid-groupname,ON,120,text,ON
Description,description,ON,180,text,ON
Home,directory,ON,160,text,ON
Shell,shell,ON,120,text,ON
Added,added-dt,ON,100,date,ON
Modified,updated-dt,ON,100,date,ON
GID,gid,off,80,number,ON
Groups,groups-groupnames,off,200,text,ON
UUID,uuid,off,220,text,ON
```

---

### 17. `controller/resources/columns/groups.csv` — new

#### Add — new file `controller/resources/columns/groups.csv`

```csv
Column header | Database name [JSON] | Visible | Width | Format | Sort

Group,groupname,ON,140,text,ON
GID,gid,ON,70,number,ON
Members,member-count,ON,70,number,ON
Added,added-dt,off,100,date,ON
Modified,updated-dt,off,100,date,ON
```

---

### 18. `controller/resources/argusrm.gresource.xml`

#### Keep

```xml
    <file>columns/cpu_info_machine.csv</file>
    <file>columns/logged_in_users_machine.csv</file>
    <file>columns/interface_addresses_machine.csv</file>
```

#### Remove

```xml
    <file>columns/logged_in_users_machine.csv</file>
```

#### Replace with

```xml
    <file>columns/users.csv</file>
    <file>columns/groups.csv</file>
```

---

### 19. `controller/tab/Asset/Machine/Groups.vala` — left pane

#### Add — new file `controller/tab/Asset/Machine/Groups.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Tab.Asset.Machine
{
	/**
	 * Per-machine groups list in {@link Users}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads ''groups.csv''.
	 * {@link Argus.Controller.Store.Groups} loads ''Groups.list''.
	 * Selection drives the users filter. {@link clear_selection} is the
	 * Clear control.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var groups = new Argus.Controller.Tab.Asset.Machine.Groups(window);
	 * groups.load(1);
	 * }}}
	 */
	public class Groups : Argus.Controller.Tab.Base
	{
		/**
		 * Backing store for this list.
		 */
		public Argus.Controller.Store.Groups store;
		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Selected group name changed. Empty when cleared.
		 *
		 * @param group_name selected ''groupname'', or empty
		 */
		public signal void group_selected(string group_name);

		/**
		 * Build the per-machine groups list.
		 *
		 * @param window the window this page belongs to
		 */
		public Groups(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "groups",
				expand_column: "groupname"
			);
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Groups(window.app);
			this.column_grid(this.store);
			var selection = (Gtk.SingleSelection) this.grid.model;
			selection.autoselect = false;
			selection.can_unselect = true;
			selection.selection_changed.connect((position, n_items) => {
				var row = selection.selected_item as Argus.Shared.OSQuery.Groups;
				if (row == null) {
					this.group_selected("");
					return;
				}
				this.group_selected(row.groupname);
			});
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 32,
				height_request = 32,
				visible = false
			};
			spinner.add_css_class("package-wait");
			var overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(spinner);
			this.store.notify["busy"].connect(() => {
				spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = this.store.busy && this.store.get_n_items() > 0;
			});
			this.append(overlay);
		}

		/**
		 * Clear the current group selection.
		 */
		public void clear_selection()
		{
			var selection = (Gtk.SingleSelection) this.grid.model;
			selection.unselect_all();
			this.group_selected("");
		}

		/**
		 * Load groups for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.clear_selection();
			this.store.load(agent_id);
		}
	}
}
```

---

### 20. `controller/tab/Asset/Machine/Users.vala` — replace LoggedInUsers page

#### Add — new file `controller/tab/Asset/Machine/Users.vala`

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Controller.Tab.Asset.Machine
{
	/**
	 * Per-machine users page in {@link Detail}.
	 *
	 * Groups list on the left with Clear. Users grid on the right with
	 * search and show-system. {@link Argus.Controller.Tab.Base.column_menu}
	 * on the users grid reads ''users.csv''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.Users(window);
	 * tab.load(1);
	 * }}}
	 */
	public class Users : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Users store;
		private Argus.Controller.Filters.Users filter;
		private Groups groups;

		/**
		 * True while a later list is in flight and rows are already shown.
		 */
		public bool refreshing { get; private set; default = false; }

		/**
		 * Build the split groups / users page.
		 *
		 * @param window the window this page belongs to
		 */
		public Users(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "users",
				expand_column: "username"
			);
			this.hexpand = true;
			this.vexpand = true;
			this.store = new Argus.Controller.Store.Users(window.app);
			this.filter = new Argus.Controller.Filters.Users();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var search = new Gtk.SearchEntry() {
				hexpand = true,
				placeholder_text = "Search users"
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var show_system = new Gtk.CheckButton.with_label("Show system users");
			show_system.toggled.connect(() => {
				this.filter.show_system = show_system.active;
			});
			var filter_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 4
			};
			filter_bar.append(search);
			filter_bar.append(show_system);
			this.groups = new Groups(window);
			this.groups.group_selected.connect((group_name) => {
				this.filter.group_name = group_name;
			});
			var clear = new Gtk.Button.with_label("Clear");
			clear.clicked.connect(() => {
				this.groups.clear_selection();
			});
			var groups_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				margin_start = 8,
				margin_end = 8,
				margin_top = 4,
				margin_bottom = 4
			};
			groups_bar.append(new Gtk.Label("Groups") {
				hexpand = true,
				xalign = 0
			});
			groups_bar.append(clear);
			var groups_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			groups_box.append(groups_bar);
			groups_box.append(this.groups);
			var users_spinner = new Adw.Spinner() {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				width_request = 48,
				height_request = 48,
				visible = false
			};
			users_spinner.add_css_class("package-wait");
			var users_overlay = new Gtk.Overlay() {
				child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				hexpand = true,
				vexpand = true
			};
			users_overlay.add_overlay(users_spinner);
			this.store.notify["busy"].connect(() => {
				users_spinner.visible = this.store.busy && this.store.get_n_items() == 0;
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			this.groups.notify["refreshing"].connect(() => {
				this.refreshing = (this.store.busy && this.store.get_n_items() > 0) ||
					this.groups.refreshing;
			});
			var paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
				start_child = groups_box,
				end_child = users_overlay,
				resize_start_child = false,
				shrink_start_child = false,
				position = 260,
				hexpand = true,
				vexpand = true
			};
			this.append(filter_bar);
			this.append(paned);
		}

		/**
		 * Load groups and users for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.groups.load(agent_id);
			this.store.load(agent_id);
		}
	}
}
```

---

### 21. `controller/tab/Asset/Machine/Detail.vala` — wire `Users`

#### Part 1 — field type

#### Keep

```vala
		private General general;
		private LoggedInUsers users;
		private DebPackages debian;
```

#### Remove

```vala
		private LoggedInUsers users;
```

#### Replace with

```vala
		private Users users;
```

#### Part 2 — constructor

#### Keep

```vala
			this.users = new LoggedInUsers(window);
			this.pages.add_titled_with_icon(
				this.users, "users", "Users", "system-users-symbolic");
```

#### Remove

```vala
			this.users = new LoggedInUsers(window);
```

#### Replace with

```vala
			this.users = new Users(window);
```

#### Part 3 — class doc mention

#### Keep

```vala
	 * Displays per-machine {@link LoggedInUsers}, the relevant package
```

#### Remove

```vala
	 * Displays per-machine {@link LoggedInUsers}, the relevant package
```

#### Replace with

```vala
	 * Displays per-machine {@link Users}, the relevant package
```

---

### 22. `controller/tab/Asset/Machine/namespace.vala`

#### Keep

```vala
 * {@link General}, {@link LoggedInUsers}, {@link DebPackages},
```

#### Remove

```vala
 * {@link General}, {@link LoggedInUsers}, {@link DebPackages},
```

#### Replace with

```vala
 * {@link General}, {@link Users}, {@link Groups}, {@link DebPackages},
```

---

### 23. `controller/meson.build`

#### Keep

```meson
	'store/CpuInfo.vala',
	'store/LoggedInUsers.vala',
	'store/InterfaceAddresses.vala',
```

#### Remove

```meson
	'store/LoggedInUsers.vala',
```

#### Replace with

```meson
	'store/Users.vala',
	'store/Groups.vala',
```

#### Keep

```meson
	'filter/SystemInfo.vala',
	'filter/DebPackages.vala',
	'filter/Tasks.vala',
```

#### Add — after `DebPackages.vala`

```meson
	'filter/Users.vala',
```

#### Keep

```meson
	'tab/Asset/Machine/General.vala',
	'tab/Asset/Machine/LoggedInUsers.vala',
	'tab/Asset/Machine/DebPackages.vala',
```

#### Remove

```meson
	'tab/Asset/Machine/LoggedInUsers.vala',
```

#### Replace with

```meson
	'tab/Asset/Machine/Users.vala',
	'tab/Asset/Machine/Groups.vala',
```

---

### 24. Delete unused controller LoggedInUsers files

#### Remove — delete file `controller/tab/Asset/Machine/LoggedInUsers.vala`

(Entire current file. No replacement.)

#### Remove — delete file `controller/store/LoggedInUsers.vala`

(Entire current file. No replacement.)

#### Remove — delete file `controller/resources/columns/logged_in_users_machine.csv`

(Entire current file. No replacement.)

- ℹ️ Keep `shared/OSQuery/LoggedInUsers.vala`, agent sync, and `LoggedInUsers.list` for `SystemInfo` and `logged_in_users_time`.

---

### 25. `docs/meson.build` — valadoc inputs

#### Keep

```meson
  '../shared/OSQuery/CpuInfo.vala',
  '../shared/OSQuery/LoggedInUsers.vala',
  '../shared/OSQuery/InterfaceAddresses.vala',
```

#### Add — after `LoggedInUsers.vala`

```meson
  '../shared/OSQuery/Users.vala',
  '../shared/OSQuery/Groups.vala',
  '../shared/OSQuery/UserGroups.vala',
```

#### Keep

```meson
  '../controller/store/CpuInfo.vala',
  '../controller/store/LoggedInUsers.vala',
```

#### Remove

```meson
  '../controller/store/LoggedInUsers.vala',
```

#### Replace with

```meson
  '../controller/store/Users.vala',
  '../controller/store/Groups.vala',
```

#### Keep

```meson
  '../controller/tab/Asset/Machine/LoggedInUsers.vala',
```

#### Remove

```meson
  '../controller/tab/Asset/Machine/LoggedInUsers.vala',
```

#### Replace with

```meson
  '../controller/tab/Asset/Machine/Users.vala',
  '../controller/tab/Asset/Machine/Groups.vala',
```

#### Add — with other controller filter sources if listed; otherwise only if `filter/DebPackages.vala` is present, after it:

```meson
  '../controller/filter/Users.vala',
```

---

### 26. `server/tests/packages.vala` — exercise sync/list

**Why:** Prepare list SQL and join fills against a temp DB.

#### Keep

```vala
			new Argus.Shared.OSQuery.LoggedInUsers().list(request, (int) first);
			new Argus.Shared.OSQuery.InterfaceAddresses().list(request, (int) first);
```

#### Add — after `LoggedInUsers().list(...)`

```vala
			var users_q = new SQ.Query<Argus.Shared.OSQuery.Users>(db, "users");
			if (users_q.insert(new Argus.Shared.OSQuery.Users() {
				agent_id = first,
				uid = 1000,
				gid = 1000,
				username = "alan",
				directory = "/home/alan",
				shell = "/bin/bash"
			}) < 1) {
				GLib.printerr("fail insert users\n");
				return 1;
			}
			var groups_q = new SQ.Query<Argus.Shared.OSQuery.Groups>(db, "groups");
			if (groups_q.insert(new Argus.Shared.OSQuery.Groups() {
				agent_id = first,
				gid = 1000,
				groupname = "alan"
			}) < 1) {
				GLib.printerr("fail insert groups\n");
				return 1;
			}
			var ug_q = new SQ.Query<Argus.Shared.OSQuery.UserGroups>(db, "user_groups");
			if (ug_q.insert(new Argus.Shared.OSQuery.UserGroups() {
				agent_id = first,
				uid = 1000,
				gid = 1000
			}) < 1) {
				GLib.printerr("fail insert user_groups\n");
				return 1;
			}
			var li_q = new SQ.Query<Argus.Shared.OSQuery.LoggedInUsers>(db, "logged_in_users");
			if (li_q.insert(new Argus.Shared.OSQuery.LoggedInUsers() {
				agent_id = first,
				user = "alan",
				time = 1763000000
			}) < 1) {
				GLib.printerr("fail insert logged_in_users for users join\n");
				return 1;
			}
			new Argus.Shared.OSQuery.Users().list(request, (int) first);
			new Argus.Shared.OSQuery.Groups().list(request, (int) first);
```

---

## Attempts / changelog

- ✔️ Diagnosed missing `users`/`groups` sync; confirmed osquery schemas and counts.
- ✔️ User: groups split + Clear, tick, replace LoggedInUsers tab, `deleted_dt = 0`, default `uid >= 1000` hide `nobody`, keep other `>= 1000`, Added/Modified.
- ✔️ User: table-name prefix for weak keys; drop tty/host; drop gid array; keep `groups_groupnames`; `member_count` OK; CSVs without `_machine`; full verbatim proposal required before apply.
- 🚫 Unapproved product code removed earlier; this log is proposal-only until approval.
- ✔️ 2026-11-14: Approved fences applied; compile and 6/6 tests pass.
- ✔️ 2026-11-14: Live UI — `/var/log/argusrm/server.log` `RPC dispatch: no handler for 'Groups'/'Users'` and `Unrecognized type alias: Users` on `OSQuery.sync`. Root cause: `server/OSQuery.rpc_register()` never called `Users`/`Groups`/`UserGroups.rpc_register()` (`add_class` + `Bin.register`). `Request.register` alone is not enough. Fixed in `server/OSQuery.vala`.

## Next

- ✔️ Applied approved fences; `meson compile -C build` and `meson test -C build` (6/6) pass.
- ✔️ Added `Users`/`Groups`/`UserGroups.rpc_register()` to `server/OSQuery.rpc_register()`.
- ✔️ Empty grids after successful sync: agent log shows `users` 69 / `groups` 102 / `user_groups` 95 sent at 12:59:58; controller called `Users.list`/`Groups.list` at 12:59:42 (before sync) and `users_loaded` cached the empty reply. Dropped `users_loaded` so the Users tab reloads whenever it becomes active (same as [package-status-cache-notification.md](2026-11-14-package-status-cache-notification.md)).
- ⏳ 🔷 Reinstall/restart controller (server already has data after agent sync), open Users again and verify rows.
