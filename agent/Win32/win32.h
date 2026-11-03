/* Include order for the tray binding. No program logic.
 * Same includes as Snappr src/Win32/win32.h. */
#ifndef ARGUS_WIN32_H
#define ARGUS_WIN32_H

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#ifndef _WIN32_IE
#define _WIN32_IE 0x0601
#endif

#include <windows.h>
#include <shellapi.h>
#include <commctrl.h>
#include <psapi.h>
#include <wtsapi32.h>
#include <wchar.h>

HANDLE argus_create_registration_pipe(void);

#endif
