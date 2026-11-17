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
	 * One machine that has a package name.
	 *
	 * Not a table. ''PackageMachine.machines'' fills
	 * {@link agent_id}, {@link machine}, {@link logged_in_users},
	 * {@link version}, {@link update_since}, and
	 * {@link uninstall_string}. The Software dialog shows the
	 * machine, the users, and the version. The wire alias is
	 * ''Argus.PackageMachine''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQV.PackageMachine.rpc_register();
	 * var row = new Argus.Shared.SQV.PackageMachine() {
	 *     machine = "office",
	 *     logged_in_users = "ada",
	 *     version = "1.2.3"
	 * };
	 * }}}
	 */
	public class PackageMachine : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/**
		 * ''agent.id'' of this machine.
		 */
		public int64 agent_id { get; set; default = 0; }
		/**
		 * Name shown in the grid.
		 */
		public string machine { get; set; default = ""; }
		/**
		 * Distinct logged-in users, comma separated, or empty.
		 *
		 * The same join the Machines list uses. It is not a column of
		 * ''system_info''.
		 */
		public string logged_in_users { get; set; default = ""; }
		/**
		 * Version installed on this machine.
		 *
		 * Debian is version and revision. RPM is epoch, version, and
		 * release. Windows is ''programs.version''.
		 */
		public string version { get; set; default = ""; }
		/**
		 * Earliest unix time an update for this name has been waiting
		 * on this machine.
		 *
		 * Filled from ''package_updates''. Zero when this name has no
		 * pending update.
		 */
		public int update_since { get; set; default = 0; }
		/**
		 * Windows uninstall command for this machine.
		 *
		 * Filled from ''programs.uninstall_string''. Empty for Debian
		 * and RPM, and empty when Windows has no command.
		 */
		public string uninstall_string { get; set; default = ""; }

		/**
		 * Register the wire name ''Argus.PackageMachine''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.PackageMachine", typeof(PackageMachine));
		}
	}
}
