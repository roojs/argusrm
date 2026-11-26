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

namespace Argus.Controller.Rdp
{
	/**
	 * One machine's picture.
	 *
	 * FreeRDP dials the loopback port {@link Viewer} is reading.
	 * {@link begin} runs after ''relay.ready''. The password
	 * dialog is FreeRDP's authenticate callback.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var screen = new Argus.Controller.Rdp.Screen(window, 4);
	 * screen.begin();
	 * }}}
	 */
	public class Screen : GLib.Object
	{
		/**
		 * The picture for this machine.
		 *
		 * It stays at the desktop's pixel size. The remote desktop
		 * page scrolls it when that is larger than the view.
		 */
		public Gtk.Picture picture { get; private set; }
		/**
		 * True after ''relay.ready'' has started this picture.
		 */
		public bool started = false;
		/**
		 * Why this picture did not start. Empty while it is waiting
		 * or showing the desktop.
		 */
		public string problem { get; set; default = ""; }
		private bool stopping = false;
		private bool rendered = false;
		private GLib.Mutex paint_lock;
		private bool painting = false;
		private uint8[] latest = new uint8[0];
		private int latest_width;
		private int latest_height;
		private int latest_stride;
		private static Gee.ArrayList<Screen> live = new Gee.ArrayList<Screen>();
		private Argus.Controller.Window window;
		private int agent_id;
		private FreeRDP.Instance? instance;
		private string user = "";
		private string pass = "";

		/**
		 * @param window the window that owns the certificate
		 * @param agent_id ''agent.id'' of the machine
		 */
		public Screen(Argus.Controller.Window window, int agent_id)
		{
			this.window = window;
			this.agent_id = agent_id;
			this.picture = new Gtk.Picture() {
				can_shrink = false,
				content_fit = Gtk.ContentFit.SCALE_DOWN,
				halign = Gtk.Align.START,
				valign = Gtk.Align.START
			};
		}

		/**
		 * Open the splice and run FreeRDP on its own thread.
		 */
		public void begin()
		{
			this.window.rdp.toast(
				this.agent_id, Argus.Rdp.State.REQUEST_CONTROLLER_JOIN_RELAY, 0);
			GLib.TlsCertificate certificate;
			GLib.TlsDatabase trust;
			try {
				certificate = this.window.server.tls_certificate();
#if ANDROID
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(), "argusrm");
#else
				var dir = GLib.Environment.get_user_runtime_dir();
#endif
				trust = GLib.TlsFileDatabase.new(
					GLib.Path.build_filename(dir, "argusrm-ca.pem"));
			} catch (GLib.Error e) {
				GLib.debug("%s", e.message);
				this.problem = Argus.Rdp.State.FAIL_PREPARE_RENDER.to_string();
				this.window.rdp.toast(this.agent_id, Argus.Rdp.State.FAIL_PREPARE_RENDER, 0);
				return;
			}
			var viewer = new Viewer();
			viewer.failed.connect((message) => {
				GLib.debug("%s", message);
				this.window.rdp.toast(
					this.agent_id, Argus.Rdp.State.RETRY_CONTROLLER_JOIN_RELAY, 1);
			});
			try {
				viewer.serve(
					this.window.host,
					(uint16) this.window.server.port,
					certificate,
					trust,
					this.agent_id);
			} catch (GLib.Error e) {
				GLib.debug("%s", e.message);
				this.problem = Argus.Rdp.State.FAIL_PREPARE_RENDER.to_string();
				this.window.rdp.toast(this.agent_id, Argus.Rdp.State.FAIL_PREPARE_RENDER, 0);
				return;
			}
			this.window.rdp.toast(
				this.agent_id, Argus.Rdp.State.REQUEST_RENDER_DESKTOP, 0);
			this.instance = new FreeRDP.Instance();
			if (!this.instance.context_new()) {
				this.problem = Argus.Rdp.State.FAIL_PREPARE_RENDER.to_string();
				this.window.rdp.toast(this.agent_id, Argus.Rdp.State.FAIL_PREPARE_RENDER, 0);
				return;
			}
			this.instance.PostConnect = Screen.connected;
			this.instance.Authenticate = Screen.authenticate;
			this.instance.VerifyCertificateEx = Screen.verify;
			Screen.live.add(this);
			var width = this.picture.get_width();
			var height = this.picture.get_height();
			if (width < 64) {
				width = 1280;
			}
			if (height < 64) {
				height = 720;
			}
			unowned FreeRDP.Settings settings = this.instance.context.settings;
			settings.set_string(FreeRDP.SettingsString.ServerHostname, "127.0.0.1");
			settings.set_uint32(FreeRDP.SettingsUint32.ServerPort, viewer.view_port);
			settings.set_uint32(FreeRDP.SettingsUint32.DesktopWidth, width);
			settings.set_uint32(FreeRDP.SettingsUint32.DesktopHeight, height);
			settings.set_uint32(FreeRDP.SettingsUint32.ColorDepth, 32);
			settings.set_bool(FreeRDP.SettingsBool.BitmapCacheEnabled, true);
			settings.set_bool(FreeRDP.SettingsBool.BitmapCacheV3Enabled, true);
			settings.set_bool(FreeRDP.SettingsBool.RemoteFxCodec, true);
			settings.set_bool(FreeRDP.SettingsBool.NSCodec, true);
			settings.set_bool(FreeRDP.SettingsBool.SurfaceCommandsEnabled, true);
			settings.set_bool(FreeRDP.SettingsBool.SupportGraphicsPipeline, true);
			settings.set_bool(FreeRDP.SettingsBool.GfxH264, true);
			settings.set_bool(FreeRDP.SettingsBool.GfxAVC444, true);
			settings.set_bool(FreeRDP.SettingsBool.GfxAVC444v2, true);
			settings.set_bool(FreeRDP.SettingsBool.RedirectDrives, false);
			settings.set_bool(FreeRDP.SettingsBool.AudioPlayback, false);
			settings.set_bool(FreeRDP.SettingsBool.RedirectClipboard, false);
			var port = viewer.view_port;
			new GLib.Thread<int>("screen", () => {
				for (var attempt = 0; attempt < 3 && !this.stopping; attempt++) {
					if (attempt > 0) {
						GLib.Thread.usleep(500000);
						if (this.stopping || this.instance == null) {
							break;
						}
						this.instance.disconnect();
						FreeRDP.gdi_free(this.instance);
						this.instance.context_free();
						if (!this.instance.context_new()) {
							break;
						}
						this.instance.PostConnect = Screen.connected;
						this.instance.Authenticate = Screen.authenticate;
						this.instance.VerifyCertificateEx = Screen.verify;
						unowned FreeRDP.Settings again = this.instance.context.settings;
						again.set_string(FreeRDP.SettingsString.ServerHostname, "127.0.0.1");
						again.set_uint32(FreeRDP.SettingsUint32.ServerPort, port);
						again.set_uint32(FreeRDP.SettingsUint32.DesktopWidth, width);
						again.set_uint32(FreeRDP.SettingsUint32.DesktopHeight, height);
						again.set_uint32(FreeRDP.SettingsUint32.ColorDepth, 32);
						again.set_bool(FreeRDP.SettingsBool.BitmapCacheEnabled, true);
						again.set_bool(FreeRDP.SettingsBool.BitmapCacheV3Enabled, true);
						again.set_bool(FreeRDP.SettingsBool.RemoteFxCodec, true);
						again.set_bool(FreeRDP.SettingsBool.NSCodec, true);
						again.set_bool(FreeRDP.SettingsBool.SurfaceCommandsEnabled, true);
						again.set_bool(FreeRDP.SettingsBool.SupportGraphicsPipeline, true);
						again.set_bool(FreeRDP.SettingsBool.GfxH264, true);
						again.set_bool(FreeRDP.SettingsBool.GfxAVC444, true);
						again.set_bool(FreeRDP.SettingsBool.GfxAVC444v2, true);
						again.set_bool(FreeRDP.SettingsBool.RedirectDrives, false);
						again.set_bool(FreeRDP.SettingsBool.AudioPlayback, false);
						again.set_bool(FreeRDP.SettingsBool.RedirectClipboard, false);
					}
					if (!this.instance.connect()) {
						var shown = attempt + 1;
						GLib.Idle.add(() => {
							this.problem = Argus.Rdp.State.RETRY_RENDER_CONNECT.to_string();
							this.window.rdp.toast(
								this.agent_id, Argus.Rdp.State.RETRY_RENDER_CONNECT, shown);
							return false;
						});
						continue;
					}
					while (!this.stopping && !this.instance.shall_disconnect()) {
						if (!FreeRDP.check_event_handles(this.instance.context)) {
							break;
						}
						this.publish();
					}
					if (this.stopping) {
						break;
					}
					var dropped = attempt + 1;
					GLib.Idle.add(() => {
						this.window.rdp.toast(
							this.agent_id, Argus.Rdp.State.RETRY_DESKTOP_DISCONNECTED, dropped);
						return false;
					});
				}
				return 0;
			});
		}

		/**
		 * Stop this picture. {@link Argus.Controller.Tab.Rdp.drop}
		 * calls this.
		 */
		public void stop()
		{
			this.stopping = true;
			Screen.live.remove(this);
			if (this.instance == null) {
				return;
			}
			this.instance.disconnect();
			FreeRDP.gdi_free(this.instance);
			this.instance.context_free();
			this.instance = null;
		}

		/**
		 * Copy the current desktop into the picture.
		 *
		 * One copy is kept. A later event replaces it. The window
		 * paints that copy once.
		 */
		private void publish()
		{
			unowned FreeRDP.Gdi? gdi = this.instance.context.gdi;
			if (gdi == null || gdi.width < 1 || gdi.height < 1) {
				return;
			}
			var width = gdi.width;
			var height = gdi.height;
			var stride = (int) gdi.stride;
			var size = stride * height;
			this.paint_lock.lock();
			if (this.latest.length != size) {
				this.latest = new uint8[size];
			}
			GLib.Memory.copy((void*) this.latest, gdi.primary_buffer, size);
			this.latest_width = width;
			this.latest_height = height;
			this.latest_stride = stride;
			if (this.painting) {
				this.paint_lock.unlock();
				return;
			}
			this.painting = true;
			this.paint_lock.unlock();
			GLib.Idle.add(() => {
				this.paint_lock.lock();
				var copy = new uint8[this.latest.length];
				GLib.Memory.copy((void*) copy, this.latest, this.latest.length);
				var frame_width = this.latest_width;
				var frame_height = this.latest_height;
				var frame_stride = this.latest_stride;
				this.painting = false;
				this.paint_lock.unlock();
				if (this.stopping) {
					return false;
				}
				var bytes = new GLib.Bytes(copy);
				var texture = new Gdk.MemoryTexture(
					frame_width, frame_height, Gdk.MemoryFormat.B8G8R8A8,
					bytes, (uint) frame_stride);
				this.picture.set_paintable(texture);
				if (!this.rendered) {
					this.rendered = true;
					this.window.rdp.toast(
						this.agent_id, Argus.Rdp.State.SUCCESS_DESKTOP_RENDERED, 0);
				}
				return false;
			});
		}

		/**
		 * Ask for the Windows user and password.
		 *
		 * The FreeRDP thread waits. The dialog runs on the GTK thread.
		 *
		 * @return true when both fields are filled
		 */
		private bool prompt()
		{
			var user_entry = new Gtk.Entry() {
				placeholder_text = "User"
			};
			var pass_entry = new Gtk.PasswordEntry();
			var form = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
			form.append(user_entry);
			form.append(pass_entry);
			var dialog = new Adw.AlertDialog("Windows sign-in", null);
			dialog.extra_child = form;
			dialog.add_response("cancel", "Cancel");
			dialog.add_response("ok", "Sign in");
			dialog.default_response = "ok";
			dialog.close_response = "cancel";
			bool ok = false;
			bool done = false;
			var mutex = GLib.Mutex();
			var cond = GLib.Cond();
			GLib.Idle.add(() => {
				dialog.response.connect((response) => {
					mutex.lock();
					if (response == "ok") {
						this.user = user_entry.text;
						this.pass = pass_entry.text;
						ok = this.user != "" && this.pass != "";
					}
					done = true;
					cond.signal();
					mutex.unlock();
				});
				dialog.present(this.picture);
				return false;
			});
			mutex.lock();
			while (!done) {
				cond.wait(mutex);
			}
			mutex.unlock();
			return ok;
		}

		private static Screen? find(FreeRDP.Instance instance)
		{
			foreach (var screen in Screen.live) {
				if (screen.instance == instance) {
					return screen;
				}
			}
			return null;
		}

		private static bool connected(FreeRDP.Instance instance)
		{
			return FreeRDP.gdi_init(instance, FreeRDP.PIXEL_FORMAT_BGRA32);
		}

		private static bool authenticate(
			FreeRDP.Instance instance,
			out string username,
			out string password,
			out string domain)
		{
			username = "";
			password = "";
			domain = "";
			var screen = Screen.find(instance);
			if (screen == null) {
				return false;
			}
			if (screen.user == "" || screen.pass == "") {
				if (!screen.prompt()) {
					return false;
				}
			}
			username = screen.user;
			password = screen.pass;
			return true;
		}

		private static uint32 verify(
			FreeRDP.Instance instance,
			string host,
			uint16 port,
			string common_name,
			string subject,
			string issuer,
			string fingerprint,
			uint32 flags)
		{
			return 1;
		}
	}
}
