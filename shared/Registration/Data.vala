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

namespace Argus.Shared.Registration
{
	/**
	 * Local controller registration result.
	 *
	 * The running server returns this object over the Unix RPC connection.
	 * The privileged controller command serializes it to standard output.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var data = new Argus.Shared.Registration.Data() {
	 *     name = "office-server",
	 *     addresses = { "192.0.2.10" },
	 *     port = 817
	 * };
	 * }}}
	 */
	public class Data : GLib.Object, Json.Serializable, OLLMrpc.Bin.Serializable
	{
		public string error { get; set; default = ""; }
		public string private_key { get; set; default = ""; }
		public string client_certificate { get; set; default = ""; }
		public string ca_certificate { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public string[] addresses { get; set; default = {}; }
		public int port { get; set; default = 0; }

		/**
		 * Register the local registration result wire type.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Registration.Data", typeof(Data));
		}
	}
}
