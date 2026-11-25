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

/**
 * Stub {@link Application} for the ''argus-offering-registration'' binary only.
 *
 * Linked in place of ''server/Application.vala''. Not installed and not used
 * by ''argusrm-server''.
 */
namespace Argus.Server
{
	public class Application : GLib.Object
	{
		public static string opt_data_dir = "";
		public static bool opt_test_minimal = true;

		public string socket { get; set; default = ""; }

		public string download { get; set; default = ""; }

		public string registration { get; set; default = ""; }

		public OLLMrpc.Transport.Cert tls {
			get; set; default = new OLLMrpc.Transport.Cert();
		}

		public Net.SslListen ssl_listen { get; private set; }

		public Offering.Network? offering { get; set; }

		public Net.Download download_listen { get; private set; }

		public Net.Interfaces interfaces { get; private set; }

		public Net.NFTables firewall { get; set; }

		public SQ.Database db { get; private set; }

		public OLLMrpc.Transport.SocketListen listen { get; private set; }

		public SQT.Scheduler scheduler { get; private set; }

		construct
		{
			this.interfaces = new Net.Interfaces();
			this.ssl_listen = new Net.SslListen(this);
			this.download_listen = new Net.Download(this);
		}

		/**
		 * Open sqlite and the unix socket under ''data_dir''.
		 *
		 * Call after ''socket'' is set so the app-port firewall gets the
		 * loopback test port.
		 */
		public void init_data_dir(string data_dir)
		{
			if (!GLib.FileUtils.test(data_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(data_dir, 0700);
			}
			this.db = new SQ.Database(
				GLib.Path.build_filename(data_dir, "argus.sqlite"), true);
			this.listen = new OLLMrpc.Transport.SocketListen(
				GLib.Path.build_filename(data_dir, "argus.sock")) {
				live_handles = true
			};
			this.scheduler = new SQT.Scheduler(this);
			var app_port = Argus.SOCKET_PORT;
			var colon = this.socket.last_index_of(":");
			if (colon > 0) {
				int.try_parse(this.socket.substring(colon + 1), out app_port);
			}
			if (app_port < 1 || app_port > 65535) {
				app_port = Argus.SOCKET_PORT;
			}
			this.firewall = new Net.NFTables((uint16) app_port);
		}

		public void broadcast(OLLMrpc.Notification notification)
		{
			if (this.listen != null) {
				this.listen.broadcast(notification);
			}
			this.ssl_listen.broadcast(notification);
		}
	}
}