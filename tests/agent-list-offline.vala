/*
 * Offline copy of the server Agent.list path — same ocsqlite load + select.
 *
 * Usage:
 *   build-probe/tests/argus-agent-list-offline PATH_TO_COPIED_SQLITE
 *
 * Copy the live file first (on the server host):
 *   sudo cp /var/lib/argusrm/argus.sqlite /tmp/argus.sqlite.copy
 *   sudo chown "$USER:$USER" /tmp/argus.sqlite.copy
 */

class AgentListOffline
{
	private static void note(string line)
	{
		GLib.print("%s\n", line);
	}

	private static void print_row(Argus.Shared.Agent row)
	{
		var fp = row.fingerprint;
		if (fp.length > 12) {
			fp = fp.substring(0, 12) + "…";
		}
		note(@"  id=$(row.id) hostname='$(row.hostname)' username='$(row.username)' " +
			@"controller=$(row.is_controller) status=$(row.status) ip=$(row.ip) fp=$(fp)");
	}

	private static int raw_agent_count(SQ.Database db)
	{
		db.db_mutex.lock();
		Sqlite.Statement stmt;
		if (db.db.prepare_v2(
				"SELECT COUNT(*) FROM agent",
				-1,
				out stmt) != Sqlite.OK) {
			db.db_mutex.unlock();
			return -1;
		}
		var count = -1;
		var rc = stmt.step();
		if (rc != Sqlite.DONE) {
			count = stmt.column_int(0);
		}
		stmt.reset();
		db.db_mutex.unlock();
		return count;
	}

	private static void try_encode_list(Gee.ArrayList<Argus.Shared.Agent> rows)
	{
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		try {
			var packed = OLLMrpc.val("o", rows);
			var list = (Gee.ArrayList<GLib.Object>) packed.get_object();
			note(@"RPC pack whole list OK ($(list.size) objects)");
		} catch (GLib.Error e) {
			GLib.printerr("RPC pack whole list FAIL: %s\n", e.message);
		}
		foreach (var row in rows) {
			try {
				OLLMrpc.val("o", row);
				note(@"  RPC pack id=$(row.id) OK");
			} catch (GLib.Error e) {
				GLib.printerr(@"  RPC pack id=$(row.id) FAIL: $(e.message)\n");
			}
		}
	}

	public static int main(string[] args)
	{
		if (args.length < 2) {
			GLib.printerr(
				"usage: %s PATH_TO_COPIED_SQLITE\n",
				args[0]);
			return 2;
		}
		var path = args[1];
		if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
			GLib.printerr("no such file: %s\n", path);
			return 2;
		}
		note(@"Opening $(path) (ocsqlite in-memory load, same as argusrm-server) …");
		var db = new SQ.Database(path, false);
		Argus.Shared.Agent.init_db(db);
		var raw_count = raw_agent_count(db);
		note(@"sqlite COUNT(agent) = $(raw_count)");
		var rows = new Gee.ArrayList<Argus.Shared.Agent>();
		Argus.Shared.Agent.query(db).select("", rows);
		note(@"Agent.query.select(\"\", rows) => $(rows.size) row(s) (server Agent.list body)");
		foreach (var row in rows) {
			print_row(row);
		}
		if (rows.size != raw_count && raw_count >= 0) {
			GLib.printerr(
				"WARNING: ORM select count %d != sqlite count %d\n",
				rows.size,
				raw_count);
		}
		try_encode_list(rows);
		return rows.size == raw_count ? 0 : 1;
	}
}