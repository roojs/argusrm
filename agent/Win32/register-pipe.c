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
