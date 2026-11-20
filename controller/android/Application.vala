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
	 * Android controller application.
	 *
	 * Same public surface as desktop {@link Application} so shared
	 * tabs and dialogs compile unchanged. Waits for Android
	 * {@link GLib.Application.activate} from ''ToplevelActivity'',
	 * configures the Adwaita icon theme and CSS, presents {@link Window},
	 * and opens {@link Dialog.Bootstrap}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var app = new Argus.Controller.Application();
	 * return app.run(args);
	 * }}}
	 */
	public class Application : Adw.Application
	{
		public static string agent = "";
		public static string command = "";
		public OLLMrpc.Client rpc { get; set; }
		/**
		 * Local ''server.sqlite'' for this process.
		 */
		public SQ.Database client_db { get; private set; }
		/**
		 * Main window opened after a connection answers.
		 */
		public Window window { get; set; }
		/**
		 * True while {@link Window} is on screen.
		 */
		public bool running_window = false;
		private static GLib.FileStream? debug_log_file;
		private static bool debug_log_in_progress;

		/**
		 * Create the Android controller application and wire activate.
		 */
		public Application()
		{
			Object(
				application_id: "org.roojs.ArgusController",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS
			);
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				if (debug_log_in_progress) {
					return;
				}
				var timestamp = (new GLib.DateTime.now_local()).format("%H:%M:%S.%f");
				var shown_domain = dom == null ? "" : dom;
				if ((lvl & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0) {
					GLib.stderr.printf("%s: %s : %s : %s\n",
						timestamp, lvl.to_string(), shown_domain, msg);
				}
				debug_log_in_progress = true;
				if (debug_log_file == null) {
					var log_dir = GLib.Path.build_filename(
						GLib.Environment.get_user_config_dir(), "argusrm");
					var log_file_path = GLib.Path.build_filename(log_dir, "controller.log");
					if (!GLib.FileUtils.test(log_dir, GLib.FileTest.IS_DIR)) {
						GLib.DirUtils.create_with_parents(log_dir, 0755);
					}
					debug_log_file = GLib.FileStream.open(log_file_path, "w");
				}
				if (debug_log_file != null) {
					debug_log_file.puts(timestamp + ": " + lvl.to_string() + " : " + msg + "\n");
					debug_log_file.flush();
				}
				debug_log_in_progress = false;
			});
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm");
			if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
				GLib.warning("Could not create the configuration directory");
			} else {
				var path = GLib.Path.build_filename(dir, "server.sqlite");
				this.client_db = new SQ.Database(path, true);
				Argus.Shared.SQT.Server.init_db(this.client_db);
			}
			this.shutdown.connect(() => {
				if (this.client_db != null) {
					this.client_db.backup_real();
				}
			});
			this.activate.connect(() => {
				OLLMrpc.rpc_register();
				Argus.Shared.Agent.rpc_register();
				Argus.Shared.OSQuery.rpc_register();
				Argus.Shared.OsReleases.rpc_register();
				Argus.Shared.SQT.rpc_register();
				Argus.Shared.SQV.rpc_register();
				Argus.Controller.Command.rpc_register();
				Gtk.Settings.get_default().gtk_icon_theme_name = "Adwaita";
				var screen = Gdk.Display.get_default();
				if (screen != null) {
					var css = new Gtk.CssProvider();
					css.load_from_resource("/argusrm/style.css");
					Gtk.StyleContext.add_provider_for_display(
						screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
					Gtk.IconTheme.get_for_display(screen).add_resource_path("/argusrm/icons");
				}
				Gtk.Window.set_default_icon_name("org.roojs.ArgusController");
				this.window = new Window(this);
				this.window.present();
				var bootstrap = new Dialog.Bootstrap(this);
				bootstrap.present(this.window);
			});
		}
	}
}
