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
}
