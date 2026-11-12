# Package edits landed before a proposal

**Status:** ✅ closed 2026-11-12. `Query` is `Execute`. `Initialize` installs and returns. Startup calls `send_startup`.

**Pointer:** `docs/bug-fix-process.md`. The send proposal is [2026-11-12-package-monitor-send-rejected](2026-11-12-FIXED-package-monitor-send-rejected.md). The phase plan is [5.9.1](../../plans/done/5.9.1-DONE-assets-software-data.md).

---

## Problem

- 🔷 A spoken correction was written into product files. The correction belonged in a bug first.
- 🔷 The `osqueryi` path was passed around. The class that runs `osqueryi` holds the path. Callers do not receive it and do not store it.
- 🔷 `Initialize` downloads and installs the binary. That is the cutoff. It does not run `osqueryi`, and it does not post a table.
- 🔷 The runner is named `Execute`. The namespace is already `OSQuery`, so the type is `OSQuery.Execute`. `OSQuery.Query` names the namespace twice.
- 🔷 The first bug was then marked applied. The files do not match its fences. `shared/OSQuery/Package.vala` is not on disk. `DebPackages`, `RpmPackages`, and `Programs` extend `Package`. `agent/meson.build` lists `agent/OSQuery/Package.vala`, and that file is not on disk.

## What was written

- ✔️ `Application.send_packages` calls `new OSQuery.DebPackages().send(this)`, and the RPM and Windows lines match. Those agent classes are not in the tree. The shared classes have no `send`.
- ✔️ `agent/OSQuery/Initialize.vala` reads `Query.osqueryi` and calls `new Query(row_type)`. `agent/OSQuery/Query.vala` still takes the path: `Query(string osqueryi, GLib.Type row_type)`, and `osqueryi` is an instance field. Those two files do not compile together.
- ✔️ `Application` has no `osqueryi` field. `Initialize` no longer searches `PATH` or `Program Files\osquery\osqueryi.exe`.
- ✔️ The three package classes no longer override `sync`. `Row` gained `table_name` and `rpc_name`. The package base those classes extend was deleted after it was written as agent subclasses plus a `sync_rows<T>` branch.
- ✔️ `agent/meson.build` lists `OSQuery/Package.vala` in the Linux agent, the Windows agent, and `argusrm-agent`. `shared/meson.build` and `docs/meson.build` list `shared/OSQuery/Package.vala`. `docs/meson.build` also lists `agent/OSQuery/Package.vala`.

## Why that happened

- 🔷 The first bug's open point says `Package` is in the shared library and `Application` and `Query` are in the agent, and that `SQ.Query<Package>` skips `name`, `arch`, and `identifying_number`. Those two facts were treated as permission to add `agent/OSQuery/Package.vala` and to put the hash in `Row.sync_rows`.
- 🔷 The next correction, that `Query` owns the executable, was edited into `Initialize` and into the first bug's fences. `Query.vala` was put back. The calls stayed.

## Evidence

- ℹ️ `agent/OSQuery/Query.vala` `Query(string osqueryi, GLib.Type row_type)`. `agent/OSQuery/Initialize.vala` `run`, `Query.osqueryi` and `new Query(row_type)`.
- ℹ️ `agent/Application.vala` `send_packages`. `shared/OSQuery/DebPackages.vala` `: Package`. `shared/meson.build` and `agent/meson.build`.

## Root cause

- ✔️ The proposal and the files were updated in the same turn. A rejected shape was replaced with another shape that was not written down first. The tree is the record of those turns, and it does not build.

## Proposed fix

Do not apply this while the status is ⏳. No product file changes until it is accepted.

- 🔷 A correction is a fence in this file. The product files change only after this status says accepted.
- 🚫 Do not add a class, a file, or a branch in `sync_rows` to get past an open point.
- 🚫 Do not add `agent/OSQuery/Package.vala`. There is no agent subclass of `DebPackages`, `RpmPackages`, or `Programs`.
- 🚫 Do not put `osqueryi` on `Application`. Do not pass the path into `Execute`, into `sync_table`, or into `Package.send`.
- 🚫 Do not leave `select`, `sync_table`, or `send_packages` on `Initialize`. Do not leave `send_packages` on `Application`.
- 🔷 `Application` holds one `Execute`. The field is `osquery`. The constructor sets `this.osquery = new OSQuery.Execute(this)`.
- 🔷 `Execute.osqueryi` is a static string. `Execute.init` sets it when it is still empty. `select` and `send_startup` call `init`. `Initialize` calls `init`, and an empty string means download and install. After that, `Initialize` returns. Startup then calls `this.osquery.send_startup`.
- 🔷 `send_packages` is a method on `Execute`. It switches on `application.os_version.package_manager` and calls `send` on the shared package. `send_startup` calls `this.send_packages`.
- 🔷 `Package.send` uses `application.osquery.select`. It does not construct another `Execute`.
- 🔷 Android compiles `agent/android/OSQuery/Execute.vala`. That class has the same methods and does nothing. `Application` does not use `#if ANDROID` to choose the runner.
- 💩 `Package` is still in the shared library. `Application` and `Execute` are still agent-only, so `Package.send` still cannot name them from `shared_lib`. `SQ.Query<Package>` still skips `name`, `arch`, and `identifying_number`. This bug does not pick a workaround for either one.

### `agent/OSQuery/Execute.vala` — rename `Query`, own the run

The file `agent/OSQuery/Query.vala` becomes `agent/OSQuery/Execute.vala`. The class becomes `Execute`. `select` is the one statement. `send_startup` and `sync_table` are added in this class, after `select`. `Initialize` does not have `sync_table`.

#### Replace

The instance path and the constructor that takes it.

```vala
		/**
		 * Path to ''osqueryi'', or the name looked up on ''PATH''.
		 */
		public string osqueryi = "";
		public GLib.Type row_type { get; construct; }

		/**
		 * @param osqueryi path or name of ''osqueryi''
		 * @param row_type shared osquery row class
		 */
		public Query(string osqueryi, GLib.Type row_type)
		{
			Object(row_type: row_type);
			this.osqueryi = osqueryi;
		}
```

#### Replace with

```vala
		/**
		 * Path to ''osqueryi''. Empty until {@link init}.
		 */
		public static string osqueryi = "";

		/**
		 * Find ''osqueryi'' when {@link osqueryi} is still empty.
		 *
		 * The first call searches ''PATH''. On Windows it then
		 * checks ''Program Files\osquery\osqueryi.exe''. A hit
		 * is kept. A miss leaves the string empty, so the next
		 * call searches again.
		 */
		public static void init()
		{
			if (Execute.osqueryi != "") {
				return;
			}
			var found = GLib.Environment.find_program_in_path("osqueryi");
			if (found != null && found != "") {
				Execute.osqueryi = found;
				return;
			}
#if WINDOWS
			var program_files = GLib.Environment.get_variable("ProgramFiles");
			if (program_files == null || program_files == "") {
				program_files = "C:\\Program Files";
			}
			var installed = GLib.Path.build_filename(
				program_files, "osquery", "osqueryi.exe");
			if (GLib.FileUtils.test(installed, GLib.FileTest.EXISTS)) {
				Execute.osqueryi = installed;
			}
#endif
		}

		private Application application;

		/**
		 * @param application agent whose server connection is open
		 */
		public Execute(Application application)
		{
			this.application = application;
		}
```

#### Replace

`select` launches `this.osqueryi`.

```vala
			try {
				child = new GLib.Subprocess.newv({
					this.osqueryi, "--json", sql
				}, GLib.SubprocessFlags.STDOUT_PIPE);
```

#### Replace with

An empty path leaves the caller's list unchanged.

```vala
			try {
				Execute.init();
				if (Execute.osqueryi == "") {
					return;
				}
				child = new GLib.Subprocess.newv({
					Execute.osqueryi, "--json", sql
				}, GLib.SubprocessFlags.STDOUT_PIPE);
```

#### Replace

The example passes a path in.

```vala
	 * var query = new Argus.Agent.OSQuery.Query(
	 *     osqueryi, typeof(Argus.Shared.OSQuery.SystemInfo));
```

#### Replace with

```vala
	 * var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
	 * new Argus.Agent.OSQuery.Execute(application).select(
	 *     typeof(Argus.Shared.OSQuery.SystemInfo),
	 *     "SELECT * FROM system_info", rows);
```

#### Replace

`select` takes the row type. `this.row_type` is gone with the old constructor.

```vala
		public void select(string sql, Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> rows)
```

```vala
				var obj = Json.gobject_deserialize(this.row_type, element);
```

#### Replace with

```vala
		public void select(GLib.Type row_type, string sql, Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> rows)
```

```vala
				var obj = Json.gobject_deserialize(row_type, element);
```

#### Add

In `agent/OSQuery/Execute.vala`, inside `class Execute`, after `select`. These two methods are not added to `Initialize`.

```vala
		/**
		 * Post the startup tables, then the one package class.
		 */
		public void send_startup()
		{
			Execute.init();
			if (Execute.osqueryi == "") {
				return;
			}
			var code = 0;
			code += this.sync_table("system_info", "SystemInfo");
			code += this.sync_table("cpu_info", "CpuInfo");
			code += this.sync_table("logged_in_users", "LoggedInUsers");
			code += this.sync_table("interface_addresses", "InterfaceAddresses");
			code += this.sync_table("os_version", "OsVersion");
			code += this.send_packages();
			GLib.debug("osquery %d", code);
		}

		/**
		 * Query one table and post it.
		 *
		 * @param table osquery table name
		 * @param class_name registered row name
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		private int sync_table(string table, string class_name)
		{
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			this.select(row_type, "SELECT * FROM " + table, rows);
			GLib.debug("SELECT * FROM %s %d rows", table, rows.size);
			var connection = this.application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Response response;
			try {
				response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", class_name, rows)
				});
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", table, response.error.message);
				return response.error.code;
			}
			if (table == "os_version" && rows.size > 0) {
				this.application.os_version = (Argus.Shared.OSQuery.OsVersion) rows.get(0);
			}
			GLib.debug("%s sent", table);
			return 0;
		}

		/**
		 * Forward the one package class for this host.
		 *
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		internal int send_packages()
		{
			switch (this.application.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return new Argus.Shared.OSQuery.DebPackages().send(this.application);

				case Argus.Shared.OSQuery.PackageManager.DNF:
					return new Argus.Shared.OSQuery.RpmPackages().send(this.application);

				case Argus.Shared.OSQuery.PackageManager.WIN:
					return new Argus.Shared.OSQuery.Programs().send(this.application);

				default:
					return 0;
			}
		}
```

### `agent/OSQuery/Initialize.vala` — install, then stop

`run` calls `Execute.init` and downloads while `Execute.osqueryi` is empty. When the loop ends, installed or not, `run` returns. This class has no `sync_table`.

#### Remove

From `agent/OSQuery/Initialize.vala`, the posts at the end of `run`, and the whole `sync_table` method.

```vala
			GLib.debug("syncing osquery rows");
			var code = 0;
			code += this.sync_table("system_info", "SystemInfo");
			code += this.sync_table("cpu_info", "CpuInfo");
			code += this.sync_table("logged_in_users", "LoggedInUsers");
			code += this.sync_table("interface_addresses", "InterfaceAddresses");
			code += this.sync_table("os_version", "OsVersion");
			code += this.application.send_packages();
			return code;
		}

		private int sync_table(string table, string class_name)
		{
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			new Query(row_type).select("SELECT * FROM " + table, rows);
			GLib.debug("SELECT * FROM %s %d rows", table, rows.size);
			var connection = this.application.connection;
			if (connection == null) {
				GLib.warning("server connection is not open");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Response response;
			try {
				response = connection.call(new OLLMrpc.Request() {
					method = "OSQuery.sync",
					args = OLLMrpc.args("so", class_name, rows)
				});
			} catch (GLib.Error e) {
				Argus.Agent.Application.connection_down = true;
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				GLib.debug("%s send failed %s", table, response.error.message);
				return response.error.code;
			}
			if (table == "os_version" && rows.size > 0) {
				this.application.os_version = (Argus.Shared.OSQuery.OsVersion) rows.get(0);
			}
			GLib.debug("%s sent", table);
			return 0;
		}
```

#### Replace with

```vala
			return 0;
		}
```

### `agent/android/OSQuery/Execute.vala` — the phone stub

#### Add

New file. Same methods as `Execute`. None of them run `osqueryi`. `agent/meson.build` lists it next to `android/OSQuery/Initialize.vala`. The Linux and Windows builds do not compile this file.

```vala
	public class Execute : GLib.Object
	{
		public static string osqueryi = "";

		public static void init()
		{
		}

		private Application application;

		public Execute(Application application)
		{
			this.application = application;
		}

		public void select(
			GLib.Type row_type,
			string sql,
			Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo> rows)
		{
		}

		public void send_startup()
		{
		}

		internal int send_packages()
		{
			return 0;
		}
	}
```

### `agent/Application.vala` — one `Execute`

#### Add

In `Application`, next to `connection`. The constructor assigns it.

```vala
		internal OSQuery.Execute osquery;
```

```vala
			this.osquery = new OSQuery.Execute(this);
```

#### Replace

```vala
					new OSQuery.Initialize(this).start();
```

#### Replace with

`Initialize` installs. `this.osquery` posts. Android's `Execute` is the stub, so there is no `#if`.

```vala
					new OSQuery.Initialize(this).start();
					this.osquery.send_startup();
```

#### Remove

`send_packages` leaves `Application`. The method now on `Execute` is the one above.

```vala
		internal int send_packages()
		{
			switch (this.os_version.package_manager()) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					return new OSQuery.DebPackages().send(this);

				case Argus.Shared.OSQuery.PackageManager.DNF:
					return new OSQuery.RpmPackages().send(this);

				case Argus.Shared.OSQuery.PackageManager.WIN:
					return new OSQuery.Programs().send(this);

				default:
					return 0;
			}
		}
```

### Meson — `Query.vala` becomes `Execute.vala`

#### Replace

`agent/meson.build`, all three source lists, and `docs/meson.build`.

```vala
		'OSQuery/Query.vala',
```

```vala
				'OSQuery/Query.vala',
```

```vala
  '../agent/OSQuery/Query.vala',
```

#### Replace with

```vala
		'OSQuery/Execute.vala',
```

```vala
				'OSQuery/Execute.vala',
```

```vala
  '../agent/OSQuery/Execute.vala',
```

#### Add

`agent/meson.build`, the Android source list, next to `android/OSQuery/Initialize.vala`.

```vala
		'android/OSQuery/Execute.vala',
```

### Meson — the agent package file

#### Remove

`agent/meson.build`, all three source lists.

```vala
		'OSQuery/Package.vala',
```

```vala
				'OSQuery/Package.vala',
```

#### Remove

`docs/meson.build`.

```vala
  '../agent/OSQuery/Package.vala',
```

## Attempts / changelog

- ✔️ Applied the fences in this file. `agent/OSQuery/Query.vala` is now `agent/OSQuery/Execute.vala`. `Initialize.run` installs and returns. `Application.osquery` is constructed in `Application`. Startup calls `this.osquery.send_startup`. Android has `agent/android/OSQuery/Execute.vala`. `ninja -C build agent/argusrm-agent` stops in Meson: `File OSQuery/Package.vala does not exist`.

## Next

- ✅ Closed. The file split is [2026-11-12-package-file-wrong-place](2026-11-12-FIXED-package-file-wrong-place.md).
