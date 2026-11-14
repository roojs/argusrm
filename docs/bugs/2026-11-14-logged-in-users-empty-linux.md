# Logged-in users empty on systemd 256+ Linux hosts

**Status:** ✔️ fix implemented in `agent/OSQuery/Execute.vala` (`ninja` build and 6/6 `meson test` pass); awaiting install + live service verification

**Pointer:** `docs/bug-fix-process.md`, `agent/OSQuery/Execute.vala`, `shared/OSQuery/LoggedInUsers.vala`, [2026-11-13-machines-detail-pane.md](2026-11-13-machines-detail-pane.md), [2026-11-13-log-monitoring.md](2026-11-13-log-monitoring.md)

---

## Problem

- 🔷 After fixing the agent startup connection race, `DebPackages`, `InterfaceAddresses`, and `CpuInfo` appear in `argusrm-controller`, but **Users** (`logged_in_users` in both the Machines grid column and the per-machine `Users` detail tab) is empty on this Linux host (`fastboy`).
- 🔷 Expected: active logged-in sessions on Linux are reported by `agent` and shown in `Logged in users` and the `Users` detail tab.
- 🔷 Actual: `/var/log/argusrm/agent.log` logs `SELECT * FROM logged_in_users 0 rows`, so `LoggedInUsers.list` returns 0 rows.

---

## Evidence

- ✔️ `/var/log/argusrm/agent.log` (`09:45:59.474082`): `Execute.vala:183: SELECT * FROM logged_in_users 0 rows`, followed by `logged_in_users sent`.
- ✔️ `/home/alan/.cache/argusrm/controller.log` (`09:46:10.745704`) & `/var/log/argusrm/server.log` (`09:46:10.746696`): `LoggedInUsers.list` returns an empty list (`type id '0' is invalid`).
- ✔️ On this host (Ubuntu 25.04, `osqueryi` 5.24.0), `/run/utmp` and `/var/run/utmp` do not exist (removed in glibc/systemd 256+ for Y2038), so `osqueryi --json "SELECT * FROM logged_in_users"` returns `[]`.
- ✔️ `who` and `org.freedesktop.login1` (`ListSessions` + `org.freedesktop.DBus.Properties.GetAll` on `org.freedesktop.login1.Session`) on the system bus report the 3 active user sessions (`Class == "user"`, skipping `Class == "manager"`):
  - `alan` on `tty4` (`seat0`, `pid=1697978`, `time=1794269998`, `State=online`)
  - `alan2` on `tty7` (`seat0`, `pid=1705223`, `time=1794270237`, `State=online`)
  - `alan` on `tty3` (`seat0`, `pid=5096`, `time=1792826801`, `State=active`)
- ✔️ Temporary probe `/tmp/argus-logind-probe.vala` verified querying `org.freedesktop.login1` over `GLib.BusType.SYSTEM`, syncing via `LoggedInUsers.sync`, and selecting the 3 rows back from SQLite (`sync=true stored=3`).
  - ℹ️ Note: `OLLMchat/libocsqlite/Query.vala` (`insert` / `updateOld`) does not map DB column `type` to GObject property `ctype` (only `setObjectProperty` on `SELECT` does), so `ctype` stays empty in SQLite; `user`, `tty`, `host`, `time`, and `pid` store and load cleanly.

---

## Root cause

- ✔️ `agent/OSQuery/Execute.vala` (`sync_table()`) relies exclusively on `osqueryi` `SELECT * FROM logged_in_users`, which reads `/run/utmp` on Linux and returns 0 rows on systemd 256+ distributions (Ubuntu 24.04+, 25.04, Debian 13, Fedora 41+) where `utmp` has been removed.

---

## Proposed fix

### `agent/OSQuery/Execute.vala` — fall back to `org.freedesktop.login1` on Linux when `logged_in_users` is empty

- 🔷 Inside `Execute.sync_table()` (`#if LINUX`), when `table == "logged_in_users" && rows.size == 0`, query `org.freedesktop.login1` (`ListSessions` + `org.freedesktop.DBus.Properties.GetAll` for `org.freedesktop.login1.Session`) over `GLib.BusType.SYSTEM` and append one `Argus.Shared.OSQuery.LoggedInUsers` row per session whose `Class` is `"user"`.
- ℹ️ Systems with `/run/utmp` (and Windows / macOS) continue using `osqueryi` directly; systems without `systemd-logind` catch and log the D-Bus error without failing `send_startup()`.

#### Remove

```vala
		private int sync_table(string table, string class_name)
		{
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			this.select(row_type, "SELECT * FROM " + table, rows);
			GLib.debug("SELECT * FROM %s %d rows", table, rows.size);
```

#### Replace with

```vala
		private int sync_table(string table, string class_name)
		{
			var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
			var row_type = OLLMrpc.Bin.alias_to_gtype.get(class_name);
			this.select(row_type, "SELECT * FROM " + table, rows);
#if LINUX
			if (table == "logged_in_users" && rows.size == 0) {
				try {
					var bus = GLib.Bus.get_sync(GLib.BusType.SYSTEM);
					var reply = bus.call_sync(
						"org.freedesktop.login1",
						"/org/freedesktop/login1",
						"org.freedesktop.login1.Manager",
						"ListSessions",
						null,
						new GLib.VariantType("(a(susso))"),
						GLib.DBusCallFlags.NONE,
						-1
					);
					var iter = reply.get_child_value(0).iterator();
					GLib.Variant? entry = null;
					while ((entry = iter.next_value()) != null) {
						string sid, uname, seat, path;
						uint32 uid;
						entry.get("(susso)", out sid, out uid, out uname, out seat, out path);
						var props_reply = bus.call_sync(
							"org.freedesktop.login1",
							path,
							"org.freedesktop.DBus.Properties",
							"GetAll",
							new GLib.Variant("(s)", "org.freedesktop.login1.Session"),
							new GLib.VariantType("(a{sv})"),
							GLib.DBusCallFlags.NONE,
							-1
						);
						var dict = props_reply.get_child_value(0);
						var sclass = "";
						var v_class = dict.lookup_value("Class", GLib.VariantType.STRING);
						if (v_class != null) {
							sclass = v_class.get_string();
						}
						if (sclass != "user") {
							continue;
						}
						var tty = "";
						var v_tty = dict.lookup_value("TTY", GLib.VariantType.STRING);
						if (v_tty != null) {
							tty = v_tty.get_string();
						}
						var display = "";
						var v_display = dict.lookup_value("Display", GLib.VariantType.STRING);
						if (v_display != null) {
							display = v_display.get_string();
						}
						var stype = "";
						var v_type = dict.lookup_value("Type", GLib.VariantType.STRING);
						if (v_type != null) {
							stype = v_type.get_string();
						}
						var state = "";
						var v_state = dict.lookup_value("State", GLib.VariantType.STRING);
						if (v_state != null) {
							state = v_state.get_string();
						}
						var remote_host = "";
						var v_rhost = dict.lookup_value("RemoteHost", GLib.VariantType.STRING);
						if (v_rhost != null) {
							remote_host = v_rhost.get_string();
						}
						var ts = (uint64) 0;
						var v_ts = dict.lookup_value("Timestamp", GLib.VariantType.UINT64);
						if (v_ts != null) {
							ts = v_ts.get_uint64();
						}
						var leader = (uint32) 0;
						var v_leader = dict.lookup_value("Leader", GLib.VariantType.UINT32);
						if (v_leader != null) {
							leader = v_leader.get_uint32();
						}
						rows.add(new Argus.Shared.OSQuery.LoggedInUsers() {
							user = uname,
							tty = tty != "" ? tty : (display != "" ? display : stype),
							host = remote_host != "" ? remote_host : (display != "" ? display : seat),
							time = (int) (ts / 1000000),
							ctype = state != "" ? state : sclass,
							pid = (int) leader
						});
					}
				} catch (GLib.Error e) {
					GLib.warning("logind sessions: %s", e.message);
				}
			}
#endif
			GLib.debug("SELECT * FROM %s %d rows", table, rows.size);
```

---

## Attempts / changelog

- ✔️ Checked `/var/log/argusrm/agent.log`, `/var/log/argusrm/server.log`, `~/.cache/argusrm/controller.log`, `/run/utmp`, `osqueryi`, `who`, and `org.freedesktop.login1`.
- ✔️ Proved `org.freedesktop.login1` -> `LoggedInUsers.sync` -> SQLite round-trip in `/tmp/argus-logind-probe.vala` (`sync=true stored=3`).

- ✔️ Applied replacement in `agent/OSQuery/Execute.vala`; `ninja -C build agent/argusrm-agent agent/argusrm-agent-gtk` succeeded and `meson test -C build` passed (6/6).

## Next

- ⏳ 🔷 Install rebuilt binaries (`sudo ninja -C build install`) and restart `argusrm-agent` to verify live `logged_in_users` sync on this host.
