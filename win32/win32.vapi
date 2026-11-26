/* Windows service control. Field names match the headers. */

[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "win32.h")]
namespace Win32 {

	[CCode (cname = "SERVICE_WIN32_OWN_PROCESS", cheader_filename = "win32.h")]
	public const uint32 SERVICE_WIN32_OWN_PROCESS;
	[CCode (cname = "SERVICE_START_PENDING", cheader_filename = "win32.h")]
	public const uint32 SERVICE_START_PENDING;
	[CCode (cname = "SERVICE_RUNNING", cheader_filename = "win32.h")]
	public const uint32 SERVICE_RUNNING;
	[CCode (cname = "SERVICE_STOP_PENDING", cheader_filename = "win32.h")]
	public const uint32 SERVICE_STOP_PENDING;
	[CCode (cname = "SERVICE_STOPPED", cheader_filename = "win32.h")]
	public const uint32 SERVICE_STOPPED;
	[CCode (cname = "SERVICE_ACCEPT_STOP", cheader_filename = "win32.h")]
	public const uint32 SERVICE_ACCEPT_STOP;
	[CCode (cname = "SERVICE_CONTROL_STOP", cheader_filename = "win32.h")]
	public const uint32 SERVICE_CONTROL_STOP;
	[CCode (cname = "SERVICE_CONTROL_INTERROGATE", cheader_filename = "win32.h")]
	public const uint32 SERVICE_CONTROL_INTERROGATE;
	[CCode (cname = "ERROR_FAILED_SERVICE_CONTROLLER_CONNECT", cheader_filename = "win32.h")]
	public const uint32 ERROR_FAILED_SERVICE_CONTROLLER_CONNECT;
	[CCode (cname = "ERROR_SERVICE_ALREADY_RUNNING", cheader_filename = "win32.h")]
	public const uint32 ERROR_SERVICE_ALREADY_RUNNING;
	[CCode (cname = "SC_MANAGER_CONNECT", cheader_filename = "win32.h")]
	public const uint32 SC_MANAGER_CONNECT;
	[CCode (cname = "SERVICE_QUERY_STATUS", cheader_filename = "win32.h")]
	public const uint32 SERVICE_QUERY_STATUS;
	[CCode (cname = "SERVICE_START", cheader_filename = "win32.h")]
	public const uint32 SERVICE_START;
	[CCode (cname = "SERVICE_CHANGE_CONFIG", cheader_filename = "win32.h")]
	public const uint32 SERVICE_CHANGE_CONFIG;
	[CCode (cname = "SERVICE_AUTO_START", cheader_filename = "win32.h")]
	public const uint32 SERVICE_AUTO_START;
	[CCode (cname = "SERVICE_NO_CHANGE", cheader_filename = "win32.h")]
	public const uint32 SERVICE_NO_CHANGE;
	[CCode (cname = "KEY_SET_VALUE", cheader_filename = "win32.h")]
	public const uint32 KEY_SET_VALUE;
	[CCode (cname = "REG_DWORD", cheader_filename = "win32.h")]
	public const uint32 REG_DWORD;
	[CCode (cname = "SERVICE_STOP", cheader_filename = "win32.h")]
	public const uint32 SERVICE_STOP;
	[CCode (cname = "SC_STATUS_PROCESS_INFO", cheader_filename = "win32.h")]
	public const uint32 SC_STATUS_PROCESS_INFO;

	[CCode (cheader_filename = "win32.h", has_type_id = false, destroy_function = "")]
	public struct SERVICE_STATUS {
		public uint32 dwServiceType;
		public uint32 dwCurrentState;
		public uint32 dwControlsAccepted;
		public uint32 dwWin32ExitCode;
		public uint32 dwServiceSpecificExitCode;
		public uint32 dwCheckPoint;
		public uint32 dwWaitHint;
	}

	[CCode (cheader_filename = "win32.h", has_type_id = false, destroy_function = "")]
	public struct SERVICE_STATUS_PROCESS {
		public uint32 dwServiceType;
		public uint32 dwCurrentState;
		public uint32 dwControlsAccepted;
		public uint32 dwWin32ExitCode;
		public uint32 dwServiceSpecificExitCode;
		public uint32 dwCheckPoint;
		public uint32 dwWaitHint;
		public uint32 dwProcessId;
		public uint32 dwServiceFlags;
	}

	[CCode (cheader_filename = "win32.h", has_target = false)]
	public delegate void LPSERVICE_MAIN_FUNCTIONW (uint32 dwArgc, uint16** lpServiceArgVectors);

	[CCode (cheader_filename = "win32.h", has_target = false)]
	public delegate void LPHANDLER_FUNCTION (uint32 dwControl);

	[CCode (cheader_filename = "win32.h", has_type_id = false, destroy_function = "")]
	public struct SERVICE_TABLE_ENTRYW {
		public uint16* lpServiceName;
		[CCode (delegate_target = false)]
		public unowned LPSERVICE_MAIN_FUNCTIONW lpServiceProc;
	}

	[CCode (cheader_filename = "win32.h")]
	public bool StartServiceCtrlDispatcherW ([CCode (array_length = false)] SERVICE_TABLE_ENTRYW[] lpServiceStartTable);

	[CCode (cheader_filename = "win32.h")]
	public void* RegisterServiceCtrlHandlerW (uint16* lpServiceName, LPHANDLER_FUNCTION lpHandlerProc);

	[CCode (cheader_filename = "win32.h")]
	public bool SetServiceStatus (void* hServiceStatus, ref SERVICE_STATUS lpServiceStatus);

	[CCode (cheader_filename = "win32.h")]
	public void* OpenSCManagerW (void* lpMachineName, void* lpDatabaseName, uint32 dwDesiredAccess);

	[CCode (cheader_filename = "win32.h")]
	public void* OpenServiceW (void* hSCManager, string16 lpServiceName, uint32 dwDesiredAccess);

	[CCode (cheader_filename = "win32.h")]
	public bool CloseServiceHandle (void* hSCObject);

	[CCode (cheader_filename = "win32.h")]
	public bool ControlService (void* hService, uint32 dwControl, ref SERVICE_STATUS lpServiceStatus);

	[CCode (cheader_filename = "win32.h")]
	public bool StartServiceW (void* hService, uint32 dwNumServiceArgs, void* lpServiceArgVectors);

	[CCode (cheader_filename = "win32.h")]
	public bool ChangeServiceConfigW (void* hService, uint32 dwServiceType, uint32 dwStartType,
		uint32 dwErrorControl, void* lpBinaryPathName, void* lpLoadOrderGroup, void* lpdwTagId,
		void* lpDependencies, void* lpServiceStartName, void* lpPassword, void* lpDisplayName);

	[CCode (cheader_filename = "win32.h")]
	public void* argus_hkey_local_machine ();

	[CCode (cheader_filename = "win32.h")]
	public int32 RegOpenKeyExW (void* hKey, string16 lpSubKey, uint32 ulOptions, uint32 samDesired, void* phkResult);

	[CCode (cheader_filename = "win32.h")]
	public int32 RegSetValueExW (void* hKey, string16 lpValueName, uint32 reserved, uint32 dwType, void* lpData, uint32 cbData);

	[CCode (cheader_filename = "win32.h")]
	public int32 RegCloseKey (void* hKey);

	[CCode (cheader_filename = "win32.h")]
	public bool QueryServiceStatusEx (void* hService, uint32 InfoLevel, void* lpBuffer, uint32 cbBufSize, void* pcbBytesNeeded);

	[CCode (cheader_filename = "win32.h")]
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
	[CCode (cname = "NIF_INFO", cheader_filename = "win32.h")]
	public const uint32 NIF_INFO;
	[CCode (cname = "NIIF_INFO", cheader_filename = "win32.h")]
	public const uint32 NIIF_INFO;
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
	[CCode (cname = "WM_NULL", cheader_filename = "win32.h")]
	public const uint32 WM_NULL;
	[CCode (cname = "WM_DESTROY", cheader_filename = "win32.h")]
	public const uint32 WM_DESTROY;
	[CCode (cname = "WM_QUIT", cheader_filename = "win32.h")]
	public const uint32 WM_QUIT;
	[CCode (cname = "WM_TIMER", cheader_filename = "win32.h")]
	public const uint32 WM_TIMER;
	[CCode (cname = "WM_COMMAND", cheader_filename = "win32.h")]
	public const uint32 WM_COMMAND;
	[CCode (cname = "WM_CONTEXTMENU", cheader_filename = "win32.h")]
	public const uint32 WM_CONTEXTMENU;
	[CCode (cname = "WM_LBUTTONUP", cheader_filename = "win32.h")]
	public const uint32 WM_LBUTTONUP;
	[CCode (cname = "WM_RBUTTONUP", cheader_filename = "win32.h")]
	public const uint32 WM_RBUTTONUP;
	[CCode (cname = "WM_APP", cheader_filename = "win32.h")]
	public const uint32 WM_APP;
	[CCode (cname = "WS_POPUP", cheader_filename = "win32.h")]
	public const uint32 WS_POPUP;
	[CCode (cname = "WS_EX_TOOLWINDOW", cheader_filename = "win32.h")]
	public const uint32 WS_EX_TOOLWINDOW;
	[CCode (cname = "WS_EX_NOACTIVATE", cheader_filename = "win32.h")]
	public const uint32 WS_EX_NOACTIVATE;
	[CCode (cname = "MF_STRING", cheader_filename = "win32.h")]
	public const uint32 MF_STRING;
	[CCode (cname = "MF_GRAYED", cheader_filename = "win32.h")]
	public const uint32 MF_GRAYED;
	[CCode (cname = "MF_SEPARATOR", cheader_filename = "win32.h")]
	public const uint32 MF_SEPARATOR;
	[CCode (cname = "TPM_RIGHTBUTTON", cheader_filename = "win32.h")]
	public const uint32 TPM_RIGHTBUTTON;
	[CCode (cname = "SW_SHOWNORMAL", cheader_filename = "win32.h")]
	public const int32 SW_SHOWNORMAL;
	[CCode (cname = "SEE_MASK_NOCLOSEPROCESS", cheader_filename = "win32.h")]
	public const uint32 SEE_MASK_NOCLOSEPROCESS;
	[CCode (cname = "SEE_MASK_FLAG_NO_UI", cheader_filename = "win32.h")]
	public const uint32 SEE_MASK_FLAG_NO_UI;
	[CCode (cname = "ERROR_CANCELLED", cheader_filename = "win32.h")]
	public const uint32 ERROR_CANCELLED;
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

	[CCode (cname = "POINT", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct POINT {
		public int32 x;
		public int32 y;
	}

	[CCode (cname = "SHELLEXECUTEINFOW", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct SHELLEXECUTEINFOW {
		public uint32 cbSize;
		public uint32 fMask;
		public void* hwnd;
		public unowned string16 lpVerb;
		public unowned string16 lpFile;
		public unowned string16 lpParameters;
		public unowned string16 lpDirectory;
		public int32 nShow;
		public void* hInstApp;
		public void* hProcess;
	}

	[CCode (cname = "MSG", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct Msg {
		[CCode (cname = "message")]
		public uint32 message;
	}

	[CCode (cname = "LASTINPUTINFO", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct LastInputInfo {
		[CCode (cname = "cbSize")]
		public uint32 cb_size;
		[CCode (cname = "dwTime")]
		public uint32 time;
	}

	[CCode (cname = "GetLastInputInfo", cheader_filename = "win32.h")]
	public bool GetLastInputInfo (ref LastInputInfo info);

	[CCode (cname = "GetTickCount", cheader_filename = "win32.h")]
	public uint32 GetTickCount ();

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
	[CCode (cname = "ShellExecuteExW", cheader_filename = "win32.h")]
	public bool ShellExecuteExW (ref SHELLEXECUTEINFOW info);
	[CCode (cname = "GetCursorPos", cheader_filename = "win32.h")]
	public bool GetCursorPos (out POINT pt);
	[CCode (cname = "CreatePopupMenu", cheader_filename = "win32.h")]
	public void* CreatePopupMenu ();
	[CCode (cname = "AppendMenuW", cheader_filename = "win32.h")]
	public bool AppendMenuW (void* menu, uint32 flags, uint64 id, void* text);
	[CCode (cname = "DestroyMenu", cheader_filename = "win32.h")]
	public bool DestroyMenu (void* menu);
	[CCode (cname = "SetForegroundWindow", cheader_filename = "win32.h")]
	public bool SetForegroundWindow (void* hwnd);
	[CCode (cname = "TrackPopupMenu", cheader_filename = "win32.h")]
	public bool TrackPopupMenu (void* menu, uint32 flags, int32 x, int32 y, int32 reserved, void* hwnd, void* rect);
	[CCode (cname = "PostMessageW", cheader_filename = "win32.h")]
	public bool PostMessageW (void* hwnd, uint32 msg, uint64 wparam, int64 lparam);
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

	/* Process and pipe. Copied from Snappr src/Win32/win32.vapi.
	 * CreateProcessAsUserW is the service launch into the signed-in
	 * session. Snappr starts its tray with CreateProcessW. */

	[CCode (cname = "WAIT_TIMEOUT", cheader_filename = "win32.h")]
	public const uint32 WAIT_TIMEOUT;
	[CCode (cname = "ERROR_IO_PENDING", cheader_filename = "win32.h")]
	public const uint32 ERROR_IO_PENDING;
	[CCode (cname = "ERROR_PIPE_CONNECTED", cheader_filename = "win32.h")]
	public const uint32 ERROR_PIPE_CONNECTED;
	[CCode (cname = "ERROR_PIPE_LISTENING", cheader_filename = "win32.h")]
	public const uint32 ERROR_PIPE_LISTENING;
	[CCode (cname = "ERROR_NO_DATA", cheader_filename = "win32.h")]
	public const uint32 ERROR_NO_DATA;
	[CCode (cname = "ERROR_BROKEN_PIPE", cheader_filename = "win32.h")]
	public const uint32 ERROR_BROKEN_PIPE;
	[CCode (cname = "GENERIC_READ", cheader_filename = "win32.h")]
	public const uint32 GENERIC_READ;
	[CCode (cname = "GENERIC_WRITE", cheader_filename = "win32.h")]
	public const uint32 GENERIC_WRITE;
	[CCode (cname = "OPEN_EXISTING", cheader_filename = "win32.h")]
	public const uint32 OPEN_EXISTING;
	[CCode (cname = "FILE_ATTRIBUTE_NORMAL", cheader_filename = "win32.h")]
	public const uint32 FILE_ATTRIBUTE_NORMAL;
	[CCode (cname = "FILE_FLAG_OVERLAPPED", cheader_filename = "win32.h")]
	public const uint32 FILE_FLAG_OVERLAPPED;
	[CCode (cname = "PIPE_ACCESS_DUPLEX", cheader_filename = "win32.h")]
	public const uint32 PIPE_ACCESS_DUPLEX;
	[CCode (cname = "PIPE_TYPE_MESSAGE", cheader_filename = "win32.h")]
	public const uint32 PIPE_TYPE_MESSAGE;
	[CCode (cname = "PIPE_READMODE_MESSAGE", cheader_filename = "win32.h")]
	public const uint32 PIPE_READMODE_MESSAGE;
	[CCode (cname = "PIPE_WAIT", cheader_filename = "win32.h")]
	public const uint32 PIPE_WAIT;
	[CCode (cname = "PIPE_NOWAIT", cheader_filename = "win32.h")]
	public const uint32 PIPE_NOWAIT;
	[CCode (cname = "PROCESS_QUERY_LIMITED_INFORMATION", cheader_filename = "win32.h")]
	public const uint32 PROCESS_QUERY_LIMITED_INFORMATION;
	[CCode (cname = "PROCESS_TERMINATE", cheader_filename = "win32.h")]
	public const uint32 PROCESS_TERMINATE;
	[CCode (cname = "SYNCHRONIZE", cheader_filename = "win32.h")]
	public const uint32 SYNCHRONIZE;
	[CCode (cname = "MAXIMUM_ALLOWED", cheader_filename = "win32.h")]
	public const uint32 MAXIMUM_ALLOWED;
	[CCode (cname = "SecurityIdentification", cheader_filename = "win32.h")]
	public const int SecurityIdentification;
	[CCode (cname = "TokenPrimary", cheader_filename = "win32.h")]
	public const int TokenPrimary;

	[CCode (cname = "OVERLAPPED", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct Overlapped {
		[CCode (cname = "hEvent")]
		public void* event;
	}

	[CCode (cname = "STARTUPINFOW", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct StartupInfo {
		[CCode (cname = "cb")]
		public uint32 cb;
		[CCode (cname = "lpReserved")]
		public string16 reserved;
		[CCode (cname = "lpDesktop")]
		public string16 desktop;
		[CCode (cname = "lpTitle")]
		public string16 title;
		[CCode (cname = "dwX")]
		public uint32 x;
		[CCode (cname = "dwY")]
		public uint32 y;
		[CCode (cname = "dwXSize")]
		public uint32 width;
		[CCode (cname = "dwYSize")]
		public uint32 height;
		[CCode (cname = "dwXCountChars")]
		public uint32 x_chars;
		[CCode (cname = "dwYCountChars")]
		public uint32 y_chars;
		[CCode (cname = "dwFillAttribute")]
		public uint32 fill;
		[CCode (cname = "dwFlags")]
		public uint32 flags;
		[CCode (cname = "wShowWindow")]
		public uint16 show;
		[CCode (cname = "cbReserved2")]
		public uint16 reserved2;
		[CCode (cname = "lpReserved2")]
		public void* reserved2_bytes;
		[CCode (cname = "hStdInput")]
		public void* stdin_handle;
		[CCode (cname = "hStdOutput")]
		public void* stdout_handle;
		[CCode (cname = "hStdError")]
		public void* stderr_handle;
	}

	[CCode (cname = "PROCESS_INFORMATION", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct ProcessInfo {
		[CCode (cname = "hProcess")]
		public void* process;
		[CCode (cname = "hThread")]
		public void* thread;
		[CCode (cname = "dwProcessId")]
		public uint32 pid;
		[CCode (cname = "dwThreadId")]
		public uint32 tid;
	}

	[CCode (cname = "SECURITY_ATTRIBUTES", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct SecurityAttributes {
		[CCode (cname = "nLength")]
		public uint32 length;
		[CCode (cname = "lpSecurityDescriptor")]
		public void* descriptor;
		[CCode (cname = "bInheritHandle")]
		public bool inherit;
	}

	[CCode (cname = "JOBOBJECT_ASSOCIATE_COMPLETION_PORT", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct JobCompletionPort {
		[CCode (cname = "CompletionKey")]
		public void* key;
		[CCode (cname = "CompletionPort")]
		public void* port;
	}

	[CCode (cname = "GetModuleFileNameW", cheader_filename = "win32.h")]
	public uint32 GetModuleFileNameW (void* module, string16 name, uint32 size);
	[CCode (cname = "CloseHandle", cheader_filename = "win32.h")]
	public bool CloseHandle (void* handle);
	[CCode (cname = "CreateFileW", cheader_filename = "win32.h")]
	public void* CreateFileW (string16 name, uint32 access, uint32 share, void* security, uint32 disposition, uint32 flags, void* template);
	[CCode (cname = "CreateNamedPipeW", cheader_filename = "win32.h")]
	public void* CreateNamedPipeW (string16 name, uint32 open_mode, uint32 mode, uint32 instances, uint32 out_size, uint32 in_size, uint32 timeout, void* security);
	[CCode (cheader_filename = "win32.h")]
	public uint32 argus_active_session ();
	[CCode (cheader_filename = "win32.h")]
	public void argus_end_rdp_sessions ();
	[CCode (cname = "LoadLibraryW", cheader_filename = "win32.h")]
	public void* LoadLibraryW (string16 path);
	[CCode (cname = "GetProcAddress", cheader_filename = "win32.h")]
	public void* GetProcAddress (void* module, string name);
	[CCode (cname = "ERROR_OBJECT_ALREADY_EXISTS", cheader_filename = "win32.h")]
	public const uint32 ERROR_OBJECT_ALREADY_EXISTS;
	[CCode (cname = "ERROR_NO_MORE_ITEMS", cheader_filename = "win32.h")]
	public const uint32 ERROR_NO_MORE_ITEMS;

	[CCode (has_target = false)]
	public delegate void* WintunCreateAdapter (string16 name, string16 tunnel_type, void* guid);
	[CCode (has_target = false)]
	public delegate void* WintunOpenAdapter (string16 name);
	[CCode (has_target = false)]
	public delegate void WintunCloseAdapter (void* adapter);
	[CCode (has_target = false)]
	public delegate void WintunGetLuid (void* adapter, out uint64 luid);
	[CCode (has_target = false)]
	public delegate void* WintunStartSession (void* adapter, uint32 capacity);
	[CCode (has_target = false)]
	public delegate void* WintunReceive (void* session, out uint32 size);
	[CCode (has_target = false)]
	public delegate void WintunRelease (void* session, void* packet);
	[CCode (has_target = false)]
	public delegate void* WintunAllocSend (void* session, uint32 size);
	[CCode (has_target = false)]
	public delegate void WintunSend (void* session, void* packet);
	[CCode (has_target = false)]
	public delegate void* WintunWait (void* session);

	[CCode (cheader_filename = "adapter-row.h")]
	public uint32 argus_adapter_address (uint64 luid, string ip, uint8 prefix);
	[CCode (cheader_filename = "adapter-row.h")]
	public uint32 argus_adapter_route (uint64 luid, string ip);
	[CCode (cheader_filename = "adapter-row.h")]
	public uint32 argus_adapter_neighbor (uint64 luid, string ip);
	[CCode (cheader_filename = "adapter-row.h")]
	public void argus_adapter_read ([CCode (array_length = false)] uint8[] dest, void* src, uint32 n);
	[CCode (cheader_filename = "adapter-row.h")]
	public void argus_adapter_write (void* dest, [CCode (array_length = false)] uint8[] src, uint32 n);
	[CCode (cheader_filename = "adapter-row.h")]
	public void argus_adapter_move ([CCode (array_length = false)] uint8[] dest, uint32 dest_off, [CCode (array_length = false)] uint8[] src, uint32 n);
	[CCode (cname = "ConnectNamedPipe", cheader_filename = "win32.h")]
	public bool ConnectNamedPipe (void* pipe, Overlapped* ov);
	[CCode (cname = "DisconnectNamedPipe", cheader_filename = "win32.h")]
	public bool DisconnectNamedPipe (void* pipe);
	[CCode (cname = "SetNamedPipeHandleState", cheader_filename = "win32.h")]
	public bool SetNamedPipeHandleState (void* pipe, ref uint32 mode, void* max, void* timeout);
	[CCode (cname = "PeekNamedPipe", cheader_filename = "win32.h")]
	public bool PeekNamedPipe (void* pipe, void* buffer, uint32 size, void* read, out uint32 avail, void* left);
	[CCode (cname = "ReadFile", cheader_filename = "win32.h")]
	public bool ReadFile (void* file, [CCode (array_length = false)] uint8[] buffer, uint32 bytes, out uint32 read, Overlapped* ov);
	[CCode (cname = "WriteFile", cheader_filename = "win32.h")]
	public bool WriteFile (void* file, [CCode (array_length = false)] uint8[] buffer, uint32 bytes, out uint32 written, Overlapped* ov);
	[CCode (cname = "CreateProcessAsUserW", cheader_filename = "win32.h")]
	public bool CreateProcessAsUserW (void* token, string16? app, [CCode (array_length = false)] uint16[]? command, void* process_attr, void* thread_attr, bool inherit, uint32 flags, [CCode (array_length = false)] uint16[]? env, string16? cwd, StartupInfo* startup, out ProcessInfo info);
	[CCode (cname = "CreateProcessW", cheader_filename = "win32.h")]
	public bool CreateProcessW (string16? app, [CCode (array_length = false)] uint16[]? command, void* process_attr, void* thread_attr, bool inherit, uint32 flags, [CCode (array_length = false)] uint16[]? env, string16? cwd, StartupInfo* startup, out ProcessInfo info);
	[CCode (cname = "CREATE_SUSPENDED", cheader_filename = "win32.h")]
	public const uint32 CREATE_SUSPENDED;
	[CCode (cname = "CREATE_UNICODE_ENVIRONMENT", cheader_filename = "win32.h")]
	public const uint32 CREATE_UNICODE_ENVIRONMENT;
	[CCode (cname = "STARTF_USESTDHANDLES", cheader_filename = "win32.h")]
	public const uint32 STARTF_USESTDHANDLES;
	[CCode (cname = "HANDLE_FLAG_INHERIT", cheader_filename = "win32.h")]
	public const uint32 HANDLE_FLAG_INHERIT;
	[CCode (cname = "JobObjectAssociateCompletionPortInformation", cheader_filename = "win32.h")]
	public const int JobObjectAssociateCompletionPortInformation;
	[CCode (cname = "JOB_OBJECT_MSG_NEW_PROCESS", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_NEW_PROCESS;
	[CCode (cname = "JOB_OBJECT_MSG_EXIT_PROCESS", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_EXIT_PROCESS;
	[CCode (cname = "JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS;
	[CCode (cname = "JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO", cheader_filename = "win32.h")]
	public const uint32 JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO;
	[CCode (cname = "_O_RDONLY", cheader_filename = "win32.h")]
	public const int O_RDONLY;
	[CCode (cname = "_O_WRONLY", cheader_filename = "win32.h")]
	public const int O_WRONLY;
	[CCode (cname = "_O_BINARY", cheader_filename = "win32.h")]
	public const int O_BINARY;
	[CCode (cname = "CreateJobObjectW", cheader_filename = "win32.h")]
	public void* CreateJobObjectW (void* security, string16? name);
	[CCode (cname = "SetInformationJobObject", cheader_filename = "win32.h")]
	public bool SetInformationJobObject (void* job, int klass, void* info, uint32 length);
	[CCode (cname = "AssignProcessToJobObject", cheader_filename = "win32.h")]
	public bool AssignProcessToJobObject (void* job, void* process);
	[CCode (cname = "CreateIoCompletionPort", cheader_filename = "win32.h")]
	public void* CreateIoCompletionPort (void* file, void* existing, uint64 key, uint32 threads);
	[CCode (cname = "GetQueuedCompletionStatus", cheader_filename = "win32.h")]
	public bool GetQueuedCompletionStatus (void* port, out uint32 bytes, out uint64 key, out void* overlapped, uint32 ms);
	[CCode (cname = "ResumeThread", cheader_filename = "win32.h")]
	public uint32 ResumeThread (void* thread);
	[CCode (cname = "CreatePipe", cheader_filename = "win32.h")]
	public bool CreatePipe (out void* read, out void* write, SecurityAttributes* security, uint32 size);
	[CCode (cname = "SetHandleInformation", cheader_filename = "win32.h")]
	public bool SetHandleInformation (void* handle, uint32 mask, uint32 flags);
	[CCode (cname = "SearchPathW", cheader_filename = "win32.h")]
	public uint32 SearchPathW (string16? path, string16 file, string16? extension, uint32 size, string16 buffer, void* part);
	[CCode (cname = "wcslen", cheader_filename = "win32.h")]
	public uint64 wide_length (string16 text);
	[CCode (cname = "argus_wide_at", cheader_filename = "win32.h")]
	public uint16 wide_at (string16 text, uint64 index);
	[CCode (cname = "argus_invalid_handle", cheader_filename = "win32.h")]
	public void* invalid_handle ();
	[CCode (cname = "argus_open_osfhandle", cheader_filename = "win32.h")]
	public int open_osfhandle (void* handle, int flags);
	[CCode (cname = "_close", cheader_filename = "win32.h")]
	public int close_fd (int fd);
	[CCode (cname = "OpenProcess", cheader_filename = "win32.h")]
	public void* OpenProcess (uint32 access, bool inherit, uint32 pid);
	[CCode (cname = "GetCurrentProcessId", cheader_filename = "win32.h")]
	public uint32 GetCurrentProcessId ();
	[CCode (cname = "WaitForSingleObject", cheader_filename = "win32.h")]
	public uint32 WaitForSingleObject (void* handle, uint32 ms);
	[CCode (cname = "TerminateProcess", cheader_filename = "win32.h")]
	public bool TerminateProcess (void* process, uint32 code);
	[CCode (cname = "GetExitCodeProcess", cheader_filename = "win32.h")]
	public bool GetExitCodeProcess (void* process, void* code);
	[CCode (cname = "FILETIME", has_type_id = false, destroy_function = "", cheader_filename = "win32.h")]
	public struct FileTime {
		[CCode (cname = "dwLowDateTime")]
		public uint32 low;
		[CCode (cname = "dwHighDateTime")]
		public uint32 high;
	}
	[CCode (cname = "GetProcessTimes", cheader_filename = "win32.h")]
	public bool GetProcessTimes (void* process, out FileTime created, out FileTime exited, out FileTime kernel, out FileTime user);
	[CCode (cname = "EnumProcesses", cheader_filename = "win32.h")]
	public bool EnumProcesses ([CCode (array_length = false)] uint32[] ids, uint32 bytes, out uint32 needed);
	[CCode (cname = "QueryFullProcessImageNameW", cheader_filename = "win32.h")]
	public bool QueryFullProcessImageNameW (void* process, uint32 flags, string16 name, ref uint32 size);
	[CCode (cname = "WTSGetActiveConsoleSessionId", cheader_filename = "win32.h")]
	public uint32 WTSGetActiveConsoleSessionId ();
	[CCode (cname = "WTSQueryUserToken", cheader_filename = "win32.h")]
	public bool WTSQueryUserToken (uint32 session, out void* token);
	[CCode (cname = "DuplicateTokenEx", cheader_filename = "win32.h")]
	public bool DuplicateTokenEx (void* existing, uint32 access, void* attr, int level, int type, out void* dup);

	/* Application log. EvtSubscribe is the package monitor. */

	[CCode (cname = "EvtSubscribeToFutureEvents", cheader_filename = "win32.h")]
	public const uint32 EvtSubscribeToFutureEvents;
	[CCode (cheader_filename = "win32.h", has_target = false)]
	public delegate uint32 EVT_SUBSCRIBE_CALLBACK (int action, void* context, void* event);
	[CCode (cname = "EvtSubscribe", cheader_filename = "win32.h")]
	public void* EvtSubscribe (void* session, void* signal, string16 channel, string16 query,
		void* bookmark, void* context, EVT_SUBSCRIBE_CALLBACK callback, uint32 flags);

	/* PE Authenticode (pe-authenticode.c). */

	[CCode (cname = "win_pe_authenticode", cheader_filename = "pe-authenticode.h", has_type_id = false)]
	public struct WinPeAuthenticode {
		public char signing_result[64];
		public char signer_cert_sha256[65];
		public char signer_subject_key_id[128];
		public char signer_publisher[256];
		public char signer_issuer[512];
		public char signer_serial[64];
	}

	[CCode (cname = "win_pe_read_authenticode", cheader_filename = "pe-authenticode.h")]
	public bool win_pe_read_authenticode (string16 path, ref WinPeAuthenticode out);
}
