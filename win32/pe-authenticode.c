#include "pe-authenticode.h"

#include <windows.h>
#include <wintrust.h>
#include <softpub.h>
#include <wincrypt.h>
#include <mscat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "wintrust")
#pragma comment(lib, "crypt32")

static void
clear_out(win_pe_authenticode *out)
{
	memset(out, 0, sizeof(*out));
}

static void
hex_lower(const BYTE *data, DWORD len, char *out, size_t out_cap)
{
	static const char hex[] = "0123456789abcdef";
	size_t i;

	if (out_cap == 0) {
		return;
	}
	out[0] = '\0';
	if (len * 2 + 1 > out_cap) {
		return;
	}
	for (i = 0; i < len; i++) {
		out[i * 2] = hex[data[i] >> 4];
		out[i * 2 + 1] = hex[data[i] & 0x0f];
	}
	out[len * 2] = '\0';
}

static void
copy_ascii(const WCHAR *wide, char *out, size_t out_cap)
{
	if (out_cap == 0) {
		return;
	}
	if (wide == NULL) {
		out[0] = '\0';
		return;
	}
	if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, (int) out_cap, NULL, NULL) == 0) {
		out[0] = '\0';
	}
}

static void
set_signing_result(win_pe_authenticode *out, LONG status)
{
	switch (status) {
	case ERROR_SUCCESS:
		strncpy(out->signing_result, "Valid", sizeof(out->signing_result) - 1);
		break;
	case TRUST_E_NOSIGNATURE:
		strncpy(out->signing_result, "NotSigned", sizeof(out->signing_result) - 1);
		break;
	case TRUST_E_SUBJECT_NOT_TRUSTED:
		strncpy(out->signing_result, "UnknownError", sizeof(out->signing_result) - 1);
		break;
	case TRUST_E_PROVIDER_UNKNOWN:
		strncpy(out->signing_result, "UnknownError", sizeof(out->signing_result) - 1);
		break;
	case CERT_E_EXPIRED:
		strncpy(out->signing_result, "NotValid", sizeof(out->signing_result) - 1);
		break;
	case CERT_E_UNTRUSTEDROOT:
		strncpy(out->signing_result, "NotValid", sizeof(out->signing_result) - 1);
		break;
	default:
		snprintf(out->signing_result, sizeof(out->signing_result), "0x%08lx", (unsigned long) status);
		break;
	}
}

static void
fill_cert_fields(PCCERT_CONTEXT cert, win_pe_authenticode *out)
{
	BYTE hash[32];
	DWORD hash_len;
	DWORD cn_len;
	WCHAR cn[256];
	WCHAR issuer[512];
	PCERT_EXTENSION ext;

	if (cert == NULL) {
		return;
	}
	hash_len = sizeof(hash);
	if (CertGetCertificateContextProperty(cert, CERT_SHA256_HASH_PROP_ID, hash, &hash_len) &&
		hash_len > 0) {
		hex_lower(hash, hash_len, out->signer_cert_sha256, sizeof(out->signer_cert_sha256));
	}
	cn_len = CertGetNameStringW(cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, NULL, cn, 256);
	if (cn_len > 1) {
		copy_ascii(cn, out->signer_publisher, sizeof(out->signer_publisher));
	}
	cn_len = CertGetNameStringW(cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, CERT_NAME_ISSUER_FLAG,
		NULL, issuer, 512);
	if (cn_len > 1) {
		copy_ascii(issuer, out->signer_issuer, sizeof(out->signer_issuer));
	}
	if (cert->pCertInfo->SerialNumber.cbData > 0) {
		hex_lower(cert->pCertInfo->SerialNumber.pbData,
			cert->pCertInfo->SerialNumber.cbData,
			out->signer_serial, sizeof(out->signer_serial));
	}
	ext = CertFindExtension(szOID_SUBJECT_KEY_IDENTIFIER,
		cert->pCertInfo->cExtension, cert->pCertInfo->rgExtension);
	if (ext != NULL && ext->Value.cbData > 0) {
		hex_lower(ext->Value.pbData, ext->Value.cbData,
			out->signer_subject_key_id, sizeof(out->signer_subject_key_id));
	}
}

static void
fill_from_trust(WINTRUST_DATA *trust, win_pe_authenticode *out)
{
	CRYPT_PROVIDER_DATA *prov;
	CRYPT_PROVIDER_SGNR *signer;
	CRYPT_PROVIDER_CERT *cert;

	if (trust->hWVTStateData == NULL) {
		return;
	}
	prov = WTHelperProvDataFromStateData(trust->hWVTStateData);
	if (prov == NULL) {
		return;
	}
	signer = WTHelperGetProvSignerFromChain(prov, 0, FALSE, 0);
	if (signer == NULL) {
		return;
	}
	cert = WTHelperGetProvCertFromChain(signer, 0);
	if (cert == NULL) {
		return;
	}
	fill_cert_fields(cert->pCert, out);
}

static void
close_trust(WINTRUST_DATA *trust, GUID *policy)
{
	trust->dwStateAction = WTD_STATEACTION_CLOSE;
	WinVerifyTrust(NULL, policy, trust);
}

static void
fill_from_catalog(const wchar_t *path, win_pe_authenticode *out)
{
	HANDLE file;
	HCATADMIN admin = NULL;
	HCATINFO info = NULL;
	CATALOG_INFO cat;
	BYTE hash[64];
	DWORD hash_len;
	wchar_t tag[160];
	DWORD i;
	WINTRUST_CATALOG_INFO cat_info;
	WINTRUST_DATA trust;
	GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
	LONG status;

	file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
	if (file == INVALID_HANDLE_VALUE) {
		return;
	}
	if (!CryptCATAdminAcquireContext2(&admin, NULL, BCRYPT_SHA256_ALGORITHM, NULL, 0)) {
		CloseHandle(file);
		return;
	}
	hash_len = sizeof(hash);
	if (!CryptCATAdminCalcHashFromFileHandle2(admin, file, &hash_len, hash, 0)) {
		CryptCATAdminReleaseContext(admin, 0);
		CloseHandle(file);
		return;
	}
	CloseHandle(file);
	info = CryptCATAdminEnumCatalogFromHash(admin, hash, hash_len, 0, NULL);
	if (info == NULL) {
		CryptCATAdminReleaseContext(admin, 0);
		return;
	}
	memset(&cat, 0, sizeof(cat));
	cat.cbStruct = sizeof(cat);
	if (!CryptCATCatalogInfoFromContext(info, &cat, 0)) {
		CryptCATAdminReleaseCatalogContext(admin, info, 0);
		CryptCATAdminReleaseContext(admin, 0);
		return;
	}
	for (i = 0; i < hash_len && i < 64; i++) {
		swprintf(tag + (size_t) i * 2, 3, L"%02X", hash[i]);
	}
	memset(&cat_info, 0, sizeof(cat_info));
	cat_info.cbStruct = sizeof(cat_info);
	cat_info.pcwszCatalogFilePath = cat.wszCatalogFile;
	cat_info.pcwszMemberFilePath = path;
	cat_info.pcwszMemberTag = tag;
	memset(&trust, 0, sizeof(trust));
	trust.cbStruct = sizeof(trust);
	trust.dwUIChoice = WTD_UI_NONE;
	trust.fdwRevocationChecks = WTD_REVOKE_NONE;
	trust.dwUnionChoice = WTD_CHOICE_CATALOG;
	trust.pCatalog = &cat_info;
	trust.dwStateAction = WTD_STATEACTION_VERIFY;
	status = WinVerifyTrust(NULL, &policy, &trust);
	if (status == ERROR_SUCCESS) {
		set_signing_result(out, status);
		fill_from_trust(&trust, out);
	}
	close_trust(&trust, &policy);
	CryptCATAdminReleaseCatalogContext(admin, info, 0);
	CryptCATAdminReleaseContext(admin, 0);
}

static PCCERT_CONTEXT
signer_from_pkcs7(HCERTSTORE store, HCRYPTMSG msg)
{
	DWORD signer_count = 0;
	DWORD size = sizeof(signer_count);
	PCERT_INFO cert_info = NULL;
	PCCERT_CONTEXT cert = NULL;

	if (store == NULL || msg == NULL) {
		return NULL;
	}
	if (!CryptMsgGetParam(msg, CMSG_SIGNER_COUNT_PARAM, 0, &signer_count, &size) ||
		signer_count < 1) {
		return NULL;
	}
	size = 0;
	if (!CryptMsgGetParam(msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, NULL, &size) || size == 0) {
		return NULL;
	}
	cert_info = (PCERT_INFO) malloc(size);
	if (cert_info == NULL) {
		return NULL;
	}
	if (!CryptMsgGetParam(msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, cert_info, &size)) {
		free(cert_info);
		return NULL;
	}
	cert = CertGetSubjectCertificateFromStore(store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
		cert_info);
	free(cert_info);
	return cert;
}

bool
win_pe_read_authenticode(const wchar_t *path, win_pe_authenticode *out)
{
	WINTRUST_FILE_INFO file_info;
	WINTRUST_DATA trust;
	GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
	LONG status;
	HCERTSTORE store = NULL;
	HCRYPTMSG msg = NULL;
	DWORD encoding = 0;
	DWORD content_type = 0;
	DWORD format_type = 0;
	PCCERT_CONTEXT signer = NULL;

	if (path == NULL || out == NULL) {
		return false;
	}
	clear_out(out);
	memset(&file_info, 0, sizeof(file_info));
	file_info.cbStruct = sizeof(file_info);
	file_info.pcwszFilePath = path;
	memset(&trust, 0, sizeof(trust));
	trust.cbStruct = sizeof(trust);
	trust.dwUIChoice = WTD_UI_NONE;
	trust.fdwRevocationChecks = WTD_REVOKE_NONE;
	trust.dwUnionChoice = WTD_CHOICE_FILE;
	trust.pFile = &file_info;
	trust.dwStateAction = WTD_STATEACTION_VERIFY;
	trust.dwProvFlags = WTD_SAFER_FLAG;
	status = WinVerifyTrust(NULL, &policy, &trust);
	set_signing_result(out, status);
	fill_from_trust(&trust, out);
	close_trust(&trust, &policy);
	if (out->signer_cert_sha256[0] == '\0') {
		fill_from_catalog(path, out);
	}
	if (out->signer_cert_sha256[0] != '\0') {
		return true;
	}
	if (CryptQueryObject(CERT_QUERY_OBJECT_FILE, path,
			CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED |
			CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED,
			CERT_QUERY_FORMAT_FLAG_BINARY, 0,
			&encoding, &content_type, &format_type,
			&store, &msg, NULL)) {
		signer = signer_from_pkcs7(store, msg);
		if (signer == NULL && store != NULL) {
			signer = CertEnumCertificatesInStore(store, NULL);
		}
		fill_cert_fields(signer, out);
		if (signer != NULL) {
			CertFreeCertificateContext(signer);
		}
	}
	if (store != NULL) {
		CertCloseStore(store, 0);
	}
	if (msg != NULL) {
		CryptMsgClose(msg);
	}
	return true;
}