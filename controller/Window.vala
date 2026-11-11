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

namespace Argus.Controller
{
	/**
	 * Main controller window for one server.
	 *
	 * The sidebar title is ''Argus RM''. While the server connection
	 * is down that title is ''Offline'' in red, and the connection is
	 * opened again every thirty seconds. The page on the right is
	 * the saved server name, a dash, and the place in front. An
	 * empty name uses the first saved address. {@link TabList}
	 * lists places. {@link Tab.Agent} lists registered machines.
	 * {@link Tab.Assets} switches {@link Tab.Asset.SystemInfo} and
	 * {@link Tab.Asset.Software}. {@link Store.SystemInfo} loads
	 * ''SystemInfo.list''. Software is three package grids.
	 * {@link Tab.Repository} lists script clones. The other places
	 * are blank. Settings stays at the bottom of the list.
	 * The open server's row is ''Deregister and disconnect''.
	 * Holding it for two seconds closes this window and returns
	 * to the startup check.
	 * ''Agent or Controller'' is on the Agents page.
	 * It opens {@link Dialog.Pairing}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var window = new Argus.Controller.Window(app, connection, issued);
	 * window.present();
	 * }}}
	 */
	public class Window : Adw.Window
	{
		public Application app;
		public Connection connection { get; set; default = new Connection(); }
		public Argus.Shared.Registration.Data issued {
			get; set; default = new Argus.Shared.Registration.Data();
		}
		/**
		 * Header of the page on the right.
		 */
		public Adw.HeaderBar content_header;
		/**
		 * Toolbar around the page on the right.
		 */
		public Adw.ToolbarView content_bar;
		/**
		 * True when this window is closing without quitting.
		 *
		 * Disconnect and a switch to another server set this
		 * before close. The close request then leaves the process
		 * running.
		 */
		public bool leaving = false;
		private GLib.SimpleAction deregister_action;
		private Dialog.Pairing pairing_dialog;
		private Gtk.Label title_label;
		private uint connection_check_id = 0;
		private bool reconnecting = false;
		private bool was_connected = true;
		private bool closed = false;
		private int64 next_reconnect = 0;

		/**
		 * Create the window for one server.
		 *
		 * Closing it quits the controller.
		 *
		 * @param app the controller process
		 * @param connection the server that answered
		 * @param issued certificate from this process, or empty
		 */
		public Window(
			Application app,
			Connection connection,
			Argus.Shared.Registration.Data issued
		) {
			this.app = app;
			this.connection = connection;
			this.issued = issued;
			this.issued.name = connection.name;
			this.issued.finished.connect((removed) => {
				if (removed) {
					this.app.quit();
					return;
				}
				this.deregister_action.set_enabled(true);
			});
			this.title = "Argus RM";
			this.set_default_size(960, 640);
			var header = new Adw.HeaderBar();
			this.title_label = new Gtk.Label("Argus RM") {
				css_classes = { "title" }
			};
			header.title_widget = this.title_label;
			this.pairing_dialog = new Dialog.Pairing(this);
			var actions = new GLib.SimpleActionGroup();
			this.deregister_action = new GLib.SimpleAction("deregister", null);
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.issued.deregister(this, this.app.rpc);
			});
			var register_action = new GLib.SimpleAction("register", null);
			register_action.activate.connect(() => {
				if (this.pairing_dialog.pairing) {
					return;
				}
				this.pairing_dialog.open();
			});
			actions.add_action(this.deregister_action);
			actions.add_action(register_action);
			this.insert_action_group("win", actions);
			var sidebar_bar = new Adw.ToolbarView();
			sidebar_bar.add_top_bar(header);
			var tabs = new TabList();
			sidebar_bar.content = tabs;
			this.content_header = new Adw.HeaderBar();
			var host_name = connection.name;
			if (host_name == "" && connection.addresses.length > 0) {
				host_name = connection.addresses[0];
			}
			if (host_name == "") {
				host_name = "Argus RM";
			}
			var content_title = new Gtk.Label(host_name + " - " + tabs.titles[0]) {
				css_classes = { "title" }
			};
			this.content_header.title_widget = content_title;
			this.content_bar = new Adw.ToolbarView() {
				vexpand = true,
				hexpand = true
			};
			this.content_bar.add_top_bar(this.content_header);
			var pages = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.CROSSFADE
			};
			this.content_bar.content = pages;
			var agent = new Tab.Agent(this);
			var repository = new Tab.Repository(this);
			for (var i = 0; i < tabs.keys.length; i++) {
				var key = tabs.keys[i];
				if (key == "agents") {
					pages.add_named(agent, key);
					continue;
				}
				if (key == "repositories") {
					pages.add_named(repository, key);
					continue;
				}
				if (key == "assets") {
					pages.add_named(new Tab.Assets(this), key);
					continue;
				}
				pages.add_named(new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true
				}, key);
			}
			pages.add_named(new Tab.Settings(this), "settings");
			var sidebar_page = new Adw.NavigationPage(sidebar_bar, "Argus RM");
			var content_page = new Adw.NavigationPage(this.content_bar, content_title.label);
			tabs.chosen.connect((key, title) => {
				pages.visible_child_name = key;
				content_title.label = host_name + " - " + title;
				content_page.title = content_title.label;
			});
			pages.visible_child_name = tabs.keys[0];
			var split = new Adw.NavigationSplitView() {
				sidebar = sidebar_page,
				content = content_page,
				min_sidebar_width = 200,
				max_sidebar_width = 280,
				hexpand = true,
				vexpand = true
			};
			this.content = split;
			this.close_request.connect(() => {
				this.closed = true;
				if (this.connection_check_id != 0) {
					GLib.Source.remove(this.connection_check_id);
					this.connection_check_id = 0;
				}
				if (this.leaving) {
					return false;
				}
				this.app.quit();
				return false;
			});
			this.connection_check_id = GLib.Timeout.add_seconds(1, this.check_connection);
		}

		/**
		 * Show whether the server connection is open, and open it
		 * again after it drops.
		 *
		 * This runs once a second and sets the sidebar title.
		 * A failed open waits thirty seconds before the next try.
		 *
		 * @return true while this window is open
		 */
		private bool check_connection()
		{
			if (this.closed) {
				this.connection_check_id = 0;
				return false;
			}
			var rpc = this.app.rpc;
			var connected = rpc != null && rpc.connected;
			if (connected) {
				this.title_label.label = "Argus RM";
				this.title_label.css_classes = { "title" };
			} else {
				this.title_label.label = "Offline";
				this.title_label.css_classes = { "title", "offline-title" };
			}
			if (connected || rpc == null || this.reconnecting) {
				if (connected) {
					this.was_connected = true;
				}
				return true;
			}
			var now = GLib.get_monotonic_time();
			if (!this.was_connected && now < this.next_reconnect) {
				return true;
			}
			this.was_connected = false;
			/* Monotonic time is microseconds. Try the connection again in 30 seconds. */
			this.next_reconnect = now + (int64) 30 * 1000000;
			this.reconnecting = true;
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("is", 1, "argus-controller")
			}, null, (obj, res) => {
				this.reconnecting = false;
				if (this.closed) {
					return;
				}
				try {
					rpc.connect.end(res);
				} catch (GLib.Error e) {
					GLib.debug("%s", e.message);
				}
			});
			return true;
		}
	}
}
