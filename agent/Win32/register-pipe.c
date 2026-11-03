#include "win32.h"
#include <sddl.h>

HANDLE
argus_create_registration_pipe(void)
{
	PSECURITY_DESCRIPTOR descriptor = NULL;
	SECURITY_ATTRIBUTES security = {
		sizeof(SECURITY_ATTRIBUTES),
		NULL,
		FALSE
	};
	HANDLE pipe;

	if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
		L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)",
		SDDL_REVISION_1,
		&descriptor,
		NULL)) {
		return INVALID_HANDLE_VALUE;
	}
	security.lpSecurityDescriptor = descriptor;
	pipe = CreateNamedPipeW(
		L"\\\\.\\pipe\\Argus.Register",
		PIPE_ACCESS_DUPLEX,
		PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT |
			PIPE_REJECT_REMOTE_CLIENTS,
		1,
		4096,
		4096,
		0,
		&security);
	LocalFree(descriptor);
	return pipe;
}
