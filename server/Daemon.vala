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

namespace Argus.Server
{
	/**
	 * Local handshake for the controller.
	 *
	 * ''RPC-Daemon.hello'' is the first call on the Unix socket,
	 * the same hello ''ollmfilesd'' answers. The reply is ''ok''.
	 * The controller does not read a daemon object.
	 *
	 * == Example ==
	 *
	 * {{{
	 * OLLMrpc.Request.register("RPC-Daemon", new Argus.Server.Daemon());
	 * }}}
	 */
	public class Daemon : GLib.Object
	{
		/**
		 * Register ''RPC-Daemon.hello''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"RPC-Daemon", typeof(Daemon),
				"hello", "is"
			);
		}

		/**
		 * Answer the controller's first call.
		 *
		 * @param request inbound RPC on the Unix socket
		 * @param protocol client protocol number
		 * @param client client name
		 */
		public void hello(OLLMrpc.Request request, int protocol, string client)
		{
			GLib.debug("hello %s %d", client, protocol);
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}
