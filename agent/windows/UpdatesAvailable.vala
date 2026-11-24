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

namespace Argus.Agent
{
	/**
	 * Windows has no pending-package list to read.
	 *
	 * {@link check} throws. It does not report the packages
	 * as up to date.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var pending = new Argus.Agent.UpdatesAvailable();
	 * var names = pending.check(application.os_version);
	 * }}}
	 */
	public class UpdatesAvailable : GLib.Object
	{
		/**
		 * There is no pending-update list.
		 *
		 * @param os_version startup ''os_version'' row
		 * @return does not return
		 */
		public Gee.ArrayList<string> check(Argus.Shared.OSQuery.OsVersion os_version) throws GLib.Error
		{
			return new Gee.ArrayList<string>();
		}
	}
}
