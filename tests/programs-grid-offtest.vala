/*
 * Off-test: Windows fleet Programs grid using copied controller code under
 * programs-grid-offtest-lib/ (Tab.Base, HoldButton, Filters.Programs, etc.).
 *
 * Usage:
 *   build/tests/argus-programs-grid-offtest SQLITE_PATH [--gui] [--legacy-sql]
 *   build/tests/argus-programs-grid-offtest --rpc HOST PORT SERVER_NAME [--gui]
 *
 * Needs a display for product_grid scenarios (use xvfb-run or --gui on a desktop).
 */

class ProgramsGridOfftest
{
	private const string LEGACY_FLEET_SQL = """
		SELECT
			source,
			name,
			GROUP_CONCAT(DISTINCT NULLIF(publisher, '')) AS publisher,
			GROUP_CONCAT(DISTINCT NULLIF(language, '')) AS language,
			GROUP_CONCAT(DISTINCT NULLIF(identifying_number, '')) AS identifying_number,
			GROUP_CONCAT(DISTINCT NULLIF(install_date, '')) AS install_date,
			GROUP_CONCAT(DISTINCT NULLIF(install_location, '')) AS install_location,
			GROUP_CONCAT(DISTINCT NULLIF(install_source, '')) AS install_source,
			GROUP_CONCAT(DISTINCT NULLIF(uninstall_string, '')) AS uninstall_string,
			GROUP_CONCAT(DISTINCT NULLIF(architecture, '')) AS architecture,
			GROUP_CONCAT(DISTINCT NULLIF(scope, '')) AS scope,
			GROUP_CONCAT(DISTINCT NULLIF(user_account, '')) AS user_account,
			GROUP_CONCAT(DISTINCT NULLIF(extra, '')) AS extra,
			MIN(version) AS min_version,
			MAX(version) AS max_version,
			COUNT(DISTINCT agent_id) AS installed,
			COUNT(DISTINCT CASE
				WHEN uninstall_string != '' THEN agent_id
			END) AS uninstall_count
		FROM
			programs
		WHERE
			agent_id IN (SELECT id FROM agent)
		AND
			deleted_dt = 0
		GROUP BY
			source,
			name
		ORDER BY
			source,
			name
		""";

	private const string SLIM_FLEET_SQL = """
		SELECT
			source,
			name,
			MIN(NULLIF(publisher, '')) AS publisher,
			'' AS language,
			'' AS identifying_number,
			'' AS install_date,
			'' AS install_location,
			'' AS install_source,
			'' AS uninstall_string,
			'' AS architecture,
			MIN(NULLIF(scope, '')) AS scope,
			'' AS user_account,
			'' AS extra,
			MIN(version) AS min_version,
			MAX(version) AS max_version,
			COUNT(DISTINCT agent_id) AS installed,
			COUNT(DISTINCT CASE
				WHEN uninstall_string != '' THEN agent_id
			END) AS uninstall_count
		FROM
			programs
		WHERE
			agent_id IN (SELECT id FROM agent)
		AND
			deleted_dt = 0
		GROUP BY
			source,
			name
		ORDER BY
			source,
			name
		""";

	private static void line(string text)
	{
		GLib.print("%s\n", text);
	}

	private static int64 payload_chars(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		int64 total = 0;
		foreach (var row in rows) {
			total += row.name.length;
			total += row.publisher.length;
			total += row.install_location.length;
			total += row.uninstall_string.length;
			total += row.extra.length;
			total += row.min_version.length;
			total += row.max_version.length;
		}
		return total;
	}

	private static void print_source_mix(string path)
	{
		Sqlite.Database db;
		if (Sqlite.Database.open(path, out db) != Sqlite.OK) {
			return;
		}
		Sqlite.Statement stmt;
		if (db.prepare_v2("""
			SELECT
				source,
				COUNT(*) AS n
			FROM
				programs
			WHERE
				deleted_dt = 0
			AND
				agent_id IN (SELECT id FROM agent)
			GROUP BY
				source
			ORDER BY
				n DESC
			""", -1, out stmt) != Sqlite.OK) {
			return;
		}
		line("per-machine rows by source:");
		while (stmt.step() == Sqlite.ROW) {
			line("  %s: %d".printf(stmt.column_text(0), stmt.column_int(1)));
		}
		stmt.reset();
		if (db.prepare_v2(
			"SELECT COUNT(*) FROM programs WHERE deleted_dt=0 AND agent_id IN (SELECT id FROM agent)",
			-1, out stmt) == Sqlite.OK && stmt.step() == Sqlite.ROW) {
			line("raw_program_rows=%d".printf(stmt.column_int(0)));
		}
		stmt.reset();
	}

	private static Gee.ArrayList<Argus.Shared.OSQuery.Programs> load_sqlite(
		string path,
		bool legacy_sql,
		out int64 query_ms)
	{
		var db = new SQ.Database(path, false);
		Argus.Shared.Agent.init_db(db);
		Argus.Shared.OSQuery.init_db(db);
		var rows = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
		var query = new SQ.Query<Argus.Shared.OSQuery.Programs>(db, "programs");
		var sql = legacy_sql ? LEGACY_FLEET_SQL : SLIM_FLEET_SQL;
		var start = GLib.get_monotonic_time();
		query.selectQuery(sql, rows);
		query_ms = (GLib.get_monotonic_time() - start) / 1000;
		return rows;
	}

	private struct ReproResult
	{
		/** Time inside ''replace_all'' only (matches store RPC callback body). */
		int64 sync_replace_ms;
		/** Time from replace start until 16 ms UI timer fires twice (spinner can animate). */
		int64 until_ui_alive_ms;
		int timer_ticks;
		/** Ms from scroll request until vadjustment actually moves; -1 if no scroll widget. */
		int64 scroll_lag_ms;
	}

	private class TickCounter : GLib.Object
	{
		public int ticks { get; private set; default = 0; }
		private uint source_id = 0;

		public void start()
		{
			this.stop();
			this.ticks = 0;
			this.source_id = GLib.Timeout.add(16, () => {
				this.ticks++;
				return true;
			});
		}

		public void stop()
		{
			if (this.source_id < 1) {
				return;
			}
			GLib.Source.remove(this.source_id);
			this.source_id = 0;
		}
	}

	private static void drain_main_context(bool may_block = false)
	{
		var ctx = GLib.MainContext.default();
		while (ctx.iteration(may_block)) {
		}
	}

	/** Run the default main context until ''deadline_us'' (monotonic). */
	private static void pump_main_until(int64 deadline_us)
	{
		var ctx = GLib.MainContext.default();
		while (GLib.get_monotonic_time() < deadline_us) {
			while (ctx.iteration(false)) {
			}
			Thread.usleep(4000);
		}
	}

	/**
	 * Same path as store RPC callback: busy, replace_all, busy=false — **no**
	 * artificial main-loop pumping after apply (that was masking the freeze).
	 */
	private static ReproResult? run_repro_grid(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows,
		string label,
		bool sort_incremental,
		bool defer_sorter,
		bool freeze_while_busy)
	{
		if (Gdk.Display.get_default() == null) {
			line("repro %s — SKIP (no display)".printf(label));
			return null;
		}
		var store = new ProgramsGridStore();
		var page = new ProgramsGridProbePage(store);
		page.tune_sort(sort_incremental, defer_sorter);
		var win = new Gtk.Window() {
			title = "programs off-test",
			default_width = 920,
			default_height = 620,
			child = page
		};
		win.show();
		win.present();
		pump_main_until(GLib.get_monotonic_time() + 50 * 1000);
		if (freeze_while_busy) {
			store.notify["busy"].connect(() => {
				page.freeze_sort_while_busy(store.busy);
			});
		}
		var counter = new TickCounter();
		counter.start();
		var t0 = GLib.get_monotonic_time();
		store.busy = true;
		var t_replace = GLib.get_monotonic_time();
		store.replace_all(rows);
		var sync_replace_ms = (GLib.get_monotonic_time() - t_replace) / 1000;
		if (defer_sorter) {
			page.attach_sorter();
		}
		store.busy = false;
		var ctx = GLib.MainContext.default();
		const int64 deadline_us = 15 * 1000 * 1000;
		while (counter.ticks < 2 && GLib.get_monotonic_time() - t0 < deadline_us) {
			while (ctx.iteration(false)) {
			}
			Thread.usleep(4000);
		}
		var until_ui_alive_ms = (GLib.get_monotonic_time() - t0) / 1000;
		var adj = page.scrolled_window().get_vadjustment();
		int64 scroll_lag_ms = -1;
		if (adj != null) {
			var before = adj.value;
			var t_scroll = GLib.get_monotonic_time();
			adj.set_value(before + 240);
			while (adj.value == before
				&& GLib.get_monotonic_time() - t_scroll < deadline_us) {
				while (ctx.iteration(false)) {
				}
				Thread.usleep(4000);
			}
			if (adj.value != before) {
				scroll_lag_ms = (GLib.get_monotonic_time() - t_scroll) / 1000;
			}
		}
		counter.stop();
		var result = ReproResult() {
			sync_replace_ms = sync_replace_ms,
			until_ui_alive_ms = until_ui_alive_ms,
			timer_ticks = counter.ticks,
			scroll_lag_ms = scroll_lag_ms
		};
		line(("repro %s sync_ms=%lld ui_alive_ms=%lld scroll_lag_ms=%lld "
			+ "timer_ticks=%d").printf(
			label, result.sync_replace_ms, result.until_ui_alive_ms,
			result.scroll_lag_ms, result.timer_ticks));
		win.destroy();
		return result;
	}

	private static void run_gui(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		var store = new ProgramsGridStore();
		var page = new ProgramsGridProbePage(store);
		var win = new Gtk.Window() {
			title = "Programs off-test (%d rows)".printf(rows.size),
			default_width = 920,
			default_height = 620,
			child = page
		};
		var loop = new GLib.MainLoop();
		win.close_request.connect(() => {
			loop.quit();
			return true;
		});
		win.present();
		store.busy = true;
		store.replace_all(rows);
		store.busy = false;
		line("gui: loaded — scroll the real programs grid");
		loop.run();
	}

	private async Gee.ArrayList<Argus.Shared.OSQuery.Programs>? load_rpc(
		string host,
		uint16 port,
		string server_name,
		out int64 rpc_ms) throws GLib.Error
	{
		var stored = new Argus.Controller.SQT.Server() { name = server_name };
		stored.load_certificates();
		if (!stored.has_certificate) {
			line("No libsecret credentials for " + server_name);
			return null;
		}
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		var dir = GLib.Path.build_filename(
			GLib.Environment.get_user_config_dir(), "argusrm", "list-probe");
		GLib.DirUtils.create_with_parents(dir, 0700);
		var ca_path = GLib.Path.build_filename(dir, "argusrm-ca.pem");
		GLib.FileUtils.set_contents(ca_path, stored.pem_ca_certificate);
		var trust = GLib.TlsFileDatabase.@new(ca_path);
		var cert = stored.tls_certificate();
		var rpc = new OLLMrpc.Client("", "", @"tcp://$(host):$(port)") {
			live_handles = true,
			call_timeout_seconds = 600,
			force_localhost_tls = true
		};
		rpc.configure_tls.connect((tls) => {
			tls.certificate = cert;
			tls.database = trust;
		});
		var opened = yield rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("iss", 1, "argus-controller", Argus.VERSION)
		});
		if (!opened) {
			line("Hello failed: " + rpc.connect_error);
			return null;
		}
		var start = GLib.get_monotonic_time();
		var response = yield rpc.call(new OLLMrpc.Request() {
			method = "Programs.list",
			args = OLLMrpc.args("ii", 0, 0)
		});
		rpc_ms = (GLib.get_monotonic_time() - start) / 1000;
		if (response.error != null) {
			line("Programs.list error: " + response.error.message);
			return null;
		}
		var rows = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
		if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
			rows = (Gee.ArrayList<Argus.Shared.OSQuery.Programs>) response.retval.get_object();
		}
		rpc.disconnect();
		return rows;
	}

	private static int64 bin_wire_roundtrip_ms(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		OLLMrpc.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		var snapshot = new OLLMrpc.Response() {
			retval = OLLMrpc.val("o", rows)
		};
		var start = GLib.get_monotonic_time();
		var mem = new GLib.MemoryOutputStream.resizable();
		var out_stream = new GLib.DataOutputStream(mem);
		var write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
		write_bin.write(snapshot);
		out_stream.close();
		var wire = mem.steal_as_bytes().get_data();
		var in_base = new GLib.MemoryInputStream.from_bytes(new GLib.Bytes(wire));
		var in_stream = new GLib.DataInputStream(in_base);
		var read_bin = new OLLMrpc.Bin.Stream(in_stream, null);
		var msg = read_bin.parse();
		var response = msg as OLLMrpc.Response;
		if (response == null) {
			return -1;
		}
		var list = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
		return (GLib.get_monotonic_time() - start) / 1000;
	}

	/** First fleet load: grid starts empty (overlay spinner would show in product). */
	private static ReproResult? run_repro_first_load(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows,
		string label,
		bool sort_incremental)
	{
		if (Gdk.Display.get_default() == null) {
			return null;
		}
		var store = new ProgramsGridStore();
		var page = new ProgramsGridProbePage(store);
		page.tune_sort(sort_incremental, false);
		var win = new Gtk.Window() {
			title = "programs off-test (first load)",
			default_width = 920,
			default_height = 620,
			child = page
		};
		win.show();
		win.present();
		pump_main_until(GLib.get_monotonic_time() + 50 * 1000);
		var counter = new TickCounter();
		counter.start();
		var t0 = GLib.get_monotonic_time();
		store.busy = true;
		var t_replace = GLib.get_monotonic_time();
		store.replace_all(rows);
		var sync_replace_ms = (GLib.get_monotonic_time() - t_replace) / 1000;
		store.busy = false;
		var ctx = GLib.MainContext.default();
		const int64 deadline_us = 15 * 1000 * 1000;
		while (counter.ticks < 2 && GLib.get_monotonic_time() - t0 < deadline_us) {
			while (ctx.iteration(false)) {
			}
			Thread.usleep(4000);
		}
		var until_ui_alive_ms = (GLib.get_monotonic_time() - t0) / 1000;
		counter.stop();
		line(("first_load %s sync_ms=%lld ui_alive_ms=%lld timer_ticks=%d").printf(
			label, sync_replace_ms, until_ui_alive_ms, counter.ticks));
		win.destroy();
		return null;
	}

	private static void run_repro_suite(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows,
		string heading)
	{
		line("");
		line("=== " + heading + " ===");
		line("rows=%d payload_chars=%lld".printf(rows.size, payload_chars(rows)));
		line("bin_encode_decode_ms=%lld".printf(bin_wire_roundtrip_ms(rows)));
		run_repro_first_load(rows, "prod", false);
		run_repro_first_load(rows, "fixA_incr_sort", true);
		run_repro_grid(rows, "prod", false, false, false);
		run_repro_grid(rows, "fixA_incr_sort", true, false, false);
		run_repro_grid(rows, "fixB_defer_sorter", true, true, false);
		run_repro_grid(rows, "fixC_freeze_sort", true, true, true);
		line("TARGET: user reports ~3000-4000 ms frozen — this run does NOT pass until prod ~that.");
		line("ui_alive_ms: until 16ms timer ticks twice (high ~ frozen spinner).");
		line("scroll_lag_ms: until scrollbar moves after one scroll nudge.");
	}

	private static int run_batch_sqlite(string sqlite_path)
	{
		int64 slim_query_ms = 0;
		int64 legacy_query_ms = 0;
		var slim = load_sqlite(sqlite_path, false, out slim_query_ms);
		var legacy = load_sqlite(sqlite_path, true, out legacy_query_ms);
		line("slim fleet rows=%d query_ms=%lld payload_chars=%lld".printf(
			slim.size, slim_query_ms, payload_chars(slim)));
		line("legacy fleet rows=%d query_ms=%lld payload_chars=%lld".printf(
			legacy.size, legacy_query_ms, payload_chars(legacy)));
		run_repro_suite(legacy,
			"grid repro — legacy fleet sql (fat fields like Programs.list)");
		return 0;
	}

	private static int run_batch_rpc(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		run_repro_suite(rows, "grid repro — live Programs.list rows");
		return 0;
	}

	public static int main(string[] args)
	{
		Adw.init();
		var gui = false;
		var rpc = false;
		string? sqlite_path = null;
		string rpc_host = "";
		string rpc_name = "";
		uint16 rpc_port = 817;

		for (int i = 1; i < args.length; i++) {
			if (args[i] == "--gui") {
				gui = true;
			} else if (args[i] == "--legacy-sql") {
				line("--legacy-sql ignored: grid repro always uses legacy fleet sql");
			} else if (args[i] == "--rpc") {
				rpc = true;
				if (i + 3 >= args.length) {
					GLib.printerr("--rpc needs HOST PORT SERVER_NAME\n");
					return 2;
				}
				rpc_host = args[i + 1];
				int parsed = 0;
				if (!int.try_parse(args[i + 2], out parsed)) {
					GLib.printerr("invalid port\n");
					return 2;
				}
				rpc_port = (uint16) parsed;
				rpc_name = args[i + 3];
				i += 3;
			} else if (args[i].has_prefix("-")) {
				GLib.printerr("unknown option %s\n", args[i]);
				return 2;
			} else if (sqlite_path == null) {
				sqlite_path = args[i];
			}
		}

		if (!rpc && sqlite_path == null) {
			GLib.printerr(
				"usage: %s SQLITE_PATH [--legacy-sql] [--gui]\n"
				+ "       %s --rpc HOST PORT SERVER_NAME [--gui]\n",
				args[0], args[0]);
			return 2;
		}

		if (rpc) {
			var loop = new GLib.MainLoop();
			Gee.ArrayList<Argus.Shared.OSQuery.Programs>? rows = null;
			int64 rpc_ms = 0;
			var probe = new ProgramsGridOfftest();
			probe.load_rpc.begin(rpc_host, rpc_port, rpc_name, (obj, res) => {
				try {
					rows = probe.load_rpc.end(res, out rpc_ms);
				} catch (GLib.Error e) {
					line("RPC failed: " + e.message);
				}
				loop.quit();
			});
			loop.run();
			if (rows == null) {
				return 1;
			}
			line("Programs.list RPC ms=%lld rows=%d".printf(rpc_ms, rows.size));
			if (gui) {
				run_gui(rows);
				return 0;
			}
			if (gui) {
				run_gui(rows);
				return 0;
			}
			return run_batch_rpc(rows);
		}

		print_source_mix(sqlite_path);
		if (gui) {
			int64 query_ms = 0;
			var rows = load_sqlite(sqlite_path, true, out query_ms);
			if (rows.size < 1) {
				line("No fleet rows — check path and programs table.");
				return 1;
			}
			run_gui(rows);
			return 0;
		}
		return run_batch_sqlite(sqlite_path);
	}
}