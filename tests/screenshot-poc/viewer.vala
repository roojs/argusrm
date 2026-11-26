const uint8 MSG_FRAME_FULL = 0x01;
const uint8 MSG_FRAME_TILES = 0x03;
const uint8 MSG_FRAME_ACK = 0x10;
const uint8 MSG_MOUSE_CLICK = 0x11;
const uint8 MSG_KEY_UNICODE = 0x13;
const uint8 MSG_KEY_VK = 0x14;

static uint16 get_u16(uint8[] b, int off)
{
	return (uint16) b[off] | ((uint16) b[off + 1] << 8);
}

static uint32 get_u32(uint8[] b, int off)
{
	return (uint32) b[off] | ((uint32) b[off + 1] << 8) |
		((uint32) b[off + 2] << 16) | ((uint32) b[off + 3] << 24);
}

static void put_u16(uint8[] b, int off, uint16 v)
{
	b[off] = (uint8) (v & 0xFF);
	b[off + 1] = (uint8) ((v >> 8) & 0xFF);
}

static void put_u32(uint8[] b, int off, uint32 v)
{
	b[off] = (uint8) (v & 0xFF);
	b[off + 1] = (uint8) ((v >> 8) & 0xFF);
	b[off + 2] = (uint8) ((v >> 16) & 0xFF);
	b[off + 3] = (uint8) ((v >> 24) & 0xFF);
}

public class ShotViewer : GLib.Object
{
	private OLLMrpc.Transport.TlsClient rpc;
	private GLib.AsyncQueue<GLib.Bytes> out_queue = new GLib.AsyncQueue<GLib.Bytes>();
	private uint8[] fb = new uint8[0];
	private int fb_w = 0;
	private int fb_h = 0;
	private bool saved_before = false;
	private bool sent_actions = false;
	private bool saved_after = false;
	private int64 start_us = 0;
	private int64 action_done_us = 0;
	private uint64 frames_full = 0;
	private uint64 frames_tiles = 0;
	private uint64 tiles_total = 0;
	private uint64 active_bytes = 0;
	private uint64 idle_bytes = 0;
	private uint64 idle_frames = 0;
	private double decode_ms_sum = 0.0;
	private int decode_count = 0;
	private uint64 send_errors = 0;
	private int btn_x;
	private int btn_y;
	private int edit_x;
	private int edit_y;
	private int duration_sec;
	private GLib.MainLoop loop;

	public ShotViewer(
		string cert_dir,
		uint16 port,
		int btn_x,
		int btn_y,
		int edit_x,
		int edit_y,
		int duration_sec
	) throws GLib.Error
	{
		this.btn_x = btn_x;
		this.btn_y = btn_y;
		this.edit_x = edit_x;
		this.edit_y = edit_y;
		this.duration_sec = duration_sec;
		this.loop = new GLib.MainLoop();
		this.rpc = new OLLMrpc.Transport.TlsClient("127.0.0.1", port) {
			tls_certificate = new GLib.TlsCertificate.from_files(
				GLib.Path.build_filename(cert_dir, "view.crt"),
				GLib.Path.build_filename(cert_dir, "view.key")),
			tls_database = GLib.TlsFileDatabase.new(
				GLib.Path.build_filename(cert_dir, "ca.crt")),
			timeout = 0
		};
	}

	private void enqueue(uint8[] payload)
	{
		this.out_queue.push(new GLib.Bytes(payload));
	}

	private void send_ack(uint32 seq)
	{
		var buf = new uint8[5];
		buf[0] = MSG_FRAME_ACK;
		put_u32(buf, 1, seq);
		this.enqueue(buf);
	}

	private void send_click(int x, int y, uint8 btn = 1)
	{
		var nx = (uint16) (((int64) x * 65535) / (this.fb_w > 1 ? this.fb_w - 1 : 1));
		var ny = (uint16) (((int64) y * 65535) / (this.fb_h > 1 ? this.fb_h - 1 : 1));
		var buf = new uint8[6];
		buf[0] = MSG_MOUSE_CLICK;
		put_u16(buf, 1, nx);
		put_u16(buf, 3, ny);
		buf[5] = btn;
		this.enqueue(buf);
	}

	private void send_text(string text)
	{
		for (var i = 0; i < text.length; i++) {
			var buf = new uint8[3];
			buf[0] = MSG_KEY_UNICODE;
			put_u16(buf, 1, (uint16) text[i]);
			this.enqueue(buf);
		}
	}

	private void send_vk_tap(uint16 vk)
	{
		var dn = new uint8[4];
		dn[0] = MSG_KEY_VK;
		put_u16(dn, 1, vk);
		dn[3] = 0;
		this.enqueue(dn);
		var up = new uint8[4];
		up[0] = MSG_KEY_VK;
		put_u16(up, 1, vk);
		up[3] = 1;
		this.enqueue(up);
	}

	private Gdk.MemoryTexture snapshot_texture()
	{
		var copy = new uint8[this.fb.length];
		GLib.Memory.copy((void*) copy, this.fb, this.fb.length);
		return new Gdk.MemoryTexture(
			this.fb_w, this.fb_h, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
			new GLib.Bytes(copy), (size_t) (this.fb_w * 4));
	}

	private void on_data(GLib.Bytes blob)
	{
		unowned uint8[] data = blob.get_data();
		if (data == null || data.length < 5) {
			return;
		}
		var now = GLib.get_monotonic_time();
		if (this.action_done_us > 0 && now > this.action_done_us + 2000000) {
			this.idle_bytes += data.length;
			this.idle_frames++;
		} else {
			this.active_bytes += data.length;
		}
		var type = data[0];
		var seq = get_u32(data, 1);
		var t0 = GLib.get_monotonic_time();

		if (type == MSG_FRAME_FULL && data.length > 9) {
			var w = (int) get_u16(data, 5);
			var h = (int) get_u16(data, 7);
			var jpg = new uint8[data.length - 9];
			GLib.Memory.copy((void*) jpg, &data[9], jpg.length);
			try {
				var tex = Gdk.Texture.from_bytes(new GLib.Bytes(jpg));
				this.fb_w = w;
				this.fb_h = h;
				this.fb = new uint8[w * h * 4];
				tex.download(this.fb, (size_t) (w * 4));
				this.frames_full++;
			} catch (GLib.Error e) {
				stderr.printf("decode full err: %s\n", e.message);
			}
		} else if (type == MSG_FRAME_TILES && data.length >= 7 && this.fb.length > 0) {
			var count = (int) get_u16(data, 5);
			var pos = 7;
			for (var i = 0; i < count && pos + 12 <= data.length; i++) {
				var tx = (int) get_u16(data, pos);
				var ty = (int) get_u16(data, pos + 2);
				var tw = (int) get_u16(data, pos + 4);
				var th = (int) get_u16(data, pos + 6);
				var tlen = (int) get_u32(data, pos + 8);
				pos += 12;
				if (tlen <= 0 || pos + tlen > data.length) {
					break;
				}
				var jpg = new uint8[tlen];
				GLib.Memory.copy((void*) jpg, &data[pos], tlen);
				pos += tlen;
				try {
					var tex = Gdk.Texture.from_bytes(new GLib.Bytes(jpg));
					var scratch = new uint8[tw * th * 4];
					tex.download(scratch, (size_t) (tw * 4));
					for (var ry = 0; ry < th && (ty + ry) < this.fb_h; ry++) {
						var dst_off = ((ty + ry) * this.fb_w + tx) * 4;
						var src_off = ry * tw * 4;
						GLib.Memory.copy((void*) (&this.fb[dst_off]), &scratch[src_off], tw * 4);
					}
					this.tiles_total++;
				} catch (GLib.Error e) {
					stderr.printf("decode tile err: %s\n", e.message);
				}
			}
			this.frames_tiles++;
		}

		this.decode_ms_sum += (GLib.get_monotonic_time() - t0) / 1000.0;
		this.decode_count++;
		this.send_ack(seq);

		if (!this.saved_before && this.fb.length > 0) {
			this.saved_before = true;
			this.snapshot_texture().save_to_png("/tmp/argus-shot-phase2-before.png");
			stdout.printf("viewer saved_before seq=%u %dx%d\n", seq, this.fb_w, this.fb_h);
			stdout.flush();
		}
		if (!this.sent_actions && this.fb.length > 0) {
			this.sent_actions = true;
			GLib.Timeout.add(600, () => {
				stdout.printf("viewer sending_clicks_and_text btn=%d,%d edit=%d,%d\n",
					this.btn_x, this.btn_y, this.edit_x, this.edit_y);
				stdout.flush();
				this.send_click(this.btn_x, this.btn_y);
				GLib.Timeout.add(350, () => {
					this.send_click(this.btn_x, this.btn_y);
					return false;
				});
				GLib.Timeout.add(700, () => {
					this.send_click(this.btn_x, this.btn_y);
					return false;
				});
				GLib.Timeout.add(1100, () => {
					this.send_click(this.edit_x, this.edit_y);
					return false;
				});
				GLib.Timeout.add(1500, () => {
					this.send_text("Hello via Relay!");
					this.send_vk_tap(0x0D);
					this.action_done_us = GLib.get_monotonic_time();
					return false;
				});
				GLib.Timeout.add(3000, () => {
					if (!this.saved_after && this.fb.length > 0) {
						this.saved_after = true;
						this.snapshot_texture().save_to_png("/tmp/argus-shot-phase2-after.png");
						stdout.printf("viewer saved_after active_bytes=%llu\n", this.active_bytes);
						stdout.flush();
					}
					return false;
				});
				return false;
			});
		}
	}

	public int run() throws GLib.Error
	{
		this.rpc.notification.connect((notif) => {
			if (notif.method != "relay.data" || notif.args.size < 1) {
				return;
			}
			var blob = (GLib.Bytes) notif.args.get(0).get_boxed();
			this.on_data(blob);
		});
		this.rpc.open();
		var joined = this.rpc.call(new OLLMrpc.Request() {
			method = "Relay.join",
			args = OLLMrpc.args("s", "view")
		});
		if (joined.error != null) {
			stderr.printf("viewer join err: %s\n", joined.error.message);
			return 1;
		}
		this.start_us = GLib.get_monotonic_time();
		stdout.printf("viewer joined\n");
		stdout.flush();
		this.rpc.watch();

		var sender_stop = false;
		new GLib.Thread<int>("view-send", () => {
			while (!sender_stop) {
				var blob = this.out_queue.timeout_pop(200000);
				if (blob == null) {
					continue;
				}
				var held = GLib.Value(typeof(GLib.Bytes));
				held.set_boxed(blob);
				var req = new OLLMrpc.Request() {
					method = "Relay.write"
				};
				req.args.add(held);
				try {
					var resp = this.rpc.call(req);
					if (resp.error != null) {
						this.send_errors++;
						stderr.printf("viewer write err: %s\n", resp.error.message);
					}
				} catch (GLib.Error e) {
					this.send_errors++;
					stderr.printf("viewer call err: %s\n", e.message);
					break;
				}
			}
			return 0;
		});

		GLib.Timeout.add_seconds((uint) this.duration_sec, () => {
			sender_stop = true;
			var elapsed_s = (GLib.get_monotonic_time() - this.start_us) / 1000000.0;
			var idle_s = this.action_done_us > 0 ?
				(GLib.get_monotonic_time() - (this.action_done_us + 2000000)) / 1000000.0 : 0.0;
			var avg_dec = this.decode_count > 0 ? this.decode_ms_sum / this.decode_count : 0.0;
			stdout.printf(
				"viewer_summary elapsed=%.1fs full=%llu tile_batches=%llu tiles=%llu avg_decode=%.2fms active_bytes=%llu idle_sec=%.1fs idle_frames=%llu idle_bytes=%llu send_errors=%llu\n",
				elapsed_s, this.frames_full, this.frames_tiles, this.tiles_total,
				avg_dec, this.active_bytes, idle_s, this.idle_frames, this.idle_bytes,
				this.send_errors);
			stdout.flush();
			this.loop.quit();
			return false;
		});
		this.loop.run();
		return (this.frames_full > 0 && this.send_errors == 0) ? 0 : 1;
	}
}

int main(string[] args)
{
	if (args.length < 8) {
		stderr.printf("usage: argus-shot-viewer <cert_dir> <port> <btn_x> <btn_y> <edit_x> <edit_y> <duration_sec>\n");
		return 1;
	}
	OLLMrpc.rpc_register();
	try {
		var viewer = new ShotViewer(
			args[1],
			(uint16) int.parse(args[2]),
			int.parse(args[3]),
			int.parse(args[4]),
			int.parse(args[5]),
			int.parse(args[6]),
			int.parse(args[7]));
		return viewer.run();
	} catch (GLib.Error e) {
		stderr.printf("viewer err: %s\n", e.message);
		return 1;
	}
}
