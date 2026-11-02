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
	 * calls {@link on_message}. There is no quit menu. Snappr's
	 * worker process and pipe are not part of this.
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
			this.present();
			var hs = new void*[1];
			while (true) {
				if (this.window_up) {
					GLib.MainContext.@default().iteration(true);
					continue;
				}
				var wr = MsgWaitForMultipleObjects(0, hs, false, INFINITE, QS_ALLINPUT);
				if (wr == WAIT_OBJECT_0) {
					if (!this.pump()) {
						break;
					}
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
		 * Present the registration window.
		 *
		 * Startup and a tray click both call this. A certificate
		 * already stored for this machine means there is no action.
		 */
		private void present()
		{
			var cert = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus", "client.pem");
			if (GLib.FileUtils.test(cert, GLib.FileTest.EXISTS)) {
				return;
			}
			if (!this.gtk_up) {
				Gtk.init();
				this.gtk_up = true;
			}
			if (this.window_up) {
				this.registration.present(null);
				return;
			}
			this.registration = new Argus.Shared.RegisterWindow();
			this.window_up = true;
			this.registration.closed.connect(() => {
				this.window_up = false;
			});
			this.registration.show_add();
			this.registration.present(null);
		}
	}
}
