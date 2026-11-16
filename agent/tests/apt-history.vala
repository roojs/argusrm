/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Agent
{
	/**
	 * Stand-in so the history parser test can compile without the
	 * service {@link Application}.
	 */
	public class Application : GLib.Object
	{
		internal static bool connection_down = false;
		internal OLLMrpc.Transport.TlsClient? connection { get; private set; }
	}
}

namespace Argus.Agent.Tests
{
	/**
	 * Apt history explicit-install parse (offline, no network).
	 */
	class AptHistoryTest
	{
		const string LOG = """
Start-Date: 2026-10-12  11:33:24
Commandline: apt install qemu-kvm libvirt-daemon-system
End-Date: 2026-10-12  11:40:00

Start-Date: 2026-11-06  11:41:54
Commandline: apt install libnftables-dev
End-Date: 2026-11-06  11:41:57

Start-Date: 2026-11-06  13:14:54
Commandline: apt-get install -y libnl-3-dev
End-Date: 2026-11-06  13:14:57

Start-Date: 2026-11-06  14:00:00
Commandline: apt install foo=1.2 bar
End-Date: 2026-11-06  14:00:05

Start-Date: 2026-11-06  15:00:00
Commandline: apt-get install -y ./local.deb
End-Date: 2026-11-06  15:00:05

Start-Date: 2026-11-11  17:32:52
Commandline: apt autoremove --purge
End-Date: 2026-11-11  17:33:20

Start-Date: 2026-11-16  12:31:34
Commandline: apt install libnftables-dev
End-Date: 2026-11-16  12:31:40

Start-Date: 2026-11-16  18:00:00
Commandline: apt install dnstwist
""";

		static int main()
		{
			var names = new Gee.HashMap<string, int>();
			var consumed = 0;
			if (AptHistoryTest.read(AptHistoryTest.LOG, 0, names, ref consumed) != 0) {
				return 1;
			}
			if (names.size != 5) {
				GLib.printerr("fail name count %u\n", names.size);
				return 1;
			}
			if (!names.has_key("qemu-kvm") || !names.has_key("libvirt-daemon-system") ||
				!names.has_key("libnftables-dev") || !names.has_key("libnl-3-dev") ||
				!names.has_key("./local.deb")) {
				GLib.printerr("fail missing explicit name\n");
				return 1;
			}
			if (names.has_key("foo") || names.has_key("bar") || names.has_key("dnstwist")) {
				GLib.printerr("fail unexpected name\n");
				return 1;
			}
			var first = new GLib.DateTime.local(2026, 11, 6, 11, 41, 54);
			if (names.get("libnftables-dev") != (int) first.to_unix()) {
				GLib.printerr("fail first install date %d\n", names.get("libnftables-dev"));
				return 1;
			}
			var end = new GLib.DateTime.local(2026, 11, 16, 12, 31, 40);
			if (consumed != (int) end.to_unix()) {
				GLib.printerr("fail watermark %d\n", consumed);
				return 1;
			}
			var again = new Gee.HashMap<string, int>();
			var again_consumed = consumed;
			if (AptHistoryTest.read(AptHistoryTest.LOG, consumed, again, ref again_consumed) != 0) {
				return 1;
			}
			if (again.size != 0 || again_consumed != consumed) {
				GLib.printerr("fail second pass names %u consumed %d\n", again.size, again_consumed);
				return 1;
			}
			return 0;
		}

		static int read(string log, int watermark, Gee.HashMap<string, int> names, ref int consumed)
		{
			var history = new Argus.Agent.Apt.History();
			history.watermark = watermark;
			history.consumed = consumed;
			history.names = names;
			var memory = new GLib.MemoryInputStream();
			memory.add_bytes(new GLib.Bytes(log.data));
			try {
				history.read(new GLib.DataInputStream(memory));
			} catch (GLib.Error e) {
				GLib.printerr("fail read %s\n", e.message);
				return 1;
			}
			consumed = history.consumed;
			return 0;
		}
	}
}
