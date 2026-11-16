# Machine detail: additional osquery inventory (uptime, storage, connection)

**Status:** ✅ closed 2026-11-16. Slices **1a** (`uptime` on General), **1b** (Storage tab / `mounts`), **1c** (General **Connection** via **`Agent.list(i)`**); build verified. User requested close without blocking on on-device check.

**Pointer:** `docs/bug-fix-process.md`, `docs/guide-to-writing-plans.md` (**Checklist for plans**, **Edit syntax contract**), `docs/coding-standards.md`, `docs/plans/5.8-assets-page.md`, `docs/plans/4.0-data-types.md`, [2026-11-13-FIXED-machines-detail-pane.md](2026-11-13-FIXED-machines-detail-pane.md), [2026-11-14-FIXED-machine-cpu-in-general.md](2026-11-14-FIXED-machine-cpu-in-general.md), [2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md)

---

## Problem

- 🔷 Machine detail already shows startup-synced tables (`system_info`, `os_version`, `cpu_info`, `interface_addresses`, packages, `users` / `groups`). Several useful osquery tables are **not** collected or shown.
- 🔷 **Expected:** low-cardinality startup sync — **`uptime`** on **General**; **storage** on its own machine tab as a **standard grid**; high-cardinality **processes / listening ports** use view-driven live sync ([2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md)).
- 🔷 **Actual:** no server rows and no UI for the candidates below.

---

## Decisions (2026-11-14, refined 2026-11-16)

| Topic | Decision |
| --- | --- |
| `uptime` | Osquery **`uptime`** is **one row per host** (`total_seconds`, `days`, `hours`, …). **General** expander: format **`total_seconds`** in **`controller/store/ColumnSchema.vala`** (`uptime` format) like **`elapsed`** in `controller/tab/Base.vala` — **at most two** abbreviated units (`1y 15d`, `1d 1h`, `5h 30m`, `45m`, `30s`). **No** full `y d h m s` tail. **No** separate shared duration file. Raw `days` / `hours` / … columns **off in CSV by default**. |
| Storage | **Dedicated Storage tab** — startup sync of osquery **`mounts`**. **`Tab.Base`** + **`mounts_machine.csv`** (same pattern as **Interfaces** / **Debian packages**): `path`, `device`, `ctype`, **`bytes`** columns for total/used/free, **`number`** for **% full** (sort via column header / `Gtk.SortListModel`, not the store). **Search** + **Show snap mounts** via `Filters.Mounts` + `FilterListModel`. 🚫 **No** custom `ListBox` / `mount_row` / per-row progress widgets in v1 (grid only). **No periodic resync** in v1. 💩 **Open:** free ≤15% / ≤10% warning colouring (dropped with custom bars — column format? row CSS? defer?). |
| Processes / ports | **Separate bug** — live watch while tab visible, not startup sync. |
| “Power state” | **Not** osquery power for v1. Show **agent connection** on machine **General** from the existing **`agent`** row (`Argus.Shared.Agent`: **`display-connected`**, **`display-last`** — same as **Agents** grid). **🚫 Not** on `SystemInfo` / osquery inventory. Slice **1c**: **`Agent.list(i)`** (`i = 0` → all rows; `i > 0` → that machine) + `machine_general.csv` source **`agent`**. |
| Other candidates | Still out of scope here: `routes`, `interface_details` ([machines-detail-pane](2026-11-13-FIXED-machines-detail-pane.md) §3). |

---

## Evidence

✔️ Startup sync today (`agent/OSQuery/Execute.vala` `send_startup`):

- ✔️ `system_info`, `cpu_info`, `logged_in_users`, `users`, `groups`, `user_groups`, `interface_addresses`, `os_version`, one package class.

🚫 Not in startup or server schema:

| Table (osquery) | Notes |
| --- | --- |
| `uptime` | One row per host ([5.8](../plans/5.8-assets-page.md)). |
| `mounts` / `disk_info` | Storage / fullness — not in [4.0](../plans/4.0-data-types.md). |
| `processes` / `listening_ports` | [2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md). |
| `routes` / `interface_details` | Inspected in detail-pane bug; not synced. |

ℹ️ [2026-11-13-FIXED-machines-detail-pane.md](2026-11-13-FIXED-machines-detail-pane.md) §6 — `users` shipped ([2026-11-14-FIXED-machine-users-tab.md](2026-11-14-FIXED-machine-users-tab.md)).

ℹ️ Live session refresh for logins is phase 1 — not this bug.

---

## Proposed fix (phased — shipped)

✅ **Landed** — fences below are the record; product matches items **1–29**.

ℹ️ **One bug, one log** — fences live here per `docs/bug-fix-process.md` and `docs/guide-to-writing-plans.md` (**Code proposals — one place, not two**). The former `-proposals.md` split was erroneous and is removed.

🚫 **Do not** add proposed product sources under `docs/bugs/` (no `docs/bugs/*.vala` companions).

**Suggested apply order:** Slice **1a** items **1–11**, then Slice **1b** items **12–23**, then Slice **1c** items **24–29** after approval.

- 🔷 **Slice 1a** — items **1–11** below (`uptime` sync + General UI).
- 🔷 **Slice 1b** — items **12–23** (`mounts` sync + **`Tab.Base` Storage** + `Detail.vala`; **bytes** columns use existing **`Tab.Base`** / **`ColumnSchema`** formatting only).
- ✔️ **Slice 1c** — agent connection on General (items **24–29**; landed — **`Agent.list(i)`**, no `LIMIT 20`).
- 🚫 Out of scope here: [2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md), `routes`, `interface_details`.

---

## Slice 1a — `uptime` on General

### 1. `controller/store/ColumnSchema.vala` — `uptime` format (two units max)

**Why:** General tab **`total_seconds`** display lives here with the other CSV formats — not a new `shared/` duration module. Match **`elapsed`** in `controller/tab/Base.vala`: **one or two** abbreviated units, coarsest + optional remainder (`y`/`d`/`h`/`m`/`s` only as needed). Examples: `1y 15d`, `3d 5h`, `2h 10m`, `45m`, `12s` — **not** `1d 3h 22m 5s`.

**Where:** `display_value`, new `case "uptime":` before `case "date":`.

#### Remove (`controller/store/ColumnSchema.vala`)

```vala
				case "date":
```

#### Replace with (`controller/store/ColumnSchema.vala`)

```vala
				case "uptime":
					var secs = (int64) 0;
					if (prop.value_type == GLib.Type.INT64) {
						secs = value.get_int64();
					}
					if (prop.value_type == GLib.Type.INT) {
						secs = (int64) value.get_int();
					}
					if (secs < 1) {
						return ret;
					}
					const int64 day = 86400;
					const int64 hour = 3600;
					const int64 year = 365 * day;
					if (secs < 60) {
						ret.val = secs.to_string() + "s";
						return ret;
					}
					if (secs < 3600) {
						ret.val = (secs / 60).to_string() + "m";
						return ret;
					}
					if (secs < day) {
						var rem_mins = (secs % 3600) / 60;
						ret.val = (secs / 3600).to_string() + "h";
						if (rem_mins > 0) {
							ret.val += " " + rem_mins.to_string() + "m";
						}
						return ret;
					}
					if (secs < year) {
						var rem_hours = (secs % day) / 3600;
						ret.val = (secs / day).to_string() + "d";
						if (rem_hours > 0) {
							ret.val += " " + rem_hours.to_string() + "h";
						}
						return ret;
					}
					var rem_days = (secs % year) / day;
					ret.val = (secs / year).to_string() + "y";
					if (rem_days > 0) {
						ret.val += " " + rem_days.to_string() + "d";
					}
					return ret;

				case "date":
```

### 2. `shared/OSQuery/Uptime.vala` — `uptime` row + RPC

**Why:** Store osquery `uptime` (one row per host) and serve `Uptime.list`.

**Where:** new file; mirror `shared/OSQuery/CpuInfo.vala` list pattern with `sync_rows<Uptime>(…, "uptime", {})`.

**Depends on:** item 4 (`init_db` / `register`), item 6 (agent startup sync), item 8 (`rpc-commands.md`).

#### Add — `shared/OSQuery/Uptime.vala`

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
	 * One ''uptime'' row per host.
	 */
	public class Uptime : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Uptime>(db, agent_id, rows, "uptime", {});
		}

		public override string table_name() { return "uptime"; }

		public override string rpc_name() { return "Uptime"; }

		/**
		 * Create ''uptime''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Uptime.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS uptime (
					id             INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id       INTEGER NOT NULL,
					days           INTEGER NOT NULL DEFAULT 0,
					hours          INTEGER NOT NULL DEFAULT 0,
					minutes        INTEGER NOT NULL DEFAULT 0,
					seconds        INTEGER NOT NULL DEFAULT 0,
					total_seconds  INT64 NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("uptime create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "uptime");
		}

		/**
		 * Register this row and ''Uptime.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Uptime", typeof(Uptime));
			OLLMrpc.Request.add_class(
				"Uptime", typeof(Uptime),
				"list", "i"
			);
		}

		/**
		 * Stored ''uptime'' rows for one agent.
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
			var rows = new Gee.ArrayList<Uptime>();
			if (agent_id > 0) {
				var query = new SQ.Query<Uptime>(Uptime.db, "uptime");
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					""".printf(agent_id), rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		public int days { get; set; default = 0; }
		public int hours { get; set; default = 0; }
		public int minutes { get; set; default = 0; }
		public int seconds { get; set; default = 0; }
		public int64 total_seconds { get; set; default = 0; }
	}
}
```

### 3. `shared/meson.build` — compile new shared sources

**Where:** `shared_osquery_sources` and `shared_sources` in `shared/meson.build`.

#### Remove (`shared/meson.build`)

```meson
	'OSQuery/CpuInfo.vala',
	'OSQuery/LoggedInUsers.vala',
```

#### Replace with (`shared/meson.build`)

```meson
	'OSQuery/CpuInfo.vala',
	'OSQuery/Uptime.vala',
	'OSQuery/Mounts.vala',
	'OSQuery/LoggedInUsers.vala',
```

### 4. `shared/OSQuery/namespace.vala` — `init_db` and `register`

#### Remove (`shared/OSQuery/namespace.vala`)

```vala
		CpuInfo.init_db(db);
		LoggedInUsers.init_db(db);
```

#### Replace with (`shared/OSQuery/namespace.vala`)

```vala
		CpuInfo.init_db(db);
		Uptime.init_db(db);
		Mounts.init_db(db);
		LoggedInUsers.init_db(db);
```

#### Remove (`shared/OSQuery/namespace.vala`)

```vala
		OLLMrpc.Request.register("CpuInfo", new CpuInfo());
		OLLMrpc.Request.register("LoggedInUsers", new LoggedInUsers());
```

#### Replace with (`shared/OSQuery/namespace.vala`)

```vala
		OLLMrpc.Request.register("CpuInfo", new CpuInfo());
		OLLMrpc.Request.register("Uptime", new Uptime());
		OLLMrpc.Request.register("Mounts", new Mounts());
		OLLMrpc.Request.register("LoggedInUsers", new LoggedInUsers());
```

### 5. `server/OSQuery.vala` — wire RPC types on server

#### Remove (`server/OSQuery.vala`)

```vala
			Argus.Shared.OSQuery.CpuInfo.rpc_register();
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
```

#### Replace with (`server/OSQuery.vala`)

```vala
			Argus.Shared.OSQuery.CpuInfo.rpc_register();
			Argus.Shared.OSQuery.Uptime.rpc_register();
			Argus.Shared.OSQuery.Mounts.rpc_register();
			Argus.Shared.OSQuery.LoggedInUsers.rpc_register();
```

### 6. `agent/OSQuery/Execute.vala` — startup sync

#### Remove (`agent/OSQuery/Execute.vala`)

```vala
			code += this.sync_table("cpu_info", "CpuInfo");
#if LINUX
```

#### Replace with (`agent/OSQuery/Execute.vala`)

```vala
			code += this.sync_table("cpu_info", "CpuInfo");
			code += this.sync_table("uptime", "Uptime");
			code += this.sync_table("mounts", "Mounts");
#if LINUX
```

### 7. `docs/meson.build` — valadoc inputs

#### Remove (`docs/meson.build`)

```meson
  '../shared/OSQuery/CpuInfo.vala',
  '../shared/OSQuery/LoggedInUsers.vala',
```

#### Replace with (`docs/meson.build`)

```meson
  '../shared/OSQuery/CpuInfo.vala',
  '../shared/OSQuery/Uptime.vala',
  '../shared/OSQuery/Mounts.vala',
  '../shared/OSQuery/LoggedInUsers.vala',
```

### 8. `docs/rpc-commands.md` — `Uptime.list` and `Mounts.list`

**Where:** after `CpuInfo.list`, before `LoggedInUsers.list`.

#### Add — `docs/rpc-commands.md`

```markdown
### `Uptime.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent_id`.
- Reply `retval` `o`: an array of `Uptime` rows (`deleted_dt = 0`) for that `agent_id` when `agent_id` is in `agent`. An `agent_id` less than one returns an empty array. Osquery returns one row per host.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/Uptime.vala`. `Store.MachineGeneral` calls it for the per-machine **General** tab **Uptime** expander.

### `Mounts.list`

- Socket: the Unix socket, or a controller TLS connection.
- Direction: controller calls the server.
- Arguments `i`: `agent_id`.
- Reply `retval` `o`: an array of `Mounts` rows (`deleted_dt = 0`) for that `agent_id` when `agent_id` is in `agent`, ordered by `path`. An `agent_id` less than one returns an empty array.
- A caller that is not a controller is `controller only`.
- ℹ️ The method is `shared/OSQuery/Mounts.vala`. `Store.Mounts` calls it for the per-machine **Storage** tab.
```

### 9. `controller/resources/columns/machine_general.csv` — Uptime expander

**Where:** after the `os_releases` block, before the `cpu_info` rows.

#### Add — `controller/resources/columns/machine_general.csv`

```text
0,Uptime,total-seconds,ON,0,expander,off,uptime
1,Up for,total-seconds,ON,0,uptime,off,uptime
1,Days,days,off,0,number,off,uptime
1,Hours,hours,off,0,number,off,uptime
1,Minutes,minutes,off,0,number,off,uptime
1,Seconds,seconds,off,0,number,off,uptime
```

### 10. `controller/store/MachineGeneral.vala` — load uptime before CPU

#### Remove (`controller/store/MachineGeneral.vala`)

```vala
			if (!yield this.load_section(
				"os_releases", "OsReleases.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_cpu_section(agent_id)) {
				return;
			}
```

#### Replace with (`controller/store/MachineGeneral.vala`)

```vala
			if (!yield this.load_section(
				"os_releases", "OsReleases.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_section(
				"uptime", "Uptime.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
			if (!yield this.load_cpu_section(agent_id)) {
				return;
			}
```

### 11. `controller/store/MachineGeneral.vala` — docblock

#### Remove (`controller/store/MachineGeneral.vala`)

```vala
	 * ''CpuInfo.list'' for one ''agent_id'' and replaces {@link items} from
```

#### Replace with (`controller/store/MachineGeneral.vala`)

```vala
	 * ''CpuInfo.list'', and ''Uptime.list'' for one ''agent_id'' and replaces {@link items} from
```

---

## Slice 1b — **Storage** tab (`mounts`)

### 12. `shared/OSQuery/Mounts.vala` — `mounts` row

**Why:** Store osquery `mounts`. Grid sizes use **`display_*`** getters (same idea as {@link Argus.Shared.Agent.display_connected}) — **`df -h`** math from `blocks_*` inline, not a pile of `volume_*` methods.

**Where:** new file. Osquery JSON `type` → property `ctype` (see `Row.deserialize_property`); DB column `type` like `interface_addresses`.

**Depends on:** items 2–7, 8 (`Mounts.list`), item 13 (`Store.Mounts`).

#### Add — `shared/OSQuery/Mounts.vala`

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
	 * One ''mounts'' row.
	 */
	public class Mounts : Row
	{
		private static SQ.Database db;

		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Mounts>(db, agent_id, rows, "mounts", { "path" });
		}

		public override string table_name() { return "mounts"; }

		public override string rpc_name() { return "Mounts"; }

		/**
		 * Create ''mounts''.
		 *
		 * @param db Argus database
		 */
		public static void init_db(SQ.Database db)
		{
			Mounts.db = db;
			string errmsg;
			var ddl = """
				CREATE TABLE IF NOT EXISTS mounts (
					id                INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
					agent_id          INTEGER NOT NULL,
					device            TEXT NOT NULL DEFAULT '',
					device_alias      TEXT NOT NULL DEFAULT '',
					path              TEXT NOT NULL DEFAULT '',
					type              TEXT NOT NULL DEFAULT '',
					flags             TEXT NOT NULL DEFAULT '',
					blocks            INT64 NOT NULL DEFAULT 0,
					blocks_free       INT64 NOT NULL DEFAULT 0,
					blocks_available  INT64 NOT NULL DEFAULT 0,
					blocks_size       INT64 NOT NULL DEFAULT 0,
					inodes            INT64 NOT NULL DEFAULT 0,
					inodes_free       INT64 NOT NULL DEFAULT 0
				);
				""";
			if (Sqlite.OK != db.db.exec(ddl, null, out errmsg)) {
				GLib.warning("mounts create failed: %s", db.db.errmsg());
			}
			Argus.Shared.init_db_audit(db, "mounts");
		}

		/**
		 * Register this row and ''Mounts.list''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Mounts", typeof(Mounts));
			OLLMrpc.Request.add_class(
				"Mounts", typeof(Mounts),
				"list", "i"
			);
		}

		/**
		 * Stored ''mounts'' rows for one agent.
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
			var rows = new Gee.ArrayList<Mounts>();
			if (agent_id > 0) {
				var query = new SQ.Query<Mounts>(Mounts.db, "mounts");
				query.select("""
					WHERE
						agent_id = %d
					AND
						deleted_dt = 0
					AND
						agent_id IN (SELECT id FROM agent)
					ORDER BY
						path
					""".printf(agent_id), rows);
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * True for snap squashfs mounts and ''/snap'' paths (filter only — not a ''display_'' field).
		 */
		public bool is_snap_mount()
		{
			if (this.path == "/snap" || this.path.has_prefix("/snap/")) {
				return true;
			}
			if (this.device.has_prefix("/dev/loop") && this.ctype == "squashfs") {
				return true;
			}
			return false;
		}

		/**
		 * Total capacity for the Storage grid (''blocks * blocks_size'').
		 */
		public int64 display_total_bytes {
			get {
				return this.blocks * this.blocks_size;
			}
		}

		/**
		 * Free space for unprivileged users (''blocks_available * blocks_size'').
		 */
		public int64 display_free_bytes {
			get {
				return this.blocks_available * this.blocks_size;
			}
		}

		/**
		 * Used bytes (total minus free) for the Storage grid.
		 */
		public int64 display_used_bytes {
			get {
				var total = this.display_total_bytes;
				var free = this.display_free_bytes;
				if (total <= free) {
					return 0;
				}
				return total - free;
			}
		}

		/**
		 * Used capacity 0–100 for the Storage grid.
		 */
		public int display_percent_full {
			get {
				var total = this.display_total_bytes;
				if (total < 1) {
					return 0;
				}
				return (int) ((double) this.display_used_bytes / (double) total * 100.0 + 0.5);
			}
		}

		public string device { get; set; default = ""; }
		public string device_alias { get; set; default = ""; }
		public string path { get; set; default = ""; }
		public string ctype { get; set; default = ""; }
		public string flags { get; set; default = ""; }
		public int64 blocks { get; set; default = 0; }
		public int64 blocks_free { get; set; default = 0; }
		public int64 blocks_available { get; set; default = 0; }
		public int64 blocks_size { get; set; default = 0; }
		public int64 inodes { get; set; default = 0; }
		public int64 inodes_free { get; set; default = 0; }
	}
}
```

### 13. `controller/store/Mounts.vala` — list model for Storage tab

**Why:** Fetch `Mounts.list` (grid sort is {@link Argus.Controller.Tab.Base} / column sorter — not the store).

#### Add — `controller/store/Mounts.vala`

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
	 * ''mounts'' rows for one agent on the open server.
	 */
	public class Mounts : GLib.Object, GLib.ListModel
	{
		public Application app;
		private Gee.ArrayList<Argus.Shared.OSQuery.Mounts> items_store {
			get; set; default = new Gee.ArrayList<Argus.Shared.OSQuery.Mounts>();
		}
		private int epoch = 0;
		private int loaded_agent = -1;

		/**
		 * Rows from the last list reply. This list is the model.
		 */
		public Gee.ArrayList<Argus.Shared.OSQuery.Mounts> items {
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

		public bool busy { get; private set; default = false; }

		public signal void failed(string heading, string message);

		public Mounts(Application app)
		{
			Object();
			this.app = app;
		}

		public GLib.Type get_item_type()
		{
			return typeof(Argus.Shared.OSQuery.Mounts);
		}

		public uint get_n_items()
		{
			return (uint) this.items.size;
		}

		public GLib.Object? get_item(uint position)
		{
			if (position >= (uint) this.items.size) {
				return null;
			}
			return this.items.get((int) position);
		}

		/**
		 * Fetch ''Mounts.list'' for ''agent_id''.
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
				this.items = new Gee.ArrayList<Argus.Shared.OSQuery.Mounts>();
			}
			this.loaded_agent = agent_id;
			this.epoch++;
			var epoch = this.epoch;
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Mounts.list",
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
					this.failed("Could not load Mounts.list", e.message);
					return;
				}
				if (response.error != null) {
					this.busy = false;
					this.failed("Could not load Mounts.list", response.error.message);
					return;
				}
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					this.items = (Gee.ArrayList<Argus.Shared.OSQuery.Mounts>) response.retval.get_object();
				} else {
					this.items = new Gee.ArrayList<Argus.Shared.OSQuery.Mounts>();
				}
				this.busy = false;
			});
		}
	}
}
```

### 14. `mounts_machine.csv` + gresource — grid columns

**Why:** Standard {@link Argus.Controller.Tab.Base} column menu (same pattern as {@link DebPackages} / {@link InterfaceAddresses}). {@link Argus.Shared.OSQuery.Mounts.display_total_bytes} and siblings feed **bytes** / **number** formats.

#### Add — `controller/resources/columns/mounts_machine.csv`

```csv
Column header | Database name [JSON] | Visible | Width | Format | Sort

Mount,path,ON,200,text,ON
Device,device,ON,140,text,ON
Type,ctype,ON,90,text,ON
Total,display-total-bytes,ON,96,bytes,ON
Used,display-used-bytes,ON,96,bytes,ON
Free,display-free-bytes,ON,96,bytes,ON
% full,display-percent-full,ON,72,number,ON
```

#### Remove (`controller/resources/argusrm.gresource.xml`)

```xml
    <file>columns/interface_addresses_machine.csv</file>
```

#### Replace with (`controller/resources/argusrm.gresource.xml`)

```xml
    <file>columns/interface_addresses_machine.csv</file>
    <file>columns/mounts_machine.csv</file>
```

### 15. `controller/filter/Mounts.vala` — search + snap toggle

**Why:** Same {@link Gtk.FilterListModel} pattern as {@link Argus.Controller.Filters.Users} on the machine **Users** tab.

#### Add — `controller/filter/Mounts.vala`

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
	 * Local filter for the per-machine mounts grid.
	 */
	public class Mounts : Gtk.Filter
	{
		public string search { get; set; default = ""; }
		/**
		 * When false, {@link Argus.Shared.OSQuery.Mounts.is_snap_mount} rows are hidden.
		 */
		public bool show_snap_mounts { get; set; default = false; }

		construct
		{
			this.notify.connect((pspec) => {
				this.changed(Gtk.FilterChange.DIFFERENT);
			});
		}

		public override bool match(GLib.Object? item)
		{
			var row = (Argus.Shared.OSQuery.Mounts) item;
			if (!this.show_snap_mounts && row.is_snap_mount()) {
				return false;
			}
			var query = this.search.strip().down();
			if (query == "") {
				return true;
			}
			if (row.path.down().contains(query)) {
				return true;
			}
			if (row.device.down().contains(query)) {
				return true;
			}
			return row.ctype.down().contains(query);
		}

		public override Gtk.FilterMatch get_strictness()
		{
			if (this.search.strip() == "" && this.show_snap_mounts) {
				return Gtk.FilterMatch.ALL;
			}
			return Gtk.FilterMatch.SOME;
		}
	}
}
```

### 16. `controller/tab/Asset/Machine/Storage.vala` — standard grid

**Why:** {@link Argus.Controller.Tab.Asset.Machine.InterfaceAddresses}-style {@link Argus.Controller.Tab.Base} grid with a filter bar like **Users** (not a custom {@link Gtk.ListBox} or `mount_row` builder).

**Depends on:** items **13**, **14**, **15**.

#### Add — `controller/tab/Asset/Machine/Storage.vala`

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
	 * Per-machine storage grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''mounts_machine.csv''. {@link Argus.Controller.Store.Mounts} loads
	 * ''Mounts.list'' (column sort via {@link Argus.Controller.Tab.Base} / CSV).
	 */
	public class Storage : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Mounts store;
		private Argus.Controller.Filters.Mounts filter;

		public Storage(Argus.Controller.Window window)
		{
			base("mounts_machine", "path");
			this.store = new Argus.Controller.Store.Mounts(window.app);
			this.filter = new Argus.Controller.Filters.Mounts();
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
				placeholder_text = "Search mounts"
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var show_snaps = new Gtk.CheckButton.with_label("Show snap mounts");
			show_snaps.toggled.connect(() => {
				this.filter.show_snap_mounts = show_snaps.active;
			});
			var filter_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				margin_start = 12,
				margin_end = 12,
				margin_top = 8,
				margin_bottom = 4
			};
#if ANDROID
			filter_bar.spacing = 6;
			filter_bar.margin_start = 0;
			filter_bar.margin_end = 0;
			filter_bar.margin_top = 0;
			filter_bar.margin_bottom = 0;
			var search_toggle = new Gtk.ToggleButton() {
				icon_name = "system-search-symbolic",
				tooltip_text = "Search"
			};
			var search_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				css_classes = { "machines-filter" },
				hexpand = true,
				visible = false
			};
			search_bar.append(search);
			search_toggle.toggled.connect(() => {
				search_bar.visible = search_toggle.active;
				if (search_toggle.active) {
					search.grab_focus();
				}
			});
			filter_bar.append(search_toggle);
			filter_bar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			filter_bar.append(show_snaps);
			this.content.append(filter_bar);
			this.content.append(search_bar);
#else
			filter_bar.append(search);
			filter_bar.append(show_snaps);
			this.content.append(filter_bar);
#endif
			this.content.append(this.overlay);
		}

		public void load(int agent_id)
		{
			this.store.load(agent_id);
		}
	}
}
```

### 17. `controller/meson.build` — Storage sources

#### Remove (`controller/meson.build`)

```meson
	'store/MachineGeneral.vala',
	'store/TaskTarget.vala',
```

#### Replace with (`controller/meson.build`)

```meson
	'store/MachineGeneral.vala',
	'store/Mounts.vala',
	'store/TaskTarget.vala',
```

#### Remove (`controller/meson.build`)

```meson
	'tab/Asset/Machine/InterfaceAddresses.vala',
	'tab/Asset/Machine/Detail.vala',
```

#### Replace with (`controller/meson.build`)

```meson
	'tab/Asset/Machine/InterfaceAddresses.vala',
	'tab/Asset/Machine/Storage.vala',
	'tab/Asset/Machine/Detail.vala',
```

#### Remove (`controller/meson.build`)

```meson
	'filter/Groups.vala',
	'filter/Tasks.vala',
```

#### Replace with (`controller/meson.build`)

```meson
	'filter/Groups.vala',
	'filter/Mounts.vala',
	'filter/Tasks.vala',
```

### 18. `controller/tab/Asset/Machine/namespace.vala` — doc list

#### Remove (`controller/tab/Asset/Machine/namespace.vala`)

```vala
 * {@link Programs}, and {@link InterfaceAddresses}
```

#### Replace with (`controller/tab/Asset/Machine/namespace.vala`)

```vala
 * {@link Programs}, {@link InterfaceAddresses}, and {@link Storage}
```

### 19. `controller/tab/Asset/Machine/Detail.vala` — fields and storage tab

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private Adw.Toggle interfaces_toggle;
		private General general;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private Adw.Toggle interfaces_toggle;
		private Adw.Toggle storage_toggle;
		private General general;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private InterfaceAddresses interfaces;
		private int current_agent_id = 0;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private InterfaceAddresses interfaces;
		private Storage storage;
		private int current_agent_id = 0;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private bool interfaces_loaded = false;

		/**
		 * Build the per-machine tab switcher and stacked detail pages.
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
		private bool interfaces_loaded = false;
		private bool storage_loaded = false;

		/**
		 * Build the per-machine tab switcher and stacked detail pages.
```

### 20. `controller/tab/Asset/Machine/Detail.vala` — register Storage page + toggle

**Where:** constructor, immediately after `this.interfaces.bind_property("refreshing", interfaces_spin, …)`.

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
			this.interfaces.bind_property("refreshing", interfaces_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.group.notify["active-name"].connect(() => {
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
			this.interfaces.bind_property("refreshing", interfaces_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.storage = new Storage(window);
			this.pages.add_titled_with_icon(
				this.storage, "storage", "Storage", "drive-harddisk-symbolic");
			var storage_spin = new Adw.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var storage_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			storage_row.append(new Gtk.Image.from_icon_name("drive-harddisk-symbolic"));
#if !ANDROID
			storage_row.append(new Gtk.Label("Storage"));
#endif
			this.storage_toggle = new Adw.Toggle() {
				name = "storage",
				tooltip = "Storage",
				child = new Gtk.CenterBox() {
					center_widget = storage_row,
					end_widget = storage_spin,
					hexpand = true
				}
			};
			this.storage.bind_property("refreshing", storage_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.group.notify["active-name"].connect(() => {
```

### 21. `controller/tab/Asset/Machine/Detail.vala` — lazy load on tab switch (`group.notify`)

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
					case "interfaces":
						if (this.interfaces_loaded) {
							break;
						}
						this.interfaces_loaded = true;
						this.interfaces.load(this.current_agent_id);
						break;

					default:
						break;
				}
			});
			this.bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
					case "interfaces":
						if (this.interfaces_loaded) {
							break;
						}
						this.interfaces_loaded = true;
						this.interfaces.load(this.current_agent_id);
						break;

					case "storage":
						if (this.storage_loaded) {
							break;
						}
						this.storage_loaded = true;
						this.storage.load(this.current_agent_id);
						break;

					default:
						break;
				}
			});
			this.bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
```

### 22. `controller/tab/Asset/Machine/Detail.vala` — `clear()` and `show_machine()`

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
			this.interfaces_loaded = false;
		}

		/**
		 * Update visible detail tabs and load the active tab for
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
			this.interfaces_loaded = false;
			this.storage_loaded = false;
		}

		/**
		 * Update visible detail tabs and load the active tab for
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
			this.interfaces_loaded = false;
			var pm = machine.package_manager();
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
			this.interfaces_loaded = false;
			this.storage_loaded = false;
			var pm = machine.package_manager();
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
				this.group.add(this.interfaces_toggle);
				var target = "general";
				switch (previous) {
					case "general":
					case "users":
					case "interfaces":
						target = previous;
						break;
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
				this.group.add(this.interfaces_toggle);
				this.group.add(this.storage_toggle);
				var target = "general";
				switch (previous) {
					case "general":
					case "users":
					case "interfaces":
					case "storage":
						target = previous;
						break;
```

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
				case "interfaces":
					if (this.interfaces_loaded) {
						break;
					}
					this.interfaces_loaded = true;
					this.interfaces.load(agent_id);
					break;

				default:
					break;
			}
		}
	}
}
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
				case "interfaces":
					if (this.interfaces_loaded) {
						break;
					}
					this.interfaces_loaded = true;
					this.interfaces.load(agent_id);
					break;

				case "storage":
					if (this.storage_loaded) {
						break;
					}
					this.storage_loaded = true;
					this.storage.load(agent_id);
					break;

				default:
					break;
			}
		}
	}
}
```

### 23. `controller/tab/Asset/Machine/Detail.vala` — class docblock

#### Remove (`controller/tab/Asset/Machine/Detail.vala`)

```vala
	 * {@link InterfaceAddresses}. Tabs lazy-load
```

#### Replace with (`controller/tab/Asset/Machine/Detail.vala`)

```vala
	 * {@link InterfaceAddresses}, and {@link Storage}. Tabs lazy-load
```

---

## Slice 1c — agent connection on General

### Rejected (do not implement)

- 🚫 **`SystemInfo.list` JOIN `agent`** and session fields on **`SystemInfo`**.
- 🚫 A separate **`Agent.get`** RPC (use the same **`Agent.list`** as everywhere else, with **`i`** like **`CpuInfo.list`**).

### Intended shape (minimal)

- 🔷 **`Agent.list(i)`** — `i < 1` returns **all** registered rows (removed legacy **`LIMIT 20`**); `i > 0` returns that **`agent`** row (0–1 elements). **`connected`** still comes from live sockets.
- 🔷 **`MachineGeneral`** — one more **`load_section`**: `source` **`agent`**, method **`Agent.list`**, args **`i`** = selected `agent_id`.
- 🔷 **`machine_general.csv`** — three rows (**Connection** expander; **`display-connected`** / **`display-last`** text — existing **`Agent`** getters).
- 🔷 **Callers** that today use no-arg **`Agent.list`** pass **`i = 0`**.

**Scope:** items **24–29** only. No `SystemInfo`, no new tab, no `ColumnSchema` formats, no store sort hacks.

### 24. `server/Agent.vala` — `Agent.list(i)`

**Why:** Same RPC family as **`Uptime.list`**, **`CpuInfo.list`**, etc.

#### Remove (`server/Agent.vala`)

```vala
				"list", "",
				"remove", "i"
```

#### Replace with (`server/Agent.vala`)

```vala
				"list", "i",
				"remove", "i"
```

#### Remove (`server/Agent.vala`)

```vala
		public void list(OLLMrpc.Request request)
		{
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			Argus.Shared.Agent.query(this.app.db).select("LIMIT 20", rows);
```

#### Replace with (`server/Agent.vala`)

```vala
		public void list(OLLMrpc.Request request, int agent_id)
		{
			var rows = new Gee.ArrayList<Argus.Shared.Agent>();
			if (agent_id > 0) {
				var int_binds = new Gee.HashMap<string, int>();
				var text_binds = new Gee.HashMap<string, string>();
				int_binds.set("id", agent_id);
				Argus.Shared.Agent.query(this.app.db).selectWhere(
					"WHERE id = $id", int_binds, text_binds, rows);
			} else {
				Argus.Shared.Agent.query(this.app.db).select("", rows);
			}
```

*(Keep the existing live-socket loop and `request.reply` unchanged below.)*

### 25. Existing `Agent.list` callers — pass `0`

#### Remove (`controller/store/Agent.vala`)

```vala
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.list"
			}, (obj, res) => {
```

#### Replace with (`controller/store/Agent.vala`)

```vala
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Agent.list",
				args = OLLMrpc.args("i", 0)
			}, (obj, res) => {
```

#### Remove (`controller/Agents.vala`)

```vala
				method = "Agent.list"
```

#### Replace with (`controller/Agents.vala`)

```vala
				method = "Agent.list",
				args = OLLMrpc.args("i", 0)
```

### 26. `docs/rpc-commands.md` — `Agent.list`

#### Remove (`docs/rpc-commands.md`)

```markdown
- Arguments: none.
- Reply `retval` `o`: an array of `Argus.Shared.Agent` rows, at most twenty.
```

#### Replace with (`docs/rpc-commands.md`)

```markdown
- Arguments `i`: `agent_id`, or `0` for the Agents grid list.
- Reply `retval` `o`: an array of `Argus.Shared.Agent` rows. When `agent_id` is less than one, every row. When `agent_id` is greater than zero, zero or one row for that id. Unknown id returns an empty array.
- ℹ️ `Store.MachineGeneral` calls `Agent.list` with the selected machine id for the **General** tab **Connection** expander.
```

### 27. `controller/store/MachineGeneral.vala` — load `agent` section

#### Remove (`controller/store/MachineGeneral.vala`)

```vala
			if (!yield this.load_section(
				"system_info", "SystemInfo.list", OLLMrpc.args("ib", agent_id, false))) {
				return;
			}
```

#### Replace with (`controller/store/MachineGeneral.vala`)

```vala
			if (!yield this.load_section(
				"system_info", "SystemInfo.list", OLLMrpc.args("ib", agent_id, false))) {
				return;
			}
			if (!yield this.load_section(
				"agent", "Agent.list", OLLMrpc.args("i", agent_id))) {
				return;
			}
```

### 28. `controller/resources/columns/machine_general.csv` — Connection expander

**Where:** immediately after the **System info** block (before **OS version**).

#### Add — `controller/resources/columns/machine_general.csv`

```text
0,Connection,id,ON,0,expander,off,agent
1,Connected,display-connected,ON,0,text,off,agent
1,Last connected,display-last,ON,0,text,off,agent
```

### 29. `controller/store/MachineGeneral.vala` — docblock

#### Remove (`controller/store/MachineGeneral.vala`)

```vala
	 * ''CpuInfo.list'', and ''Uptime.list'' for one ''agent_id'' and replaces {@link items} from
```

#### Replace with (`controller/store/MachineGeneral.vala`)

```vala
	 * ''CpuInfo.list'', ''Uptime.list'', and ''Agent.list'' for one ''agent_id'' and replaces {@link items} from
```

---

## Next

- 💩 Optional: [4.0-data-types.md](../plans/4.0-data-types.md) — document `uptime` / `mounts` when accepted for the type catalog.
- 💩 Optional: Storage grid free-space warning colouring (≤15% / ≤10%) — deferred from slice **1b**.
- ℹ️ Processes / ports — [2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md).

---

## LLM notes

- ✅ Bug **closed** — file lives under `docs/bugs/done/` as **`2026-11-16-FIXED-machine-additional-osquery-data.md`**.
- 🚫 **Do not** write companion `*.vala` under `docs/bugs/` — proposed sources are **markdown fences only** (`docs/guide-to-writing-plans.md`, `docs/bug-fix-process.md`).
- 🚫 Do not fold this into [5.8](../plans/5.8-assets-page.md) as a new plan chapter; keep work here until closed.
- 🚫 Do not add processes/ports startup sync — see [2026-11-14-machine-processes-ports-live.md](../2026-11-14-machine-processes-ports-live.md).
- 🚫 Do not duplicate `cpu_info` work — [2026-11-14-FIXED-machine-cpu-in-general.md](2026-11-14-FIXED-machine-cpu-in-general.md).
- 🚫 **No** `shared/Duration.vala` (or other shared duration module) — uptime display is **`ColumnSchema`** `uptime` format only, **two units max** like **`elapsed`** in `controller/tab/Base.vala` (not a full **`y d h m s`** breakdown).
- 🚫 **No** unsolicited shared helpers (e.g. **`ColumnSchema.format_bytes`**, dedup utilities) — use existing column **`bytes`** handling in **`Tab.Base`** / **`ColumnSchema`**; add a helper only when the user asks.
- 🚫 **No** `volume_*` (or similar) method stacks on osquery rows — grid-facing derived fields are **`display_*`** properties (see **`Agent.display_connected`**, **`TaskTarget.display_duration`**). Non-display logic (e.g. snap filter) may be one small predicate such as **`is_snap_mount()`**.
- 🚫 **Slice 1c** — do **not** JOIN **`agent`** onto **`SystemInfo`**. Use **`Agent.list(i)`** + CSV **`source` = `agent`** only (items **24–29**).