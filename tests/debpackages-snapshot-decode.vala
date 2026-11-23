/*
 * Offline: decode ~/.cache/argusrm/debpackages-reply-snapshot.bin (from argus-debpackages-reply-snapshot).
 *
 * Usage:
 *   build-probe/tests/argus-debpackages-snapshot-decode [PATH.bin]
 */

class DebPackagesSnapshotDecode
{
	private static void note(string line)
	{
		GLib.print("%s\n", line);
	}

	public static int main(string[] args)
	{
		var path = args.length >= 2 ? args[1] : GLib.Path.build_filename(
			GLib.Environment.get_user_cache_dir(),
			"argusrm",
			"debpackages-reply-snapshot.bin");
		if (!GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
			GLib.printerr("no file: %s (run argus-debpackages-reply-snapshot first)\n", path);
			return 2;
		}
		var bytes = GLib.File.new_for_path(path).load_bytes(null);
		var data = bytes.get_data();
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		Argus.Shared.OsReleases.rpc_register();
		Argus.Shared.SQT.rpc_register();
		Argus.Shared.SQV.rpc_register();
		try {
			var in_base = new GLib.MemoryInputStream.from_bytes(new GLib.Bytes(data));
			var in_stream = new GLib.DataInputStream(in_base);
			var read_bin = new OLLMrpc.Bin.Stream(in_stream, null);
			var msg = read_bin.parse();
			var response = msg as OLLMrpc.Response;
			if (response == null) {
				GLib.printerr("not a Response\n");
				return 1;
			}
			var list = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			note(@"decode OK: $(list.size) row(s), $(data.length) byte(s) from $(path)");
			if (list.size > 0) {
				var first = list.get(0) as Argus.Shared.OSQuery.DebPackages;
				if (first != null) {
					note(@"  first: $(first.name)");
				}
			}
		} catch (GLib.Error e) {
			GLib.printerr("decode FAIL: %s\n", e.message);
			return 1;
		}
		return 0;
	}
}