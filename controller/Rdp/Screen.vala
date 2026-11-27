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
		/**
		 * Remote Assistance RACS2 connection string when taking over
		 * a signed-in Windows session without user credentials.
		 */
		public string invite = "";
		/**
		 * One-time invitation password paired with {@link invite}.
		 */
		public string ticket_pass = "";
		private bool stopping = false;
		private bool running = false;
		private bool rendered = false;
		private bool ready = false;
		private bool dirty = false;
		private int64 painted_at = 0;
		private GLib.Mutex input_lock;
		private GLib.Mutex paint_lock;
		private bool painting = false;
		private GLib.Bytes? latest;
		private int latest_width;
		private int latest_height;
		private int latest_stride;
		private int pointer_x = 0;
		private int pointer_y = 0;
		private static bool addins_registered = false;
		private static Gee.ArrayList<Screen> live = new Gee.ArrayList<Screen>();
		private Argus.Controller.Window window;
		private int agent_id;
		private Viewer? viewer;
		private Adw.AlertDialog? auth_dialog;
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
				can_focus = true,
				focusable = true,
				content_fit = Gtk.ContentFit.SCALE_DOWN,
				halign = Gtk.Align.START,
				valign = Gtk.Align.START
			};
			var motion = new Gtk.EventControllerMotion();
			motion.motion.connect((x, y) => {
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return;
				}
				unowned FreeRDP.Gdi? gdi = this.instance.context.gdi;
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (gdi == null || input == null || gdi.width < 1 || gdi.height < 1) {
					this.input_lock.unlock();
					return;
				}
				var pw = this.picture.get_width();
				var ph = this.picture.get_height();
				if (pw < 1 || ph < 1) {
					this.input_lock.unlock();
					return;
				}
				var scale = double.min((double) pw / (double) gdi.width, (double) ph / (double) gdi.height);
				var rx = ((int) (x / scale)).clamp(0, gdi.width - 1);
				var ry = ((int) (y / scale)).clamp(0, gdi.height - 1);
				this.pointer_x = rx;
				this.pointer_y = ry;
				FreeRDP.input_send_mouse_event(input, FreeRDP.PTR_FLAGS_MOVE, (uint16) rx, (uint16) ry);
				this.input_lock.unlock();
			});
			this.picture.add_controller(motion);
			var click = new Gtk.GestureClick() {
				button = 0
			};
			click.pressed.connect((n_press, x, y) => {
				this.picture.grab_focus();
				var flag = (uint16) 0;
				switch (click.get_current_button()) {
					case 1:
						flag = FreeRDP.PTR_FLAGS_BUTTON1;
						break;
					case 2:
						flag = FreeRDP.PTR_FLAGS_BUTTON3;
						break;
					case 3:
						flag = FreeRDP.PTR_FLAGS_BUTTON2;
						break;
					default:
						return;
				}
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return;
				}
				unowned FreeRDP.Gdi? gdi = this.instance.context.gdi;
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (gdi == null || input == null || gdi.width < 1 || gdi.height < 1) {
					this.input_lock.unlock();
					return;
				}
				var pw = this.picture.get_width();
				var ph = this.picture.get_height();
				if (pw < 1 || ph < 1) {
					this.input_lock.unlock();
					return;
				}
				var scale = double.min((double) pw / (double) gdi.width, (double) ph / (double) gdi.height);
				var rx = ((int) (x / scale)).clamp(0, gdi.width - 1);
				var ry = ((int) (y / scale)).clamp(0, gdi.height - 1);
				this.pointer_x = rx;
				this.pointer_y = ry;
				FreeRDP.input_send_mouse_event(
					input, (uint16) (FreeRDP.PTR_FLAGS_DOWN | flag), (uint16) rx, (uint16) ry);
				this.input_lock.unlock();
			});
			click.released.connect((n_press, x, y) => {
				var flag = (uint16) 0;
				switch (click.get_current_button()) {
					case 1:
						flag = FreeRDP.PTR_FLAGS_BUTTON1;
						break;
					case 2:
						flag = FreeRDP.PTR_FLAGS_BUTTON3;
						break;
					case 3:
						flag = FreeRDP.PTR_FLAGS_BUTTON2;
						break;
					default:
						return;
				}
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return;
				}
				unowned FreeRDP.Gdi? gdi = this.instance.context.gdi;
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (gdi == null || input == null || gdi.width < 1 || gdi.height < 1) {
					this.input_lock.unlock();
					return;
				}
				var pw = this.picture.get_width();
				var ph = this.picture.get_height();
				if (pw < 1 || ph < 1) {
					this.input_lock.unlock();
					return;
				}
				var scale = double.min((double) pw / (double) gdi.width, (double) ph / (double) gdi.height);
				var rx = ((int) (x / scale)).clamp(0, gdi.width - 1);
				var ry = ((int) (y / scale)).clamp(0, gdi.height - 1);
				this.pointer_x = rx;
				this.pointer_y = ry;
				FreeRDP.input_send_mouse_event(input, flag, (uint16) rx, (uint16) ry);
				this.input_lock.unlock();
			});
			this.picture.add_controller(click);
			var scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.BOTH_AXES);
			scroll.scroll.connect((dx, dy) => {
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return false;
				}
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (input == null) {
					this.input_lock.unlock();
					return false;
				}
				if (dy != 0) {
					var flags = (uint16) (FreeRDP.PTR_FLAGS_WHEEL | 0x0078);
					if (dy > 0) {
						flags = (uint16) (FreeRDP.PTR_FLAGS_WHEEL | FreeRDP.PTR_FLAGS_WHEEL_NEGATIVE | 0x0088);
					}
					FreeRDP.input_send_mouse_event(
						input, flags, (uint16) this.pointer_x, (uint16) this.pointer_y);
				}
				if (dx != 0) {
					var flags = (uint16) (FreeRDP.PTR_FLAGS_HWHEEL | 0x0078);
					if (dx < 0) {
						flags = (uint16) (FreeRDP.PTR_FLAGS_HWHEEL | FreeRDP.PTR_FLAGS_WHEEL_NEGATIVE | 0x0088);
					}
					FreeRDP.input_send_mouse_event(
						input, flags, (uint16) this.pointer_x, (uint16) this.pointer_y);
				}
				this.input_lock.unlock();
				return true;
			});
			this.picture.add_controller(scroll);
			var keys = new Gtk.EventControllerKey();
			keys.key_pressed.connect((keyval, keycode, state) => {
				var vk = WinPr.get_vk_from_keycode(keycode, WinPr.KEYCODE_TYPE_XKB);
				var scancode = WinPr.get_scancode_from_vk(vk, WinPr.KBD_TYPE_IBM_ENHANCED);
				if (scancode == 0) {
					return false;
				}
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return false;
				}
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (input == null) {
					this.input_lock.unlock();
					return false;
				}
				FreeRDP.input_send_keyboard_event_ex(input, true, false, scancode);
				this.input_lock.unlock();
				return true;
			});
			keys.key_released.connect((keyval, keycode, state) => {
				var vk = WinPr.get_vk_from_keycode(keycode, WinPr.KEYCODE_TYPE_XKB);
				var scancode = WinPr.get_scancode_from_vk(vk, WinPr.KBD_TYPE_IBM_ENHANCED);
				if (scancode == 0) {
					return;
				}
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return;
				}
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (input == null) {
					this.input_lock.unlock();
					return;
				}
				FreeRDP.input_send_keyboard_event_ex(input, false, false, scancode);
				this.input_lock.unlock();
			});
			this.picture.add_controller(keys);
			var focus = new Gtk.EventControllerFocus();
			focus.enter.connect(() => {
				this.input_lock.lock();
				if (!this.ready || this.stopping || this.instance == null) {
					this.input_lock.unlock();
					return;
				}
				unowned FreeRDP.Input? input = this.instance.context.input;
				if (input != null) {
					FreeRDP.input_send_focus_in_event(input, 0);
				}
				this.input_lock.unlock();
			});
			this.picture.add_controller(focus);
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
			this.viewer = viewer;
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
			if (!Screen.addins_registered) {
				Screen.addins_registered = true;
				FreeRDP.register_addin_provider(FreeRDP.static_addin_loader, 0);
			}
			this.instance = new FreeRDP.Instance();
			var width = this.picture.get_width();
			var height = this.picture.get_height();
			if (width < 64) {
				width = 1280;
			}
			if (height < 64) {
				height = 720;
			}
			var port = viewer.view_port;
			if (!this.configure(port, width, height)) {
				this.problem = Argus.Rdp.State.FAIL_PREPARE_RENDER.to_string();
				this.window.rdp.toast(this.agent_id, Argus.Rdp.State.FAIL_PREPARE_RENDER, 0);
				return;
			}
			Screen.live.add(this);
			this.running = true;
			new GLib.Thread<int>("screen", () => {
				this.run(port, width, height);
				return 0;
			});
		}

		/**
		 * Create the FreeRDP context and apply display and assistance settings.
		 *
		 * @param port local viewer loopback port
		 * @param width initial desktop width in pixels
		 * @param height initial desktop height in pixels
		 * @return false when the context or Remote Assistance ticket failed
		 */
		private bool configure(uint16 port, int width, int height)
		{
			if (!this.instance.context_new()) {
				return false;
			}
			this.instance.PreConnect = Screen.pre_connect;
			this.instance.PostConnect = Screen.connected;
			this.instance.Authenticate = Screen.authenticate;
			this.instance.VerifyCertificateEx = Screen.verify;
			this.instance.VerifyChangedCertificateEx = Screen.verify_changed;
			unowned FreeRDP.Settings settings = this.instance.context.settings;
			settings.set_bool(FreeRDP.SettingsBool.IgnoreCertificate, true);
			settings.set_string(FreeRDP.SettingsString.ServerHostname, "127.0.0.1");
			settings.set_uint32(FreeRDP.SettingsUint32.ServerPort, port);
			settings.set_uint32(FreeRDP.SettingsUint32.DesktopWidth, width);
			settings.set_uint32(FreeRDP.SettingsUint32.DesktopHeight, height);
			settings.set_uint32(FreeRDP.SettingsUint32.ColorDepth, 32);
			settings.set_bool(FreeRDP.SettingsBool.SupportMultitransport, false);
			settings.set_uint32(FreeRDP.SettingsUint32.MultitransportFlags, 0);
			settings.set_bool(FreeRDP.SettingsBool.BitmapCacheEnabled, true);
			settings.set_bool(FreeRDP.SettingsBool.BitmapCacheV3Enabled, true);
			settings.set_bool(FreeRDP.SettingsBool.RemoteFxCodec, false);
			settings.set_bool(FreeRDP.SettingsBool.NSCodec, false);
			settings.set_bool(FreeRDP.SettingsBool.SurfaceCommandsEnabled, false);
			settings.set_bool(FreeRDP.SettingsBool.SupportDynamicChannels, true);
			settings.set_bool(FreeRDP.SettingsBool.SupportGraphicsPipeline, true);
			settings.set_bool(FreeRDP.SettingsBool.GfxProgressive, true);
			settings.set_bool(FreeRDP.SettingsBool.GfxProgressiveV2, true);
			settings.set_bool(FreeRDP.SettingsBool.GfxH264, false);
			settings.set_bool(FreeRDP.SettingsBool.GfxAVC444, false);
			settings.set_bool(FreeRDP.SettingsBool.GfxAVC444v2, false);
			settings.set_bool(FreeRDP.SettingsBool.RedirectDrives, false);
			settings.set_bool(FreeRDP.SettingsBool.AudioPlayback, false);
			settings.set_bool(FreeRDP.SettingsBool.RedirectClipboard, false);
			if (this.invite == "") {
				return true;
			}
			var assist = new FreeRDP.AssistanceFile();
			if (assist.parse_buffer(this.invite, this.invite.length, this.ticket_pass) < 0 || !assist.populate_settings(settings)) {
				GLib.warning("remote assistance ticket could not be parsed");
				return false;
			}
			settings.set_uint32(FreeRDP.SettingsUint32.TargetNetAddressCount, 0);
			settings.set_string(FreeRDP.SettingsString.ServerHostname, "127.0.0.1");
			settings.set_uint32(FreeRDP.SettingsUint32.ServerPort, port);
			settings.set_bool(FreeRDP.SettingsBool.RemoteAssistanceRequestControl, true);
			settings.set_bool(FreeRDP.SettingsBool.NlaSecurity, false);
			return true;
		}

		/**
		 * Connect FreeRDP and pump its event loop on the screen thread.
		 *
		 * @param port local viewer loopback port
		 * @param width initial desktop width in pixels
		 * @param height initial desktop height in pixels
		 */
		private void run(uint16 port, int width, int height)
		{
			var handles = new void*[64];
			for (var attempt = 0; attempt < 3 && !this.stopping; attempt++) {
				if (attempt > 0) {
					GLib.Thread.usleep(500000);
					this.input_lock.lock();
					this.ready = false;
					if (this.stopping || this.instance == null) {
						this.input_lock.unlock();
						break;
					}
					this.instance.disconnect();
					FreeRDP.gdi_free(this.instance);
					this.instance.context_free();
					if (!this.configure(port, width, height)) {
						this.input_lock.unlock();
						break;
					}
					this.input_lock.unlock();
				}
				if (!this.instance.connect()) {
					if (this.stopping) {
						break;
					}
					var err = FreeRDP.get_last_error(this.instance.context);
					GLib.warning("desktop connect failed: 0x%08x %s", err, FreeRDP.get_last_error_name(err));
					var shown = attempt + 1;
					GLib.Idle.add(() => {
						this.problem = Argus.Rdp.State.RETRY_RENDER_CONNECT.to_string();
						this.window.rdp.toast(this.agent_id, Argus.Rdp.State.RETRY_RENDER_CONNECT, shown);
						return false;
					});
					continue;
				}
				this.input_lock.lock();
				this.ready = true;
				this.dirty = true;
				this.input_lock.unlock();
				while (!this.stopping && !this.instance.shall_disconnect()) {
					var count = FreeRDP.get_event_handles(this.instance.context, handles, 64);
					if (count == 0) {
						break;
					}
					var wait_ms = this.dirty ? (uint32) 16 : (uint32) 100;
					var waited = WinPr.wait(count, handles, false, wait_ms);
					if (waited == WinPr.WAIT_FAILED) {
						break;
					}
					if (waited == WinPr.WAIT_TIMEOUT) {
						if (this.dirty) {
							this.publish();
						}
						continue;
					}
					if (!FreeRDP.check_event_handles(this.instance.context)) {
						break;
					}
					if (this.dirty && GLib.get_monotonic_time() - this.painted_at >= 16000) {
						this.publish();
					}
				}
				this.input_lock.lock();
				this.ready = false;
				this.input_lock.unlock();
				if (this.stopping) {
					break;
				}
				var err = FreeRDP.get_last_error(this.instance.context);
				GLib.warning("desktop disconnected: 0x%08x %s", err, FreeRDP.get_last_error_name(err));
				var dropped = attempt + 1;
				GLib.Idle.add(() => {
					this.window.rdp.toast(this.agent_id, Argus.Rdp.State.RETRY_DESKTOP_DISCONNECTED, dropped);
					return false;
				});
			}
			this.input_lock.lock();
			this.ready = false;
			this.running = false;
			if (this.instance != null) {
				this.instance.disconnect();
				FreeRDP.gdi_free(this.instance);
				this.instance.context_free();
				this.instance = null;
			}
			this.input_lock.unlock();
		}

		/**
		 * Stop this picture. {@link Argus.Controller.Tab.Rdp.drop}
		 * calls this.
		 */
		public void stop()
		{
			this.input_lock.lock();
			this.stopping = true;
			this.ready = false;
			Screen.live.remove(this);
			var viewer = this.viewer;
			this.viewer = null;
			var dialog = this.auth_dialog;
			this.auth_dialog = null;
			if (!this.running && this.instance != null) {
				this.instance.disconnect();
				FreeRDP.gdi_free(this.instance);
				this.instance.context_free();
				this.instance = null;
			}
			this.input_lock.unlock();
			if (dialog != null) {
				dialog.force_close();
			}
			if (viewer != null) {
				viewer.stop();
			}
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
			this.dirty = false;
			this.painted_at = GLib.get_monotonic_time();
			var width = gdi.width;
			var height = gdi.height;
			var stride = (int) gdi.stride;
			var size = stride * height;
			var frame = new uint8[size];
			GLib.Memory.copy((void*) frame, gdi.primary_buffer, size);
			var bytes = new GLib.Bytes.take((owned) frame);
			this.paint_lock.lock();
			this.latest = bytes;
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
				var ready_bytes = this.latest;
				var frame_width = this.latest_width;
				var frame_height = this.latest_height;
				var frame_stride = this.latest_stride;
				this.painting = false;
				this.paint_lock.unlock();
				if (this.stopping || ready_bytes == null) {
					return false;
				}
				var texture = new Gdk.MemoryTexture(
					frame_width, frame_height, Gdk.MemoryFormat.B8G8R8A8,
					ready_bytes, (uint) frame_stride);
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
				if (this.stopping) {
					mutex.lock();
					done = true;
					cond.signal();
					mutex.unlock();
					return false;
				}
				this.auth_dialog = dialog;
				dialog.response.connect((response) => {
					if (this.auth_dialog == dialog) {
						this.auth_dialog = null;
					}
					mutex.lock();
					if (!done) {
						if (response == "ok") {
							this.user = user_entry.text;
							this.pass = pass_entry.text;
							ok = this.user != "" && this.pass != "";
						}
						done = true;
						cond.signal();
					}
					mutex.unlock();
				});
				dialog.closed.connect(() => {
					if (this.auth_dialog == dialog) {
						this.auth_dialog = null;
					}
					mutex.lock();
					if (!done) {
						done = true;
						cond.signal();
					}
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

		private static bool pre_connect(FreeRDP.Instance instance)
		{
			unowned FreeRDP.Context ctx = instance.context;
			FreeRDP.subscribe_channel_connected(ctx.pubSub, Screen.channel_connected);
			FreeRDP.subscribe_channel_disconnected(ctx.pubSub, Screen.channel_disconnected);
			return FreeRDP.client_load_addins(ctx.channels, ctx.settings);
		}

		private static bool connected(FreeRDP.Instance instance)
		{
			if (!FreeRDP.gdi_init(instance, FreeRDP.PIXEL_FORMAT_BGRA32)) {
				return false;
			}
			instance.context.update.EndPaint = Screen.end_paint;
			return true;
		}

		private static bool end_paint(FreeRDP.Context context)
		{
			var screen = Screen.find(context.instance);
			if (screen != null) {
				screen.dirty = true;
			}
			return true;
		}

		private static void channel_connected(void* context, FreeRDP.ChannelConnectedEventArgs e)
		{
			unowned FreeRDP.Context ctx = (FreeRDP.Context) context;
			if (e.name == FreeRDP.RDPGFX_DVC_CHANNEL_NAME && ctx.gdi != null) {
				FreeRDP.gdi_graphics_pipeline_init(ctx.gdi, e.pInterface);
			}
		}

		private static void channel_disconnected(void* context, FreeRDP.ChannelDisconnectedEventArgs e)
		{
			unowned FreeRDP.Context ctx = (FreeRDP.Context) context;
			if (e.name == FreeRDP.RDPGFX_DVC_CHANNEL_NAME && ctx.gdi != null) {
				FreeRDP.gdi_graphics_pipeline_uninit(ctx.gdi, e.pInterface);
			}
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
			if (screen == null || screen.invite != "") {
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
			return 2;
		}

		private static uint32 verify_changed(
			FreeRDP.Instance instance,
			string host,
			uint16 port,
			string common_name,
			string subject,
			string issuer,
			string new_fingerprint,
			string old_subject,
			string old_issuer,
			string old_fingerprint,
			uint32 flags)
		{
			return 2;
		}
	}
}
