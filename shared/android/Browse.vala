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

namespace Argus.Shared
{
	/**
	 * Android browse for Argus registration.
	 *
	 * Same result as ''PairBrowse'': service ''_rpc._tcp'', TXT
	 * ''id'', then host and port. {@link poll} is empty while
	 * waiting, ''none'' when browse fails, or the id, a newline,
	 * and ''host:port''. {@link start} calls
	 * ''org.roojs.argus.PairBrowse'', the class the Android
	 * controller uses. {@link label} is the phone name that class
	 * stored at bind, for {@link Register.try_connection}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var browse = new Argus.Shared.Browse();
	 * browse.start();
	 * var line = browse.poll();
	 * browse.stop();
	 * }}}
	 */
	public class Browse : GLib.Object
	{
		/**
		 * Phone name stored when the controller binds ''PairBrowse''.
		 *
		 * Empty until that bind runs.
		 */
		public string label {
			get {
				return Android.argus_android_phone_label();
			}
		}

		/**
		 * Begin browsing for ''_rpc._tcp''.
		 *
		 * A later {@link poll} returns the first service whose TXT
		 * record has an ''id''. No result within 30 seconds, or a
		 * failure, sets that result to ''none''.
		 */
		public void start()
		{
			Android.argus_android_pair_browse_start();
		}

		/**
		 * Latest browse line.
		 *
		 * Empty while waiting. ''none'' when browse failed or the
		 * wait ended. Otherwise the id, a newline, and ''host:port''.
		 *
		 * @return the line described above
		 */
		public string poll()
		{
			return Android.argus_android_pair_browse_poll();
		}

		/**
		 * Stop browsing.
		 *
		 * A result already stored for {@link poll} stays.
		 */
		public void stop()
		{
			Android.argus_android_pair_browse_stop();
		}
	}
}
