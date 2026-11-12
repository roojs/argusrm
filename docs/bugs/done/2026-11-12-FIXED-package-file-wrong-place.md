# Package file was in the wrong place

**Status:** ✅ closed 2026-11-12. The approved split is in the tree. Shared `Package` holds `pkg_name` and `sync`. Agent `Package` is `send`. Each package class is its own file.

**Pointer:** `docs/bug-fix-process.md`. The runner is [2026-11-12-package-edits-before-proposal](2026-11-12-FIXED-package-edits-before-proposal.md). The hash proposal is [2026-11-12-package-monitor-send-rejected](2026-11-12-FIXED-package-monitor-send-rejected.md).

---

## Problem

- 🔷 `Package` exists so `DebPackages`, `RpmPackages`, and `Programs` share one `sync`. `pkg_name` is the hash key. The three classes do not each carry that method.
- 🔷 The file was added at `shared/OSQuery/Package.vala`. That directory is compiled into `shared_server_lib`, `shared_cli_lib`, and `shared_lib`. The controller links `shared_lib`. The server links `shared_server_lib`.
- 🔷 `send` was written in that same file. `send` runs `osqueryi` and posts the snapshot. Those are `Application` and `Execute`. Neither type is in the shared library.
- 🔷 A second file, `agent/OSQuery/Package.vala`, then defined agent subclasses of the three package classes. That file was not accepted either.

## What was written

- ✔️ `shared/meson.build` and `docs/meson.build` listed `OSQuery/Package.vala`. The file was not on disk. Meson stopped with `File OSQuery/Package.vala does not exist`.
- ✔️ `DebPackages`, `RpmPackages`, and `Programs` extended `Package` and dropped their own `sync`. After the file was removed from the build, those three classes extend `Row` again and each `sync` is back.
- ✔️ `Execute.send_packages` switches on the package manager. It does not call `DebPackages.send`. That method was on the missing file.

## Why that place is wrong

- 🔷 The row type has to be shared. The server calls `sync` on it, and the agent serializes the same class.
- 🔷 `send` is the agent. `Application.osquery` is the `Execute` that holds the path, runs the statement, and posts. A method in `shared/OSQuery/Package.vala` cannot name `Application` or `Execute`.
- 🔷 The shared package class is the row. `pkg_name` and `sync` stay in `shared/OSQuery/Package.vala`.
- 🔷 `send` is an agent interface, in its own file. That file holds that one type.
- 🚫 Do not put `DebPackages`, `RpmPackages`, and `Programs` in the agent file. One class is one file. A child class, when it is added, is `agent/OSQuery/DebPackages.vala`, and the same for RPM and Programs.

## Evidence

- ℹ️ `shared/meson.build` `shared_sources` feeds `shared_server_lib`, `shared_cli_lib`, and `shared_lib`.
- ℹ️ `controller/meson.build` links `shared_dep`. `server/meson.build` links `shared_server_dep`.
- ℹ️ `agent/OSQuery/Execute.vala` `send_packages`. `shared/OSQuery/DebPackages.vala` `: Row`.

## Root cause

- ✔️ One file was given two jobs, and the agent attempt then put every child class in the one send file. `sync` belongs in the shared package class. `send` belongs on one agent type. The children each have their own file.

## Proposed fix

Applied. This is the approved split.

- 🔷 `shared/OSQuery/Package.vala` is one class. `pkg_name` and `sync`. No `send`.
- 🔷 `agent/OSQuery/Package.vala` is one interface. `send` is `public virtual` on that interface, the same way `SQ.Interface.copy_from` carries a body. The file does not declare the three package classes.
- 🔷 `agent/OSQuery/DebPackages.vala`, `agent/OSQuery/RpmPackages.vala`, and `agent/OSQuery/Programs.vala` are the agent classes. Each extends the shared class of the same name and implements `Package`. They are not compiled into the Android agent.
- ✔️ `shared/OSQuery/DebPackages.vala`, `RpmPackages.vala`, and `Programs.vala` extend `Package`. Their `sync` overrides are removed. `pkg_name` is `name` plus a newline plus `arch`, or `identifying_number` for `Programs`.
- ℹ️ On 2026-11-12, `build/server/argus-packages-test` stops while applying a Debian snapshot. `Package.sync` loads stored rows as `Package`, and that class is only a base. That run is not a new design.

### `shared/OSQuery/Package.vala` — the row

#### Add

`send` is not in this class. The rest is the review copy.

```vala
namespace Argus.Shared.OSQuery
{
	/**
	 * One installed package row.
	 *
	 * {@link DebPackages}, {@link RpmPackages}, and
	 * {@link Programs} extend this. {@link pkg_name} is the
	 * hash key. {@link sync} applies one snapshot.
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

### `agent/OSQuery/Package.vala` — the `send` interface

#### Add

One interface in this file. `send` is `public virtual`, so the body stays here.

```vala
namespace Argus.Agent.OSQuery
{
	/**
	 * Post one package snapshot.
	 *
	 * The shared {@link Argus.Shared.OSQuery.Package} applies it.
	 * This type does not declare {@link Argus.Shared.OSQuery.DebPackages},
	 * {@link Argus.Shared.OSQuery.RpmPackages}, or
	 * {@link Argus.Shared.OSQuery.Programs}.
	 */
	public interface Package : Argus.Shared.OSQuery.Package
	{
		/**
		 * Query this table and post the snapshot.
		 *
		 * {@link Execute.select} fills the list.
		 * {@link Execute.init} sets {@link Execute.osqueryi}
		 * when it is still empty. An empty path posts nothing.
		 * An empty query after ''application.packages_sent''
		 * posts nothing.
		 *
		 * @param application agent that holds the connection and
		 *   {@link Application.packages_sent}
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public virtual int send(Application application)
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return 0;
			}
			var fresh = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
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
				Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			application.packages_sent = true;
			return 0;
		}
	}
}
```

### `agent/OSQuery/DebPackages.vala` — APT

#### Add

Extends the shared row and implements `Package`. `send` stays on the interface. The same shape is `RpmPackages.vala` and `Programs.vala`.

```vala
namespace Argus.Agent.OSQuery
{
	/**
	 * Agent ''deb_packages'' row.
	 *
	 * Extends {@link Argus.Shared.OSQuery.DebPackages} and
	 * implements {@link Package}.
	 */
	public class DebPackages : Argus.Shared.OSQuery.DebPackages, Package
	{
	}
}
```

### `agent/OSQuery/RpmPackages.vala` — DNF

#### Add

```vala
namespace Argus.Agent.OSQuery
{
	/**
	 * Agent ''rpm_packages'' row.
	 *
	 * Extends {@link Argus.Shared.OSQuery.RpmPackages} and
	 * implements {@link Package}.
	 */
	public class RpmPackages : Argus.Shared.OSQuery.RpmPackages, Package
	{
	}
}
```

### `agent/OSQuery/Programs.vala` — Windows

#### Add

```vala
namespace Argus.Agent.OSQuery
{
	/**
	 * Agent ''programs'' row.
	 *
	 * Extends {@link Argus.Shared.OSQuery.Programs} and
	 * implements {@link Package}.
	 */
	public class Programs : Argus.Shared.OSQuery.Programs, Package
	{
	}
}
```

These three files go in the Linux GTK, Windows, and CLI source lists in `agent/meson.build`, next to `OSQuery/Execute.vala`. They do not go in the Android list.

### `agent/OSQuery/Execute.vala` — `send_packages`

#### Replace with

```vala
		internal int send_packages()
		{
			switch (this.application.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return new DebPackages().send(this.application);

				case Argus.Shared.OSQuery.PackageManager.DNF:
					return new RpmPackages().send(this.application);

				case Argus.Shared.OSQuery.PackageManager.WIN:
					return new Programs().send(this.application);

				default:
					return 0;
			}
		}
```

## Attempts / changelog

- ✔️ `shared/OSQuery/Package.vala` is the row. `pkg_name` and `sync`. `DebPackages`, `RpmPackages`, and `Programs` extend it.
- ✔️ `agent/OSQuery/Package.vala` is the `send` interface. `DebPackages`, `RpmPackages`, and `Programs` are one file each and implement it. `Execute.send_packages` constructs the matching class.
- ✔️ `ninja -C build agent/argusrm-agent agent/argusrm-agent-gtk server/argus-packages-test` linked the agent targets. The package test aborts on the abstract `Package`.

## Next

- ✅ Closed 2026-11-12. The approved split is in the tree.
