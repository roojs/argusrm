#ifndef ARGUS_WIN_PE_AUTHENTICODE_H
#define ARGUS_WIN_PE_AUTHENTICODE_H

#include <stdbool.h>
#include <wchar.h>

/* Filled by win_pe_read_authenticode; mirrors win_file_identity signer columns. */
typedef struct {
	char signing_result[64];
	char signer_cert_sha256[65];
	char signer_subject_key_id[128];
	char signer_publisher[256];
	char signer_issuer[512];
	char signer_serial[64];
} win_pe_authenticode;

bool win_pe_read_authenticode(const wchar_t *path, win_pe_authenticode *out);

#endif