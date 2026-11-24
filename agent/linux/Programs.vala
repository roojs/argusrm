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

namespace Argus.Agent.OSQuery
{
	/**
	 * Linux stand-in for the Windows ''programs'' snapshot.
	 *
	 * {@link Execute.send_packages} names this class for
	 * {@link Argus.Shared.OSQuery.PackageManager.WIN}. A Linux
	 * agent is APT or DNF, so this post does nothing. The
	 * Windows agent compiles its own ''Programs'' class.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var code = new Programs().send(application);
	 * }}}
	 */
	public class Programs : Argus.Shared.OSQuery.Programs, Package
	{
		/**
		 * Skip the Windows program inventory.
		 *
		 * @param application agent that would hold the connection
		 * @return zero
		 */
		public int send(Application application)
		{
			return 0;
		}
	}
}
