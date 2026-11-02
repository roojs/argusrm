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
	 * D-Bus registration for the systemd process.
	 *
	 * ''--register'' calls {@link register}. This process calls
	 * {@link Argus.Shared.Register} and keeps the certificate.
	 * {@link registered} is that certificate. Linux meson includes
	 * this file.
	 */
	[DBus (name = "org.roojs.ArgusAgent")]
	internal class BusRegistration : Object
	{
		private static BusRegistration current;

		/**
		 * Browsing agent that owns the certificate.
		 */
		public weak Application agent;

		/**
		 * Own ''org.roojs.ArgusAgent'' on the system bus.
		 *
		 * @param agent the process that browses and stores the
		 *   certificate
		 */
		public static void start(Application agent)
		{
			var bus = new BusRegistration();
			bus.agent = agent;
			BusRegistration.current = bus;
			GLib.Bus.own_name(GLib.BusType.SYSTEM, "org.roojs.ArgusAgent",
				GLib.BusNameOwnerFlags.NONE,
				(connection, bus_name) => {
					try {
						connection.register_object("/org/roojs/ArgusAgent", BusRegistration.current);
					} catch (GLib.Error e) {
						GLib.warning("registration bus: %s", e.message);
					}
				},
				(connection, bus_name) => {
					GLib.debug("registration bus owned");
				},
				(connection, bus_name) => {
					GLib.warning("registration bus lost");
				});
		}

		/**
		 * Whether ''client.pem'' is already stored here.
		 *
		 * @return true when this process has the certificate
		 */
		public bool registered() throws GLib.DBusError, GLib.IOError
		{
			var cert = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			return GLib.FileUtils.test(cert, GLib.FileTest.EXISTS);
		}

		/**
		 * Register with the pin from ''--register''.
		 *
		 * Waits until browse returns a line, then calls
		 * {@link Argus.Shared.Register.try_connection}.
		 *
		 * @param pin the six digits
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode}
		 */
		public async int register(string pin) throws GLib.DBusError, GLib.IOError
		{
			if (pin.length != 6 || this.agent == null) {
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var line = this.agent.browse.poll();
			while (line == "") {
				GLib.Timeout.add_seconds(1, () => {
					this.register.callback();
					return false;
				});
				yield;
				if (this.agent == null) {
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				line = this.agent.browse.poll();
			}
			if (line == "none") {
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var host = "";
			var port = 0;
			var split = line.index_of("\n");
			var hostport = "";
			if (split >= 1) {
				hostport = line.substring(split + 1);
			}
			var colon = hostport.last_index_of(":");
			if (colon >= 1) {
				host = hostport.substring(0, colon);
				port = int.parse(hostport.substring(colon + 1));
			}
			var code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			if (host != "" && port > 0) {
				var registration = new Argus.Shared.Register();
				code = registration.try_connection(host, (uint16) port,
					pin, GLib.Environment.get_host_name());
				GLib.debug("registration %d", code);
			}
			return code;
		}
	}
}
