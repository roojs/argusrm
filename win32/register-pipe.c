#include "win32.h"

DWORD
argus_active_session(void)
{
	PWTS_SESSION_INFOW info = NULL;
	DWORD count = 0;
	DWORD session = 0xFFFFFFFF;
	DWORD i;

	if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &info, &count)) {
		return 0xFFFFFFFF;
	}
	for (i = 0; i < count; i++) {
		if (info[i].State != WTSActive || info[i].SessionId == 0) {
			continue;
		}
		session = info[i].SessionId;
		break;
	}
	WTSFreeMemory(info);
	return session;
}

static int
argus_is_rdp(const WCHAR *name)
{
	WCHAR a;
	WCHAR b;
	WCHAR c;

	if (name == NULL || name[0] == 0 || name[1] == 0 || name[2] == 0) {
		return 0;
	}
	a = name[0];
	b = name[1];
	c = name[2];
	if (a >= L'a' && a <= L'z') {
		a = (WCHAR) (a - 32);
	}
	if (b >= L'a' && b <= L'z') {
		b = (WCHAR) (b - 32);
	}
	if (c >= L'a' && c <= L'z') {
		c = (WCHAR) (c - 32);
	}
	return a == L'R' && b == L'D' && c == L'P';
}

void
argus_end_rdp_sessions(void)
{
	PWTS_SESSION_INFOW info = NULL;
	DWORD count = 0;
	DWORD i;

	if (!WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &info, &count)) {
		return;
	}
	for (i = 0; i < count; i++) {
		if (info[i].SessionId == 0) {
			continue;
		}
		if (info[i].State != WTSActive && info[i].State != WTSDisconnected) {
			continue;
		}
		if (!argus_is_rdp(info[i].pWinStationName)) {
			continue;
		}
		WTSLogoffSession(WTS_CURRENT_SERVER_HANDLE, info[i].SessionId, TRUE);
	}
	WTSFreeMemory(info);
}
