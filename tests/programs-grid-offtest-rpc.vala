/*
 * Minimal Unix-socket RPC for programs-grid-offtest only.
 * Real Programs.list SQL + bin wire; no libsecret or live argusrm-server.
 */

public class ProgramsGridOfftestRpcServer : GLib.Object
{
	private OLLMrpc.Transport.SocketListen? listen;
	private SQ.Database? database;
	private Argus.Server.Daemon daemon;

	public string socket_path { get; private set; default = ""; }

	public bool start(string sqlite_path) throws GLib.Error
	{
		if (this.listen != null) {
			return true;
		}
		this.database = new SQ.Database(sqlite_path, false);
		OLLMrpc.rpc_register();
		Argus.Shared.Agent.rpc_register();
		Argus.Shared.OSQuery.rpc_register();
		Argus.Server.Daemon.rpc_register();
		Argus.Shared.Agent.init_db(this.database);
		Argus.Shared.OSQuery.init_db(this.database);
		Argus.Shared.OSQuery.register();
		this.daemon = new Argus.Server.Daemon();
		OLLMrpc.Request.register("RPC-Daemon", this.daemon);
		var dir = GLib.Path.build_filename(
			GLib.Environment.get_user_cache_dir(),
			"argusrm", "programs-grid-offtest");
		GLib.DirUtils.create_with_parents(dir, 0700);
		var sock = GLib.Path.build_filename(dir, "rpc-%d.sock".printf(
			GLib.Random.int_range(0, 1000000)));
		if (GLib.FileUtils.test(sock, GLib.FileTest.EXISTS)) {
			GLib.FileUtils.unlink(sock);
		}
		this.socket_path = sock;
		this.listen = new OLLMrpc.Transport.SocketListen(sock) {
			live_handles = true
		};
		if (!this.listen.start()) {
			throw new GLib.IOError.FAILED("SocketListen did not bind at " + sock);
		}
		return true;
	}

	public void stop()
	{
		if (this.listen != null) {
			this.listen.stop();
			this.listen = null;
		}
		if (this.socket_path != "" && GLib.FileUtils.test(
			this.socket_path, GLib.FileTest.EXISTS)) {
			GLib.FileUtils.unlink(this.socket_path);
		}
		this.socket_path = "";
		this.database = null;
	}

	public static async Gee.ArrayList<Argus.Shared.OSQuery.Programs>? fetch_list(
		string socket_path,
		out int64 rpc_ms) throws GLib.Error
	{
		if (!GLib.FileUtils.test(socket_path, GLib.FileTest.EXISTS)) {
			throw new GLib.IOError.FAILED(
				"Unix socket missing: " + socket_path);
		}
		var rpc = new OLLMrpc.Client("", "", socket_path) {
			live_handles = true,
			call_timeout_seconds = 120
		};
		var opened = yield rpc.connect(new OLLMrpc.Request() {
			method = "RPC-Daemon.hello",
			args = OLLMrpc.args("iss", 1, "programs-grid-offtest", Argus.VERSION)
		});
		if (!opened) {
			throw new GLib.IOError.FAILED(
				"RPC hello failed: " + rpc.connect_error);
		}
		var start = GLib.get_monotonic_time();
		var response = yield rpc.call(new OLLMrpc.Request() {
			method = "Programs.list",
			args = OLLMrpc.args("ii", 0, 0)
		});
		rpc_ms = (GLib.get_monotonic_time() - start) / 1000;
		rpc.disconnect();
		if (response.error != null) {
			throw new GLib.IOError.FAILED(
				"Programs.list: " + response.error.message);
		}
		if (!response.retval.type().is_a(typeof(Gee.ArrayList))) {
			throw new GLib.IOError.FAILED("Programs.list retval is not ArrayList");
		}
		return (Gee.ArrayList<Argus.Shared.OSQuery.Programs>) response.retval.get_object();
	}
}