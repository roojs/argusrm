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

namespace Argus.Server.Git
{
	/**
	 * Credentials for {@link Ggit.Repository.clone} and fetch.
	 *
	 * Username and password become {@link Ggit.CredPlaintext}. A
	 * key file is used through ''GIT_SSH_COMMAND''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var callbacks = new Argus.Server.Git.Callbacks() {
	 *     username = row.username,
	 *     password = row.password
	 * };
	 * fetch.set_remote_callbacks(callbacks);
	 * }}}
	 */
	public class Callbacks : Ggit.RemoteCallbacks
	{
		public string username { get; set; default = ""; }
		public string password { get; set; default = ""; }

		public Callbacks()
		{
			Object();
		}

		protected override Ggit.Cred? credentials(string url, string? username_from_url, Ggit.Credtype allowed_types) throws GLib.Error 
		{
			var user = this.username;
			if (user == "" && username_from_url != null) {
				user = username_from_url;
			}
			if (this.password != "" && (allowed_types & Ggit.Credtype.USERPASS_PLAINTEXT) != 0) {
				return new Ggit.CredPlaintext(user, this.password);
			}
			return null;
		}
	}
}
