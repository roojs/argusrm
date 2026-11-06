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
	 * The title is ''Argus remote manager''. A cog on the left opens
	 * the menu. The centre says the server is connected.
	 * ''Deregister this controller'' calls
	 * {@link Argus.Shared.Registration.Data.deregister}. OK after
	 * deletion quits.
	 * ''Register agent'' and ''Register controller'' open
	 * {@link PairingDialog}.
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
		private GLib.SimpleAction deregister_action;
		private PairingDialog pairing_dialog;

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
			this.title = "Argus remote manager";
			this.set_default_size(960, 640);
			var header = new Adw.HeaderBar();
			var menu = new GLib.Menu();
			menu.append("Deregister this controller", "win.deregister");
			menu.append("Register agent", "win.register('Agent')");
			menu.append("Register controller", "win.register('Controller')");
			var cog = new Gtk.MenuButton() {
				icon_name = "emblem-system-symbolic",
				menu_model = menu,
				tooltip_text = "Menu"
			};
			header.pack_start(cog);
			this.pairing_dialog = new PairingDialog(this);
			var actions = new GLib.SimpleActionGroup();
			this.deregister_action = new GLib.SimpleAction("deregister", null);
			this.deregister_action.activate.connect(() => {
				this.deregister_action.set_enabled(false);
				this.issued.deregister(this, this.app.rpc);
			});
			var register_action = new GLib.SimpleAction("register", GLib.VariantType.STRING);
			register_action.activate.connect((parameter) => {
				if (parameter == null || this.pairing_dialog.pairing) {
					return;
				}
				this.pairing_dialog.open(parameter.get_string());
			});
			actions.add_action(this.deregister_action);
			actions.add_action(register_action);
			this.insert_action_group("win", actions);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = new Gtk.Label("connected to Argus server") {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				hexpand = true,
				vexpand = true,
				css_classes = { "title-1" }
			};
			this.content = toolbar;
			this.close_request.connect(() => {
				this.app.quit();
				return false;
			});
		}
	}
}
