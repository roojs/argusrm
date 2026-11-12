/* Include order for the Windows binding. No program logic.
 * Tray headers match Snappr src/Win32/win32.h. winsvc.h and
 * wtsapi32.h are the service additions. winevt.h follows
 * windows.h. It uses those types.
 */
#ifndef ARGUS_WIN32_H
#define ARGUS_WIN32_H

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#ifndef _WIN32_IE
#define _WIN32_IE 0x0601
#endif

#include <windows.h>
#include <winsvc.h>
#include <shellapi.h>
#include <commctrl.h>
#include <psapi.h>
#include <wtsapi32.h>
#include <wchar.h>
#include <winevt.h>

HANDLE argus_create_registration_pipe(void);
DWORD argus_active_session(void);

#endif
