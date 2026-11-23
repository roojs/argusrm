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
	 * are blank. Agent / Controllers and Settings stay at the
	 * bottom of the list.
	 * The open server's row is ''Deregister and disconnect''.
	 * Holding it for two seconds closes this window and returns
	 * to the startup check.
	 * ''Agent or Controller'' is on the Agent / Controllers page.
	 * It opens {@link Dialog.Pairing}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var window = new Argus.Controller.Window(app, server, host);
	 * window.present();
	 * }}}
	 */
	public class Window : Adw.Window
	{
		public Application app;
		public Argus.Controller.SQT.Server server {
			get; set; default = new Argus.Controller.SQT.Server();
		}
		private Argus.Shared.Register registration {
			get; set; default = new Argus.Shared.Register();
		}
		public string host { get; set; default = ""; }
		/**
		 * Sidebar places for this window.
		 */
		public TabList tabs;
		private Gtk.Stack pages;
		/**
		 * Remote desktop page for this window.
		 */
		public Tab.Rdp rdp;
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
		private bool told_offline = false;
		private bool told_wait = false;
		private bool closed = false;
		private int64 next_reconnect = 0;

		/**
		 * Create the window for one server.
		 *
		 * Closing it quits the controller.
		 *
		 * @param app the controller process
		 * @param server saved management-server row for this window
		 * @param host address that answered the startup probe
		 */
		public Window(
			Application app,
			Argus.Controller.SQT.Server server,
			string host
		) {
			this.app = app;
			this.server = server;
			this.host = host;
			this.title = "Argus RM " + Argus.VERSION;
			this.set_default_size(960, 640);
			var header = new Adw.HeaderBar();
			this.title_label = new Gtk.Label("Argus RM " + Argus.VERSION) {
				css_classes = { "title" }
			};
			header.title_widget = this.title_label;
			var logo = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				width_request = 34,
				height_request = 34,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			logo.append(new Gtk.Image() {
				icon_name = "org.roojs.ArgusController",
				pixel_size = 24,
				hexpand = true,
				vexpand = true,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			});
			header.pack_start(logo);
			header.pack_end(new About());
			this.pairing_dialog = new Dialog.Pairing(this);
			var actions = new GLib.SimpleActionGroup();
			this.deregister_action = new GLib.SimpleAction("deregister", null);
			this.registration.remove_failed.connect((message) => {
				this.deregister_action.set_enabled(true);
				var failed = new Argus.Shared.Notice("Could not deregister", message);
				failed.add_response("ok", "OK");
				failed.present(this);
			});
			this.registration.remove_server_unreachable.connect((message) => {
				this.deregister_action.set_enabled(true);
				var down = new Argus.Shared.Notice("Could not deregister", message);
				down.add_response("cancel", "Cancel");
				down.add_response("local", "Deregister locally");
				down.responded.connect((response) => {
					if (response != "local") {
						return;
					}
					this.deregister_action.set_enabled(false);
					this.registration.client_db = this.app.client_db;
					this.registration.remove_local(this.server);
				});
				down.present(this);
			});
			this.registration.remove_row_deleted.connect(() => {
				var done = new Argus.Shared.Notice("Deleted okay", "");
				done.add_response("ok", "OK");
				done.closed.connect(() => {
					this.app.quit();
				});
				done.present(this);
			});
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.registration.client_db = this.app.client_db;
				this.registration.remove(this.server, this.app.rpc);
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
			this.tabs = new TabList();
			var tabs = this.tabs;
			sidebar_bar.content = tabs;
			this.content_header = new Adw.HeaderBar();
			var host_name = server.title;
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
			this.pages = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.CROSSFADE
			};
			var pages = this.pages;
			this.content_bar.content = pages;
			var repository = new Tab.Repository(this);
			for (var i = 0; i < tabs.keys.length; i++) {
				var key = tabs.keys[i];
				if (key == "dashboard") {
					pages.add_named(new Tab.Dashboard(this), key);
					continue;
				}
				if (key == "repositories") {
					pages.add_named(repository, key);
					continue;
				}
				if (key == "distributables") {
					pages.add_named(new Tab.Distributables(this), key);
					continue;
				}
				if (key == "assets") {
					pages.add_named(new Tab.Assets(this), key);
					continue;
				}
				if (key == "tasks") {
					pages.add_named(new Tab.Tasks(this), key);
					continue;
				}
				pages.add_named(new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
					hexpand = true,
					vexpand = true
				}, key);
			}
			pages.add_named(new Tab.Agent(this), "agents");
			pages.add_named(new Tab.Settings(this), "settings");
			this.rdp = new Tab.Rdp(this);
			pages.add_named(this.rdp, "rdp");
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
			this.app.rpc.notification.connect((notification) => {
				if (notification.method != "event.osquery") {
					return;
				}
				if (notification.args.size < 1 || notification.action == "") {
					return;
				}
				this.app.db_changed(
					notification.action,
					notification.args.get(0).get_int());
			});
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
				this.title_label.label = "Argus RM " + Argus.VERSION;
				this.title_label.css_classes = { "title" };
				if (this.told_offline) {
					foreach (var agent_id in this.rdp.screens.keys) {
						this.rdp.note(agent_id, Argus.Rdp.State.SUCCESS_SERVER_RECONNECTED, 0);
					}
					this.told_offline = false;
					this.told_wait = false;
				}
			} else {
				this.title_label.label = "Offline";
				this.title_label.css_classes = { "title", "offline-title" };
				if (!this.told_offline) {
					foreach (var agent_id in this.rdp.screens.keys) {
						this.rdp.note(agent_id, Argus.Rdp.State.RETRY_SERVER_DISCONNECTED, 1);
					}
					this.told_offline = true;
				}
			}
			if (connected || rpc == null || this.reconnecting) {
				if (connected) {
					this.was_connected = true;
				}
				return true;
			}
			var now = GLib.get_monotonic_time();
			if (!this.was_connected && now < this.next_reconnect) {
				if (!this.told_wait) {
					foreach (var agent_id in this.rdp.screens.keys) {
						this.rdp.note(agent_id, Argus.Rdp.State.RETRY_SERVER_CONNECT_REFUSED, 1);
					}
					this.told_wait = true;
				}
				return true;
			}
			this.told_wait = false;
			this.was_connected = false;
			/* Monotonic time is microseconds. Try the connection again in 30 seconds. */
			this.next_reconnect = now + (int64) 30 * 1000000;
			this.reconnecting = true;
			rpc.disconnect();
			rpc.connect.begin(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "argus-controller", Argus.VERSION)
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
