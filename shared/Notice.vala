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
	 * Standard message dialog for the agent.
	 *
	 * Same size and chrome as {@link RegisterWindow}: 480×280, a
	 * close-only header, a centred heading and body, then action
	 * buttons. The elevation prompt and the already-registered
	 * prompt use this instead of {@link Adw.AlertDialog}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var notice = new Argus.Shared.Notice(
	 *     "This application needs to run as admin",
	 *     "You will be prompted to escalate privileges.");
	 * notice.add_response("ok", "OK");
	 * notice.responded.connect((response) => {
	 *     // ok
	 * });
	 * notice.present(null);
	 * }}}
	 */
	public class Notice : Adw.Dialog
	{
		/**
		 * A button was pressed.
		 *
		 * @param response id passed to {@link add_response}
		 */
		public signal void responded(string response);

		private static bool styled = false;
		private Gtk.Box actions;

		/**
		 * Draw an edge on a dialog.
		 *
		 * A dialog presented over another dialog uses the same
		 * background, so the edge is the only outline.
		 *
		 * @param dialog the dialog to outline
		 */
		public static void edge(Adw.Dialog dialog)
		{
			dialog.add_css_class("argus-dialog");
			if (Notice.styled) {
				return;
			}
			var display = Gdk.Display.get_default();
			if (display == null) {
				return;
			}
			Notice.styled = true;
			var css = new Gtk.CssProvider();
			css.load_from_string(
				"dialog.argus-dialog {" +
				" background-color: @card_bg_color;" +
				" border: 1px solid @borders;" +
				" }");
			Gtk.StyleContext.add_provider_for_display(
				display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		}

		/**
		 * Create the dialog.
		 *
		 * @param heading large centred title
		 * @param body dim text under the heading, or empty
		 */
		public Notice(string heading, string body)
		{
			Notice.edge(this);
			this.title = heading;
			this.set_content_height(280);
			this.set_content_width(480);

			var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false,
				show_title = false
			};
			var close_button =
				new Gtk.Button.from_icon_name("window-close-symbolic") {
					tooltip_text = "Close",
					css_classes = {"flat"}
				};
			close_button.clicked.connect(() => {
				this.close();
			});
			header.pack_end(close_button);
			content.append(header);

			var body_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 24,
				margin_bottom = 24,
				margin_start = 24,
				margin_end = 24,
				valign = Gtk.Align.CENTER,
				vexpand = true
			};
			var heading_label = new Gtk.Label(heading) {
				wrap = true,
				xalign = 0.5f,
				justify = Gtk.Justification.CENTER,
				css_classes = {"title-2"}
			};
			body_box.append(heading_label);
			if (body != "") {
				var body_label = new Gtk.Label(body) {
					wrap = true,
					xalign = 0.5f,
					justify = Gtk.Justification.CENTER,
					css_classes = {"dim-label"}
				};
				body_box.append(body_label);
			}
			this.actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.CENTER,
				margin_top = 12
			};
			body_box.append(this.actions);
			content.append(body_box);
			this.set_child(content);
		}

		/**
		 * Add a button. The last one is the suggested action.
		 *
		 * @param response id emitted on {@link responded}
		 * @param label button text
		 */
		public void add_response(string response, string label)
		{
			var child = this.actions.get_first_child();
			while (child != null) {
				child.remove_css_class("suggested-action");
				child = child.get_next_sibling();
			}
			var button = new Gtk.Button.with_label(label) {
				width_request = 120,
				css_classes = {"suggested-action"}
			};
			button.clicked.connect(() => {
				this.responded(response);
				this.close();
			});
			this.actions.append(button);
		}
	}
}
