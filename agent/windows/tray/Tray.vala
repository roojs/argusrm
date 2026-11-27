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

namespace Argus.Agent.Windows
{
	using Win32;
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
	 * var tray = new Argus.Agent.Windows.Tray();
	 * return tray.run();
	 * }}}
	 */
	public class Tray : GLib.Object
	{
		private static Tray app;
		private static Win32.WndProc proc_slot;
		private void* hwnd;
		private Win32.NotifyIcon nid;
		private bool added = false;
		private uint32 taskbar = 0;
		private uint32 tray_msg = WM_APP + 42;
		private Argus.Shared.RegisterWindow registration;
		private Argus.Shared.Notice status_notice;
		private bool window_up = false;
		private bool notice_up = false;
		private bool gtk_up = false;
		private OLLMrpc.Client rpc;
		private bool registered = false;
		private bool connected = false;
		private bool started = false;
		private bool submitted = false;
		private int waits = 0;
		private bool connecting = false;
		private bool waiting_service = false;
		private string tip_text = "";
		private void* restart_proc = null;
		private bool restarting = false;
		private bool version_retry = false;
		private bool remote_active = false;

		/**
		 * Return true when another ''argus-tray.exe'' process is running.
		 *
		 * @return true if another tray process already exists
		 */
		private bool other_copy()
		{
			var ids = new uint32[4096];
			var needed = (uint32) 0;
			if (!EnumProcesses(ids, (uint32) (ids.length * 4), out needed)) {
				return false;
			}
			var count = int.min((int) (needed / 4), ids.length);
			var self = GetCurrentProcessId();
			for (var i = 0; i < count; i++) {
				if (ids[i] == 0 || ids[i] == self) {
					continue;
				}
				var proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, ids[i]);
				if (proc == null) {
					continue;
				}
				var image = g_utf8_to_utf16(string.nfill(259, ' '));
				var size = (uint32) 260;
				if (!QueryFullProcessImageNameW(proc, 0, image, ref size)) {
					CloseHandle(proc);
					continue;
				}
				CloseHandle(proc);
				try {
					if (image.to_utf8().down().has_suffix("\\argus-tray.exe")) {
						return true;
					}
				} catch (GLib.ConvertError e) {
					continue;
				}
			}
			return false;
		}

		/**
		 * Connect to the local Windows service and query its initial status.
		 */
		private async void connect_service()
		{
			if (this.connecting || this.rpc.connected) {
				return;
			}
			this.connecting = true;
			var ok = yield this.rpc.connect(new OLLMrpc.Request() {
				method = "AgentService.hello",
				args = OLLMrpc.args("is", 1, "argus-tray")
			});
			if (!ok) {
				this.connecting = false;
				this.waits++;
				if (!this.started && this.waits >= 10) {
					this.started = true;
					this.present();
				}
				return;
			}
			try {
				var resp = yield this.rpc.call(new OLLMrpc.Request() {
					method = "AgentService.status"
				});
				var info = (string[]) resp.retval;
				if (info.length >= 3) {
					this.registered = info[0] == "1";
					this.connected = info[1] == "1";
					this.tip_text = info[2];
					this.set_tip(this.tip_text);
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			this.connecting = false;
			if (!this.started) {
				this.started = true;
				if (!this.registered) {
					this.present();
				}
			}
			if (this.window_up && this.registered && !this.submitted) {
				this.registration.close();
			}
			if (this.window_up && !this.registered && this.waiting_service) {
				this.waiting_service = false;
				this.registration.show_add();
			}
		}

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
			if (this.other_copy()) {
				return 0;
			}
			Tray.app = this;
			Tray.proc_slot = Tray.proc;
			if (!this.install()) {
				return 1;
			}
			OLLMrpc.rpc_register();
			this.rpc = new OLLMrpc.Client("", "", "tcp://127.0.0.1:4142");
			this.rpc.notification.connect((notif) => {
				if (notif.method == "agent.desktop_active" && notif.args.size >= 1) {
					this.remote_active = notif.args.get(0).get_boolean();
					if (this.remote_active) {
						this.set_tip("Remote control active");
						this.balloon("Remote control active",
							"An administrator is controlling your desktop. Right-click the Argus icon to disconnect.");
						return;
					}
					this.set_tip(this.tip_text != "" ? this.tip_text : "Connected to management server");
					return;
				}
				if (notif.method != "agent.status" || notif.args.size < 3) {
					return;
				}
				this.registered = notif.args.get(0).get_boolean();
				this.connected = notif.args.get(1).get_boolean();
				this.tip_text = notif.args.get(2).get_string();
				if (!this.remote_active) {
					this.set_tip(this.tip_text);
				}
				if (this.version_retry && this.notice_up) {
					var mismatch = this.tip_text.has_prefix("The server is ") &&
						this.tip_text.contains(". This client is ");
					var settled = this.connected || mismatch ||
						(this.tip_text != "" &&
							this.tip_text != "Disconnected" &&
							this.tip_text != "Not registered");
					if (settled) {
						this.version_retry = false;
						if (this.connected) {
							this.status_notice.heading_label.label = "The agent is connected.";
							this.status_notice.body_label.label =
								"Connected to the management server.";
						} else if (mismatch) {
							this.status_notice.heading_label.label = "The versions still differ.";
							this.status_notice.body_label.label = this.tip_text;
						} else {
							this.status_notice.heading_label.label = "The agent is not connected.";
							this.status_notice.body_label.label = this.tip_text;
						}
						this.status_notice.body_label.visible = true;
						this.status_notice.actions.visible = false;
						var notice = this.status_notice;
						GLib.Timeout.add_seconds(4, () => {
							if (this.notice_up && this.status_notice == notice) {
								notice.close();
							}
							return false;
						});
					}
				}
				if (!this.started) {
					this.started = true;
					if (!this.registered) {
						this.present();
					}
				}
				if (this.window_up && this.registered && !this.submitted) {
					this.registration.close();
				}
				if (this.window_up && !this.registered && !this.waiting_service &&
					this.tip_text != "Not registered") {
					this.registration.listen_label.label = this.tip_text;
				}
			});
			GLib.Timeout.add(500, () => {
				if (!this.rpc.connected && !this.connecting) {
					this.connect_service.begin();
				}
				return true;
			});
			this.connect_service.begin();
			var hs = new void*[1];
			while (true) {
				while (GLib.MainContext.@default().iteration(false)) {
				}
				if (this.window_up || this.notice_up) {
					GLib.MainContext.@default().iteration(true);
					continue;
				}
				var wr = MsgWaitForMultipleObjects(0, hs, false, 100, QS_ALLINPUT);
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
				WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
				g_utf8_to_utf16("ArgusAgentTray"), g_utf8_to_utf16(""),
				WS_POPUP, 0, 0, 0, 0, null, null, wc.instance, null);
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
		 * The taskbar id is assigned at runtime, so it is tested
		 * before the switch. Each other message goes to one helper.
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
				this.on_taskbar();
				return 0;
			}
			switch (msg) {
				case WM_APP + 42:
					return this.on_icon(hwnd, lparam);

				case WM_TIMER:
					return this.on_timer(hwnd, wparam, lparam);

				case WM_COMMAND:
					return this.on_command(hwnd, wparam, lparam);

				case WM_DESTROY:
					if (this.added) {
						Shell_NotifyIconW(NIM_DELETE, &this.nid);
						this.added = false;
					}
					return 0;

				default:
					return DefWindowProcW(hwnd, msg, wparam, lparam);
			}
		}

		/**
		 * Put the icon back after Explorer restarts.
		 */
		private void on_taskbar()
		{
			this.added = false;
			this.add_icon();
			if (this.remote_active) {
				this.set_tip("Remote control active");
			}
		}

		/**
		 * Handle a click on the tray icon.
		 *
		 * A left click opens status. A right click opens the menu.
		 *
		 * @param hwnd window the message was sent to
		 * @param lparam notification code in the low word
		 * @return 0
		 */
		private int64 on_icon(void* hwnd, int64 lparam)
		{
			switch ((uint32) (lparam & 0xffff)) {
				case NIN_SELECT:
				case NIN_KEYSELECT:
				case WM_LBUTTONUP:
					SetTimer(hwnd, 1, 150, null);
					return 0;

				case WM_RBUTTONUP:
				case WM_CONTEXTMENU:
					var pt = POINT();
					GetCursorPos(out pt);
					var menu = CreatePopupMenu();
					AppendMenuW(menu, MF_STRING | MF_GRAYED, 0,
						g_utf8_to_utf16("Argus RM Agent " + Argus.VERSION));
					var status = this.tip_text != "" ? this.tip_text : "Not registered";
					if (this.remote_active) {
						status = "Remote control active";
					}
					if (this.restarting) {
						status = "Restarting agent…";
					}
					AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, g_utf8_to_utf16(status));
					AppendMenuW(menu, MF_SEPARATOR, 0, null);
					if (this.remote_active) {
						AppendMenuW(menu, MF_STRING, 1003, g_utf8_to_utf16("Disconnect remote control"));
					}
					var restart_flags = this.restarting ? MF_STRING | MF_GRAYED : MF_STRING;
					AppendMenuW(menu, restart_flags, 1001, g_utf8_to_utf16("Restart Agent"));
					var version_mismatch = this.registered && !this.connected &&
						this.tip_text.has_prefix("The server is ") &&
						this.tip_text.contains(". This client is ");
					if ((!this.registered || !this.connected) && !version_mismatch) {
						AppendMenuW(menu, MF_STRING, 1002, g_utf8_to_utf16("Register…"));
					}
					SetForegroundWindow(this.hwnd);
					TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, this.hwnd, null);
					PostMessageW(this.hwnd, WM_NULL, 0, 0);
					DestroyMenu(menu);
					return 0;

				default:
					return 0;
			}
		}

		/**
		 * Handle a timer on the tray window.
		 *
		 * Timer 1 opens registration or the status dialog.
		 *
		 * @param hwnd window the message was sent to
		 * @param wparam timer id
		 * @param lparam message parameter
		 * @return 0 when the timer was handled, otherwise the
		 *   default window procedure
		 */
		private int64 on_timer(void* hwnd, uint64 wparam, int64 lparam)
		{
			switch (wparam) {
				case 1:
					KillTimer(hwnd, 1);
					if (!this.registered) {
						this.present();
						return 0;
					}
					if (!this.gtk_up) {
						Adw.init();
						this.gtk_up = true;
					}
					if (this.notice_up) {
						this.status_notice.present(null);
						return 0;
					}
					var heading = this.restarting ?
						"Argus agent is restarting" : "Argus agent is running";
					var detail = this.tip_text != "" ?
						this.tip_text : "Not connected to the management server.";
					if (this.registered && !this.connected) {
						heading = "Argus agent is not connected";
					}
					var version_mismatch = this.registered && !this.connected &&
						this.tip_text.has_prefix("The server is ") &&
						this.tip_text.contains(". This client is ");
					var offer_register = (!this.registered || !this.connected) &&
						!version_mismatch;
					this.status_notice = new Argus.Shared.Notice(heading, detail);
					this.status_notice.title =
						"Argus Remote Management Agent " + Argus.VERSION;
					if (this.remote_active) {
						this.status_notice.add_response("disconnect", "Disconnect remote control");
					}
					if (version_mismatch && !this.restarting) {
						this.status_notice.add_response("restart", "Restart");
					}
					if (version_mismatch) {
						this.status_notice.add_response("retry", "Retry", false);
					}
					if (offer_register) {
						this.status_notice.add_response("register", "Register");
					}
					if (!version_mismatch && !this.restarting) {
						this.status_notice.add_response("restart", "Restart");
					}
					this.status_notice.responded.connect((response) => {
						if (response == "disconnect") {
							PostMessageW(this.hwnd, WM_COMMAND, 1003, 0);
						}
						if (response == "restart") {
							PostMessageW(this.hwnd, WM_COMMAND, 1001, 0);
						}
						if (response == "retry" && this.rpc.connected) {
							this.version_retry = true;
							this.status_notice.heading_label.label = "Trying the server again.";
							try {
								this.rpc.call_sync(new OLLMrpc.Request() {
									method = "AgentService.retry"
								});
							} catch (GLib.Error e) {
								this.version_retry = false;
								this.status_notice.heading_label.label =
									"Could not try the server again.";
								this.status_notice.body_label.label = e.message;
								this.status_notice.body_label.visible = true;
								this.status_notice.actions.visible = false;
								var notice = this.status_notice;
								GLib.Timeout.add_seconds(4, () => {
									if (this.notice_up && this.status_notice == notice) {
										notice.close();
									}
									return false;
								});
							}
						}
						if (response == "register") {
							this.status_notice.close();
							this.present(true);
						}
					});
					this.notice_up = true;
					this.status_notice.closed.connect(() => {
						this.notice_up = false;
						this.version_retry = false;
					});
					this.status_notice.present(null);
					return 0;

				default:
					return DefWindowProcW(hwnd, WM_TIMER, wparam, lparam);
			}
		}

		/**
		 * Handle a menu command.
		 *
		 * 1001 restarts the service elevated. 1002 opens
		 * registration.
		 *
		 * @param hwnd window the message was sent to
		 * @param wparam command id in the low word
		 * @param lparam message parameter
		 * @return 0 when the command was handled, otherwise the
		 *   default window procedure
		 */
		private int64 on_command(void* hwnd, uint64 wparam, int64 lparam)
		{
			switch ((uint32) (wparam & 0xffff)) {
				case 1001:
					if (this.restarting) {
						return 0;
					}
					var exe_buf = g_utf8_to_utf16(string.nfill(259, ' '));
					if (GetModuleFileNameW(null, exe_buf, 260) == 0) {
						return 0;
					}
					var exe_path = "";
					try {
						exe_path = exe_buf.to_utf8();
					} catch (GLib.ConvertError e) {
						return 0;
					}
					var slash = exe_path.last_index_of("\\");
					var dir_w = g_utf8_to_utf16(slash > 0 ? exe_path.substring(0, slash) : "");
					var verb_w = g_utf8_to_utf16("runas");
					var params_w = g_utf8_to_utf16("--restart");
					var sei = Win32.SHELLEXECUTEINFOW() {
						cbSize = (uint32) sizeof(Win32.SHELLEXECUTEINFOW),
						fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI,
						hwnd = this.hwnd,
						lpVerb = verb_w,
						lpFile = exe_buf,
						lpParameters = params_w,
						nShow = SW_SHOWNORMAL,
					};
					if (slash > 0) {
						sei.lpDirectory = dir_w;
					}
					if (!ShellExecuteExW(ref sei)) {
						var err = GetLastError();
						var title = "Could not restart the Argus agent service";
						var detail = "Error %u.".printf(err);
						if (err == ERROR_CANCELLED) {
							title = "Could not request administrator access";
							detail = "Administrator access was not granted.";
						}
						if (!this.gtk_up) {
							Adw.init();
							this.gtk_up = true;
						}
						if (!this.notice_up) {
							this.status_notice = new Argus.Shared.Notice(title, detail);
							this.status_notice.title =
								"Argus Remote Management Agent " + Argus.VERSION;
							this.status_notice.add_response("ok", "OK");
							this.notice_up = true;
							this.status_notice.closed.connect(() => {
								this.notice_up = false;
							});
							this.status_notice.present(null);
						}
						return 0;
					}
					this.restarting = true;
					this.set_tip("Restarting agent…");
					if (sei.hProcess == null) {
						this.restarting = false;
						return 0;
					}
					this.restart_proc = sei.hProcess;
					GLib.Timeout.add(200, () => {
						if (this.restart_proc == null) {
							return false;
						}
						if (WaitForSingleObject(this.restart_proc, 0) != WAIT_OBJECT_0) {
							return true;
						}
						var code = (uint32) 1;
						GetExitCodeProcess(this.restart_proc, (void*) (&code));
						CloseHandle(this.restart_proc);
						this.restart_proc = null;
						this.restarting = false;
						if (code == 0) {
							this.set_tip("Argus RM Agent");
							this.balloon(
								"Argus RM Agent",
								"The agent service has been restarted.");
							return false;
						}
						this.set_tip(this.tip_text != "" ? this.tip_text : "Disconnected");
						if (!this.gtk_up) {
							Adw.init();
							this.gtk_up = true;
						}
						if (this.notice_up) {
							return false;
						}
						var detail = "Restart exited with code %u.".printf(code);
						switch (code) {
							case 5:
								detail = "Administrator access was not granted.";
								break;

							case 1060:
								detail = "The Argus agent service is not installed.";
								break;

							default:
								break;
						}
						this.status_notice = new Argus.Shared.Notice(
							"Could not restart the Argus agent service", detail);
						this.status_notice.title =
							"Argus Remote Management Agent " + Argus.VERSION;
						this.status_notice.add_response("ok", "OK");
						this.notice_up = true;
						this.status_notice.closed.connect(() => {
							this.notice_up = false;
						});
						this.status_notice.present(null);
						return false;
					});
					return 0;

				case 1002:
					this.present(true);
					return 0;

				case 1003:
					this.remote_active = false;
					this.set_tip(this.tip_text != "" ? this.tip_text : "Connected to management server");
					if (!this.rpc.connected) {
						return 0;
					}
					try {
						this.rpc.call_sync(new OLLMrpc.Request() {
							method = "AgentService.disconnect"
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
					return 0;

				default:
					return DefWindowProcW(hwnd, WM_COMMAND, wparam, lparam);
			}
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
			this.nid = Win32.NotifyIcon() {
				cb_size = (uint32) sizeof(Win32.NotifyIcon),
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
		 * Show a tray balloon.
		 *
		 * Same ''NIF_INFO'' modify as Snappr ''TrayKeeper.balloon''.
		 *
		 * @param title balloon title
		 * @param body balloon text
		 */
		private void balloon(string title, string body)
		{
			if (!this.added) {
				return;
			}
			var tip = Win32.NotifyIcon() {
				cb_size = (uint32) sizeof(Win32.NotifyIcon),
				hwnd = this.hwnd,
				id = 1,
				flags = NIF_INFO,
				info_flags = NIIF_INFO,
			};
			try {
				copy_wide(&tip.info_title[0], title.to_utf16(), 63);
				tip.info_title[63] = 0;
				copy_wide(&tip.info[0], body.to_utf16(), 255);
			} catch (GLib.ConvertError e) {
				return;
			}
			tip.info[255] = 0;
			Shell_NotifyIconW(NIM_MODIFY, &tip);
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
		private void present(bool allow_reregister = false)
		{
			if (this.registered && !allow_reregister) {
				return;
			}
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
				if (!this.rpc.connected) {
					this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					return;
				}
				try {
					var resp = this.rpc.call_sync(new OLLMrpc.Request() {
						method = "AgentService.register",
						args = OLLMrpc.args("ss", pin, hostport)
					});
					if (resp.error != null) {
						this.registration.pipe_code = resp.error.code;
						return;
					}
					var code = resp.retval.get_int();
					if (code == 0) {
						this.registered = true;
					}
					this.registration.pipe_code = code;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					this.registration.pipe_code = (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
			});
			this.window_up = true;
			this.registration.closed.connect(() => {
				this.window_up = false;
			});
			this.waiting_service = true;
			this.registration.show_add();
			if (this.rpc.connected) {
				this.waiting_service = false;
				this.registration.show_add();
			}
			this.registration.present(null);
		}
	}
}
