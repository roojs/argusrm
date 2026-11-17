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
	 * One machine that can take a distributable.
	 *
	 * Not a table. ''DistributeMachine.machines'' fills {@link agent_id},
	 * {@link machine}, {@link existing}, and {@link logged_in_users}.
	 * The installer dialog sets {@link version} and {@link picked}. The
	 * wire alias is ''Argus.DistributeMachine''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.SQV.DistributeMachine.rpc_register();
	 * var row = new Argus.Shared.SQV.DistributeMachine() {
	 *     machine = "office",
	 *     existing = "1.0.0",
	 *     version = "1.2.3",
	 *     picked = true
	 * };
	 * }}}
	 */
	public class DistributeMachine : GLib.Object, OLLMrpc.Bin.Serializable
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
		 * Installed ''programs.version'', or empty when it is absent.
		 */
		public string existing { get; set; default = ""; }
		/**
		 * Distinct logged-in users, comma separated, or empty.
		 *
		 * The same join the Machines list uses. It is not a column of
		 * ''system_info''.
		 */
		public string logged_in_users { get; set; default = ""; }
		/**
		 * Version this dialog will send.
		 */
		public string version { get; set; default = ""; }
		/**
		 * True when this machine is a target.
		 *
		 * Starts true when {@link existing} is set.
		 */
		public bool picked { get; set; default = false; }

		/**
		 * Register the wire name ''Argus.DistributeMachine''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.DistributeMachine", typeof(DistributeMachine));
		}
	}
}
