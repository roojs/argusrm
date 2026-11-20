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
	 * Settings page.
	 *
	 * The Servers group lists each saved server. The server
	 * this window has open shows a green circle. Expanding
	 * that row offers deregister and disconnect via
	 * {@link Argus.Controller.Widget.HoldButton}. Holding for two
	 * seconds closes this window
	 * and returns to the startup check, which waits for a choice.
	 * Expanding another row offers connect. Add a connection is
	 * the last row in that group. Connect and add open
	 * {@link Dialog.Bootstrap}.
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
		 * Build the Servers group for one open window.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Settings(Argus.Controller.Window window)
		{
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			var servers = new Adw.PreferencesGroup() {
				title = "Servers"
			};
			var saved = new Gee.ArrayList<Argus.Controller.SQT.Server>();
			var broken = false;
			try {
				var store = new Argus.Controller.Store.Server(this.window.app);
				saved = store.list();
			} catch (GLib.Error e) {
				broken = true;
			}
			if (broken) {
				servers.description = "The saved connections could not be read.";
			}
			var live_name = this.window.server.name;
			for (var i = 0; i < saved.size; i++) {
				var row = saved.get(i);
				if (row.name == "") {
					continue;
				}
				var server_name = row.name;
				var open = server_name != "" && server_name == live_name;
				var server = new Adw.ExpanderRow() {
					title = row.title
				};
				if (row.addresses_subtitle != "") {
					server.subtitle = row.addresses_subtitle;
				}
				if (open) {
					server.add_prefix(new Gtk.Label("●") {
						valign = Gtk.Align.CENTER,
						css_classes = { "server-current" }
					});
					var disconnect = new Argus.Controller.Widget.HoldButton() {
						icon_name = "system-log-out-symbolic",
						label = "Deregister and disconnect",
						hexpand = true
					};
					disconnect.tooltip_text = "Press and hold to disconnect";
					disconnect.confirmed.connect(() => {
						this.window.app.running_window = false;
						this.window.app.rpc.disconnect();
#if ANDROID
						this.window.unload();
						new Dialog.Bootstrap(this.window.app, "choose").present(this.window);
#else
						this.window.leaving = true;
						this.window.close();
						new Dialog.Bootstrap(this.window.app, "choose").present(null);
#endif
					});
					server.add_row(disconnect);
					servers.add(server);
					continue;
				}
				var connect = new Adw.ActionRow() {
					title = "Connect",
					activatable = true
				};
				connect.add_prefix(
					new Gtk.Image.from_icon_name("network-transmit-symbolic"));
				connect.activated.connect(() => {
					new Dialog.Bootstrap(this.window.app, server_name).present(this.window);
				});
				server.add_row(connect);
				servers.add(server);
			}
			var add = new Adw.ActionRow() {
				title = "Add a connection",
				activatable = true
			};
			add.add_prefix(new Gtk.Image.from_icon_name("list-add-symbolic"));
			add.activated.connect(() => {
				new Dialog.Bootstrap(this.window.app, "add").present(this.window);
			});
			servers.add(add);
			this.add(servers);
		}
	}
}
