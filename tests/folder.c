/*
 * Phase 1 proof. Creates the desktop backing folder and a placeholder
 * for each name in a pretend tree. No socket, no file bytes copied.
 * Not linked into argus-agent.
 *
 *   argus-folder-test.exe C:\pretend\tree
 *
 * The backing folder is Desktop\Argus RM. It stays after the process
 * exits. cldapi.dll is loaded at run time. This mingw tree has no
 * cfapi.h, so the types below are the Windows 10 ones.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum CF_HYDRATION_POLICY_PRIMARY {
	CF_HYDRATION_POLICY_PARTIAL = 0,
	CF_HYDRATION_POLICY_PROGRESSIVE = 1,
	CF_HYDRATION_POLICY_FULL = 2,
	CF_HYDRATION_POLICY_ALWAYS_FULL = 3
} CF_HYDRATION_POLICY_PRIMARY;

typedef enum CF_HYDRATION_POLICY_MODIFIER {
	CF_HYDRATION_POLICY_MODIFIER_NONE = 0
} CF_HYDRATION_POLICY_MODIFIER;

typedef struct CF_HYDRATION_POLICY {
	CF_HYDRATION_POLICY_PRIMARY Primary;
	CF_HYDRATION_POLICY_MODIFIER Modifier;
} CF_HYDRATION_POLICY;

typedef enum CF_POPULATION_POLICY_PRIMARY {
	CF_POPULATION_POLICY_PARTIAL = 0,
	CF_POPULATION_POLICY_FULL = 2,
	CF_POPULATION_POLICY_ALWAYS_FULL = 3
} CF_POPULATION_POLICY_PRIMARY;

typedef enum CF_POPULATION_POLICY_MODIFIER {
	CF_POPULATION_POLICY_MODIFIER_NONE = 0
} CF_POPULATION_POLICY_MODIFIER;

typedef struct CF_POPULATION_POLICY {
	CF_POPULATION_POLICY_PRIMARY Primary;
	CF_POPULATION_POLICY_MODIFIER Modifier;
} CF_POPULATION_POLICY;

typedef enum CF_INSYNC_POLICY {
	CF_INSYNC_POLICY_NONE = 0
} CF_INSYNC_POLICY;

typedef enum CF_HARDLINK_POLICY {
	CF_HARDLINK_POLICY_NONE = 0
} CF_HARDLINK_POLICY;

typedef enum CF_PLACEHOLDER_MANAGEMENT_POLICY {
	CF_PLACEHOLDER_MANAGEMENT_POLICY_DEFAULT = 0
} CF_PLACEHOLDER_MANAGEMENT_POLICY;

typedef struct CF_SYNC_POLICIES {
	ULONG StructSize;
	CF_HYDRATION_POLICY Hydration;
	CF_POPULATION_POLICY Population;
	CF_INSYNC_POLICY InSync;
	CF_HARDLINK_POLICY HardLink;
	CF_PLACEHOLDER_MANAGEMENT_POLICY PlaceholderManagement;
} CF_SYNC_POLICIES;

typedef struct CF_SYNC_REGISTRATION {
	ULONG StructSize;
	LPCWSTR ProviderName;
	LPCWSTR ProviderVersion;
	LPCVOID SyncRootIdentity;
	DWORD SyncRootIdentityLength;
	LPCVOID FileIdentity;
	DWORD FileIdentityLength;
	GUID ProviderId;
} CF_SYNC_REGISTRATION;

typedef enum CF_REGISTER_FLAGS {
	CF_REGISTER_FLAG_NONE = 0x00000000,
	CF_REGISTER_FLAG_UPDATE = 0x00000001,
	CF_REGISTER_FLAG_DISABLE_ON_DEMAND_POPULATION_ON_ROOT = 0x00000002,
	CF_REGISTER_FLAG_MARK_IN_SYNC_ON_ROOT = 0x00000004
} CF_REGISTER_FLAGS;

typedef struct CF_FS_METADATA {
	FILE_BASIC_INFO BasicInfo;
	LARGE_INTEGER FileSize;
} CF_FS_METADATA;

typedef enum CF_PLACEHOLDER_CREATE_FLAGS {
	CF_PLACEHOLDER_CREATE_FLAG_NONE = 0x00000000,
	CF_PLACEHOLDER_CREATE_FLAG_DISABLE_ON_DEMAND_POPULATION = 0x00000001,
	CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC = 0x00000002,
	CF_PLACEHOLDER_CREATE_FLAG_SUPERSEDE = 0x00000004
} CF_PLACEHOLDER_CREATE_FLAGS;

typedef struct CF_PLACEHOLDER_CREATE_INFO {
	LPCWSTR RelativeFileName;
	CF_FS_METADATA FsMetadata;
	LPCVOID FileIdentity;
	DWORD FileIdentityLength;
	CF_PLACEHOLDER_CREATE_FLAGS Flags;
	HRESULT Result;
	LONGLONG CreateUsn;
} CF_PLACEHOLDER_CREATE_INFO;

typedef enum CF_CREATE_FLAGS {
	CF_CREATE_FLAG_NONE = 0
} CF_CREATE_FLAGS;

typedef enum CF_CALLBACK_TYPE {
	CF_CALLBACK_TYPE_NONE = 0
} CF_CALLBACK_TYPE;

typedef void (CALLBACK *CF_CALLBACK)(const void *info, const void *params);

typedef struct CF_CALLBACK_REGISTRATION {
	CF_CALLBACK_TYPE Type;
	CF_CALLBACK Callback;
} CF_CALLBACK_REGISTRATION;

typedef struct CF_CONNECTION_KEY {
	LONGLONG Internal;
} CF_CONNECTION_KEY;

typedef enum CF_CONNECT_FLAGS {
	CF_CONNECT_FLAG_NONE = 0
} CF_CONNECT_FLAGS;

typedef HRESULT (WINAPI *RegisterSyncRootFn)(
	LPCWSTR path,
	const CF_SYNC_REGISTRATION *registration,
	const CF_SYNC_POLICIES *policies,
	CF_REGISTER_FLAGS flags);

typedef HRESULT (WINAPI *ConnectSyncRootFn)(
	LPCWSTR path,
	const CF_CALLBACK_REGISTRATION *table,
	LPCVOID context,
	CF_CONNECT_FLAGS flags,
	CF_CONNECTION_KEY *key);

typedef HRESULT (WINAPI *DisconnectSyncRootFn)(CF_CONNECTION_KEY key);

typedef HRESULT (WINAPI *CreatePlaceholdersFn)(
	LPCWSTR base,
	CF_PLACEHOLDER_CREATE_INFO *list,
	DWORD count,
	CF_CREATE_FLAGS flags,
	DWORD *processed);

static RegisterSyncRootFn register_root;
static ConnectSyncRootFn connect_root;
static DisconnectSyncRootFn disconnect_root;
static CreatePlaceholdersFn create_placeholders;
static int created;

static const GUID provider_id = {
	0x8f3c2a1e, 0x6b47, 0x4d95,
	{0x9e, 0x10, 0x2c, 0x7b, 0x5a, 0x4d, 0x6f, 0x18}
};

struct Job {
	wchar_t *pretend;
	wchar_t *backing;
	wchar_t *rel;
	struct Job *next;
};

static struct Job *queue_head;
static struct Job *queue_tail;

static void
say(const char *label, const wchar_t *path)
{
	int bytes;
	char *utf8;

	bytes = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
	if (bytes < 1) {
		printf("%s\n", label);
		return;
	}
	utf8 = malloc((size_t) bytes);
	if (utf8 == NULL) {
		printf("%s\n", label);
		return;
	}
	WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8, bytes, NULL, NULL);
	printf("%s %s\n", label, utf8);
	free(utf8);
}

static void
fail(const char *what, HRESULT hr)
{
	fprintf(stderr, "%s failed 0x%08lx\n", what, (unsigned long) hr);
}

static wchar_t *
join_path(const wchar_t *dir, const wchar_t *name)
{
	size_t ndir;
	size_t nname;
	wchar_t *out;

	ndir = wcslen(dir);
	nname = wcslen(name);
	out = malloc((ndir + 1 + nname + 1) * sizeof(wchar_t));
	if (out == NULL) {
		return NULL;
	}
	memcpy(out, dir, ndir * sizeof(wchar_t));
	out[ndir] = L'\\';
	memcpy(out + ndir + 1, name, (nname + 1) * sizeof(wchar_t));
	return out;
}

static wchar_t *
join_rel(const wchar_t *parent, const wchar_t *name)
{
	if (parent[0] == L'\0') {
		return _wcsdup(name);
	}
	return join_path(parent, name);
}

static void
free_job(struct Job *job)
{
	free(job->pretend);
	free(job->backing);
	free(job->rel);
	free(job);
}

static HRESULT
enqueue(const wchar_t *pretend, const wchar_t *backing, const wchar_t *rel)
{
	struct Job *job;

	job = calloc(1, sizeof(struct Job));
	if (job == NULL) {
		return E_OUTOFMEMORY;
	}
	job->pretend = _wcsdup(pretend);
	job->backing = _wcsdup(backing);
	job->rel = _wcsdup(rel);
	if (job->pretend == NULL || job->backing == NULL || job->rel == NULL) {
		free_job(job);
		return E_OUTOFMEMORY;
	}
	if (queue_tail == NULL) {
		queue_head = job;
		queue_tail = job;
		return S_OK;
	}
	queue_tail->next = job;
	queue_tail = job;
	return S_OK;
}

static void
drain(void)
{
	struct Job *job;

	while (queue_head != NULL) {
		job = queue_head;
		queue_head = job->next;
		free_job(job);
	}
	queue_tail = NULL;
}

static int
load_cfapi(void)
{
	HMODULE lib;

	lib = LoadLibraryW(L"cldapi.dll");
	if (lib == NULL) {
		fprintf(stderr, "cldapi.dll did not load %lu\n", GetLastError());
		return 0;
	}
	register_root = (RegisterSyncRootFn) (void *)
		GetProcAddress(lib, "CfRegisterSyncRoot");
	connect_root = (ConnectSyncRootFn) (void *)
		GetProcAddress(lib, "CfConnectSyncRoot");
	disconnect_root = (DisconnectSyncRootFn) (void *)
		GetProcAddress(lib, "CfDisconnectSyncRoot");
	create_placeholders = (CreatePlaceholdersFn) (void *)
		GetProcAddress(lib, "CfCreatePlaceholders");
	if (register_root == NULL || connect_root == NULL ||
		disconnect_root == NULL || create_placeholders == NULL) {
		fprintf(stderr, "cldapi.dll is missing a call\n");
		return 0;
	}
	return 1;
}

static HRESULT
register_backing(const wchar_t *backing)
{
	CF_SYNC_REGISTRATION registration;
	CF_SYNC_POLICIES policies;
	CF_REGISTER_FLAGS flags;
	CF_CALLBACK_REGISTRATION table[1];
	CF_CONNECTION_KEY key;
	HRESULT hr;
	static const char identity[] = "argus-rm";

	memset(&registration, 0, sizeof(registration));
	registration.StructSize = sizeof(registration);
	registration.ProviderName = L"Argus RM";
	registration.ProviderVersion = L"0.0";
	registration.SyncRootIdentity = identity;
	registration.SyncRootIdentityLength = sizeof(identity);
	registration.ProviderId = provider_id;
	memset(&policies, 0, sizeof(policies));
	policies.StructSize = sizeof(policies);
	policies.Hydration.Primary = CF_HYDRATION_POLICY_FULL;
	policies.Population.Primary = CF_POPULATION_POLICY_ALWAYS_FULL;
	policies.InSync = CF_INSYNC_POLICY_NONE;
	policies.HardLink = CF_HARDLINK_POLICY_NONE;
	policies.PlaceholderManagement = CF_PLACEHOLDER_MANAGEMENT_POLICY_DEFAULT;
	flags = CF_REGISTER_FLAG_DISABLE_ON_DEMAND_POPULATION_ON_ROOT |
		CF_REGISTER_FLAG_MARK_IN_SYNC_ON_ROOT;
	hr = register_root(backing, &registration, &policies, flags);
	if (hr == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)) {
		hr = register_root(backing, &registration, &policies,
			flags | CF_REGISTER_FLAG_UPDATE);
	}
	if (FAILED(hr)) {
		fail("register", hr);
		return hr;
	}
	table[0].Type = CF_CALLBACK_TYPE_NONE;
	table[0].Callback = NULL;
	memset(&key, 0, sizeof(key));
	hr = connect_root(backing, table, NULL, CF_CONNECT_FLAG_NONE, &key);
	if (FAILED(hr)) {
		fail("connect", hr);
		return hr;
	}
	hr = disconnect_root(key);
	if (FAILED(hr)) {
		fail("disconnect", hr);
	}
	return hr;
}

static HRESULT
one_placeholder(const wchar_t *parent, const wchar_t *name,
	const WIN32_FIND_DATAW *data, const wchar_t *rel)
{
	CF_PLACEHOLDER_CREATE_INFO info;
	DWORD processed;
	HRESULT hr;
	int is_dir;

	memset(&info, 0, sizeof(info));
	info.RelativeFileName = name;
	info.FsMetadata.BasicInfo.CreationTime.QuadPart =
		((LONGLONG) data->ftCreationTime.dwHighDateTime << 32) |
		data->ftCreationTime.dwLowDateTime;
	info.FsMetadata.BasicInfo.LastAccessTime.QuadPart =
		((LONGLONG) data->ftLastAccessTime.dwHighDateTime << 32) |
		data->ftLastAccessTime.dwLowDateTime;
	info.FsMetadata.BasicInfo.LastWriteTime.QuadPart =
		((LONGLONG) data->ftLastWriteTime.dwHighDateTime << 32) |
		data->ftLastWriteTime.dwLowDateTime;
	info.FsMetadata.BasicInfo.ChangeTime =
		info.FsMetadata.BasicInfo.LastWriteTime;
	info.FsMetadata.BasicInfo.FileAttributes = data->dwFileAttributes;
	is_dir = (data->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
	if (is_dir) {
		info.Flags = CF_PLACEHOLDER_CREATE_FLAG_DISABLE_ON_DEMAND_POPULATION |
			CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC;
	}
	if (!is_dir && info.FsMetadata.BasicInfo.FileAttributes == 0) {
		info.FsMetadata.BasicInfo.FileAttributes = FILE_ATTRIBUTE_NORMAL;
	}
	if (!is_dir) {
		info.FsMetadata.FileSize.QuadPart =
			((LONGLONG) data->nFileSizeHigh << 32) | data->nFileSizeLow;
	}
	info.FileIdentity = rel;
	info.FileIdentityLength = (DWORD) ((wcslen(rel) + 1) * sizeof(wchar_t));
	processed = 0;
	hr = create_placeholders(parent, &info, 1, CF_CREATE_FLAG_NONE, &processed);
	if (hr == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) ||
		info.Result == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)) {
		say("exists", rel);
		return S_OK;
	}
	if (FAILED(hr)) {
		say("placeholder", rel);
		fail("create", hr);
		return hr;
	}
	if (FAILED(info.Result)) {
		say("placeholder", rel);
		fail("create", info.Result);
		return info.Result;
	}
	say("placeholder", rel);
	created++;
	return S_OK;
}

static HRESULT
fill(void)
{
	struct Job *job;
	wchar_t *pattern;
	HANDLE find;
	WIN32_FIND_DATAW data;
	DWORD err;
	HRESULT hr;

	while (queue_head != NULL) {
		job = queue_head;
		queue_head = job->next;
		if (queue_head == NULL) {
			queue_tail = NULL;
		}
		pattern = join_path(job->pretend, L"*");
		if (pattern == NULL) {
			free_job(job);
			drain();
			return E_OUTOFMEMORY;
		}
		find = FindFirstFileW(pattern, &data);
		free(pattern);
		if (find == INVALID_HANDLE_VALUE) {
			err = GetLastError();
			if (err == ERROR_FILE_NOT_FOUND) {
				free_job(job);
				continue;
			}
			fail("list", HRESULT_FROM_WIN32(err));
			free_job(job);
			drain();
			return HRESULT_FROM_WIN32(err);
		}
		do {
			wchar_t *child_pretend;
			wchar_t *child_backing;
			wchar_t *child_rel;
			if (wcscmp(data.cFileName, L".") == 0 ||
				wcscmp(data.cFileName, L"..") == 0) {
				continue;
			}
			child_rel = join_rel(job->rel, data.cFileName);
			if (child_rel == NULL) {
				FindClose(find);
				free_job(job);
				drain();
				return E_OUTOFMEMORY;
			}
			if ((data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
				say("skip reparse", child_rel);
				free(child_rel);
				continue;
			}
			hr = one_placeholder(job->backing, data.cFileName, &data, child_rel);
			if (FAILED(hr)) {
				free(child_rel);
				FindClose(find);
				free_job(job);
				drain();
				return hr;
			}
			if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
				free(child_rel);
				continue;
			}
			child_pretend = join_path(job->pretend, data.cFileName);
			child_backing = join_path(job->backing, data.cFileName);
			if (child_pretend == NULL || child_backing == NULL) {
				free(child_pretend);
				free(child_backing);
				free(child_rel);
				FindClose(find);
				free_job(job);
				drain();
				return E_OUTOFMEMORY;
			}
			hr = enqueue(child_pretend, child_backing, child_rel);
			free(child_pretend);
			free(child_backing);
			free(child_rel);
			if (FAILED(hr)) {
				FindClose(find);
				free_job(job);
				drain();
				return hr;
			}
		} while (FindNextFileW(find, &data));
		err = GetLastError();
		FindClose(find);
		free_job(job);
		if (err != ERROR_NO_MORE_FILES) {
			fail("list", HRESULT_FROM_WIN32(err));
			drain();
			return HRESULT_FROM_WIN32(err);
		}
	}
	return S_OK;
}

int
main(void)
{
	int argc;
	wchar_t **argv;
	wchar_t *desktop = NULL;
	wchar_t *backing;
	DWORD attrs;
	HRESULT hr;
	GUID desktop_id = {
		0xb4bfcc3a, 0xdb2c, 0x424c,
		{0xb0, 0x29, 0x7f, 0xe9, 0x9a, 0x87, 0xc6, 0x41}
	};

	argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	if (argv == NULL || argc != 2) {
		fprintf(stderr, "usage: argus-folder-test PRETEND_TREE\n");
		LocalFree(argv);
		return 2;
	}
	attrs = GetFileAttributesW(argv[1]);
	if (attrs == INVALID_FILE_ATTRIBUTES ||
		(attrs & FILE_ATTRIBUTE_DIRECTORY) == 0) {
		fprintf(stderr, "pretend tree is not a directory\n");
		LocalFree(argv);
		return 2;
	}
	if (!load_cfapi()) {
		LocalFree(argv);
		return 1;
	}
	hr = SHGetKnownFolderPath(&desktop_id, 0, NULL, &desktop);
	if (FAILED(hr) || desktop == NULL) {
		fail("desktop", hr);
		LocalFree(argv);
		return 1;
	}
	backing = join_path(desktop, L"Argus RM");
	CoTaskMemFree(desktop);
	if (backing == NULL) {
		LocalFree(argv);
		return 1;
	}
	if (!CreateDirectoryW(backing, NULL) &&
		GetLastError() != ERROR_ALREADY_EXISTS) {
		fail("mkdir", HRESULT_FROM_WIN32(GetLastError()));
		free(backing);
		LocalFree(argv);
		return 1;
	}
	say("backing", backing);
	hr = register_backing(backing);
	if (FAILED(hr)) {
		free(backing);
		LocalFree(argv);
		return 1;
	}
	hr = enqueue(argv[1], backing, L"");
	LocalFree(argv);
	if (FAILED(hr)) {
		free(backing);
		return 1;
	}
	hr = fill();
	SHChangeNotify(SHCNE_UPDATEDIR, SHCNF_PATHW, backing, NULL);
	free(backing);
	if (FAILED(hr)) {
		return 1;
	}
	printf("ok %d\n", created);
	return 0;
}
