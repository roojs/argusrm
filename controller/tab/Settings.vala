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
	 * that row offers deregister and disconnect. Its subtitle says
	 * to press and hold. Holding turns the row red and runs a bar
	 * along the bottom for two seconds. Letting go early clears
	 * the bar. Holding for those two seconds closes this window
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
				servers.description = "The saved connections could not be read.";
			}
			var listed = false;
			for (var i = 0; i < saved.rows.size; i++) {
				if (saved.rows.get(i).name == this.window.connection.name &&
					this.window.connection.name != "") {
					listed = true;
					break;
				}
			}
			if (!listed) {
				saved.rows.insert(0, this.window.connection);
			}
			for (var i = 0; i < saved.rows.size; i++) {
				var row = saved.rows.get(i);
				if (row.name == "" && row != this.window.connection) {
					continue;
				}
				var server_name = row.name;
				var open = server_name != "" &&
					server_name == this.window.connection.name;
				if (row == this.window.connection) {
					open = true;
				}
				var title = server_name;
				if (title == "" && row.addresses.length > 0) {
					title = row.addresses[0];
				}
				if (title == "") {
					title = "Server";
				}
				var server = new Adw.ExpanderRow() {
					title = title
				};
				if (row.addresses.length > 0) {
					server.subtitle = string.joinv(", ", row.addresses);
				}
				if (open) {
					server.add_prefix(new Gtk.Label("●") {
						valign = Gtk.Align.CENTER,
						css_classes = { "server-current" }
					});
					var disconnect = new Adw.ActionRow() {
						title = "Deregister and disconnect",
						subtitle = "Press and hold to disconnect",
						activatable = false,
						hexpand = true
					};
					disconnect.add_prefix(
						new Gtk.Image.from_icon_name("system-log-out-symbolic"));
					var bar = new Gtk.ProgressBar() {
						valign = Gtk.Align.END,
						hexpand = true,
						fraction = 0,
						visible = false,
						can_target = false,
						css_classes = { "hold-bar" }
					};
					var hold_row = new Gtk.Overlay() {
						child = disconnect,
						hexpand = true,
						css_classes = { "hold-disconnect" }
					};
					hold_row.add_overlay(bar);
					var holding = false;
					var finished = false;
					var started = (int64) 0;
					var countdown = new Adw.CallbackAnimationTarget((value) => {
						bar.fraction = value;
					});
					var animation = new Adw.TimedAnimation(
						hold_row, 1, 0, 2000, countdown) {
						easing = Adw.Easing.LINEAR,
						follow_enable_animations_setting = false
					};
					hold_row.map.connect(() => {
						if (hold_row.parent == null) {
							return;
						}
						hold_row.parent.add_css_class("hold-disconnect");
					});
					animation.done.connect(() => {
						if (!holding) {
							return;
						}
						/* A skipped animation finishes at once. */
						if (GLib.get_monotonic_time() - started < (int64) 1800 * 1000) {
							holding = false;
							animation.reset();
							bar.fraction = 0;
							bar.visible = false;
							hold_row.remove_css_class("holding");
							if (hold_row.parent != null) {
								hold_row.parent.remove_css_class("holding");
							}
							return;
						}
						holding = false;
						finished = true;
						this.window.app.running_window = false;
						this.window.leaving = true;
						this.window.app.rpc.disconnect();
						this.window.close();
						new Dialog.Bootstrap(this.window.app, "choose").present(null);
					});
					var hold = new Gtk.EventControllerLegacy();
					hold.event.connect((event) => {
						var start = false;
						var stop = false;
						switch (event.get_event_type()) {
						case Gdk.EventType.BUTTON_PRESS:
							if (event.triggers_context_menu()) {
								return false;
							}
							start = true;
							break;
						case Gdk.EventType.TOUCH_BEGIN:
							start = true;
							break;
						case Gdk.EventType.BUTTON_RELEASE:
						case Gdk.EventType.TOUCH_END:
						case Gdk.EventType.TOUCH_CANCEL:
							stop = true;
							break;
						default:
							break;
						}
						if (!start && !stop) {
							return false;
						}
						if (finished) {
							return true;
						}
						if (start) {
							if (holding) {
								return true;
							}
							holding = true;
							started = GLib.get_monotonic_time();
							hold_row.add_css_class("holding");
							if (hold_row.parent != null) {
								hold_row.parent.add_css_class("holding");
							}
							bar.visible = true;
							bar.fraction = 1;
							animation.play();
							return true;
						}
						if (!holding) {
							return true;
						}
						holding = false;
						animation.reset();
						bar.fraction = 0;
						bar.visible = false;
						hold_row.remove_css_class("holding");
						if (hold_row.parent != null) {
							hold_row.parent.remove_css_class("holding");
						}
						return true;
					});
					var motion = new Gtk.EventControllerMotion();
					motion.leave.connect(() => {
						if (finished || !holding) {
							return;
						}
						holding = false;
						animation.reset();
						bar.fraction = 0;
						bar.visible = false;
						hold_row.remove_css_class("holding");
						if (hold_row.parent != null) {
							hold_row.parent.remove_css_class("holding");
						}
					});
					hold_row.add_controller(hold);
					hold_row.add_controller(motion);
					server.add_row(hold_row);
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
