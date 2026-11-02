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
	 * One ''cpu_info'' row.
	 */
	public class CpuInfo : Row
	{
		/**
		 * Register this row with the bin codec.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("CpuInfo", typeof(CpuInfo));
		}

		public string device_id { get; set; default = ""; }
		public string model { get; set; default = ""; }
		public string manufacturer { get; set; default = ""; }
		public string processor_type { get; set; default = ""; }
		public int cpu_status { get; set; default = 0; }
		public int number_of_cores { get; set; default = 0; }
		public int logical_processors { get; set; default = 0; }
		public int address_width { get; set; default = 0; }
		public int current_clock_speed { get; set; default = 0; }
		public int max_clock_speed { get; set; default = 0; }
		public string socket_designation { get; set; default = ""; }
	}
}
