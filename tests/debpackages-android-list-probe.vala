/*
 * Android throwaway: DebPackages.list using enrolled credentials (no Gtk).
 *
 * Usage:
 *   argus-debpackages-android-list-probe HOST PORT SERVER_NAME
 *
 * Install beside the controller APK and run under the app uid (see scripts/android/run-debpackages-list-probe.sh).
 */

class DebPackagesAndroidListProbe
{
	private static void note(string line)
	{
		GLib.print("%s\n", line);
		GLib.debug("%s", line);
	}

	private static async int run(string host, uint16 port, string server_name) throws GLib.Error
	{
		var stored = new Argus.Controller.SQT.Server() { name = server_name };
		stored.load_certificates();
		if (!stored.has_certificate) {
			note(@"No credentials for '$(server_name)' under $(GLib.Environment.get_user_config_dir())/argusrm/credentials/");
			return 1;
		}
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		Argus.Shared.OsReleases.rpc_register();
		Argus.Shared.SQT.rpc_register();
		Argus.Shared.SQV.rpc_register();
		var dir = GLib.Path.build_filename(
			GLib.Environment.get_user_cache_dir(), "argusrm", "list-probe");
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
		rpc.debug = true;
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
		note("Hello ok.");
		var start = GLib.get_monotonic_time();
		var response = yield rpc.call(new OLLMrpc.Request() {
			method = "DebPackages.list",
			args = OLLMrpc.args("ii", 0, 0)
		});
		var ms = (GLib.get_monotonic_time() - start) / 1000;
		if (response.error != null) {
			note(@"DebPackages.list RPC error after $(ms) ms: $(response.error.message)");
			return 1;
		}
		var count = 0;
		var kind = response.retval.type().name();
		if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
			var list = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			count = list.size;
			if (list.size > 0 && list.get(0) != null) {
				kind = list.get(0).get_type().name();
			}
		}
		note(@"DebPackages.list OK $(count) row(s) element=$(kind) in $(ms) ms");
		rpc.disconnect();
		return count > 0 ? 0 : 0;
	}

	public static async int main_task(string[] args) throws GLib.Error
	{
		if (args.length != 4) {
			GLib.printerr("usage: %s HOST PORT SERVER_NAME\n", args[0]);
			return 1;
		}
		int parsed = 0;
		if (!int.try_parse(args[2], out parsed) || parsed < 1 || parsed > 65535) {
			GLib.printerr("invalid port\n");
			return 1;
		}
		uint16 port = (uint16) parsed;
		return yield DebPackagesAndroidListProbe.run(args[1], port, args[3]);
	}

	public static int main(string[] args)
	{
		var loop = new GLib.MainLoop();
		var code = 1;
		DebPackagesAndroidListProbe.main_task.begin(args, (obj, res) => {
			try {
				code = DebPackagesAndroidListProbe.main_task.end(res);
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