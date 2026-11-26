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
	 * version. The last number is ignored. A newer client on the
	 * first two numbers is refused. An older client is warned.
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
		 * The client version is compared with {@link Argus.VERSION}
		 * on the first two numbers. The last number can differ.
		 * A missing version is an older client. A newer client on
		 * those two numbers is refused. An older client is warned
		 * and still accepted. The reply value is this server's
		 * version.
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
			var theirs_api = theirs;
			var theirs_dot = theirs.index_of(".");
			if (theirs_dot >= 0) {
				var theirs_end = theirs.index_of(".", theirs_dot + 1);
				if (theirs_end > theirs_dot) {
					theirs_api = theirs.substring(0, theirs_end);
				}
			}
			var mine_api = mine;
			var mine_dot = mine.index_of(".");
			if (mine_dot >= 0) {
				var mine_end = mine.index_of(".", mine_dot + 1);
				if (mine_end > mine_dot) {
					mine_api = mine.substring(0, mine_end);
				}
			}
			var order = strverscmp(theirs_api, mine_api);
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
