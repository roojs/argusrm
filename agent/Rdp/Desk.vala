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

namespace Argus.Agent.Rdp
{
	/**
	 * Stand-in for the desktop the agent dials.
	 *
	 * On a managed Windows machine that desktop is TermService.
	 * This listener is the FreeRDP server used when the relay
	 * test has no Windows host. {@link Tunnel} dials the port
	 * {@link run} binds. FreeRDP's callbacks have no user-data
	 * slot, so the process keeps one {@link Desk}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var desk = new Argus.Agent.Rdp.Desk(cert, key);
	 * return desk.run(3389);
	 * }}}
	 */
	public class Desk : GLib.Object
	{
		static Desk? session;
		string cert_path;
		string key_path;

		/**
		 * Store the certificate the listener presents.
		 *
		 * @param cert_path PEM certificate
		 * @param key_path matching private key
		 */
		public Desk(string cert_path, string key_path)
		{
			this.cert_path = cert_path;
			this.key_path = key_path;
		}

		/**
		 * Bind 127.0.0.1 and accept peers until the listen socket closes.
		 *
		 * @param port loopback port
		 * @return 0, or 1 when the bind fails
		 */
		public int run(uint16 port)
		{
			session = this;
			var listener = new FreeRDP.Listener();
			listener.PeerAccepted = accepted;
			if (!listener.Open(listener, "127.0.0.1", port)) {
				stderr.printf("desk bind failed\n");
				return 1;
			}
			stderr.printf("desk listening %u\n", port);
			var events = new void*[32];
			while (true) {
				uint32 count = listener.GetEventHandles(listener, events, 32);
				if (count == 0) {
					break;
				}
				if (WinPr.wait(count, events, false, WinPr.INFINITE) == WinPr.WAIT_FAILED) {
					break;
				}
				if (!listener.CheckFileDescriptor(listener)) {
					break;
				}
			}
			listener.Close(listener);
			return 0;
		}

		static bool post_connect(FreeRDP.Peer client)
		{
			stderr.printf("POST_CONNECT\n");
			return true;
		}

		static bool activate(FreeRDP.Peer client)
		{
			stderr.printf("ACTIVATED\n");
			client.activated = 1;
			return true;
		}

		static bool logon(FreeRDP.Peer client, void* identity, bool automatic)
		{
			stderr.printf("LOGON automatic=%d\n", automatic ? 1 : 0);
			return true;
		}

		static uint32 peer_thread(void* arg)
		{
			var desk = session;
			if (desk == null) {
				return 1;
			}
			unowned FreeRDP.Peer client = (FreeRDP.Peer) arg;
			client.PostConnect = post_connect;
			client.Activate = activate;
			client.Logon = logon;
			if (!client.context_new()) {
				stderr.printf("context_new failed\n");
				return 1;
			}
			unowned FreeRDP.Settings settings = client.context.settings;
			settings.set_bool(FreeRDP.SettingsBool.NlaSecurity, false);
			settings.set_bool(FreeRDP.SettingsBool.TlsSecurity, true);
			settings.set_bool(FreeRDP.SettingsBool.RdpSecurity, false);
			settings.set_bool(FreeRDP.SettingsBool.SupportGraphicsPipeline, false);
			settings.set_bool(FreeRDP.SettingsBool.RemoteFxCodec, false);
			settings.set_bool(FreeRDP.SettingsBool.NSCodec, false);
			settings.set_uint32(
				FreeRDP.SettingsUint32.EncryptionLevel,
				FreeRDP.ENCRYPTION_LEVEL_CLIENT_COMPATIBLE);
			settings.set_uint32(FreeRDP.SettingsUint32.ColorDepth, 32);
			settings.set_pointer(
				FreeRDP.SettingsPointer.RdpServerCertificate,
				new FreeRDP.Certificate.from_file(desk.cert_path));
			settings.set_pointer(
				FreeRDP.SettingsPointer.RdpServerRsaKey,
				new FreeRDP.PrivateKey.from_file(desk.key_path));
			if (!client.Initialize(client)) {
				stderr.printf("Initialize failed\n");
				client.context_free();
				client.peer_free();
				return 1;
			}
			stderr.printf("peer up\n");
			var events = new void*[32];
			while (true) {
				uint32 count = client.GetEventHandles(client, events, 32);
				if (count == 0) {
					break;
				}
				uint32 wait = WinPr.wait(count, events, false, 20000);
				if (wait == WinPr.WAIT_TIMEOUT) {
					continue;
				}
				if (wait == WinPr.WAIT_FAILED) {
					break;
				}
				if (!client.CheckFileDescriptor(client)) {
					stderr.printf("peer closed activated=%d\n", client.activated);
					break;
				}
			}
			client.Disconnect(client);
			client.context_free();
			client.peer_free();
			return 0;
		}

		static bool accepted(FreeRDP.Listener listener, FreeRDP.Peer client)
		{
			stderr.printf("accepted\n");
			var thread = WinPr.create_thread(null, 0, peer_thread, client, 0, null);
			if (thread == null) {
				return false;
			}
			WinPr.close_handle(thread);
			return true;
		}
	}
}
