/*
 * Throwaway RPC probe for large software lists (DebPackages / RpmPackages).
 * Not wired into the controller; run manually against a live server.
 *
 * Usage (Linux — PEMs from libsecret, same as the controller):
 *   build/tests/argus-list-probe HOST PORT SERVER_NAME
 *
 * Example:
 *   build/tests/argus-list-probe 192.168.0.16 817 fastboy
 *
 * After hello, runs controller-startup lists (ScriptRepository, Distributable,
 * Agent) plus the Debian probe lists — watch /var/log/argusrm/server.log for
 * server-side GObject errors while this runs.
 */

class ListProbeHost
{
	private OLLMrpc.Client rpc;

	private static void note(string line)
	{
		GLib.print("%s\n", line);
		GLib.debug("%s", line);
	}

	private void report(string method, int64 start_us, OLLMrpc.Response response)
	{
		var ms = (GLib.get_monotonic_time() - start_us) / 1000;
		if (response.error != null) {
			note(@"  RPC error after $(ms) ms: $(response.error.message)");
			return;
		}
		var count = -1;
		var kind = response.retval.type().name();
		if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
			var list = (Gee.ArrayList<GLib.Object>) response.retval.get_object();
			count = list.size;
			const int row_preview_max = 3;
			var printed = 0;
			foreach (var entry in list) {
				if (printed >= row_preview_max) {
					break;
				}
				var agent = entry as Argus.Shared.Agent;
				var deb = entry as Argus.Shared.OSQuery.DebPackages;
				if (agent != null) {
					note(@"  row id=$(agent.id) kind=$(agent.display_kind) name=$(agent.display_name) status=$(agent.status)");
					printed++;
				} else if (deb != null) {
					note(@"  row name=$(deb.name) installed=$(deb.installed)");
					printed++;
				} else if (entry != null) {
					note(@"  row $(entry.get_type().name())");
					printed++;
				}
			}
			if (list.size > row_preview_max) {
				note(@"  … $(list.size - row_preview_max) more row(s) omitted");
			}
			if (list.size > 0 && list.get(0) != null) {
				kind = list.get(0).get_type().name();
			}
		} else if (response.retval.type() == GLib.Type.INVALID) {
			kind = "INVALID (empty list?)";
			count = 0;
		}
		if (count < 0) {
			note(@"  OK retval=$(kind) in $(ms) ms");
			return;
		}
		note(@"  OK $(count) row(s) element=$(kind) in $(ms) ms");
	}

	private async void probe_plain(string method) throws GLib.Error
	{
		note(method + " ...");
		var start = GLib.get_monotonic_time();
		var response = yield this.rpc.call(new OLLMrpc.Request() {
			method = method
		});
		this.report(method, start, response);
	}

	private async void probe_agent_list() throws GLib.Error
	{
		note("Agent.list ...");
		var start = GLib.get_monotonic_time();
		var response = yield this.rpc.call(new OLLMrpc.Request() {
			method = "Agent.list",
			args = OLLMrpc.args("i", 0)
		});
		this.report("Agent.list", start, response);
	}

	private async void probe_since_list(string method) throws GLib.Error
	{
		note(method + " ...");
		var start = GLib.get_monotonic_time();
		var response = yield this.rpc.call(new OLLMrpc.Request() {
			method = method,
			args = OLLMrpc.args("ii", 0, 0)
		});
		this.report(method, start, response);
	}

	private async int run(string host, uint16 port, string server_name) throws GLib.Error
	{
		var stored = new Argus.Controller.SQT.Server() { name = server_name };
		stored.load_certificates();
		if (!stored.has_certificate) {
			note(@"No credentials for server '$(server_name)' (libsecret service=argusrm).");
			return 1;
		}
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		Argus.Shared.OsReleases.rpc_register();
		Argus.Shared.SQT.rpc_register();
		Argus.Shared.SQV.rpc_register();
		var dir = GLib.Path.build_filename(
			GLib.Environment.get_user_config_dir(), "argusrm", "list-probe");
		GLib.DirUtils.create_with_parents(dir, 0700);
		var ca_path = GLib.Path.build_filename(dir, "argusrm-ca.pem");
		GLib.FileUtils.set_contents(ca_path, stored.pem_ca_certificate);
		var trust = GLib.TlsFileDatabase.@new(ca_path);
		var cert = stored.tls_certificate();
		this.rpc = new OLLMrpc.Client("", "", @"tcp://$(host):$(port)") {
			live_handles = true,
			call_timeout_seconds = 300,
			force_localhost_tls = true
		};
		this.rpc.debug = true;
		this.rpc.configure_tls.connect((tls) => {
			tls.certificate = cert;
			tls.database = trust;
		});
		note(@"Connecting to $(host):$(port) as $(server_name) ...");
		var opened = yield this.rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("iss", 1, "argus-controller", Argus.VERSION)
		});
		if (!opened) {
			note(@"Hello failed: $(this.rpc.connect_error)");
			note(@"Client cert SHA256: $(stored.fingerprint())");
			return 1;
		}
		note("Hello ok.");
		yield this.probe_plain("ScriptRepository.list");
		yield this.probe_plain("Distributable.list");
		yield this.probe_agent_list();
		yield this.probe_since_list("SystemInfo.list");
		yield this.probe_since_list("DebPackages.list");
		yield this.probe_since_list("RpmPackages.list");
		this.rpc.disconnect();
		return 0;
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
		var probe = new ListProbeHost();
		return yield probe.run(args[1], port, args[3]);
	}

	public static int main(string[] args)
	{
		var loop = new GLib.MainLoop();
		var code = 1;
		ListProbeHost.main_task.begin(args, (obj, res) => {
			try {
				code = ListProbeHost.main_task.end(res);
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