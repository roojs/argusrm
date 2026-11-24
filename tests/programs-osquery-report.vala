/*
 * Manual Windows throwaway. Not registered with meson test().
 *
 * Runs the programs snapshot and PE enrichment the agent send
 * uses, then prints the rows that would be posted. No server
 * connection.
 *
 *   ninja -C build tests/argus-programs-osquery-report
 *   build/tests/argus-programs-osquery-report
 */

void main()
{
	var osqueryi = GLib.Environment.find_program_in_path("osqueryi");
	if (osqueryi == null || osqueryi == "") {
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
	if (osqueryi == null || osqueryi == "") {
		GLib.printerr("osqueryi is not installed\n");
		GLib.Process.exit(1);
	}
	GLib.Subprocess child;
	try {
		child = new GLib.Subprocess.newv({
			osqueryi, "--json", Argus.Shared.OSQuery.Programs.snapshot_sql()
		}, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		GLib.Process.exit(1);
	}
	string? stdout_text = null;
	string? stderr_text = null;
	var queried = false;
	try {
		queried = child.communicate_utf8(null, null, out stdout_text, out stderr_text);
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		GLib.Process.exit(1);
	}
	if (!queried || child.get_exit_status() != 0) {
		var detail = stderr_text != null ? stderr_text.strip() : "";
		detail = detail.replace("\r\n", " ").replace("\n", " ").replace("\r", " ");
		GLib.printerr("osqueryi exited %d: %s\n", child.get_exit_status(), detail);
		GLib.Process.exit(1);
	}
	var parser = new Json.Parser();
	try {
		parser.load_from_data(stdout_text != null ? stdout_text : "");
	} catch (GLib.Error e) {
		GLib.printerr("%s\n", e.message);
		GLib.Process.exit(1);
	}
	var root = parser.get_root();
	if (root == null || root.get_node_type() != Json.NodeType.ARRAY) {
		GLib.printerr("osquery json was not a list\n");
		GLib.Process.exit(1);
	}
	var rows = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
	var list = root.get_array();
	for (var i = 0; i < (int) list.get_length(); i++) {
		var element = list.get_element(i);
		if (element.get_node_type() != Json.NodeType.OBJECT) {
			continue;
		}
		var obj = Json.gobject_deserialize(
			typeof(Argus.Shared.OSQuery.Programs), element);
		if (obj == null) {
			continue;
		}
		rows.add((Argus.Shared.OSQuery.Programs) obj);
	}
	var db_path = GLib.Path.build_filename(
		GLib.Environment.get_tmp_dir(), "argus-programs-osquery-report.sqlite");
	GLib.FileUtils.remove(db_path);
	var db = new SQ.Database(db_path);
	Argus.Agent.SQT.WinFileIdentity.init_db(db);
	var enrichment = new Argus.Agent.Windows.ExeEnrichment();
	enrichment.locate(rows);
	enrichment.enrich(rows, db);
	enrichment.attach(rows);
	var with_sha = 0;
	var with_sign = 0;
	var components = 0;
	var by_source = new Gee.HashMap<string, int>();
	foreach (var row in rows) {
		if (!by_source.has_key(row.source)) {
			by_source.set(row.source, 0);
		}
		by_source.set(row.source, by_source.get(row.source) + 1);
		if (row.file_sha256 != "") {
			with_sha++;
		}
		if (row.signing_result != "") {
			with_sign++;
		}
		if (row.system_component == "1") {
			components++;
		}
	}
	GLib.print("snapshot %d rows enrichment %d paths sha %d signing %d\n",
		rows.size, enrichment.by_path.size, with_sha, with_sign);
	GLib.print("system_component %d\n", components);
	foreach (var source in by_source.keys) {
		GLib.print("source %s %d\n", source, by_source.get(source));
	}
	foreach (var row in rows) {
		if (row.system_component == "1") {
			continue;
		}
		if (row.source != "programs" && row.source != "appx") {
			continue;
		}
		GLib.print("shown\t%s\t%s\n", row.source, row.name);
	}
	foreach (var row in rows) {
		GLib.print("%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			row.source, row.name, row.signing_result, row.file_sha256,
			row.signer_publisher, row.signer_cert_sha256, row.install_location);
	}
}
