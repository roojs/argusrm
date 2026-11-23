/*
 * Throwaway: fetch DebPackages.list, write bin-encoded retval to a file, round-trip decode.
 *
 * Usage:
 *   build-probe/tests/argus-debpackages-reply-snapshot HOST PORT SERVER_NAME [OUT.bin]
 */

class DebPackagesReplySnapshot
{
	private static void note(string line)
	{
		GLib.print("%s\n", line);
	}

	private static void hex_prefix(uint8[] data, int max)
	{
		var n = int.min(data.length, max);
		var parts = new string[n];
		for (var i = 0; i < n; i++) {
			parts[i] = "%02X".printf(data[i]);
		}
		note(@"  hex[0..$(n - 1)]: $(string.joinv(" ", parts))");
	}

	private static void round_trip(uint8[] wire) throws GLib.Error
	{
		var in_base = new GLib.MemoryInputStream.from_bytes(new GLib.Bytes(wire));
		var in_stream = new GLib.DataInputStream(in_base);
		var read_bin = new OLLMrpc.Bin.Stream(in_stream, null);
		var msg = read_bin.parse();
		var response = msg as OLLMrpc.Response;
		if (response == null) {
			throw new GLib.IOError.FAILED("parsed message is not Response");
		}
		if (!response.retval.type().is_a(typeof(Gee.ArrayList))) {
			throw new GLib.IOError.FAILED(@"retval is $(response.retval.type().name()), not ArrayList");
		}
		var list = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
		note(@"  round-trip decode: $(list.size) row(s)");
	}

	private static async int run(string host, uint16 port, string server_name, string out_path) throws GLib.Error
	{
		var stored = new Argus.Controller.SQT.Server() { name = server_name };
		stored.load_certificates();
		if (!stored.has_certificate) {
			note(@"No credentials for server '$(server_name)' (libsecret).");
			return 1;
		}
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		Argus.Shared.OsReleases.rpc_register();
		Argus.Shared.SQT.rpc_register();
		Argus.Shared.SQV.rpc_register();
		var dir = GLib.Path.build_filename(
			GLib.Environment.get_user_cache_dir(), "argusrm", "debpackages-reply-snapshot");
		GLib.DirUtils.create_with_parents(dir, 0700);
		var ca_path = GLib.Path.build_filename(dir, "argusrm-ca.pem");
		GLib.FileUtils.set_contents(ca_path, stored.pem_ca_certificate);
		var trust = GLib.TlsFileDatabase.@new(ca_path);
		var cert = stored.tls_certificate();
		var rpc = new OLLMrpc.Client("", "", @"tcp://$(host):$(port)") {
			live_handles = true,
			call_timeout_seconds = 300,
			force_localhost_tls = true
		};
		rpc.debug = false;
		rpc.configure_tls.connect((tls) => {
			tls.certificate = cert;
			tls.database = trust;
		});
		note(@"Connecting to $(host):$(port) as $(server_name) …");
		var opened = yield rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("iss", 1, "argus-controller", Argus.VERSION)
		});
		if (!opened) {
			note(@"Hello failed: $(rpc.connect_error)");
			return 1;
		}
		var start = GLib.get_monotonic_time();
		var response = yield rpc.call(new OLLMrpc.Request() {
			method = "DebPackages.list",
			args = OLLMrpc.args("ii", 0, 0)
		});
		if (response.error != null) {
			note(@"DebPackages.list error: $(response.error.message)");
			return 1;
		}
		var list = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
		var ms = (GLib.get_monotonic_time() - start) / 1000;
		note(@"DebPackages.list OK $(list.size) row(s) in $(ms) ms");
		var snapshot = new OLLMrpc.Response() {
			retval = OLLMrpc.val("o", list)
		};
		var mem = new GLib.MemoryOutputStream.resizable();
		var out_stream = new GLib.DataOutputStream(mem);
		var write_bin = new OLLMrpc.Bin.Stream(null, out_stream);
		write_bin.write(snapshot);
		out_stream.close();
		var wire = mem.steal_as_bytes().get_data();
		GLib.DirUtils.create_with_parents(GLib.Path.get_dirname(out_path), 0700);
		var fd = Posix.open(
			out_path,
			Posix.O_WRONLY | Posix.O_CREAT | Posix.O_TRUNC,
			0600);
		if (fd < 0) {
			throw new GLib.IOError.FAILED(@"Could not open $(out_path)");
		}
		Posix.write(fd, wire, wire.length);
		Posix.close(fd);
		note(@"Wrote $(wire.length) byte(s) to $(out_path)");
		hex_prefix(wire, 128);
		round_trip(wire);
		rpc.disconnect();
		return 0;
	}

	public static async int main_task(string[] args) throws GLib.Error
	{
		if (args.length < 4 || args.length > 5) {
			GLib.printerr(
				"usage: %s HOST PORT SERVER_NAME [OUT.bin]\n", args[0]);
			return 1;
		}
		int parsed = 0;
		if (!int.try_parse(args[2], out parsed) || parsed < 1 || parsed > 65535) {
			GLib.printerr("invalid port\n");
			return 1;
		}
		uint16 port = (uint16) parsed;
		var out_path = args.length == 5 ? args[4] : GLib.Path.build_filename(
			GLib.Environment.get_user_cache_dir(),
			"argusrm",
			"debpackages-reply-snapshot.bin");
		return yield DebPackagesReplySnapshot.run(args[1], port, args[3], out_path);
	}

	public static int main(string[] args)
	{
		var loop = new GLib.MainLoop();
		var code = 1;
		DebPackagesReplySnapshot.main_task.begin(args, (obj, res) => {
			try {
				code = DebPackagesReplySnapshot.main_task.end(res);
			} catch (GLib.Error e) {
				GLib.print(@"Fatal: $(e.message)\n");
				code = 1;
			}
			loop.quit();
		});
		loop.run();
		return code;
	}
}