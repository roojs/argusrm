/* Windows service control. Field names match the headers. */

[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "winsvc.h")]
namespace Argus.Agent.Win32 {

	[CCode (cname = "SERVICE_WIN32_OWN_PROCESS", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_WIN32_OWN_PROCESS;
	[CCode (cname = "SERVICE_START_PENDING", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_START_PENDING;
	[CCode (cname = "SERVICE_RUNNING", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_RUNNING;
	[CCode (cname = "SERVICE_STOP_PENDING", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_STOP_PENDING;
	[CCode (cname = "SERVICE_STOPPED", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_STOPPED;
	[CCode (cname = "SERVICE_ACCEPT_STOP", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_ACCEPT_STOP;
	[CCode (cname = "SERVICE_CONTROL_STOP", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_CONTROL_STOP;
	[CCode (cname = "SERVICE_CONTROL_INTERROGATE", cheader_filename = "winsvc.h")]
	public const uint32 SERVICE_CONTROL_INTERROGATE;
	[CCode (cname = "ERROR_FAILED_SERVICE_CONTROLLER_CONNECT", cheader_filename = "winerror.h")]
	public const uint32 ERROR_FAILED_SERVICE_CONTROLLER_CONNECT;

	[CCode (cheader_filename = "winsvc.h", has_type_id = false, destroy_function = "")]
	public struct SERVICE_STATUS {
		public uint32 dwServiceType;
		public uint32 dwCurrentState;
		public uint32 dwControlsAccepted;
		public uint32 dwWin32ExitCode;
		public uint32 dwServiceSpecificExitCode;
		public uint32 dwCheckPoint;
		public uint32 dwWaitHint;
	}

	[CCode (cheader_filename = "winsvc.h", has_target = false)]
	public delegate void LPSERVICE_MAIN_FUNCTIONW (uint32 dwArgc, uint16** lpServiceArgVectors);

	[CCode (cheader_filename = "winsvc.h", has_target = false)]
	public delegate void LPHANDLER_FUNCTION (uint32 dwControl);

	[CCode (cheader_filename = "winsvc.h", has_type_id = false, destroy_function = "")]
	public struct SERVICE_TABLE_ENTRYW {
		public uint16* lpServiceName;
		[CCode (delegate_target = false)]
		public unowned LPSERVICE_MAIN_FUNCTIONW lpServiceProc;
	}

	[CCode (cheader_filename = "winsvc.h")]
	public bool StartServiceCtrlDispatcherW ([CCode (array_length = false)] SERVICE_TABLE_ENTRYW[] lpServiceStartTable);

	[CCode (cheader_filename = "winsvc.h")]
	public void* RegisterServiceCtrlHandlerW (uint16* lpServiceName, LPHANDLER_FUNCTION lpHandlerProc);

	[CCode (cheader_filename = "winsvc.h")]
	public bool SetServiceStatus (void* hServiceStatus, ref SERVICE_STATUS lpServiceStatus);

	[CCode (cheader_filename = "errhandlingapi.h")]
	public uint32 GetLastError ();

	/* Tray icon. Copied from Snappr src/Win32/win32.vapi. */

	[CCode (cname = "NIF_MESSAGE", cheader_filename = "win32.h")]
	public const uint32 NIF_MESSAGE;
	[CCode (cname = "NIF_ICON", cheader_filename = "win32.h")]
	public const uint32 NIF_ICON;
	[CCode (cname = "NIF_TIP", cheader_filename = "win32.h")]
	public const uint32 NIF_TIP;
	[CCode (cname = "NIF_SHOWTIP", cheader_filename = "win32.h")]
	public const uint32 NIF_SHOWTIP;
	[CCode (cname = "NIM_ADD", cheader_filename = "win32.h")]
	public const uint32 NIM_ADD;
	[CCode (cname = "NIM_MODIFY", cheader_filename = "win32.h")]
	public const uint32 NIM_MODIFY;
	[CCode (cname = "NIM_DELETE", cheader_filename = "win32.h")]
	public const uint32 NIM_DELETE;
	[CCode (cname = "NIM_SETVERSION", cheader_filename = "win32.h")]
	public const uint32 NIM_SETVERSION;
	[CCode (cname = "NOTIFYICON_VERSION_4", cheader_filename = "win32.h")]
	public const uint32 NOTIFYICON_VERSION_4;
	[CCode (cname = "NIN_SELECT", cheader_filename = "win32.h")]
	public const uint32 NIN_SELECT;
	[CCode (cname = "NIN_KEYSELECT", cheader_filename = "win32.h")]
	public const uint32 NIN_KEYSELECT;
	[CCode (cname = "NIN_BALLOONUSERCLICK", cheader_filename = "win32.h")]
	public const uint32 NIN_BALLOONUSERCLICK;
	[CCode (cname = "WM_DESTROY", cheader_filename = "win32.h")]
	public const uint32 WM_DESTROY;
	[CCode (cname = "WM_QUIT", cheader_filename = "win32.h")]
	public const uint32 WM_QUIT;
	[CCode (cname = "WM_TIMER", cheader_filename = "win32.h")]
	public const uint32 WM_TIMER;
	[CCode (cname = "WM_LBUTTONUP", cheader_filename = "win32.h")]
	public const uint32 WM_LBUTTONUP;
	[CCode (cname = "WM_APP", cheader_filename = "win32.h")]
	public const uint32 WM_APP;
	[CCode (cname = "PM_REMOVE", cheader_filename = "win32.h")]
	public const uint32 PM_REMOVE;
	[CCode (cname = "QS_ALLINPUT", cheader_filename = "win32.h")]
	public const uint32 QS_ALLINPUT;
	[CCode (cname = "WAIT_OBJECT_0", cheader_filename = "win32.h")]
	public const uint32 WAIT_OBJECT_0;
	[CCode (cname = "INFINITE", cheader_filename = "win32.h")]
	public const uint32 INFINITE;
	[CCode (cname = "ERROR_CLASS_ALREADY_EXISTS", cheader_filename = "win32.h")]
	public const uint32 ERROR_CLASS_ALREADY_EXISTS;
	[CCode (cname = "IMAGE_ICON", cheader_filename = "win32.h")]
	public const uint32 IMAGE_ICON;
	[CCode (cname = "LR_DEFAULTSIZE", cheader_filename = "win32.h")]
	public const uint32 LR_DEFAULTSIZE;

	[CCode (cname = "MSG", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct Msg {
		[CCode (cname = "message")]
		public uint32 message;
	}

	[CCode (cname = "NOTIFYICONDATAW", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct NotifyIcon {
		[CCode (cname = "cbSize")]
		public uint32 cb_size;
		[CCode (cname = "hWnd")]
		public void* hwnd;
		[CCode (cname = "uID")]
		public uint32 id;
		[CCode (cname = "uFlags")]
		public uint32 flags;
		[CCode (cname = "uCallbackMessage")]
		public uint32 callback;
		[CCode (cname = "hIcon")]
		public void* icon;
		[CCode (array_length = false, cname = "szTip")]
		public uint16 tip[128];
		[CCode (array_length = false, cname = "szInfo")]
		public uint16 info[256];
		[CCode (cname = "uVersion")]
		public uint32 version;
		[CCode (array_length = false, cname = "szInfoTitle")]
		public uint16 info_title[64];
		[CCode (cname = "dwInfoFlags")]
		public uint32 info_flags;
	}

	[CCode (has_target = false, cname = "WNDPROC", cheader_filename = "win32.h")]
	public delegate int64 WndProc (void* hwnd, uint32 msg, uint64 wparam, int64 lparam);

	[CCode (cname = "WNDCLASSW", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct WndClass {
		[CCode (cname = "lpfnWndProc")]
		public WndProc proc;
		[CCode (cname = "hInstance")]
		public void* instance;
		[CCode (cname = "lpszClassName")]
		public string16 class_name;
		[CCode (cname = "hCursor")]
		public void* cursor;
		[CCode (cname = "hbrBackground")]
		public void* background;
	}

	[CCode (cname = "OutputDebugStringW", cheader_filename = "win32.h")]
	public void OutputDebugStringW (string16 text);
	[CCode (cname = "GetModuleHandleW", cheader_filename = "win32.h")]
	public void* GetModuleHandleW (void* module);
	[CCode (cname = "Sleep", cheader_filename = "win32.h")]
	public void Sleep (uint32 ms);
	[CCode (cname = "MsgWaitForMultipleObjects", cheader_filename = "win32.h")]
	public uint32 MsgWaitForMultipleObjects (uint32 count, [CCode (array_length = false)] void*[] handles, bool wait_all, uint32 ms, uint32 wake);
	[CCode (cname = "LoadImageW", cheader_filename = "win32.h")]
	public void* LoadImageW (void* instance, string16 name, uint32 type, int32 cx, int32 cy, uint32 load);
	[CCode (cname = "LoadIconW", cheader_filename = "win32.h")]
	public void* LoadIconW (void* instance, void* name);
	[CCode (cname = "Shell_NotifyIconW", cheader_filename = "win32.h")]
	public bool Shell_NotifyIconW (uint32 message, NotifyIcon* data);
	[CCode (cname = "RegisterClassW", cheader_filename = "win32.h")]
	public uint16 RegisterClassW (WndClass* klass);
	[CCode (cname = "RegisterWindowMessageW", cheader_filename = "win32.h")]
	public uint32 RegisterWindowMessageW (string16 name);
	[CCode (cname = "CreateWindowExW", cheader_filename = "win32.h")]
	public void* CreateWindowExW (uint32 ex_style, string16 class_name, string16 window_name, uint32 style, int32 x, int32 y, int32 width, int32 height, void* parent, void* menu, void* instance, void* param);
	[CCode (cname = "SetTimer", cheader_filename = "win32.h")]
	public void* SetTimer (void* hwnd, uint64 id, uint32 ms, void* proc);
	[CCode (cname = "KillTimer", cheader_filename = "win32.h")]
	public bool KillTimer (void* hwnd, uint64 id);
	[CCode (cname = "PeekMessageW", cheader_filename = "win32.h")]
	public bool PeekMessageW (out Msg msg, void* hwnd, uint32 min, uint32 max, uint32 remove);
	[CCode (cname = "TranslateMessage", cheader_filename = "win32.h")]
	public bool TranslateMessage (Msg* msg);
	[CCode (cname = "DispatchMessageW", cheader_filename = "win32.h")]
	public int64 DispatchMessageW (Msg* msg);
	[CCode (cname = "DefWindowProcW", cheader_filename = "win32.h")]
	public int64 DefWindowProcW (void* hwnd, uint32 msg, uint64 wparam, int64 lparam);
	[CCode (cname = "wcsncpy", cheader_filename = "win32.h")]
	public void copy_wide (uint16* dest, string16 src, uint64 count);
	[CCode (cname = "g_utf8_to_utf16")]
	public string16 g_utf8_to_utf16 (string str, long len = -1, void* items_read = null,
		void* items_written = null, void* error = null);
}
