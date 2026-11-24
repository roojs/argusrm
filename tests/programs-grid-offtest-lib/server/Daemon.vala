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
	[CCode (cname = "strverscmp", cheader_filename = "string.h", feature_test_macro = "_GNU_SOURCE")]
	extern int strverscmp (string s1, string s2);

	/**
	 * Local handshake for the controller.
	 *
	 * ''RPC-Daemon.hello'' is the first call on the Unix socket
	 * and on the app socket, the same hello ''ollmfilesd'' answers.
	 * The client sends its version. The reply carries this server's
	 * version. A newer client is refused. An older client is warned.
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
				"hello", "iss"
			);
		}

		/**
		 * Answer the first call from a controller or an agent.
		 *
		 * The client version is compared with {@link Argus.VERSION}.
		 * A missing version is an older client. A newer client is
		 * refused. An older client is warned and still accepted.
		 * The reply value is this server's version.
		 *
		 * @param request inbound RPC
		 * @param protocol client protocol number
		 * @param client client name
		 * @param version client {@link Argus.VERSION}, or null from an older client
		 */
		public void hello(OLLMrpc.Request request, int protocol, string client, string? version = null)
		{
			var theirs = (version == null || version == "") ? "0.0.0" : version;
			GLib.debug("hello %s %d %s", client, protocol, theirs);
			var mine = Argus.VERSION;
			var notice = "ok";
			var order = strverscmp(theirs, mine);
			if (order > 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_PARAMS(
						"The server is " + mine + ". This client is " + theirs + ".")
				});
				return;
			}
			if (order < 0) {
				notice = "This client is " + theirs + ". The server is " + mine + ".";
				GLib.warning("%s", notice);
			}
			request.reply(new OLLMrpc.Response() {
				msg = notice,
				retval = OLLMrpc.val("s", mine)
			});
		}
	}
}
