/*
 * Throwaway: compile WinFileIdentity + ExeEnrichment.
 *
 * Windows throwaway only (links win32/pe-authenticode.c).
 *
 *   ninja -C build tests/argus-programs-pe-pipeline-agent
 *   build/tests/argus-programs-pe-pipeline-agent
 */

void main()
{
	var db_path = GLib.Path.build_filename(
		GLib.Environment.get_tmp_dir(), "argus-pe-cache-test.sqlite");
	GLib.FileUtils.remove(db_path);
	var db = new SQ.Database(db_path);
	Argus.Agent.SQT.WinFileIdentity.init_db(db);

	var rows = new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();
	rows.add(new Argus.Shared.OSQuery.Programs() {
		source = "service",
		name = "Print Spooler",
		install_location = "C:\\WINDOWS\\System32\\spoolsv.exe",
	});
	rows.add(new Argus.Shared.OSQuery.Programs() {
		source = "service",
		name = "Spooler alias",
		install_location = "C:\\WINDOWS\\System32\\spoolsv.exe",
	});

	var enrich = new Argus.Agent.Windows.ExeEnrichment();
	enrich.locate(rows);
	enrich.enrich(rows, db);
	foreach (var path in enrich.by_path.keys) {
		if (!enrich.by_path.has_key(path)) {
			continue;
		}
		var row = enrich.by_path[path];
		GLib.print("%s signing=%s sha256=%s\n", path, row.signing_result, row.file_sha256);
	}
}