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

namespace Argus.Shared.SQV
{
	/**
	 * One package in a Debian dependency preview.
	 *
	 * Not a table. ''AptDepends.removed'' fills {@link name} from
	 * ''apt_pkg'' joined to ''apt_pkg_depends''. The wire alias is
	 * ''Argus.AptDepends''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQV.AptDepends.rpc_register();
	 * var row = new Argus.Shared.SQV.AptDepends() {
	 *     name = "libfoo"
	 * };
	 * }}}
	 */
	public class AptDepends : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * Package name shown in the preview.
		 */
		public string name { get; set; default = ""; }

		/**
		 * Register the wire name ''Argus.AptDepends''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.AptDepends", typeof(AptDepends));
		}
	}
}
