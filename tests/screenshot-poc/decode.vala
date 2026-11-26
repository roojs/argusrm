int main(string[] args)
{
	if (args.length < 2) {
		stderr.printf("usage: argus-shot-decode <file.jpg>\n");
		return 1;
	}
	uint8[] data;
	try {
		GLib.FileUtils.get_data(args[1], out data);
	} catch (GLib.FileError e) {
		stderr.printf("read: %s\n", e.message);
		return 1;
	}
	var bytes = new GLib.Bytes(data);
	double sum = 0.0;
	int w = 0, h = 0;
	for (var i = 0; i < 10; i++) {
		var t0 = GLib.get_monotonic_time();
		try {
			var tex = Gdk.Texture.from_bytes(bytes);
			w = tex.get_width();
			h = tex.get_height();
		} catch (GLib.Error e) {
			stderr.printf("decode: %s\n", e.message);
			return 1;
		}
		sum += (GLib.get_monotonic_time() - t0) / 1000.0;
	}
	stdout.printf("gdk_texture_from_bytes %dx%d avg %.2f ms (10 runs) input %zu bytes\n",
		w, h, sum / 10.0, data.length);
	return 0;
}
