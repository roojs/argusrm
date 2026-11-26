public class ShotRelay : GLib.Object
{
	public OLLMrpc.Transport.Connection? agent_conn;
	public OLLMrpc.Transport.Connection? view_conn;
	public uint64 a2v_msgs = 0;
	public uint64 a2v_bytes = 0;
	public uint64 v2a_msgs = 0;
	public uint64 v2a_bytes = 0;
	public Gee.ArrayList<GLib.Bytes> pending_a2v = new Gee.ArrayList<GLib.Bytes>();

	public void join(OLLMrpc.Request request, string role)
	{
		if (role == "agent") {
			this.agent_conn = request.connection;
			stdout.printf("relay joined agent\n");
		} else {
			this.view_conn = request.connection;
			stdout.printf("relay joined view\n");
		}
		stdout.flush();
		request.reply(new OLLMrpc.Response());
		if (role != "agent" && this.pending_a2v.size > 0 && this.view_conn != null) {
			foreach (var chunk in this.pending_a2v) {
				this.send_data(this.view_conn, chunk);
			}
			this.pending_a2v.clear();
		}
	}

	private void send_data(OLLMrpc.Transport.Connection target, GLib.Bytes chunk)
	{
		var held = GLib.Value(typeof(GLib.Bytes));
		held.set_boxed(chunk);
		var note = new OLLMrpc.Notification() {
			method = "relay.data"
		};
		note.args.add(held);
		target.write(note);
	}

	public void write(OLLMrpc.Request request, GLib.Bytes chunk)
	{
		var from_agent = request.connection == this.agent_conn;
		var other = from_agent ? this.view_conn : this.agent_conn;
		request.reply(new OLLMrpc.Response());
		if (chunk.get_size() == 0) {
			return;
		}
		if (from_agent) {
			this.a2v_msgs++;
			this.a2v_bytes += chunk.get_size();
		} else {
			this.v2a_msgs++;
			this.v2a_bytes += chunk.get_size();
		}
		if (other == null) {
			if (from_agent && this.pending_a2v.size < 4) {
				this.pending_a2v.add(chunk);
			}
			return;
		}
		this.send_data(other, chunk);
	}
}

int main(string[] args)
{
	if (args.length < 3) {
		stderr.printf("usage: argus-shot-relay <cert_dir> <port>\n");
		return 1;
	}
	var dir = args[1];
	var port = (uint16) int.parse(args[2]);
	OLLMrpc.rpc_register();
	var relay = new ShotRelay();
	OLLMrpc.Request.add_class(
		"Relay", typeof(ShotRelay),
		"join", "s",
		"write", "ay");
	OLLMrpc.Request.register("Relay", relay);

	try {
		var server_cert = new GLib.TlsCertificate.from_files(
			GLib.Path.build_filename(dir, "server.crt"),
			GLib.Path.build_filename(dir, "server.key"));
		GLib.TlsDatabase trust = GLib.TlsFileDatabase.new(
			GLib.Path.build_filename(dir, "ca.crt"));
		var service = new GLib.SocketService();
		var where = new GLib.InetSocketAddress(
			new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), port);
		service.add_address(where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, null);
		var live = new Gee.ArrayList<OLLMrpc.Transport.Connection>();
		service.incoming.connect((conn) => {
			try {
				conn.socket.set_option(6, 1, 1);
			} catch (GLib.Error e) {
			}
			GLib.TlsServerConnection tls;
			try {
				tls = GLib.TlsServerConnection.@new(conn, server_cert);
			} catch (GLib.Error e) {
				stderr.printf("tls: %s\n", e.message);
				return true;
			}
			tls.database = trust;
			tls.authentication_mode = GLib.TlsAuthenticationMode.REQUIRED;
			tls.accept_certificate.connect((peer, errors) => {
				return peer != null &&
					(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
			});
			tls.handshake_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
				try {
					tls.handshake_async.end(res);
				} catch (GLib.Error e) {
					stderr.printf("handshake: %s\n", e.message);
					return;
				}
				var rpc = new OLLMrpc.Transport.Connection(conn) {
					io = tls
				};
				live.add(rpc);
				rpc.start();
				stdout.printf("relay tls_connected\n");
				stdout.flush();
			});
			return true;
		});
		service.start();
		stdout.printf("relay listening %u\n", port);
		stdout.flush();
		GLib.Timeout.add_seconds(10, () => {
			stdout.printf("relay stats a2v_msgs=%llu a2v_bytes=%llu v2a_msgs=%llu v2a_bytes=%llu\n",
				relay.a2v_msgs, relay.a2v_bytes, relay.v2a_msgs, relay.v2a_bytes);
			stdout.flush();
			return true;
		});
		new GLib.MainLoop().run();
	} catch (GLib.Error e) {
		stderr.printf("relay err: %s\n", e.message);
		return 1;
	}
	return 0;
}
