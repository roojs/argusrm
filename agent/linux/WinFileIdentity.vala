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

namespace Argus.Agent.SQT
{
	/**
	 * Linux stand-in for the Windows PE identity cache.
	 *
	 * {@link Argus.Agent.Application.ensure_client_db} calls
	 * {@link init_db}. A Linux agent does not store PE hashes,
	 * so this call does nothing.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Agent.SQT.WinFileIdentity.init_db(app.client_db);
	 * }}}
	 */
	[Compact]
	public class WinFileIdentity
	{
		/**
		 * Skip creating ''win_file_identity''.
		 *
		 * @param db agent client database; unused on Linux
		 */
		public static void init_db(SQ.Database db)
		{
		}
	}
}
