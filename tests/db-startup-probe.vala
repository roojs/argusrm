/*
 * Throwaway: mirror argusrm-server SQ.Database open + Agent.init_db.
 * Compare on-disk agent count vs in-memory after load (before/after init_db).
 *
 * Usage:
 *   build-probe/tests/argus-db-startup-probe PATH_TO_SQLITE
 *
 *   G_MESSAGES_DEBUG=all build-probe/tests/argus-db-startup-probe /tmp/argus.sqlite.copy
 */

class DbStartupProbe
{
	private static void note(string line)
	{
		GLib.print("%s\n", line);
		GLib.debug("%s", line);
	}

	private static int count_agents_on_disk(string path)
	{
		Sqlite.Database disk;
		if (Sqlite.Database.open(path, out disk) != Sqlite.OK) {
			GLib.debug("disk open failed: %s", disk.errmsg());
			return -1;
		}
		Sqlite.Statement stmt;
		if (disk.prepare_v2("SELECT COUNT(*) FROM agent", -1, out stmt) != Sqlite.OK) {
			return -1;
		}
		var count = -1;
		if (stmt.step() != Sqlite.DONE) {
			count = stmt.column_int(0);
		}
		stmt.reset();
		return count;
	}

	private static int count_agents_memory(SQ.Database db)
	{
		db.db_mutex.lock();
		Sqlite.Statement stmt;
		if (db.db.prepare_v2("SELECT COUNT(*) FROM agent", -1, out stmt) != Sqlite.OK) {
			db.db_mutex.unlock();
			return -1;
		}
		var count = -1;
		if (stmt.step() != Sqlite.DONE) {
			count = stmt.column_int(0);
		}
		stmt.reset();
		db.db_mutex.unlock();
		return count;
	}

	private static void file_stat(string path)
	{
		if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
			note(@"file: $(path) — missing");
			return;
		}
		try {
			var info = GLib.File.new_for_path(path).query_info(
				GLib.FileAttribute.STANDARD_SIZE,
				GLib.FileQueryInfoFlags.NONE);
			note(@"file: $(path) — exists, size=$(info.get_size()) bytes");
		} catch (GLib.Error e) {
			note(@"file: $(path) — exists, stat failed: $(e.message)");
		}
	}

	public static int main(string[] args)
	{
		GLib.Log.set_handler(null, GLib.LogLevelFlags.LEVEL_MASK, (d, l, m) => {
			if ((l & GLib.LogLevelFlags.LEVEL_DEBUG) != 0) {
				GLib.stderr.printf("debug: %s\n", m);
			}
		});
		if (args.length < 2) {
			GLib.printerr("usage: %s PATH_TO_SQLITE\n", args[0]);
			return 2;
		}
		var path = args[1];
		file_stat(path);
		var disk_before = count_agents_on_disk(path);
		note(@"on-disk COUNT(agent) (direct sqlite) = $(disk_before)");
		note(@"new SQ.Database($(path), autosave=true) — same as server Application");
		var db = new SQ.Database(path, true);
		note(@"ocsqlite.filename field = '$(db.filename)'");
		var memory_before_init = count_agents_memory(db);
		note(@"in-memory COUNT(agent) after load, before init_db = $(memory_before_init)");
		Argus.Shared.Agent.init_db(db);
		var memory_after_init = count_agents_memory(db);
		note(@"in-memory COUNT(agent) after Agent.init_db = $(memory_after_init)");
		var rows = new Gee.ArrayList<Argus.Shared.Agent>();
		Argus.Shared.Agent.query(db).select("", rows);
		note(@"Agent.query.select => $(rows.size) row(s)");
		if (disk_before >= 0 && memory_before_init == 0 && disk_before > 0) {
			GLib.printerr(
				"FAIL: file has %d agents but memory after load has 0 (load_from_file path)\n",
				disk_before);
			return 1;
		}
		if (disk_before >= 0 && memory_after_init != disk_before) {
			GLib.printerr(
				"FAIL: disk=%d memory after init=%d\n",
				disk_before,
				memory_after_init);
			return 1;
		}
		note("OK: disk and in-memory counts match");
		return 0;
	}
}