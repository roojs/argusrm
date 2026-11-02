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
	 * Placeholder osquery start on Android.
	 *
	 * The class matches the Linux and Windows
	 * {@link Initialize}. {@link start} does not install or
	 * query. A real phone start might mean bundling the
	 * library in the Android build. That is still open.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new Argus.Agent.OSQuery.Initialize(link).start();
	 * }}}
	 */
	public class Initialize : GLib.Object
	{
		/**
		 * App socket opened by {@link Application.open_link}.
		 */
		private OLLMrpc.Transport.TlsClient link;

		/**
		 * @param link app socket already open
		 */
		public Initialize(OLLMrpc.Transport.TlsClient link)
		{
			this.link = link;
		}

		/**
		 * Pretend osquery can start on this phone.
		 *
		 * Logs and returns. No installer runs, and no table
		 * is synced.
		 */
		public void start()
		{
			if (this.link == null) {
				return;
			}
			GLib.warning("osquery was not started");
		}
	}
}
