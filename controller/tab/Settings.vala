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

namespace Argus.Controller.Tab
{
	/**
	 * Connection page.
	 *
	 * An {@link Adw.PreferencesPage} for the server this window is
	 * using. Other saved servers are a list. Choosing one opens
	 * {@link Dialog.Bootstrap} on that name. Add opens the same
	 * window to register another server. Disconnect closes this
	 * window and returns to the startup check, which waits for
	 * a choice instead of opening the same server again.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Settings(window);
	 * stack.add_named(page, "settings");
	 * }}}
	 */
	public class Settings : Adw.PreferencesPage
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;

		/**
		 * Build the connection groups for one open server.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Settings(Argus.Controller.Window window)
		{
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			var here = new Adw.PreferencesGroup() {
				title = "This server"
			};
			var here_row = new Adw.ActionRow() {
				title = this.window.connection.name,
				subtitle = "Connected"
			};
			if (this.window.connection.addresses.length > 0) {
				here_row.subtitle = "Connected, " +
					string.joinv(", ", this.window.connection.addresses);
			}
			here.add(here_row);
			var disconnect = new Adw.ActionRow() {
				title = "Disconnect",
				activatable = true
			};
			disconnect.add_prefix(new Gtk.Image.from_icon_name("system-log-out-symbolic"));
			disconnect.activated.connect(() => {
				var app = this.window.app;
				app.running_window = false;
				this.window.leaving = true;
				app.rpc.disconnect();
				this.window.close();
				new Dialog.Bootstrap(app, "choose").present(null);
			});
			here.add(disconnect);
			this.add(here);
			var others = new Adw.PreferencesGroup() {
				title = "Connect to another server"
			};
			var path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "connections.json");
			var saved = new Connections();
			var broken = false;
			if (GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				var text = "";
				try {
					GLib.FileUtils.get_contents(path, out text);
					var loaded = Json.gobject_from_data(typeof(Connections),
						"{\"rows\":" + text + "}") as Connections;
					if (loaded == null) {
						throw new GLib.FileError.FAILED("The saved connections could not be read.");
					}
					saved = loaded;
				} catch (GLib.Error e) {
					broken = true;
				}
			}
			if (broken) {
				others.description = "The saved connections could not be read.";
			}
			for (var i = 0; i < saved.rows.size; i++) {
				var row = saved.rows.get(i);
				if (row.name == "" || row.name == this.window.connection.name) {
					continue;
				}
				var server_name = row.name;
				var server = new Adw.ActionRow() {
					title = server_name,
					subtitle = string.joinv(", ", row.addresses),
					activatable = true
				};
				server.activated.connect(() => {
					new Dialog.Bootstrap(this.window.app, server_name).present(this.window);
				});
				others.add(server);
			}
			var add = new Adw.ActionRow() {
				title = "Add a connection",
				activatable = true
			};
			add.add_prefix(new Gtk.Image.from_icon_name("list-add-symbolic"));
			add.activated.connect(() => {
				new Dialog.Bootstrap(this.window.app, "add").present(this.window);
			});
			others.add(add);
			this.add(others);
		}
	}
}
