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
		private class Step : GLib.Object
		{
			public Argus.Rdp.State state;
			public int attempt;

			public Step(Argus.Rdp.State state, int attempt)
			{
				this.state = state;
				this.attempt = attempt;
			}
		}

		public Argus.Controller.Window window { get; construct; }
		private Gtk.Stack pictures;
		private Gtk.Box tabs;
		private Adw.ToastOverlay toasts;
		private Adw.Toast step_toast;
		internal Gee.HashMap<int, Argus.Controller.Rdp.Screen> screens {
			get; set; default = new Gee.HashMap<int, Argus.Controller.Rdp.Screen>();
		}
		private Gee.HashMap<int, Gtk.Label> status {
			get; set; default = new Gee.HashMap<int, Gtk.Label>();
		}
		private Gee.HashMap<int, Gee.ArrayList<Step>> pending {
			get; set; default = new Gee.HashMap<int, Gee.ArrayList<Step>>();
		}
		internal Gee.HashSet<int> armed {
			get; set; default = new Gee.HashSet<int>();
		}
		private Gee.HashSet<int> ready {
			get; set; default = new Gee.HashSet<int>();
		}
		private Gee.HashMap<int, string> ticket_invites {
			get; set; default = new Gee.HashMap<int, string>();
		}
		private Gee.HashMap<int, string> ticket_passwords {
			get; set; default = new Gee.HashMap<int, string>();
		}

		/**
		 * Build the picture stack and the tab bar.
		 *
		 * @param window the window this page belongs to
		 */
		public Rdp(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				hexpand: true,
				vexpand: true,
				window: window
			);
			this.pictures = new Gtk.Stack() {
				hexpand = true,
				vexpand = true
			};
			this.tabs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				css_classes = { "rdp-tabs" },
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			column.append(this.pictures);
			column.append(this.tabs);
			this.toasts = new Adw.ToastOverlay() {
				child = column,
				hexpand = true,
				vexpand = true
			};
			this.step_toast = new Adw.Toast("") {
				timeout = 5
			};
			this.append(this.toasts);
			this.window.app.rpc.notification.connect((notification) => {
				if (notification.method == "relay.status" && notification.args.size >= 3) {
					var agent_id = notification.args.get(0).get_int();
					var state = (Argus.Rdp.State) notification.args.get(1).get_int();
					var attempt = notification.args.get(2).get_int();
					this.toast(agent_id, state, attempt);
					return;
				}
				if (notification.method == "relay.ticket" && notification.args.size >= 3) {
					var ticket_id = notification.args.get(0).get_int();
					var invite = notification.args.get(1).get_string();
					var password = notification.args.get(2).get_string();
					if (this.screens.has_key(ticket_id)) {
						var target = this.screens.get(ticket_id);
						target.invite = invite;
						target.ticket_pass = password;
					}
					if (this.armed.contains(ticket_id) || this.screens.has_key(ticket_id)) {
						this.ticket_invites.set(ticket_id, invite);
						this.ticket_passwords.set(ticket_id, password);
					}
					return;
				}
				if (notification.method != "relay.ready" || notification.args.size < 1) {
					return;
				}
				var id = notification.args.get(0).get_int();
				if (!this.screens.has_key(id)) {
					if (!this.armed.contains(id)) {
						return;
					}
					this.ready.add(id);
					return;
				}
				var screen = this.screens.get(id);
				if (screen.started) {
					return;
				}
				if (this.ticket_invites.has_key(id)) {
					screen.invite = this.ticket_invites.get(id);
					screen.ticket_pass = this.ticket_passwords.get(id);
				}
				screen.started = true;
				screen.begin();
				var label = this.status.get(id);
				if (label != null && screen.problem != "") {
					label.label = screen.problem;
					label.visible = true;
				}
			});
		}

		/**
		 * Drop steps that arrived before the page opened.
		 *
		 * An open page is left as it is.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void forget(int agent_id)
		{
			this.pending.unset(agent_id);
			this.ready.remove(agent_id);
			this.ticket_invites.unset(agent_id);
			this.ticket_passwords.unset(agent_id);
			if (this.screens.has_key(agent_id)) {
				return;
			}
			this.armed.remove(agent_id);
		}

		/**
		 * Show this step, and leave it on the waiting label.
		 *
		 * The sentence is {@link Argus.Rdp.State.line}. That sentence
		 * replaces the toast already on screen. The toast hides itself
		 * a few seconds after the latest step. The log line is that
		 * same sentence. A step that arrives before {@link open} waits.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 * @param state the step
		 * @param attempt zero the first time, then the retry count
		 */
		public void toast(int agent_id, Argus.Rdp.State state, int attempt)
		{
			if (!this.screens.has_key(agent_id)) {
				if (!this.armed.contains(agent_id)) {
					return;
				}
				if (!this.pending.has_key(agent_id)) {
					this.pending.set(agent_id, new Gee.ArrayList<Step>());
				}
				this.pending.get(agent_id).add(new Step(state, attempt));
				return;
			}
			var text = state.line(attempt);
			this.step_toast.title = text;
			// add_toast takes this reference. The field keeps its own.
			var toast = this.step_toast;
			this.toasts.add_toast(toast);
			GLib.debug("relay.status %s %d", state.to_string(), attempt);
			var label = this.status.get(agent_id);
			if (label == null) {
				return;
			}
			if (state == Argus.Rdp.State.SUCCESS_DESKTOP_RENDERED) {
				label.visible = false;
				return;
			}
			label.label = text;
			label.visible = true;
		}

		/**
		 * Select this machine, or add its tab.
		 *
		 * @param agent_id ''agent.id'' of the machine
		 * @param name tab title
		 */
		public void open(int agent_id, string name)
		{
			this.armed.add(agent_id);
			var key = agent_id.to_string();
			if (this.screens.has_key(agent_id)) {
				var existing = this.tabs.get_first_child();
				while (existing != null) {
					if (existing.name != key) {
						existing = existing.get_next_sibling();
						continue;
					}
					var button = existing.get_first_child() as Gtk.ToggleButton;
					if (button != null) {
						button.active = true;
					}
					if (this.pending.has_key(agent_id)) {
						var list = this.pending.get(agent_id);
						this.pending.unset(agent_id);
						foreach (var step in list) {
							this.toast(agent_id, step.state, step.attempt);
						}
					}
					return;
				}
				return;
			}
			var screen = new Argus.Controller.Rdp.Screen(this.window, agent_id);
			if (this.ticket_invites.has_key(agent_id)) {
				screen.invite = this.ticket_invites.get(agent_id);
				screen.ticket_pass = this.ticket_passwords.get(agent_id);
			}
			this.screens.set(agent_id, screen);
			var waiting = new Gtk.Label("Waiting for Remote Desktop on " + name + ".") {
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				margin_start = 24,
				margin_end = 24
			};
			this.status.set(agent_id, waiting);
			screen.notify["problem"].connect(() => {
				if (screen.problem == "") {
					return;
				}
				waiting.label = screen.problem;
				waiting.visible = true;
			});
			var scroll = new Gtk.ScrolledWindow() {
				child = screen.picture,
				hexpand = true,
				vexpand = true
			};
			var overlay = new Gtk.Overlay() {
				child = scroll,
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(waiting);
			this.pictures.add_named(overlay, key);
			var select = new Gtk.ToggleButton() {
				child = new Gtk.Label(name),
				css_classes = { "flat", "rdp-tab-select" },
				valign = Gtk.Align.CENTER
			};
			var close = new Gtk.Button.from_icon_name("window-close-symbolic") {
				css_classes = { "flat", "rdp-tab-close" },
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.CENTER
			};
			close.clicked.connect(() => {
				this.drop(agent_id);
			});
			var tab = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2) {
				name = key,
				css_classes = { "rdp-tab" },
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER
			};
			tab.append(select);
			tab.append(close);
			select.toggled.connect(() => {
				if (!select.active) {
					tab.remove_css_class("active");
					return;
				}
				tab.add_css_class("active");
				this.pictures.visible_child_name = key;
				var other = this.tabs.get_first_child();
				while (other != null) {
					if (other != tab) {
						var other_select = other.get_first_child() as Gtk.ToggleButton;
						if (other_select != null) {
							other_select.active = false;
						}
						other.remove_css_class("active");
					}
					other = other.get_next_sibling();
				}
			});
			this.tabs.append(tab);
			select.active = true;
			if (this.pending.has_key(agent_id)) {
				var list = this.pending.get(agent_id);
				this.pending.unset(agent_id);
				foreach (var step in list) {
					this.toast(agent_id, step.state, step.attempt);
				}
			}
			if (!this.ready.contains(agent_id)) {
				return;
			}
			this.ready.remove(agent_id);
			if (screen.started) {
				return;
			}
			screen.started = true;
			screen.begin();
			var label = this.status.get(agent_id);
			if (label == null || screen.problem == "") {
				return;
			}
			label.label = screen.problem;
			label.visible = true;
		}

		/**
		 * Remove one machine's tab.
		 *
		 * The local picture stops and ''Relay.stop'' tells the server
		 * to end the Windows sharing session. The X on the tab calls
		 * this. The last tab hides the RDP row.
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
			this.status.unset(agent_id);
			this.pending.unset(agent_id);
			this.ready.remove(agent_id);
			this.armed.remove(agent_id);
			this.ticket_invites.unset(agent_id);
			this.ticket_passwords.unset(agent_id);
			screen.stop();
			this.window.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Relay.stop",
				args = OLLMrpc.args("i", agent_id)
			}, (obj, res) => {
				try {
					this.window.app.rpc.call.end(res);
				} catch (GLib.Error e) {
					GLib.debug("%s", e.message);
				}
			});
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
				var remaining = this.tabs.get_first_child();
				var first_select = remaining != null ? remaining.get_first_child() as Gtk.ToggleButton : null;
				if (first_select != null && this.pictures.visible_child == null) {
					first_select.active = true;
				}
				return;
			}
			this.window.tabs.hide_rdp();
		}
	}
}
