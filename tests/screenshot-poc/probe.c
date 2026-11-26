#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wtsapi32.h>
#include <tlhelp32.h>
#include <sddl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>
#include <webp/encode.h>
#include <zstd.h>

#define PROBE_DIR L"C:\\Users\\alan\\argus-shot-probe\\"
#define PROBE_EXE L"C:\\Users\\alan\\argus-shot-probe\\probe.exe"
#define WORKER_LOG "C:\\Users\\alan\\argus-shot-probe\\worker.log"
#define SERVICE_LOG "C:\\Users\\alan\\argus-shot-probe\\service.log"
#define UIPI_LOG "C:\\Users\\alan\\argus-shot-probe\\uipi.log"
#define FRAME_JPG "C:\\Users\\alan\\argus-shot-probe\\frame-q65.jpg"

static double
now_ms(void)
{
	static LARGE_INTEGER freq;
	LARGE_INTEGER cur;

	if (freq.QuadPart == 0) {
		QueryPerformanceFrequency(&freq);
	}
	QueryPerformanceCounter(&cur);
	return (double) cur.QuadPart * 1000.0 / (double) freq.QuadPart;
}

static int
attach_desktop(wchar_t *desk_name_out, size_t desk_name_cap)
{
	HWINSTA station;
	HDESK desk;
	DWORD needed = 0;

	desk_name_out[0] = 0;
	station = OpenWindowStationW(L"WinSta0", FALSE, WINSTA_ALL_ACCESS);
	if (station == NULL) {
		printf("open_winsta_err %lu\n", GetLastError());
		return 0;
	}
	if (!SetProcessWindowStation(station)) {
		printf("set_winsta_err %lu\n", GetLastError());
		return 0;
	}
	desk = OpenInputDesktop(0, FALSE,
		DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS |
		DESKTOP_SWITCHDESKTOP | GENERIC_ALL);
	if (desk == NULL) {
		desk = OpenInputDesktop(0, FALSE,
			DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS);
	}
	if (desk == NULL) {
		printf("open_input_desktop_err %lu\n", GetLastError());
		desk = OpenDesktopW(L"Winlogon", 0, FALSE,
			DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS);
	}
	if (desk == NULL) {
		desk = OpenDesktopW(L"Default", 0, FALSE,
			DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS);
	}
	if (desk == NULL) {
		printf("open_desktop_err %lu\n", GetLastError());
		return 0;
	}
	if (!SetThreadDesktop(desk)) {
		printf("set_desktop_err %lu\n", GetLastError());
		return 0;
	}
	if (GetUserObjectInformationW(desk, UOI_NAME, desk_name_out,
		(DWORD) (desk_name_cap * sizeof(wchar_t)), &needed)) {
		printf("desktop_name %ls\n", desk_name_out);
	} else {
		printf("desktop_name unknown\n");
	}
	return 1;
}

static int
capture_bgra(int width, int height, uint8_t *out)
{
	HDC dc;
	HDC mem;
	HBITMAP bmp;
	HGDIOBJ old;
	BITMAPINFO bi;

	dc = GetDC(NULL);
	if (dc == NULL) {
		return 0;
	}
	mem = CreateCompatibleDC(dc);
	bmp = CreateCompatibleBitmap(dc, width, height);
	old = SelectObject(mem, bmp);
	if (!BitBlt(mem, 0, 0, width, height, dc, 0, 0, SRCCOPY | CAPTUREBLT)) {
		SelectObject(mem, old);
		DeleteObject(bmp);
		DeleteDC(mem);
		ReleaseDC(NULL, dc);
		return 0;
	}
	memset(&bi, 0, sizeof(bi));
	bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	bi.bmiHeader.biWidth = width;
	bi.bmiHeader.biHeight = -(LONG) height;
	bi.bmiHeader.biPlanes = 1;
	bi.bmiHeader.biBitCount = 32;
	bi.bmiHeader.biCompression = BI_RGB;
	GetDIBits(mem, bmp, 0, (UINT) height, out, &bi, DIB_RGB_COLORS);
	SelectObject(mem, old);
	DeleteObject(bmp);
	DeleteDC(mem);
	ReleaseDC(NULL, dc);
	return 1;
}

static size_t
encode_jpeg_rect(const uint8_t *bgra, int stride_px, int x0, int y0, int w, int h,
	int quality, uint8_t **out_buf)
{
	struct jpeg_compress_struct cinfo;
	struct jpeg_error_mgr jerr;
	unsigned char *buf = NULL;
	unsigned long size = 0;
	int y;

	cinfo.err = jpeg_std_error(&jerr);
	jpeg_create_compress(&cinfo);
	jpeg_mem_dest(&cinfo, &buf, &size);
	cinfo.image_width = (JDIMENSION) w;
	cinfo.image_height = (JDIMENSION) h;
	cinfo.input_components = 4;
	cinfo.in_color_space = JCS_EXT_BGRA;
	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, quality, TRUE);
	jpeg_start_compress(&cinfo, TRUE);
	for (y = 0; y < h; y++) {
		JSAMPROW row = (JSAMPROW) (bgra + ((size_t) (y0 + y) * (size_t) stride_px + (size_t) x0) * 4);
		jpeg_write_scanlines(&cinfo, &row, 1);
	}
	jpeg_finish_compress(&cinfo);
	jpeg_destroy_compress(&cinfo);
	*out_buf = (uint8_t *) buf;
	return (size_t) size;
}

static int g_btn_clicks = 0;
static int g_return_seen = 0;
static HWND g_edit = NULL;

static LRESULT CALLBACK
test_wnd_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
	if (msg == WM_COMMAND && LOWORD(wparam) == 101 && HIWORD(wparam) == BN_CLICKED) {
		g_btn_clicks++;
		return 0;
	}
	if (msg == WM_DESTROY) {
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static void
pump_ms(DWORD ms)
{
	DWORD start = GetTickCount();
	MSG msg;

	while (GetTickCount() - start < ms) {
		while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
			if (msg.message == WM_KEYDOWN && msg.wParam == VK_RETURN) {
				g_return_seen++;
			}
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		Sleep(10);
	}
}

static UINT
send_click_norm(LONG nx, LONG ny)
{
	INPUT in[3];

	memset(in, 0, sizeof(in));
	in[0].type = INPUT_MOUSE;
	in[0].mi.dx = nx;
	in[0].mi.dy = ny;
	in[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
	in[1].type = INPUT_MOUSE;
	in[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
	in[2].type = INPUT_MOUSE;
	in[2].mi.dwFlags = MOUSEEVENTF_LEFTUP;
	return SendInput(3, in, sizeof(INPUT));
}

static UINT
send_unicode_text(const wchar_t *text)
{
	UINT total = 0;
	size_t i;

	for (i = 0; text[i] != 0; i++) {
		INPUT in[2];
		memset(in, 0, sizeof(in));
		in[0].type = INPUT_KEYBOARD;
		in[0].ki.wScan = (WORD) text[i];
		in[0].ki.dwFlags = KEYEVENTF_UNICODE;
		in[1].type = INPUT_KEYBOARD;
		in[1].ki.wScan = (WORD) text[i];
		in[1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
		total += SendInput(2, in, sizeof(INPUT));
	}
	return total;
}

static UINT
send_vk(WORD vk)
{
	INPUT in[2];

	memset(in, 0, sizeof(in));
	in[0].type = INPUT_KEYBOARD;
	in[0].ki.wVk = vk;
	in[1].type = INPUT_KEYBOARD;
	in[1].ki.wVk = vk;
	in[1].ki.dwFlags = KEYEVENTF_KEYUP;
	return SendInput(2, in, sizeof(INPUT));
}

static void
spawn_medium_clicker(const wchar_t *desk_name, LONG nx, LONG ny)
{
	HANDLE self_tok = NULL;
	HANDLE dup_tok = NULL;
	PSID med_sid = NULL;
	TOKEN_MANDATORY_LABEL tml;
	STARTUPINFOW si;
	PROCESS_INFORMATION pi;
	wchar_t desk_full[128];
	wchar_t cmd[512];
	DWORD code = 999;

	if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ALL_ACCESS, &self_tok)) {
		printf("uipi_open_tok_err %lu\n", GetLastError());
		return;
	}
	if (!DuplicateTokenEx(self_tok, MAXIMUM_ALLOWED, NULL,
		SecurityImpersonation, TokenPrimary, &dup_tok)) {
		printf("uipi_dup_tok_err %lu\n", GetLastError());
		CloseHandle(self_tok);
		return;
	}
	CloseHandle(self_tok);
	if (!ConvertStringSidToSidW(L"S-1-16-8192", &med_sid)) {
		printf("uipi_sid_err %lu\n", GetLastError());
		CloseHandle(dup_tok);
		return;
	}
	memset(&tml, 0, sizeof(tml));
	tml.Label.Attributes = SE_GROUP_INTEGRITY;
	tml.Label.Sid = med_sid;
	if (!SetTokenInformation(dup_tok, TokenIntegrityLevel, &tml,
		sizeof(TOKEN_MANDATORY_LABEL) + GetLengthSid(med_sid))) {
		printf("uipi_set_il_err %lu\n", GetLastError());
		LocalFree(med_sid);
		CloseHandle(dup_tok);
		return;
	}
	LocalFree(med_sid);
	snwprintf(desk_full, 128, L"winsta0\\%ls",
		desk_name[0] != 0 ? desk_name : L"Default");
	snwprintf(cmd, 512, L"\"%ls\" uipi_click %ld %ld", PROBE_EXE, nx, ny);
	memset(&si, 0, sizeof(si));
	si.cb = sizeof(si);
	si.lpDesktop = desk_full;
	memset(&pi, 0, sizeof(pi));
	if (!CreateProcessAsUserW(dup_tok, NULL, cmd, NULL, NULL, FALSE,
		CREATE_NO_WINDOW, NULL, PROBE_DIR, &si, &pi)) {
		printf("uipi_spawn_err %lu desktop %ls\n", GetLastError(), desk_full);
		CloseHandle(dup_tok);
		return;
	}
	CloseHandle(dup_tok);
	pump_ms(1200);
	WaitForSingleObject(pi.hProcess, 1000);
	GetExitCodeProcess(pi.hProcess, &code);
	CloseHandle(pi.hThread);
	CloseHandle(pi.hProcess);
	printf("uipi_child_exit %lu\n", code);
}

static int
uipi_click_main(LONG nx, LONG ny)
{
	wchar_t desk_name[64];
	UINT sent;

	freopen(UIPI_LOG, "w", stdout);
	setvbuf(stdout, NULL, _IONBF, 0);
	if (!attach_desktop(desk_name, 64)) {
		printf("uipi_attach_failed\n");
		return 2;
	}
	sent = send_click_norm(nx, ny);
	printf("uipi_sendinput %u err %lu\n", sent, GetLastError());
	return 0;
}

static void
run_input_test(const wchar_t *desk_name, int screen_w, int screen_h)
{
	WNDCLASSW wc;
	HWND hwnd;
	HWND btn;
	RECT r;
	LONG cx, cy, nx, ny;
	UINT sent;
	wchar_t text[128];

	memset(&wc, 0, sizeof(wc));
	wc.lpfnWndProc = test_wnd_proc;
	wc.hInstance = GetModuleHandleW(NULL);
	wc.lpszClassName = L"ArgusShotInputTest";
	RegisterClassW(&wc);

	hwnd = CreateWindowExW(WS_EX_TOPMOST, L"ArgusShotInputTest", L"ArgusShotProbe",
		WS_OVERLAPPEDWINDOW | WS_VISIBLE, 80, 80, 340, 180, NULL, NULL, wc.hInstance, NULL);
	if (hwnd == NULL) {
		printf("input_window_err %lu\n", GetLastError());
		return;
	}
	btn = CreateWindowW(L"BUTTON", L"ClickMe", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
		20, 20, 120, 36, hwnd, (HMENU) 101, wc.hInstance, NULL);
	g_edit = CreateWindowW(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
		20, 72, 260, 28, hwnd, (HMENU) 102, wc.hInstance, NULL);
	ShowWindow(hwnd, SW_SHOW);
	UpdateWindow(hwnd);
	SetForegroundWindow(hwnd);
	pump_ms(200);

	GetWindowRect(btn, &r);
	cx = (r.left + r.right) / 2;
	cy = (r.top + r.bottom) / 2;
	nx = (LONG) (((int64_t) cx * 65535LL) / (screen_w > 1 ? screen_w - 1 : 1));
	ny = (LONG) (((int64_t) cy * 65535LL) / (screen_h > 1 ? screen_h - 1 : 1));
	g_btn_clicks = 0;
	sent = send_click_norm(nx, ny);
	pump_ms(250);
	printf("input_sys_click sent %u clicks %d pos %ld,%ld\n", sent, g_btn_clicks, cx, cy);

	GetWindowRect(g_edit, &r);
	cx = (r.left + r.right) / 2;
	cy = (r.top + r.bottom) / 2;
	send_click_norm(
		(LONG) (((int64_t) cx * 65535LL) / (screen_w > 1 ? screen_w - 1 : 1)),
		(LONG) (((int64_t) cy * 65535LL) / (screen_h > 1 ? screen_h - 1 : 1)));
	pump_ms(150);
	SetFocus(g_edit);
	pump_ms(50);
	g_return_seen = 0;
	sent = send_unicode_text(L"Argus OK! 123");
	send_vk(VK_RETURN);
	pump_ms(250);
	memset(text, 0, sizeof(text));
	GetWindowTextW(g_edit, text, 127);
	printf("input_sys_type sent %u text \"%ls\" return_seen %d\n", sent, text, g_return_seen);

	GetWindowRect(btn, &r);
	cx = (r.left + r.right) / 2;
	cy = (r.top + r.bottom) / 2;
	nx = (LONG) (((int64_t) cx * 65535LL) / (screen_w > 1 ? screen_w - 1 : 1));
	ny = (LONG) (((int64_t) cy * 65535LL) / (screen_h > 1 ? screen_h - 1 : 1));
	g_btn_clicks = 0;
	spawn_medium_clicker(desk_name, nx, ny);
	printf("input_medium_vs_sys_clicks %d\n", g_btn_clicks);

	DestroyWindow(hwnd);
	pump_ms(100);
}

static int
worker_main(void)
{
	wchar_t desk_name[64];
	DWORD sess = 0;
	int w, h;
	size_t raw_bytes;
	uint8_t *frame1;
	uint8_t *frame2;
	double t0, dt, sum_cap = 0.0, min_cap = 1e9, max_cap = 0.0;
	int i;
	uint32_t nonzero = 0;
	int qualities[3] = { 60, 75, 85 };

	freopen(WORKER_LOG, "w", stdout);
	setvbuf(stdout, NULL, _IONBF, 0);
	ProcessIdToSessionId(GetCurrentProcessId(), &sess);
	printf("worker_session %lu\n", sess);
	if (!attach_desktop(desk_name, 64)) {
		return 1;
	}
	SetProcessDPIAware();
	w = GetSystemMetrics(SM_CXSCREEN);
	h = GetSystemMetrics(SM_CYSCREEN);
	printf("screen %d %d\n", w, h);
	if (w < 1 || h < 1) {
		return 1;
	}
	raw_bytes = (size_t) w * (size_t) h * 4;
	frame1 = malloc(raw_bytes);
	frame2 = malloc(raw_bytes);
	if (frame1 == NULL || frame2 == NULL) {
		printf("oom\n");
		return 1;
	}

	for (i = 0; i < 10; i++) {
		t0 = now_ms();
		if (!capture_bgra(w, h, i == 0 ? frame1 : frame2)) {
			printf("capture_failed %d err %lu\n", i, GetLastError());
			return 1;
		}
		dt = now_ms() - t0;
		sum_cap += dt;
		if (dt < min_cap) min_cap = dt;
		if (dt > max_cap) max_cap = dt;
		Sleep(30);
	}
	for (size_t p = 0; p < raw_bytes; p += 4) {
		if (frame1[p] || frame1[p + 1] || frame1[p + 2]) {
			nonzero++;
		}
	}
	printf("capture_10frames min %.2f ms avg %.2f ms max %.2f ms nonzero %u/%d\n",
		min_cap, sum_cap / 10.0, max_cap, nonzero, w * h);

	for (i = 0; i < 3; i++) {
		uint8_t *jpg = NULL;
		t0 = now_ms();
		size_t sz = encode_jpeg_rect(frame1, w, 0, 0, w, h, qualities[i], &jpg);
		dt = now_ms() - t0;
		printf("jpeg_q%d %.2f ms bytes %zu\n", qualities[i], dt, sz);
		free(jpg);
	}
	{
		uint8_t *jpg = NULL;
		t0 = now_ms();
		size_t sz = encode_jpeg_rect(frame1, w, 0, 0, w, h, 65, &jpg);
		dt = now_ms() - t0;
		printf("jpeg_q65 %.2f ms bytes %zu\n", dt, sz);
		FILE *f = fopen(FRAME_JPG, "wb");
		if (f != NULL) {
			fwrite(jpg, 1, sz, f);
			fclose(f);
		}
		free(jpg);
	}
	{
		uint8_t *webp = NULL;
		t0 = now_ms();
		size_t sz = WebPEncodeBGRA(frame1, w, h, w * 4, 65.0f, &webp);
		dt = now_ms() - t0;
		printf("webp_q65 %.2f ms bytes %zu\n", dt, sz);
		WebPFree(webp);
	}
	{
		size_t bound = ZSTD_compressBound(raw_bytes);
		uint8_t *zbuf = malloc(bound);
		if (zbuf != NULL) {
			t0 = now_ms();
			size_t sz1 = ZSTD_compress(zbuf, bound, frame1, raw_bytes, 1);
			dt = now_ms() - t0;
			printf("zstd_l1_full %.2f ms bytes %zu\n", dt, sz1);
			t0 = now_ms();
			size_t sz3 = ZSTD_compress(zbuf, bound, frame1, raw_bytes, 3);
			dt = now_ms() - t0;
			printf("zstd_l3_full %.2f ms bytes %zu\n", dt, sz3);
			free(zbuf);
		}
	}
	{
		/* Idle 64x64 tile diff benchmark */
		int tx, ty, changed = 0, total_tiles = 0;
		t0 = now_ms();
		for (ty = 0; ty < h; ty += 64) {
			int th = (ty + 64 <= h) ? 64 : (h - ty);
			for (tx = 0; tx < w; tx += 64) {
				int tw = (tx + 64 <= w) ? 64 : (w - tx);
				int diff = 0;
				total_tiles++;
				for (int ry = 0; ry < th; ry++) {
					size_t off = ((size_t) (ty + ry) * (size_t) w + (size_t) tx) * 4;
					if (memcmp(frame1 + off, frame2 + off, (size_t) tw * 4) != 0) {
						diff = 1;
						break;
					}
				}
				if (diff) changed++;
			}
		}
		dt = now_ms() - t0;
		printf("tile_diff_idle %.2f ms changed %d/%d\n", dt, changed, total_tiles);

		/* Simulate small UI change (256x128 = 8 tiles of 64x64) */
		memcpy(frame2, frame1, raw_bytes);
		for (int ry = 64; ry < 192 && ry < h; ry++) {
			for (int rx = 64; rx < 320 && rx < w; rx++) {
				size_t off = ((size_t) ry * (size_t) w + (size_t) rx) * 4;
				frame2[off] ^= 0x55;
				frame2[off + 1] ^= 0xAA;
			}
		}
		size_t tiles_jpg_bytes = 0;
		int dirty = 0;
		t0 = now_ms();
		for (ty = 0; ty < h; ty += 64) {
			int th = (ty + 64 <= h) ? 64 : (h - ty);
			for (tx = 0; tx < w; tx += 64) {
				int tw = (tx + 64 <= w) ? 64 : (w - tx);
				int diff = 0;
				for (int ry = 0; ry < th; ry++) {
					size_t off = ((size_t) (ty + ry) * (size_t) w + (size_t) tx) * 4;
					if (memcmp(frame1 + off, frame2 + off, (size_t) tw * 4) != 0) {
						diff = 1;
						break;
					}
				}
				if (diff) {
					uint8_t *tjpg = NULL;
					tiles_jpg_bytes += encode_jpeg_rect(frame2, w, tx, ty, tw, th, 65, &tjpg);
					free(tjpg);
					dirty++;
				}
			}
		}
		dt = now_ms() - t0;
		printf("tile_diff_8dirty_jpeg65 %.2f ms dirty %d bytes %zu\n", dt, dirty, tiles_jpg_bytes);
	}

	run_input_test(desk_name, w, h);

	free(frame1);
	free(frame2);
	printf("worker_done\n");
	return 0;
}

static HANDLE
console_system_token(DWORD target_session)
{
	HANDLE snap;
	PROCESSENTRY32W entry;
	DWORD pid = 0;
	HANDLE proc;
	HANDLE token;
	HANDLE dup;

	snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE) {
		return NULL;
	}
	entry.dwSize = sizeof(entry);
	if (Process32FirstW(snap, &entry)) {
		do {
			DWORD s = 0;
			if (_wcsicmp(entry.szExeFile, L"winlogon.exe") != 0) {
				continue;
			}
			ProcessIdToSessionId(entry.th32ProcessID, &s);
			if (s == target_session) {
				pid = entry.th32ProcessID;
				break;
			}
		} while (Process32NextW(snap, &entry));
	}
	CloseHandle(snap);
	if (pid == 0) {
		printf("no_winlogon_for_session %lu\n", target_session);
		return NULL;
	}
	proc = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pid);
	if (proc == NULL) {
		printf("open_winlogon_err %lu\n", GetLastError());
		return NULL;
	}
	if (!OpenProcessToken(proc, TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY, &token)) {
		printf("open_token_err %lu\n", GetLastError());
		CloseHandle(proc);
		return NULL;
	}
	if (!DuplicateTokenEx(token, MAXIMUM_ALLOWED, NULL, SecurityImpersonation, TokenPrimary, &dup)) {
		printf("dup_token_err %lu\n", GetLastError());
		CloseHandle(token);
		CloseHandle(proc);
		return NULL;
	}
	CloseHandle(token);
	CloseHandle(proc);
	return dup;
}

static SERVICE_STATUS_HANDLE g_svc_handle;

static void
report_svc(DWORD state)
{
	SERVICE_STATUS st;

	memset(&st, 0, sizeof(st));
	st.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
	st.dwCurrentState = state;
	st.dwControlsAccepted = SERVICE_ACCEPT_STOP;
	SetServiceStatus(g_svc_handle, &st);
}

static VOID WINAPI
svc_ctrl(DWORD code)
{
	if (code == SERVICE_CONTROL_STOP) {
		report_svc(SERVICE_STOPPED);
	}
}

static VOID WINAPI
svc_main(DWORD argc, LPWSTR *argv)
{
	DWORD sess;
	HANDLE tok;
	STARTUPINFOW si;
	PROCESS_INFORMATION pi;
	wchar_t cmd[512];
	DWORD code = 999;

	(void) argc;
	(void) argv;
	g_svc_handle = RegisterServiceCtrlHandlerW(L"ArgusShotProbe", svc_ctrl);
	report_svc(SERVICE_RUNNING);

	freopen(SERVICE_LOG, "w", stdout);
	setvbuf(stdout, NULL, _IONBF, 0);
	sess = WTSGetActiveConsoleSessionId();
	printf("active_console_session %lu\n", sess);
	tok = console_system_token(sess);
	if (tok != NULL) {
		snwprintf(cmd, 512, L"\"%ls\" worker", PROBE_EXE);
		memset(&si, 0, sizeof(si));
		si.cb = sizeof(si);
		si.lpDesktop = L"winsta0\\Default";
		memset(&pi, 0, sizeof(pi));
		if (!CreateProcessAsUserW(tok, NULL, cmd, NULL, NULL, FALSE,
			CREATE_NO_WINDOW, NULL, PROBE_DIR, &si, &pi)) {
			printf("spawn_default_err %lu\n", GetLastError());
			si.lpDesktop = L"winsta0\\Winlogon";
			if (!CreateProcessAsUserW(tok, NULL, cmd, NULL, NULL, FALSE,
				CREATE_NO_WINDOW, NULL, PROBE_DIR, &si, &pi)) {
				printf("spawn_winlogon_err %lu\n", GetLastError());
				CloseHandle(tok);
				report_svc(SERVICE_STOPPED);
				return;
			}
		}
		CloseHandle(tok);
		printf("spawned_worker pid %lu\n", pi.dwProcessId);
		WaitForSingleObject(pi.hProcess, 25000);
		GetExitCodeProcess(pi.hProcess, &code);
		printf("worker_exit %lu\n", code);
		CloseHandle(pi.hThread);
		CloseHandle(pi.hProcess);
	}
	report_svc(SERVICE_STOPPED);
}

int
main(int argc, char **argv)
{
	if (argc >= 2 && strcmp(argv[1], "worker") == 0) {
		return worker_main();
	}
	if (argc >= 4 && strcmp(argv[1], "uipi_click") == 0) {
		return uipi_click_main(atol(argv[2]), atol(argv[3]));
	}
	if (argc >= 2 && strcmp(argv[1], "service") == 0) {
		SERVICE_TABLE_ENTRYW table[2];
		table[0].lpServiceName = L"ArgusShotProbe";
		table[0].lpServiceProc = svc_main;
		table[1].lpServiceName = NULL;
		table[1].lpServiceProc = NULL;
		StartServiceCtrlDispatcherW(table);
		return 0;
	}
	printf("usage: probe.exe [service|worker|uipi_click x y]\n");
	return 1;
}
