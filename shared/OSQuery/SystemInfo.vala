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

namespace Argus.Shared.OSQuery
{
	/**
	 * One ''system_info'' row.
	 */
	public class SystemInfo : Row
	{
		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("SystemInfo", typeof(SystemInfo));
		}

		public string hostname { get; set; default = ""; }
		public string uuid { get; set; default = ""; }
		public string cpu_type { get; set; default = ""; }
		public string cpu_subtype { get; set; default = ""; }
		public string cpu_brand { get; set; default = ""; }
		public int cpu_physical_cores { get; set; default = 0; }
		public int cpu_logical_cores { get; set; default = 0; }
		public string cpu_microcode { get; set; default = ""; }
		/**
		 * Byte count. ''int64'' because it does not fit in ''int''.
		 */
		public int64 physical_memory { get; set; default = 0; }
		public string hardware_vendor { get; set; default = ""; }
		public string hardware_model { get; set; default = ""; }
		public string hardware_version { get; set; default = ""; }
		public string hardware_serial { get; set; default = ""; }
		public string board_vendor { get; set; default = ""; }
		public string board_model { get; set; default = ""; }
		public string board_version { get; set; default = ""; }
		public string board_serial { get; set; default = ""; }
		public string computer_name { get; set; default = ""; }
		public string local_hostname { get; set; default = ""; }
	}
}
