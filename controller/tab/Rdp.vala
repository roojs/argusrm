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
	 * Remote desktops for this window.
	 *
	 * One tab per machine. The selected tab is the picture
	 * in front. {@link Argus.Controller.Rdp.Screen} paints it.
	 *
	 * == Example ==
	 *
	 * {{{
	 * rdp.open(4, "web-03");
	 * }}}
	 */
	public class Rdp : Gtk.Box
	{
		private Argus.Controller.Window window;
		private Gtk.Stack pictures;
		private Gtk.Box tabs;
		private Gee.HashMap<int, Argus.Controller.Rdp.Screen> screens;

		/**
		 * Build the picture stack and the tab bar.
		 *
		 * @param window the window this page belongs to
		 */
		public Rdp(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.screens = new Gee.HashMap<int, Argus.Controller.Rdp.Screen>();
			this.pictures = new Gtk.Stack() {
				hexpand = true,
				vexpand = true
			};
			this.tabs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				css_classes = { "rdp-tabs" },
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			this.append(this.pictures);
			this.append(this.tabs);
			this.window.app.rpc.notification.connect((notification) => {
				if (notification.method != "relay.ready" || notification.args.size < 1) {
					return;
				}
				var agent_id = notification.args.get(0).get_int();
				if (!this.screens.has_key(agent_id)) {
					return;
				}
				var screen = this.screens.get(agent_id);
				if (screen.started) {
					return;
				}
				screen.started = true;
				screen.begin();
			});
		}

		/**
		 * Select this machine, or add its tab.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 * @param name tab title
		 */
		public void open(int agent_id, string name)
		{
			var key = agent_id.to_string();
			if (this.screens.has_key(agent_id)) {
				var existing = this.tabs.get_first_child();
				while (existing != null) {
					if (existing.name == key) {
						((Gtk.ToggleButton) existing).active = true;
						return;
					}
					existing = existing.get_next_sibling();
				}
				return;
			}
			var screen = new Argus.Controller.Rdp.Screen(this.window, agent_id);
			this.screens.set(agent_id, screen);
			this.pictures.add_named(screen.picture, key);
			var close = new Gtk.Button.from_icon_name("window-close-symbolic") {
				css_classes = { "flat", "rdp-tab-close" },
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.CENTER
			};
			close.clicked.connect(() => {
				this.drop(agent_id);
			});
			var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
			row.append(new Gtk.Label(name));
			row.append(close);
			var tab = new Gtk.ToggleButton() {
				name = key,
				child = row,
				css_classes = { "flat", "rdp-tab" },
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER
			};
			tab.toggled.connect(() => {
				if (!tab.active) {
					return;
				}
				this.pictures.visible_child_name = key;
				var other = this.tabs.get_first_child();
				while (other != null) {
					if (other != tab) {
						((Gtk.ToggleButton) other).active = false;
					}
					other = other.get_next_sibling();
				}
			});
			this.tabs.append(tab);
			tab.active = true;
		}

		/**
		 * Remove one machine's tab.
		 *
		 * The local picture stops. The X on the tab calls this.
		 * The last tab hides the RDP row. Letting go of the
		 * Windows session is later.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void drop(int agent_id)
		{
			if (!this.screens.has_key(agent_id)) {
				return;
			}
			var screen = this.screens.get(agent_id);
			this.screens.unset(agent_id);
			screen.stop();
			var key = agent_id.to_string();
			var child = this.pictures.get_child_by_name(key);
			if (child != null) {
				this.pictures.remove(child);
			}
			var tab = this.tabs.get_first_child();
			while (tab != null) {
				var next = tab.get_next_sibling();
				if (tab.name == key) {
					this.tabs.remove(tab);
					break;
				}
				tab = next;
			}
			if (this.screens.size > 0) {
				return;
			}
			this.window.tabs_hide_rdp();
		}
	}
}
