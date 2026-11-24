/*
 * Throwaway: trace ExeEnrichment.locate then enrich (no Win32, no sqlite).
 *
 *   ninja -C build tests/argus-programs-exe-pipeline-mock
 *   build/tests/argus-programs-exe-pipeline-mock
 */

class MockRow : GLib.Object
{
	public string source { get; set; default = ""; }
	public string name { get; set; default = ""; }
	public string install_location { get; set; default = ""; }
	public string uninstall_string { get; set; default = ""; }
	public string file_sha256 { get; set; default = ""; }
}

class MockEnrichment : GLib.Object
{
	private Gee.HashMap<MockRow, string> row_path = new Gee.HashMap<MockRow, string>();
	private Gee.HashMap<string, Gee.ArrayList<MockRow>> path_rows =
		new Gee.HashMap<string, Gee.ArrayList<MockRow>>();

	public void locate(Gee.ArrayList<MockRow> rows)
	{
		GLib.print("locate: %u row(s)\n", rows.size);
		foreach (var row in rows) {
			var path = "";
			switch (row.source) {
				case "programs":
					if (row.install_location.has_suffix(".exe")) {
						path = row.install_location;
					}
					break;

				case "service":
				case "startup":
					path = row.install_location;
					break;

				default:
					break;
			}
			GLib.print("  [%s] %s -> %s\n", row.source, row.name, path == "" ? "(no pe)" : path);
			if (path == "") {
				continue;
			}
			this.row_path.set(row, path);
			if (!this.path_rows.has_key(path)) {
				this.path_rows.set(path, new Gee.ArrayList<MockRow>());
			}
			this.path_rows.get(path).add(row);
		}
		GLib.print("locate: %u unique path(s)\n", this.path_rows.size);
	}

	public void enrich(Gee.ArrayList<MockRow> rows)
	{
		GLib.print("enrich: paths\n");
		foreach (var path in this.path_rows.keys) {
			GLib.print("  enrich path=%s (cache gate -> win32 stub)\n", path);
		}
		GLib.print("enrich: attach rows\n");
		foreach (var row in rows) {
			if (!this.row_path.has_key(row)) {
				continue;
			}
			switch (row.source) {
				case "programs":
				case "appx":
				case "chocolatey":
				case "service":
				case "startup":
					row.file_sha256 = "…";
					GLib.print("  attach [%s] %s\n", row.source, row.name);
					break;

				default:
					break;
			}
		}
	}
}

void main()
{
	var rows = new Gee.ArrayList<MockRow>();
	rows.add(new MockRow() {
		source = "programs",
		name = "7-Zip",
		install_location = "C:\\Program Files\\7-Zip\\7z.exe",
	});
	rows.add(new MockRow() {
		source = "service",
		name = "Print Spooler",
		install_location = "C:\\WINDOWS\\System32\\spoolsv.exe",
	});
	rows.add(new MockRow() {
		source = "service",
		name = "Spooler backup",
		install_location = "C:\\WINDOWS\\System32\\spoolsv.exe",
	});
	rows.add(new MockRow() {
		source = "chocolatey",
		name = "git",
		install_location = "C:\\ProgramData\\chocolatey\\lib\\git",
	});

	GLib.print("--- Phase 1 (osquery stub): %u rows ---\n", rows.size);
	var enrich = new MockEnrichment();
	enrich.locate(rows);
	enrich.enrich(rows);
	GLib.print("--- Phase 4: OSQuery.sync (not run) ---\n");
}
