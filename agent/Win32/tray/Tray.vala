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

namespace Argus.Agent.Win32
{
	/**
	 * Window and tray icon for the signed-in session.
	 *
	 * The icon path is Snappr ''TrayKeeper'': a message window,
	 * then ''Shell_NotifyIconW'' with ''NIM_ADD'', ''NIM_SETVERSION'',
	 * and ''NIM_MODIFY''. {@link proc} is the window procedure and
	 * calls {@link on_message}. There is no quit menu and no
	 * uninstall. The service starts this process at sign-in. A pin
	 * is written to the local pipe for the service.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tray = new Argus.Agent.Win32.Tray();
	 * return tray.run();
	 * }}}
	 */
	public class Tray : GLib.Object
	{
		private static Tray app;
		private static WndProc proc_slot;
		private void* hwnd;
		private NotifyIcon nid;
		private bool added = false;
		private uint32 taskbar = 0;
		private uint32 tray_msg = WM_APP + 42;
		private Argus.Shared.RegisterWindow registration;
		private bool window_up = false;
		private bool gtk_up = false;
		private void* pipe = (void*) (intptr) (-1);
		private bool known = false;
		private bool started = false;
		private bool submitted = false;
		private int waits = 0;

		/**
		 * Function pointer the message window calls.
		 *
		 * It has no instance argument, so it calls {@link on_message}
		 * on the tray {@link run} registered.
		 *
		 * @param hwnd window the message was sent to
		 * @param msg window message
		 * @param wparam message parameter
		 * @param lparam message parameter
		 * @return the result from {@link on_message}
		 */
		private static int64 proc(void* hwnd, uint32 msg, uint64 wparam, int64 lparam)
		{
			return Tray.app.on_message(hwnd, msg, wparam, lparam);
		}

		/**
		 * Show the tray icon and wait for window messages.
		 *
		 * Returns when the message loop receives ''WM_QUIT''.
		 *
		 * @return 0 when the loop ends. 1 when the icon could not
		 *   be created.
		 */
		public int run()
		{
			Tray.app = this;
			Tray.proc_slot = Tray.proc;
			if (!this.install()) {
				return 1;
			}
			try {
				this.pipe = CreateFileW(
					"\\\\.\\pipe\\Argus.Register".to_utf16(),
					GENERIC_READ | GENERIC_WRITE,
					0, null, OPEN_EXISTING, 0, null);
			} catch (GLib.ConvertError e) {
				this.pipe = (void*) (intptr) (-1);
			}
			if (this.pipe == null) {
				this.pipe = (void*) (intptr) (-1);
			}
			var mode = PIPE_READMODE_MESSAGE;
			if ((intptr) this.pipe != -1) {
				SetNamedPipeHandleState(this.pipe, ref mode, null, null);
			}
			var hs = new void*[1];
			while (true) {
				uint32 avail = 0;
				if ((intptr) this.pipe != -1 &&
					!PeekNamedPipe(this.pipe, null, 0, null, out avail, null)) {
					switch (GetLastError()) {
						case ERROR_BROKEN_PIPE:
						case 233:
							CloseHandle(this.pipe);
							this.pipe = (void*) (intptr) (-1);
							break;
						default:
							break;
					}
				}
				var msg = "";
				if ((intptr) this.pipe != -1 && avail > 0) {
					uint32 got = 0;
					var buf = new uint8[256];
					if (ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
						msg = (string) buf[0:int.min((int) got, buf.length)];
					}
				}
				if (msg.has_prefix("tip ")) {
					var text = msg.substring(4).strip();
					this.set_tip(text);
					this.known = text == "Connected to management server";
					if (!this.started) {
						this.started = true;
						this.present();
					}
					if (this.window_up && !this.known) {
						this.registration.listen_label.label = text;
					}
				}
				if (this.known && this.window_up && !this.submitted) {
					this.registration.close();
				}
				if (!this.started && (intptr) this.pipe != -1 && !this.known && this.waits < 6) {
					this.waits++;
					Sleep(200);
					continue;
				}
				if (!this.started) {
					this.started = true;
					this.present();
				}
				if (this.window_up) {
					GLib.MainContext.@default().iteration(true);
					continue;
				}
				var wait_ms = INFINITE;
				if ((intptr) this.pipe != -1) {
					wait_ms = 1000;
				}
				var wr = MsgWaitForMultipleObjects(0, hs, false, wait_ms, QS_ALLINPUT);
				if (wr == WAIT_OBJECT_0 && !this.pump()) {
					break;
				}
				if (wr == WAIT_OBJECT_0 || wr == WAIT_TIMEOUT) {
					continue;
				}
				OutputDebugStringW(g_utf8_to_utf16(
					"argus-tray: %s (%u)\n".printf("MsgWait", GetLastError())));
				Sleep(200);
			}
			if (this.added) {
				Shell_NotifyIconW(NIM_DELETE, &this.nid);
				this.added = false;
			}
			return 0;
		}

		/**
		 * Drain the window queue.
		 *
		 * Same loop as Snappr ''TrayKeeper.pump''.
		 *
		 * @return false when the queue delivered ''WM_QUIT''
		 */
		private bool pump()
		{
			while (true) {
				var msg = Msg();
				if (!PeekMessageW(out msg, null, 0, 0, PM_REMOVE)) {
					return true;
				}
				if (msg.message == WM_QUIT) {
					return false;
				}
				TranslateMessage(&msg);
				DispatchMessageW(&msg);
			}
		}

		/**
		 * Create the message window and add the icon.
		 *
		 * Same sequence as Snappr ''TrayKeeper.install''.
		 *
		 * @return false when the window class or the window failed
		 */
		private bool install()
		{
			this.taskbar = RegisterWindowMessageW(g_utf8_to_utf16("TaskbarCreated"));
			var wc = WndClass() {
				proc = Tray.proc_slot,
				instance = GetModuleHandleW(null),
				class_name = g_utf8_to_utf16("ArgusAgentTray"),
			};
			if (RegisterClassW(&wc) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
				OutputDebugStringW(g_utf8_to_utf16(
					"argus-tray: %s (%u)\n".printf("RegisterClass", GetLastError())));
				return false;
			}
			this.hwnd = CreateWindowExW(
				0, g_utf8_to_utf16("ArgusAgentTray"), g_utf8_to_utf16(""),
				0, 0, 0, 0, 0, (void*) (intptr) (-3), null, wc.instance, null);
			if (this.hwnd == null) {
				OutputDebugStringW(g_utf8_to_utf16(
					"argus-tray: %s (%u)\n".printf("CreateWindow", GetLastError())));
				return false;
			}
			return this.add_icon();
		}

		/**
		 * Window procedure for the tray.
		 *
		 * Taskbar recreate and the left-click timer are the Snappr
		 * cases. The timer does not start another process.
		 *
		 * @param hwnd window the message was sent to
		 * @param msg window message
		 * @param wparam message parameter
		 * @param lparam message parameter
		 * @return 0 when this tray handled the message, otherwise
		 *   the default window procedure
		 */
		private int64 on_message(void* hwnd, uint32 msg, uint64 wparam, int64 lparam)
		{
			if (msg == this.taskbar && this.taskbar != 0) {
				this.added = false;
				this.add_icon();
				return 0;
			}
			if (msg == this.tray_msg) {
				switch ((uint32) (lparam & 0xffff)) {
					case NIN_SELECT:
					case NIN_KEYSELECT:
					case NIN_BALLOONUSERCLICK:
					case WM_LBUTTONUP:
						SetTimer(hwnd, 1, 150, null);
						return 0;
					default:
						return 0;
				}
			}
			if (msg == WM_TIMER) {
				switch (wparam) {
					case 1:
						KillTimer(hwnd, 1);
						this.present();
						return 0;
					default:
						break;
				}
			}
			if (msg == WM_DESTROY) {
				if (this.added) {
					Shell_NotifyIconW(NIM_DELETE, &this.nid);
					this.added = false;
				}
				return 0;
			}
			return DefWindowProcW(hwnd, msg, wparam, lparam);
		}

		/**
		 * Load the notification icon.
		 *
		 * Same fallback as Snappr ''TrayKeeper.load_icon'': the
		 * module resource, then resource 1, then the system icon.
		 *
		 * @return the icon handle from those calls
		 */
		private void* load_icon()
		{
			var icon = LoadImageW(
				GetModuleHandleW(null), g_utf8_to_utf16("IDI_APP_ICON"),
				IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
			if (icon != null) {
				return icon;
			}
			icon = LoadIconW(GetModuleHandleW(null), (void*) (intptr) 1);
			if (icon != null) {
				return icon;
			}
			return LoadIconW(null, (void*) (intptr) 32512);
		}

		/**
		 * Add the notification icon for this window.
		 *
		 * Same ''NIM_ADD'', ''NIM_SETVERSION'', and ''NIM_MODIFY''
		 * sequence as Snappr ''TrayKeeper.add_icon''.
		 *
		 * @return false when ''NIM_ADD'' fails
		 */
		private bool add_icon()
		{
			if (this.hwnd == null) {
				return false;
			}
			this.nid = NotifyIcon() {
				cb_size = (uint32) sizeof(NotifyIcon),
				hwnd = this.hwnd,
				id = 1,
				flags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP,
				callback = this.tray_msg,
				icon = this.load_icon(),
			};
			copy_wide(&this.nid.tip[0], g_utf8_to_utf16("Register"), 127);
			this.nid.tip[127] = 0;
			if (!Shell_NotifyIconW(NIM_ADD, &this.nid)) {
				OutputDebugStringW(g_utf8_to_utf16(
					"argus-tray: %s (%u)\n".printf("NIM_ADD", GetLastError())));
				return false;
			}
			this.nid.version = NOTIFYICON_VERSION_4;
			Shell_NotifyIconW(NIM_SETVERSION, &this.nid);
			this.nid.flags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
			Shell_NotifyIconW(NIM_MODIFY, &this.nid);
			this.added = true;
			return true;
		}

		/**
		 * Set the tray tip.
		 *
		 * Same ''NIM_MODIFY'' as Snappr ''TrayKeeper.set_tip''.
		 * The service sends ''Connected to management server'' or
		 * ''Disconnected''.
		 *
		 * @param text tip shown on the icon
		 */
		private void set_tip(string text)
		{
			if (!this.added) {
				return;
			}
			try {
				copy_wide(&this.nid.tip[0], text.to_utf16(), 127);
			} catch (GLib.ConvertError e) {
				return;
			}
			this.nid.tip[127] = 0;
			this.nid.flags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
			Shell_NotifyIconW(NIM_MODIFY, &this.nid);
		}

		/**
		 * Present the registration window.
		 *
		 * Startup and a tray click both call this. The window waits
		 * with a spinner until the registration pipe is open, then
		 * starts the registration flow. The CA file means this machine
		 * is registered. A tip of ''Connected to management server''
		 * means there is no action. Any other tip leaves the window
		 * up. A local key alone does not. The six digits are written
		 * to the service pipe.
		 */
		private void present()
		{
			if (this.known) {
				return;
			}
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "argus");
			var registered = GLib.Path.build_filename(dir, "ollmrpc-ca.pem");
			if (GLib.FileUtils.test(registered, GLib.FileTest.EXISTS)) {
				return;
			}
			GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
			GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
			GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
			if (!this.gtk_up) {
				Adw.init();
				this.gtk_up = true;
			}
			if (this.window_up) {
				this.registration.present(null);
				return;
			}
			this.registration = new Argus.Shared.RegisterWindow();
			this.registration.use_pipe = true;
			this.registration.send_pin.connect((pin, hostport) => {
				this.submitted = true;
				var bytes = (pin + "\n" + hostport).data;
				var wrote = (uint32) 0;
				for (var attempt = 0; attempt < 15; attempt++) {
					if ((intptr) this.pipe == -1) {
						try {
							this.pipe = CreateFileW(
								"\\\\.\\pipe\\Argus.Register".to_utf16(),
								GENERIC_READ | GENERIC_WRITE,
								0, null, OPEN_EXISTING, 0, null);
						} catch (GLib.ConvertError e) {
							this.pipe = (void*) (intptr) (-1);
						}
						if (this.pipe == null || (intptr) this.pipe == -1) {
							this.pipe = (void*) (intptr) (-1);
						}
						if ((intptr) this.pipe != -1) {
							var mode = PIPE_READMODE_MESSAGE;
							SetNamedPipeHandleState(this.pipe, ref mode, null, null);
						}
					}
					if ((intptr) this.pipe != -1 &&
						WriteFile(this.pipe, bytes, (uint32) bytes.length, out wrote, null)) {
						break;
					}
					if ((intptr) this.pipe != -1) {
						CloseHandle(this.pipe);
						this.pipe = (void*) (intptr) (-1);
					}
					Sleep(200);
				}
				if ((intptr) this.pipe == -1) {
					this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					return;
				}
				while (true) {
					uint32 got = 0;
					var buf = new uint8[256];
					if (!ReadFile(this.pipe, buf, (uint32) buf.length, out got, null)) {
						this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
						return;
					}
					var n = int.min((int) got, buf.length);
					var msg = (string) buf[0:n];
					if (msg.has_prefix("tip ")) {
						this.set_tip(msg.substring(4));
						continue;
					}
					var code = 0;
					if (!int.try_parse(msg.strip(), out code)) {
						this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
						return;
					}
					if (code == 0) {
						this.known = true;
					}
					this.registration.pipe_code = code;
					return;
				}
			});
			this.window_up = true;
			this.registration.closed.connect(() => {
				this.window_up = false;
			});
			this.registration.show_add();
			if ((intptr) this.pipe != -1) {
				this.registration.show_add();
			} else {
				var window = this.registration;
				GLib.Timeout.add(200, () => {
					if (!this.window_up || this.registration != window) {
						return false;
					}
					if ((intptr) this.pipe == -1) {
						try {
							this.pipe = CreateFileW(
								"\\\\.\\pipe\\Argus.Register".to_utf16(),
								GENERIC_READ | GENERIC_WRITE,
								0, null, OPEN_EXISTING, 0, null);
						} catch (GLib.ConvertError e) {
							this.pipe = (void*) (intptr) (-1);
						}
						if (this.pipe == null || (intptr) this.pipe == -1) {
							this.pipe = (void*) (intptr) (-1);
							return true;
						}
						var mode = PIPE_READMODE_MESSAGE;
						SetNamedPipeHandleState(this.pipe, ref mode, null, null);
					}
					this.registration.show_add();
					return false;
				});
			}
			this.registration.present(null);
		}
	}
}
