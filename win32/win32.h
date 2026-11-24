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
#include <io.h>
#include <fcntl.h>

DWORD argus_active_session(void);

/* INVALID_HANDLE_VALUE is a macro. Vala needs a real function. */
static inline HANDLE argus_invalid_handle(void)
{
	return INVALID_HANDLE_VALUE;
}

/* HKEY_LOCAL_MACHINE is a macro. Vala needs a real function. */
static inline HKEY argus_hkey_local_machine(void)
{
	return HKEY_LOCAL_MACHINE;
}

/* _open_osfhandle takes intptr_t. The Vala side has a HANDLE. */
static inline int argus_open_osfhandle(HANDLE handle, int flags)
{
	return _open_osfhandle((intptr_t) handle, flags);
}

/* string16 has no index operator. This reads one UTF-16 unit. */
static inline unsigned short argus_wide_at(const wchar_t *text, size_t index)
{
	return (unsigned short) text[index];
}

#endif
