# Package monitor send was rejected

**Status:** 🚫 The product edits are not this proposal. The corrections are [2026-11-12-package-edits-before-proposal](2026-11-12-package-edits-before-proposal.md). Do not apply this file until that one is accepted.

**Pointer:** `docs/bug-fix-process.md`. The earlier report is [2026-11-12-sync-changes-out-of-scope](2026-11-12-sync-changes-out-of-scope.md). The phase plan is [5.9.1](../plans/5.9.1-assets-software-data.md).

---

## Problem

- 🔷 The comparison in `PackageMonitor.send` was rejected. It belongs on the package row class. That class builds a hash map. It does not walk columns, and it does not walk every stored row for every fresh row.
- 🔷 `Application.send_packages` is the relay. It switches on the OS type and calls `send` on that one package. Debian, RPM, and Windows are never all present, so two of the three lists are always empty.
- 🔷 The Windows timer at `agent/Win32/PackageMonitor.vala` was rejected. That callback is the watch. It is not a second copy of startup.
- 🔷 `send_packages` is a relay. The package class does the behaviour.
- 🔷 `Package` is the base. One generic `sync` indexes by `pkg_name`. `DebPackages`, `RpmPackages`, and `Programs` pass their type and return. The type supplies the row class. `table_name` and `pkg_name` supply the rest.

## What was written

- ✔️ Both monitors own a `send` method. Each one takes a table name, a class name, and a `key_columns` array.
- ✔️ The method builds a key by `get_property` on every column, for every stored row, then does that walk again for every fresh row. A miss is new. A hit calls `compare`. Keys left over get `deleted_dt` and are posted as `OSQuery.update`.
- ✔️ `agent/OSQuery/Initialize.vala` still syncs `deb_packages` and `rpm_packages` on Linux, and `programs` on Windows. One of the two Linux lists is empty on every host.
- ✔️ The Windows callback searches `PATH` for `osqueryi`, then `Program Files\osquery\osqueryi.exe`, then runs `SELECT * FROM programs`, then calls `send`.
- ✔️ The Linux timers do the same kind of search after the lock, then query the table that method was named for.

## Why that design is wrong

- 🔷 A package row already knows its own key. `DebPackages` and `RpmPackages` are `name` and `arch`. `Programs` is `name` and `identifying_number`. A `key_columns` array plus `get_property` is the monitor pretending it does not know the class, which is why the same loop is copied into both files.
- 🔷 The nested column walk is the double loop. One pass over stored rows and one pass over fresh rows is the hash map. A second search through the stored list, or a second walk of the columns, is the part that was rejected.
- 🔷 The host is one OS. The startup `os_version` row already says which. Sending the other classes queries an empty table. On a full sync, that empty list is "this class has no rows", which is the wrong class for this machine.
- 🔷 Finding `osqueryi` is startup. The Windows event only means an install or a removal happened. Pairing `1033` with `11707`, or `1034` with `11724`, is why the callback waits one second. After that wait it calls the one send. It does not name a table, and it does not search for `osqueryi` again.
- ✔️ `Query.select` is `void`. A failed launch leaves the caller's list empty. An empty list after a snapshot is already stored is a failed query, not "every package left". A host that really has no packages is cleared by the first `OSQuery.sync` of that one class, not by a later empty update.
- 🔷 The stored rows are on the server. The hash map and the writes belong with those rows. `send_packages` does not diff, and it does not keep a copy of the list.

## Evidence

- ℹ️ `agent/Win32/PackageMonitor.vala` `logged`, the one-second timeout. `agent/linux/PackageMonitor.vala` `apt`, `rpm`, and `send`. `agent/OSQuery/Initialize.vala` `run`, the `LINUX` / `WINDOWS` package syncs.
- ✔️ `Application` has no package list and no `osqueryi` path. Both monitors call `this.application.package_rows`.
- ✔️ `server/OSQuery.vala` registers `OSQuery.update` and has no `update` method. The shared package classes have `sync` and no server subclass. `server/tests/packages.vala` calls the shared `sync`.

## Root cause

- ✔️ The difference was written as a generic column walk on the monitor, and each monitor then queried its own table. The class that owns the fields, and the one OS the host actually is, were left out of that path. The Windows callback then copied startup's `osqueryi` search into the watch.

## Proposed fix

Apply the sections in order. The monitor `send` is deleted. `Package` then has one generic `sync`, and `send`.

- 🔷 Delete `PackageMonitor.send` in `agent/linux/PackageMonitor.vala` and in `agent/Win32/PackageMonitor.vala`.
- 🔷 `apt()`, `rpm()`, and the Windows log callback only wait, then call `application.osquery.send_packages`.
- 🔷 `Execute.send_packages` switches, calls `send` on one new package, and returns. `APT` constructs `DebPackages`. `DNF` constructs `RpmPackages`. `WIN` constructs `Programs`. `UNKNOWN` returns zero. `Application` holds that `Execute`.
- 🔷 `Package.send` takes the application. It reads `connection` and `packages_sent` from that object. {@link Argus.Agent.OSQuery.Execute} holds the `osqueryi` path and launches it. `send` calls `Execute.select` with `table_name`, then posts `OSQuery.sync` with `rpc_name`. The class is named in [2026-11-12-package-edits-before-proposal](2026-11-12-package-edits-before-proposal.md).
- 🔷 `shared/OSQuery/Package.vala` is the base class. `DebPackages`, `RpmPackages`, and `Programs` extend it. `pkg_name` builds the hash key. `sync` indexes stored rows by `pkg_name`, looks each incoming row up once, and writes the result. A stored key left over gets `deleted_dt`. The running object is the row class: `this.get_type()` and `this.table_name()`. The three classes do not override `sync`.
- 🚫 Leave both monitors out of `agent/meson.build`. Leave both unconstructed at startup.
- 🚫 Leave `Query.select` as `void`.
- 🚫 Leave the hash map off `Application`. Leave the hash body off the three package classes.
- 🔷 `table_name` and `rpc_name` are methods on every row. Each class returns its own table and its own RPC name, on one line.
- 🚫 Leave out `package_table` and `package_class`. These are methods. An empty string is a real name.
- 💩 `Query.select` leaves the list empty when the launch fails. After `packages_sent` is true, `send` drops that empty list. The first empty list is still posted, and that `sync` clears the host. `pkg_name` joins the two fields with a newline. `Row.sync_rows` stays the nested walk for the other osquery tables. `Package` is in the shared library. `Application` and `Query` are in the agent library, so `Package.send` cannot name them until those types are visible to shared. `SQ.Query<T>` constructs `typeof(T)` and reads properties from that type. `Query<Package>` skips `name`, `arch`, and `identifying_number`.

### `agent/linux/PackageMonitor.vala` — delete `send`

#### Remove

The whole method, from its docblock through its closing brace.

```vala
		/**
		 * Post the difference from the kept fetch.
		 *
		 * The kept rows are indexed by ''key_columns''. One pass
		 * over ''fresh'' finds a new key or compares a match once.
		 * Keys left in the index are sent with ''deleted_dt'' set.
		 * An empty ''fresh'' sends nothing: a failed query leaves
		 * the list empty, and that is not every package leaving.
		 * After a successful call the kept fetch becomes ''fresh''.
		 *
		 * @param table osquery table name
		 * @param class_name registered row name
		 * @param key_columns properties that identify a row
		 * @param fresh rows from the new query, empty on failure
		 */
		public void send(
			string table,
			string class_name,
			string[] key_columns,
			Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> fresh
		) {
			if (fresh.size == 0) {
				return;
			}
			var index = new Gee.HashMap<string, Argus.Shared.OSQuery.AgentInfo>();
			if (this.application.package_rows.has_key(table)) {
				foreach (var row in this.application.package_rows.get(table)) {
					var key = "";
					foreach (var column in key_columns) {
						var value = GLib.Value(typeof(string));
						((GLib.Object) row).get_property(column, ref value);
						var text = value.get_string();
						key = key + "\n" + (text != null ? text : "");
					}
					if (!index.has_key(key)) {
						index.set(key, row);
					}
				}
			}
			var diff = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			foreach (var row in fresh) {
				var key = "";
				foreach (var column in key_columns) {
					var value = GLib.Value(typeof(string));
					((GLib.Object) row).get_property(column, ref value);
					var text = value.get_string();
					key = key + "\n" + (text != null ? text : "");
				}
				var kept = index.get(key);
				if (kept == null) {
					diff.add(row);
					continue;
				}
				if (!kept.compare(row)) {
					diff.add(row);
				}
				index.unset(key);
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in index.values) {
				((Argus.Shared.OSQuery.Row) row).deleted_dt = now;
				diff.add(row);
			}
			if (diff.size == 0) {
				return;
			}
			var connection = this.application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			GLib.debug("%s %d rows", table, diff.size);
			try {
				var response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.update",
					args = OLLMrpc.args("so", class_name, diff)
				});
				if (response.error != null) {
					GLib.debug("%s send failed %s", table, response.error.message);
					return;
				}
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return;
			}
			this.application.package_rows.set(table, fresh);
		}
```

### `agent/Win32/PackageMonitor.vala` — delete `send`

#### Remove

The whole method, from its docblock through its closing brace.

```vala
		/**
		 * Post the difference from the kept fetch.
		 *
		 * The kept rows are indexed by ''key_columns''. One pass
		 * over ''fresh'' finds a new key or compares a match once.
		 * Keys left in the index are sent with ''deleted_dt'' set.
		 * An empty ''fresh'' sends nothing: a failed query leaves
		 * the list empty, and that is not every package leaving.
		 * After a successful call the kept fetch becomes ''fresh''.
		 *
		 * @param table osquery table name
		 * @param class_name registered row name
		 * @param key_columns properties that identify a row
		 * @param fresh rows from the new query, empty on failure
		 */
		public void send(
			string table,
			string class_name,
			string[] key_columns,
			Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> fresh
		) {
			if (fresh.size == 0) {
				return;
			}
			var index = new Gee.HashMap<string, Argus.Shared.OSQuery.AgentInfo>();
			if (this.application.package_rows.has_key(table)) {
				foreach (var row in this.application.package_rows.get(table)) {
					var key = "";
					foreach (var column in key_columns) {
						var value = GLib.Value(typeof(string));
						((GLib.Object) row).get_property(column, ref value);
						var text = value.get_string();
						key = key + "\n" + (text != null ? text : "");
					}
					if (!index.has_key(key)) {
						index.set(key, row);
					}
				}
			}
			var diff = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			foreach (var row in fresh) {
				var key = "";
				foreach (var column in key_columns) {
					var value = GLib.Value(typeof(string));
					((GLib.Object) row).get_property(column, ref value);
					var text = value.get_string();
					key = key + "\n" + (text != null ? text : "");
				}
				var kept = index.get(key);
				if (kept == null) {
					diff.add(row);
					continue;
				}
				if (!kept.compare(row)) {
					diff.add(row);
				}
				index.unset(key);
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in index.values) {
				((Argus.Shared.OSQuery.Row) row).deleted_dt = now;
				diff.add(row);
			}
			if (diff.size == 0) {
				return;
			}
			var connection = this.application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return;
			}
			GLib.debug("%s %d rows", table, diff.size);
			try {
				var response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.update",
					args = OLLMrpc.args("so", class_name, diff)
				});
				if (response.error != null) {
					GLib.debug("%s send failed %s", table, response.error.message);
					return;
				}
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return;
			}
			this.application.package_rows.set(table, fresh);
		}
```

### `agent/linux/PackageMonitor.vala` — `apt`: drop the query

#### Remove

In the `apt` timer, after the locks are held. The lock fds still close after the call.

```vala
					var osqueryi = "";
					var found = GLib.Environment.find_program_in_path("osqueryi");
					if (found != null && found != "") {
						osqueryi = found;
					}
					var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
					if (osqueryi != "") {
						new OSQuery.Query(osqueryi,
							typeof(Argus.Shared.OSQuery.DebPackages)).select(
							"SELECT * FROM deb_packages", fresh);
					}
					this.send("deb_packages", "DebPackages", { "name", "arch" }, fresh);
```

#### Replace with

```vala
					this.application.osquery.send_packages();
```

### `agent/linux/PackageMonitor.vala` — `rpm`: drop the query

#### Remove

In the `rpm` timer, after the lock is held. The lock fds still close after the call.

```vala
					var osqueryi = "";
					var found = GLib.Environment.find_program_in_path("osqueryi");
					if (found != null && found != "") {
						osqueryi = found;
					}
					var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
					if (osqueryi != "") {
						new OSQuery.Query(osqueryi,
							typeof(Argus.Shared.OSQuery.RpmPackages)).select(
							"SELECT * FROM rpm_packages", fresh);
					}
					this.send("rpm_packages", "RpmPackages", { "name", "arch" }, fresh);
```

#### Replace with

```vala
					this.application.osquery.send_packages();
```

### `agent/Win32/PackageMonitor.vala` — the watch drops the query

#### Remove

The body of the one-second timeout, from `var fresh` through the `send` call. The subscription, the idle marshal, and `later = 0` stay.

```vala
					var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
					var osqueryi = "";
					var found = GLib.Environment.find_program_in_path("osqueryi");
					if (found != null && found != "") {
						osqueryi = found;
					}
					if (osqueryi == "") {
						var program_files = GLib.Environment.get_variable("ProgramFiles");
						if (program_files == null || program_files == "") {
							program_files = "C:\\Program Files";
						}
						var installed = GLib.Path.build_filename(
							program_files, "osquery", "osqueryi.exe");
						if (GLib.FileUtils.test(installed, GLib.FileTest.EXISTS)) {
							osqueryi = installed;
						}
					}
					if (osqueryi != "") {
						new OSQuery.Query(osqueryi,
							typeof(Argus.Shared.OSQuery.Programs)).select(
							"SELECT * FROM programs", fresh);
					}
					PackageMonitor.current.send("programs", "Programs",
						{ "name", "identifying-number" }, fresh);
```

#### Replace with

```vala
					PackageMonitor.current.application.osquery.send_packages();
```

### `agent/Application.vala` — the relay

#### Add

After the `connection` property. `packages_sent` is how a failed query is kept off the wire. The class on the server owns the rows. `Query` holds the `osqueryi` path.

```vala
		/**
		 * Startup ''os_version'' row. {@link send_packages} reads
		 * {@link Argus.Shared.OSQuery.OsVersion.package_manager}.
		 */
		internal Argus.Shared.OSQuery.OsVersion os_version {
			get; set; default = new Argus.Shared.OSQuery.OsVersion();
		}

		/**
		 * True after the first package snapshot was posted.
		 * A later empty query is not forwarded.
		 */
		internal bool packages_sent = false;
```

#### Add

`send_packages`, after `open_connection`. Switch, call `send`, return.

```vala
		/**
		 * Forward the one package class for this host.
		 *
		 * {@link Argus.Shared.OSQuery.OsVersion.package_manager}
		 * selects the package. That package sends. {@link Package.sync}
		 * applies the snapshot.
		 *
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		internal int send_packages()
		{
			switch (this.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return new Argus.Shared.OSQuery.DebPackages().send(this);

				case Argus.Shared.OSQuery.PackageManager.DNF:
					return new Argus.Shared.OSQuery.RpmPackages().send(this);

				case Argus.Shared.OSQuery.PackageManager.WIN:
					return new Argus.Shared.OSQuery.Programs().send(this);

				default:
					return 0;
			}
		}
```

### `shared/OSQuery/Row.vala` — `table_name` and `rpc_name`

#### Add

After `public abstract bool sync`. Every concrete row implements both.

```vala
		/**
		 * Osquery table this row is read from.
		 *
		 * @return the table name
		 */
		public abstract string table_name();

		/**
		 * RPC name for this row.
		 *
		 * @return the wire alias
		 */
		public abstract string rpc_name();
```

### `shared/OSQuery/Package.vala` — package base, `pkg_name`

#### Add

New file, between `Row.vala` and `DebPackages.vala` in `shared/meson.build` and in `docs/meson.build`. `DebPackages`, `RpmPackages`, and `Programs` change `: Row` to `: Package`.

```vala
namespace Argus.Shared.OSQuery
{
	/**
	 * One installed package row.
	 *
	 * {@link DebPackages}, {@link RpmPackages}, and
	 * {@link Programs} extend this. {@link pkg_name} is the
	 * hash key. {@link sync} applies one snapshot.
	 * {@link send} posts that snapshot.
	 */
	public abstract class Package : Row
	{
		/**
		 * Key for the package hash.
		 *
		 * @return the fields that identify this package
		 */
		public abstract string pkg_name();

		/**
		 * Query this table and post the snapshot.
		 *
		 * {@link Argus.Agent.OSQuery.Execute.select} fills the
		 * list. {@link Argus.Agent.OSQuery.Execute.init} sets
		 * {@link Argus.Agent.OSQuery.Execute.osqueryi} when it
		 * is still empty. An empty path posts nothing. An empty
		 * query after ''application.packages_sent'' posts nothing.
		 *
		 * @param application agent that holds the connection and
		 *   {@link Argus.Agent.Application.packages_sent}
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public int send(Argus.Agent.Application application)
		{
			Argus.Agent.OSQuery.Execute.init();
			if (Argus.Agent.OSQuery.Execute.osqueryi == "") {
				return 0;
			}
			var fresh = new Gee.ArrayList<AgentInfo>();
			application.osquery.select(
				this.get_type(), "SELECT * FROM " + this.table_name(), fresh);
			if (application.packages_sent && fresh.size == 0) {
				return 0;
			}
			var connection = application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				var response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", this.rpc_name(), fresh)
				});
				if (response.error != null) {
					GLib.debug("%s send failed %s", this.table_name(), response.error.message);
					return response.error.code;
				}
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			application.packages_sent = true;
			return 0;
		}

		/**
		 * Apply one package snapshot.
		 *
		 * The instance is the row class. {@link table_name} is
		 * the stored table. {@link pkg_name} is the hash key.
		 *
		 * @param db Argus database
		 * @param agent_id registered agent
		 * @param rows complete table snapshot
		 * @return true when every row has this class
		 */
		public override bool sync(
			SQ.Database db,
			int64 agent_id,
			Gee.ArrayList<AgentInfo> rows)
		{
			foreach (var row in rows) {
				if (row.get_type() != this.get_type()) {
					return false;
				}
			}
			var query = new SQ.Query<Package>(db, this.table_name());
			var stored = new Gee.ArrayList<Package>();
			var int_binds = new Gee.HashMap<string, int>();
			int_binds.set("agent_id", (int) agent_id);
			query.selectWhere("WHERE agent_id = $agent_id", int_binds, null, stored);
			var index = new Gee.HashMap<string, Package>();
			foreach (var old in stored) {
				var key = old.pkg_name();
				if (!index.has_key(key)) {
					index.set(key, old);
				}
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			foreach (var row in rows) {
				var pkg = (Package) row;
				var key = pkg.pkg_name();
				var old = index.get(key);
				var newer = (Row) row;
				newer.agent_id = agent_id;
				if (old == null) {
					newer.id = 0;
					newer.added_dt = now;
					newer.updated_dt = 0;
					newer.deleted_dt = 0;
					query.insert(pkg);
					continue;
				}
				newer.id = old.id;
				newer.added_dt = old.added_dt;
				if (old.deleted_dt != 0) {
					newer.deleted_dt = 0;
					newer.updated_dt = now;
					query.updateOld(old, pkg);
					index.unset(key);
					continue;
				}
				newer.deleted_dt = 0;
				if (!old.compare(newer)) {
					newer.updated_dt = now;
					query.updateOld(old, pkg);
				}
				index.unset(key);
			}
			foreach (var old in index.values) {
				if (old.deleted_dt != 0) {
					continue;
				}
				old.deleted_dt = now;
				query.updateById(old);
			}
			return true;
		}
	}
}
```

### Shared package classes — `sync`

#### Remove

These overrides. `Package.sync` is the method that remains.

`shared/OSQuery/DebPackages.vala`

```vala
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<DebPackages>(db, agent_id, rows, "deb_packages", { "name", "arch" });
		}
```

`shared/OSQuery/RpmPackages.vala`

```vala
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<RpmPackages>(db, agent_id, rows, "rpm_packages", { "name", "arch" });
		}
```

`shared/OSQuery/Programs.vala`

```vala
		public override bool sync(SQ.Database db, int64 agent_id, Gee.ArrayList<AgentInfo> rows)
		{
			return this.sync_rows<Programs>(db, agent_id, rows, "programs", { "name", "identifying-number" });
		}
```

### Shared package classes — `pkg_name`

#### Add

After `sync` on each package class. One line.

`shared/OSQuery/DebPackages.vala` and `shared/OSQuery/RpmPackages.vala`

```vala
		public override string pkg_name() { return this.name + "\n" + this.arch; }
```

`shared/OSQuery/Programs.vala`

```vala
		public override string pkg_name() { return this.name + "\n" + this.identifying_number; }
```

### Shared row classes — `table_name` and `rpc_name`

#### Add

After `sync` on each class. One line each.

`shared/OSQuery/DebPackages.vala`

```vala
		public override string table_name() { return "deb_packages"; }
		public override string rpc_name() { return "DebPackages"; }
```

`shared/OSQuery/RpmPackages.vala`

```vala
		public override string table_name() { return "rpm_packages"; }
		public override string rpc_name() { return "RpmPackages"; }
```

`shared/OSQuery/Programs.vala`

```vala
		public override string table_name() { return "programs"; }
		public override string rpc_name() { return "Programs"; }
```

`shared/OSQuery/SystemInfo.vala`

```vala
		public override string table_name() { return "system_info"; }
		public override string rpc_name() { return "SystemInfo"; }
```

`shared/OSQuery/CpuInfo.vala`

```vala
		public override string table_name() { return "cpu_info"; }
		public override string rpc_name() { return "CpuInfo"; }
```

`shared/OSQuery/LoggedInUsers.vala`

```vala
		public override string table_name() { return "logged_in_users"; }
		public override string rpc_name() { return "LoggedInUsers"; }
```

`shared/OSQuery/InterfaceAddresses.vala`

```vala
		public override string table_name() { return "interface_addresses"; }
		public override string rpc_name() { return "InterfaceAddresses"; }
```

`shared/OSQuery/OsVersion.vala`

```vala
		public override string table_name() { return "os_version"; }
		public override string rpc_name() { return "OsVersion"; }
```





### `agent/OSQuery/Initialize.vala` — `run`: one package class

#### Remove

In `run`, the package syncs. The other tables stay.

```vala
#if LINUX
			code += this.sync_table(osqueryi, "deb_packages", "DebPackages");
			code += this.sync_table(osqueryi, "rpm_packages", "RpmPackages");
#elif WINDOWS
			code += this.sync_table(osqueryi, "programs", "Programs");
#endif
```

`send_packages` is not added here. `Execute.send_startup` calls it. That method is in [2026-11-12-package-edits-before-proposal](2026-11-12-package-edits-before-proposal.md).

#### Add

In `sync_table`, after a successful `OSQuery.sync`, when `table` is `os_version` and `rows.size > 0`. That row is what the switch reads.

```vala
			if (table == "os_version" && rows.size > 0) {
				this.application.os_version = (Argus.Shared.OSQuery.OsVersion) rows.get(0);
			}
```

## Attempts / changelog

- ✔️ No product code in this step. The previous send is still in both monitor files.
- ✔️ `Package.send` takes the application. `send_packages` passes `this`.
- ✔️ `server/tests/packages.vala` no longer calls `DebPackages.update`. That method does not exist, and it was the build failure. `agent/linux/PackageMonitor.vala` is out of `docs/meson.build`, so valadoc does not compile it. Neither monitor is in `agent/meson.build`. `build/server/argus-packages-test` prints `ok package lists`.
- ✔️ Applied. `shared/OSQuery/Package.vala` is the one `sync`. `send` is `agent/OSQuery/Package.vala`. The shared library is linked by the controller, so it cannot name `Application` or `Query`, and the server process has neither. `Package.sync` calls `sync_rows<DebPackages>`, `sync_rows<RpmPackages>`, or `sync_rows<Programs>` from `this.get_type()`. `SQ.Query<Package>` would skip `name` and `arch`. The hash is the package branch of `sync_rows`. The other tables keep the nested walk.
- ✔️ `build/server/argus-packages-test` prints `ok package lists` after that apply. `agent/argusrm-agent` and `agent/argusrm-agent-gtk` link.

## Next

- 🚫 Do not apply this file again until [2026-11-12-package-edits-before-proposal](2026-11-12-package-edits-before-proposal.md) is accepted. The edits in the tree are that bug.
