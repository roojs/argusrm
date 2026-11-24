/*
 * Off-test: Windows fleet Programs grid using copied controller code under
 * programs-grid-offtest-lib/ (Tab.Base, HoldButton, Filters.Programs, etc.).
 *
 * Usage:
 *   build/tests/argus-programs-grid-offtest SQLITE_PATH [--gui] [--legacy-sql]
 *   build/tests/argus-programs-grid-offtest --rpc HOST PORT SERVER_NAME [--gui]
 *
 * In-test Unix RPC server runs real ``Programs.list`` on SQLITE_PATH (no live server).
 * Exits **1** with ``REPRO_FAIL`` until prod ``frozen_ms`` >= 3000 (user ~3–4 s).
 * Needs a display (xvfb-run or desktop). Optional ``--rpc HOST PORT SERVER`` for live compare.
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

	/** Every stored row (no fleet GROUP BY) — wrong for list RPC, stress path. */
	private static Gee.ArrayList<Argus.Shared.OSQuery.Programs> load_per_machine(
		string path,
		out int64 query_ms)
	{
		var db = new SQ.Database(path, false);
		Argus.Shared.Agent.init_db(db);
		Argus.Shared.OSQuery.init_db(db);
		var rows = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
		var query = new SQ.Query<Argus.Shared.OSQuery.Programs>(db, "programs");
		var start = GLib.get_monotonic_time();
		query.select("""
			WHERE
				agent_id IN (SELECT id FROM agent)
			AND
				deleted_dt = 0
			ORDER BY
				source,
				name,
				agent_id
			""", rows);
		query_ms = (GLib.get_monotonic_time() - start) / 1000;
		return rows;
	}

	private static Gee.ArrayList<Argus.Shared.OSQuery.Programs> decode_rows_on_main(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		OLLMrpc.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		var snapshot = new OLLMrpc.Response() {
			retval = OLLMrpc.val("o", rows)
		};
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
			return rows;
		}
		return (Gee.ArrayList<Argus.Shared.OSQuery.Programs>) response.retval.get_object();
	}

	private struct ReproResult
	{
		int64 rpc_callback_ms;
		int64 sync_replace_ms;
		int64 until_ui_alive_ms;
		int64 scroll_storm_ms;
		int timer_ticks;
	}

	/** User symptom: ~3–4 s until the grid scrolls normally. */
	private const int64 REPRO_TARGET_MS = 3000;
	private static int64 prod_worst_frozen_ms = 0;

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
	 * Idle callback: bin decode + store apply, like ``Programs`` RPC completion
	 * on the UI thread. Measures scroll storm right after (user scroll jam).
	 */
	private static ReproResult? run_repro_grid(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows,
		string label,
		bool sort_incremental,
		bool defer_sorter,
		bool freeze_while_busy,
		bool bin_decode_in_callback)
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
		var ctx = GLib.MainContext.default();
		var t0 = GLib.get_monotonic_time();
		int64 rpc_callback_ms = 0;
		int64 sync_replace_ms = 0;
		var callback_done = false;
		GLib.Idle.add(() => {
			var t_cb = GLib.get_monotonic_time();
			store.busy = true;
			var listed = rows;
			if (bin_decode_in_callback) {
				listed = decode_rows_on_main(rows);
			}
			var t_rep = GLib.get_monotonic_time();
			store.replace_all(listed);
			sync_replace_ms = (GLib.get_monotonic_time() - t_rep) / 1000;
			if (defer_sorter) {
				page.attach_sorter();
			}
			store.busy = false;
			rpc_callback_ms = (GLib.get_monotonic_time() - t_cb) / 1000;
			callback_done = true;
			return false;
		});
		while (!callback_done) {
			ctx.iteration(true);
		}
		const int64 deadline_us = 20 * 1000 * 1000;
		while (counter.ticks < 2 && GLib.get_monotonic_time() - t0 < deadline_us) {
			while (ctx.iteration(false)) {
			}
			Thread.usleep(4000);
		}
		var until_ui_alive_ms = (GLib.get_monotonic_time() - t0) / 1000;
		var adj = page.scrolled_window().get_vadjustment();
		int64 scroll_storm_ms = 0;
		if (adj != null) {
			var t_storm = GLib.get_monotonic_time();
			for (int step = 0; step < 40; step++) {
				var target = adj.value + 96;
				adj.set_value(target);
				var t_one = GLib.get_monotonic_time();
				while (adj.value < target - 0.5
					&& GLib.get_monotonic_time() - t_one < deadline_us) {
					while (ctx.iteration(false)) {
					}
					Thread.usleep(1000);
				}
			}
			scroll_storm_ms = (GLib.get_monotonic_time() - t_storm) / 1000;
		}
		int64 frozen_ms = until_ui_alive_ms;
		if (rpc_callback_ms > frozen_ms) {
			frozen_ms = rpc_callback_ms;
		}
		if (scroll_storm_ms > frozen_ms) {
			frozen_ms = scroll_storm_ms;
		}
		if (label == "prod" && frozen_ms > prod_worst_frozen_ms) {
			prod_worst_frozen_ms = frozen_ms;
		}
		counter.stop();
		var result = ReproResult() {
			rpc_callback_ms = rpc_callback_ms,
			sync_replace_ms = sync_replace_ms,
			until_ui_alive_ms = until_ui_alive_ms,
			scroll_storm_ms = scroll_storm_ms,
			timer_ticks = counter.ticks
		};
		line(("repro %s callback_ms=%lld sync_ms=%lld ui_alive_ms=%lld "
			+ "scroll_storm_ms=%lld frozen_ms=%lld ticks=%d").printf(
			label, result.rpc_callback_ms, result.sync_replace_ms,
			result.until_ui_alive_ms, result.scroll_storm_ms, frozen_ms,
			result.timer_ticks));
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

	private static void run_repro_suite(
		Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows,
		string heading,
		bool sim_bin_decode_in_callback)
	{
		line("");
		line("=== " + heading + " ===");
		line("rows=%d payload_chars=%lld".printf(rows.size, payload_chars(rows)));
		line("bin_encode_decode_ms=%lld".printf(bin_wire_roundtrip_ms(rows)));
		run_repro_grid(rows, "prod", false, false, false, sim_bin_decode_in_callback);
		run_repro_grid(rows, "fixA_incr_sort", true, false, false, sim_bin_decode_in_callback);
		run_repro_grid(rows, "fixB_defer_sorter", true, true, false, sim_bin_decode_in_callback);
		run_repro_grid(rows, "fixC_freeze_sort", true, true, true, sim_bin_decode_in_callback);
	}

	private static int finish_repro_batch()
	{
		line("");
		line("REPRO prod_worst_frozen_ms=%lld (target >= %lld)".printf(
			prod_worst_frozen_ms, REPRO_TARGET_MS));
		if (prod_worst_frozen_ms < REPRO_TARGET_MS) {
			line("REPRO_FAIL: test does not reach user ~3-4s yet.");
			return 1;
		}
		line("REPRO_OK");
		return 0;
	}

	private static int run_batch_sqlite(string sqlite_path)
	{
		var server = new ProgramsGridOfftestRpcServer();
		try {
			server.start(sqlite_path);
		} catch (GLib.Error e) {
			line("test RPC server: " + e.message);
			return 1;
		}
		line("test_rpc socket %s".printf(server.socket_path));
		var loop = new GLib.MainLoop();
		var exit_code = 1;
		GLib.Idle.add(() => {
			ProgramsGridOfftestRpcServer.fetch_list.begin(
				server.socket_path, (obj, res) => {
			Gee.ArrayList<Argus.Shared.OSQuery.Programs>? rows = null;
			int64 rpc_ms = 0;
			try {
				rows = ProgramsGridOfftestRpcServer.fetch_list.end(res, out rpc_ms);
			} catch (GLib.Error e) {
				line("Programs.list over test RPC: " + e.message);
				exit_code = 1;
				server.stop();
				loop.quit();
				return;
			}
			line("Programs.list test_rpc ms=%lld rows=%d".printf(
				rpc_ms, rows.size));
			prod_worst_frozen_ms = 0;
			run_repro_suite(rows,
				"Programs.list via in-test RPC (server SQL + bin wire)",
				false);
			exit_code = finish_repro_batch();
			server.stop();
			loop.quit();
			});
			return false;
		});
		loop.run();
		return exit_code;
	}

	private static int run_batch_rpc(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		prod_worst_frozen_ms = 0;
		run_repro_suite(rows, "live Programs.list rows", false);
		return finish_repro_batch();
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