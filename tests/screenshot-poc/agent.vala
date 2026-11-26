static bool read_exact(GLib.InputStream input, uint8[] buf)
{
	size_t off = 0;
	while (off < buf.length) {
		try {
			var n = input.read(buf[off:buf.length]);
			if (n <= 0) {
				return false;
			}
			off += (size_t) n;
		} catch (GLib.Error e) {
			return false;
		}
	}
	return true;
}

static bool write_all(GLib.OutputStream output, uint8[] buf)
{
	size_t off = 0;
	while (off < buf.length) {
		try {
			var n = output.write(buf[off:buf.length]);
			if (n <= 0) {
				return false;
			}
			off += (size_t) n;
		} catch (GLib.Error e) {
			return false;
		}
	}
	return true;
}

int main(string[] args)
{
	if (args.length < 4) {
		stderr.printf("usage: argus-shot-agent <cert_dir> <relay_port> <local_port>\n");
		return 1;
	}
	var dir = args[1];
	var relay_port = (uint16) int.parse(args[2]);
	var local_port = (uint16) int.parse(args[3]);
	OLLMrpc.rpc_register();

	GLib.SocketConnection? worker_conn = null;
	GLib.Mutex write_lock = GLib.Mutex();
	uint64 up_msgs = 0;
	uint64 up_bytes = 0;
	uint64 down_msgs = 0;
	uint64 down_bytes = 0;

	try {
		var rpc = new OLLMrpc.Transport.TlsClient("127.0.0.1", relay_port) {
			tls_certificate = new GLib.TlsCertificate.from_files(
				GLib.Path.build_filename(dir, "agent.crt"),
				GLib.Path.build_filename(dir, "agent.key")),
			tls_database = GLib.TlsFileDatabase.new(
				GLib.Path.build_filename(dir, "ca.crt")),
			timeout = 0
		};
		rpc.notification.connect((notif) => {
			if (notif.method != "relay.data" || notif.args.size < 1) {
				return;
			}
			var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
			unowned uint8[] data = blob.get_data();
			if (data == null || data.length == 0) {
				return;
			}
			write_lock.lock();
			if (worker_conn != null) {
				var hdr = new uint8[4];
				var len = (uint32) data.length;
				hdr[0] = (uint8) (len & 0xFF);
				hdr[1] = (uint8) ((len >> 8) & 0xFF);
				hdr[2] = (uint8) ((len >> 16) & 0xFF);
				hdr[3] = (uint8) ((len >> 24) & 0xFF);
				if (write_all(worker_conn.output_stream, hdr) &&
					write_all(worker_conn.output_stream, data)) {
					down_msgs++;
					down_bytes += data.length;
				}
			}
			write_lock.unlock();
		});
		rpc.open();
		stdout.printf("agent tls_opened\n");
		stdout.flush();
		var joined = rpc.call(new OLLMrpc.Request() {
			method = "Relay.join",
			args = OLLMrpc.args("s", "agent")
		});
		if (joined.error != null) {
			stderr.printf("agent join err: %s\n", joined.error.message);
			return 1;
		}
		stdout.printf("agent joined\n");
		stdout.flush();
		rpc.watch();

		var listener = new GLib.SocketListener();
		var where = new GLib.InetSocketAddress(
			new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), local_port);
		listener.add_address(where, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP, null, null);
		stdout.printf("agent local_listening %u\n", local_port);
		stdout.flush();

		new GLib.Thread<int>("agent-hop", () => {
			try {
				var accepted = listener.accept(null);
				try {
					accepted.socket.set_option(6, 1, 1);
				} catch (GLib.Error e) {
				}
				write_lock.lock();
				worker_conn = accepted;
				write_lock.unlock();
				stdout.printf("agent worker_accepted\n");
				stdout.flush();

				var hdr = new uint8[4];
				while (read_exact(accepted.input_stream, hdr)) {
					uint32 len = (uint32) hdr[0] |
						((uint32) hdr[1] << 8) |
						((uint32) hdr[2] << 16) |
						((uint32) hdr[3] << 24);
					if (len == 0 || len > 16 * 1024 * 1024) {
						stderr.printf("agent bad_len %u\n", len);
						break;
					}
					var payload = new uint8[len];
					if (!read_exact(accepted.input_stream, payload)) {
						break;
					}
					var held = GLib.Value(typeof(GLib.Bytes));
					held.set_boxed(new GLib.Bytes(payload));
					var req = new OLLMrpc.Request() {
						method = "Relay.write"
					};
					req.args.add(held);
					var resp = rpc.call(req);
					if (resp.error != null) {
						stderr.printf("agent write err: %s\n", resp.error.message);
						break;
					}
					up_msgs++;
					up_bytes += len;
				}
			} catch (GLib.Error e) {
				stderr.printf("agent hop err: %s\n", e.message);
			}
			stdout.printf("agent done up_msgs=%llu up_bytes=%llu down_msgs=%llu down_bytes=%llu\n",
				up_msgs, up_bytes, down_msgs, down_bytes);
			stdout.flush();
			GLib.Process.exit(0);
		});

		new GLib.MainLoop().run();
	} catch (GLib.Error e) {
		stderr.printf("agent err: %s\n", e.message);
		return 1;
	}
	return 0;
}
