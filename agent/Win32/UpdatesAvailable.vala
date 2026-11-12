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
	 * Read which installed packages have an update waiting, on Windows.
	 *
	 * Not compiled. Nothing calls {@link check}. Windows has no file
	 * of software that needs updating, so the read does not run.
	 * ''update_available'' is not added to ''programs''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var waiting = new Argus.Agent.UpdatesAvailable().check();
	 * }}}
	 */
	public class UpdatesAvailable : GLib.Object
	{
		/**
		 * Windows has no pending-update list.
		 *
		 * @return never
		 * @throws GLib.Error always. There is no package command
		 */
		public Gee.ArrayList<string> check() throws GLib.Error
		{
			throw new GLib.IOError.FAILED("no package command");
		}
	}
}
