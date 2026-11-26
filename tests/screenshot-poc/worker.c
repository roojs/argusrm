#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <wtsapi32.h>
#include <tlhelp32.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>

#define PROBE_DIR L"C:\\Users\\alan\\argus-shot-p2\\"
#define PROBE_EXE L"C:\\Users\\alan\\argus-shot-p2\\worker.exe"
#define WORKER_LOG "C:\\Users\\alan\\argus-shot-p2\\worker.log"
#define SERVICE_LOG "C:\\Users\\alan\\argus-shot-p2\\service.log"
#define LOCAL_PORT 19444

#define MSG_FRAME_FULL  0x01
#define MSG_FRAME_TILES 0x03
#define MSG_FRAME_ACK   0x10
#define MSG_MOUSE_CLICK 0x11
#define MSG_MOUSE_MOVE  0x12
#define MSG_KEY_UNICODE 0x13
#define MSG_KEY_VK      0x14

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

static void
put_u16(uint8_t *p, uint16_t v)
{
	p[0] = (uint8_t) (v & 0xFF);
	p[1] = (uint8_t) ((v >> 8) & 0xFF);
}

static void
put_u32(uint8_t *p, uint32_t v)
{
	p[0] = (uint8_t) (v & 0xFF);
	p[1] = (uint8_t) ((v >> 8) & 0xFF);
	p[2] = (uint8_t) ((v >> 16) & 0xFF);
	p[3] = (uint8_t) ((v >> 24) & 0xFF);
}

static uint16_t
get_u16(const uint8_t *p)
{
	return (uint16_t) p[0] | ((uint16_t) p[1] << 8);
}

static uint32_t
get_u32(const uint8_t *p)
{
	return (uint32_t) p[0] | ((uint32_t) p[1] << 8) |
		((uint32_t) p[2] << 16) | ((uint32_t) p[3] << 24);
}

static int
send_all(SOCKET s, const uint8_t *buf, size_t len)
{
	size_t off = 0;

	while (off < len) {
		int n = send(s, (const char *) (buf + off), (int) (len - off), 0);
		if (n <= 0) {
			return 0;
		}
		off += (size_t) n;
	}
	return 1;
}

static int
recv_exact(SOCKET s, uint8_t *buf, size_t len)
{
	size_t off = 0;

	while (off < len) {
		int n = recv(s, (char *) (buf + off), (int) (len - off), 0);
		if (n <= 0) {
			return 0;
		}
		off += (size_t) n;
	}
	return 1;
}

static int
send_framed(SOCKET s, const uint8_t *payload, uint32_t len)
{
	uint8_t hdr[4];

	put_u32(hdr, len);
	return send_all(s, hdr, 4) && send_all(s, payload, len);
}

static HDESK g_desk = NULL;

static int
attach_desktop(void)
{
	HWINSTA station;
	HDESK desk;
	wchar_t name[64];
	DWORD needed = 0;

	station = OpenWindowStationW(L"WinSta0", FALSE, WINSTA_ALL_ACCESS);
	if (station == NULL || !SetProcessWindowStation(station)) {
		printf("winsta_err %lu\n", GetLastError());
		return 0;
	}
	desk = OpenInputDesktop(0, FALSE,
		DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS |
		DESKTOP_SWITCHDESKTOP | GENERIC_ALL);
	if (desk == NULL) {
		desk = OpenDesktopW(L"Winlogon", 0, FALSE,
			DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS);
	}
	if (desk == NULL) {
		desk = OpenDesktopW(L"Default", 0, FALSE,
			DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS);
	}
	if (desk == NULL || !SetThreadDesktop(desk)) {
		printf("desk_err %lu\n", GetLastError());
		return 0;
	}
	g_desk = desk;
	name[0] = 0;
	if (GetUserObjectInformationW(desk, UOI_NAME, name, sizeof(name), &needed)) {
		printf("desktop %ls\n", name);
	}
	return 1;
}

static int
capture_bgra(int width, int height, uint8_t *out)
{
	HDC dc = GetDC(NULL);
	if (dc == NULL) return 0;
	HDC mem = CreateCompatibleDC(dc);
	HBITMAP bmp = CreateCompatibleBitmap(dc, width, height);
	HGDIOBJ old = SelectObject(mem, bmp);
	int ok = BitBlt(mem, 0, 0, width, height, dc, 0, 0, SRCCOPY | CAPTUREBLT);
	if (ok) {
		BITMAPINFO bi;
		memset(&bi, 0, sizeof(bi));
		bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
		bi.bmiHeader.biWidth = width;
		bi.bmiHeader.biHeight = -(LONG) height;
		bi.bmiHeader.biPlanes = 1;
		bi.bmiHeader.biBitCount = 32;
		bi.bmiHeader.biCompression = BI_RGB;
		GetDIBits(mem, bmp, 0, (UINT) height, out, &bi, DIB_RGB_COLORS);
	}
	SelectObject(mem, old);
	DeleteObject(bmp);
	DeleteDC(mem);
	ReleaseDC(NULL, dc);
	return ok;
}

static size_t
encode_jpeg_rect(const uint8_t *bgra, int stride_px, int x0, int y0, int w, int h,
	int quality, uint8_t **out_buf)
{
	struct jpeg_compress_struct cinfo;
	struct jpeg_error_mgr jerr;
	unsigned char *buf = NULL;
	unsigned long size = 0;

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
	for (int y = 0; y < h; y++) {
		JSAMPROW row = (JSAMPROW) (bgra + ((size_t) (y0 + y) * (size_t) stride_px + (size_t) x0) * 4);
		jpeg_write_scanlines(&cinfo, &row, 1);
	}
	jpeg_finish_compress(&cinfo);
	jpeg_destroy_compress(&cinfo);
	*out_buf = (uint8_t *) buf;
	return (size_t) size;
}

static volatile LONG g_stop = 0;
static volatile LONG g_ack_seq = 0;
static volatile LONG g_remote_clicks = 0;
static volatile LONG g_remote_keys = 0;
static int g_btn_count = 0;
static int g_ret_count = 0;
static HWND g_btn = NULL;
static HWND g_edit = NULL;

static LRESULT CALLBACK
wnd_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
	if (msg == WM_COMMAND && LOWORD(wparam) == 101 && HIWORD(wparam) == BN_CLICKED) {
		wchar_t label[64];
		g_btn_count++;
		snwprintf(label, 64, L"Clicks: %d", g_btn_count);
		SetWindowTextW(g_btn, label);
		printf("ui_btn_clicked %d\n", g_btn_count);
		return 0;
	}
	return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static DWORD WINAPI
recv_thread(LPVOID arg)
{
	SOCKET s = (SOCKET) (intptr_t) arg;
	uint8_t hdr[4];

	if (g_desk != NULL) {
		if (!SetThreadDesktop(g_desk)) {
			printf("recv_set_desk_err %lu\n", GetLastError());
		} else {
			printf("recv_desk_attached\n");
		}
	}

	while (!g_stop && recv_exact(s, hdr, 4)) {
		uint32_t len = get_u32(hdr);
		if (len == 0 || len > 1024 * 1024) {
			break;
		}
		uint8_t *buf = malloc(len);
		if (buf == NULL || !recv_exact(s, buf, len)) {
			free(buf);
			break;
		}
		uint8_t type = buf[0];
		if (type == MSG_FRAME_ACK && len >= 5) {
			InterlockedExchange(&g_ack_seq, (LONG) get_u32(buf + 1));
		} else if (type == MSG_MOUSE_CLICK && len >= 6) {
			uint16_t nx = get_u16(buf + 1);
			uint16_t ny = get_u16(buf + 3);
			uint8_t btn = buf[5];
			INPUT in[3];
			memset(in, 0, sizeof(in));
			in[0].type = INPUT_MOUSE;
			in[0].mi.dx = nx;
			in[0].mi.dy = ny;
			in[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
			in[1].type = INPUT_MOUSE;
			in[1].mi.dwFlags = (btn == 3) ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
			in[2].type = INPUT_MOUSE;
			in[2].mi.dwFlags = (btn == 3) ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP;
			SendInput(3, in, sizeof(INPUT));
			InterlockedIncrement(&g_remote_clicks);
		} else if (type == MSG_MOUSE_MOVE && len >= 5) {
			INPUT in;
			memset(&in, 0, sizeof(in));
			in.type = INPUT_MOUSE;
			in.mi.dx = get_u16(buf + 1);
			in.mi.dy = get_u16(buf + 3);
			in.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
			SendInput(1, &in, sizeof(INPUT));
		} else if (type == MSG_KEY_UNICODE && len >= 3) {
			uint16_t ch = get_u16(buf + 1);
			INPUT in[2];
			memset(in, 0, sizeof(in));
			in[0].type = INPUT_KEYBOARD;
			in[0].ki.wScan = ch;
			in[0].ki.dwFlags = KEYEVENTF_UNICODE;
			in[1].type = INPUT_KEYBOARD;
			in[1].ki.wScan = ch;
			in[1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
			SendInput(2, in, sizeof(INPUT));
			InterlockedIncrement(&g_remote_keys);
		} else if (type == MSG_KEY_VK && len >= 4) {
			INPUT in;
			memset(&in, 0, sizeof(in));
			in.type = INPUT_KEYBOARD;
			in.ki.wVk = get_u16(buf + 1);
			in.ki.dwFlags = buf[3] ? KEYEVENTF_KEYUP : 0;
			SendInput(1, &in, sizeof(INPUT));
			InterlockedIncrement(&g_remote_keys);
		}
		free(buf);
	}
	InterlockedExchange(&g_stop, 1);
	return 0;
}

static void
pump_messages(void)
{
	MSG msg;

	while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
		if (msg.message == WM_KEYDOWN && msg.wParam == VK_RETURN) {
			g_ret_count++;
		}
		TranslateMessage(&msg);
		DispatchMessageW(&msg);
	}
}

static int
worker_main(void)
{
	WSADATA wsa;
	SOCKET sock;
	struct sockaddr_in addr;
	int w, h;
	size_t raw_bytes;
	uint8_t *cur = NULL;
	uint8_t *prev = NULL;
	WNDCLASSW wc;
	HWND hwnd;
	RECT rb, re;
	double t_start;
	uint32_t seq = 0;
	int have_prev = 0;
	uint64_t frames_sent = 0;
	uint64_t bytes_sent = 0;

	freopen(WORKER_LOG, "w", stdout);
	setvbuf(stdout, NULL, _IONBF, 0);
	if (!attach_desktop()) {
		return 1;
	}
	SetProcessDPIAware();
	w = GetSystemMetrics(SM_CXSCREEN);
	h = GetSystemMetrics(SM_CYSCREEN);
	printf("worker screen %d %d\n", w, h);

	memset(&wc, 0, sizeof(wc));
	wc.lpfnWndProc = wnd_proc;
	wc.hInstance = GetModuleHandleW(NULL);
	wc.lpszClassName = L"ArgusShotP2Test";
	RegisterClassW(&wc);
	hwnd = CreateWindowExW(WS_EX_TOPMOST, L"ArgusShotP2Test", L"Argus Remote PoC",
		WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 360, 180, NULL, NULL, wc.hInstance, NULL);
	g_btn = CreateWindowW(L"BUTTON", L"Clicks: 0", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
		20, 20, 140, 40, hwnd, (HMENU) 101, wc.hInstance, NULL);
	g_edit = CreateWindowW(L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
		20, 76, 300, 32, hwnd, (HMENU) 102, wc.hInstance, NULL);
	ShowWindow(hwnd, SW_SHOW);
	UpdateWindow(hwnd);
	SetForegroundWindow(hwnd);
	for (int i = 0; i < 15; i++) {
		pump_messages();
		Sleep(15);
	}
	GetWindowRect(g_btn, &rb);
	GetWindowRect(g_edit, &re);
	printf("targets btn=%ld,%ld edit=%ld,%ld\n",
		(rb.left + rb.right) / 2, (rb.top + rb.bottom) / 2,
		(re.left + re.right) / 2, (re.top + re.bottom) / 2);

	WSAStartup(MAKEWORD(2, 2), &wsa);
	sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(LOCAL_PORT);
	inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
	int connected = 0;
	for (int tries = 0; tries < 40; tries++) {
		if (connect(sock, (struct sockaddr *) &addr, sizeof(addr)) == 0) {
			connected = 1;
			break;
		}
		pump_messages();
		Sleep(100);
	}
	if (!connected) {
		printf("connect_local_failed %d\n", WSAGetLastError());
		DestroyWindow(hwnd);
		return 1;
	}
	{
		BOOL nodelay = TRUE;
		setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (const char *) &nodelay, sizeof(nodelay));
	}
	printf("worker local_connected\n");

	HANDLE rth = CreateThread(NULL, 0, recv_thread, (LPVOID) (intptr_t) sock, 0, NULL);

	raw_bytes = (size_t) w * (size_t) h * 4;
	cur = malloc(raw_bytes);
	prev = malloc(raw_bytes);
	t_start = now_ms();

	while (!g_stop && (now_ms() - t_start) < 70000.0) {
		pump_messages();
		/* Backpressure: wait until previous frame is ACKed */
		if (seq > 0 && (uint32_t) g_ack_seq < seq) {
			Sleep(10);
			continue;
		}
		if (!capture_bgra(w, h, cur)) {
			Sleep(100);
			continue;
		}
		if (!have_prev) {
			uint8_t *jpg = NULL;
			size_t jsz = encode_jpeg_rect(cur, w, 0, 0, w, h, 65, &jpg);
			seq++;
			uint32_t plen = (uint32_t) (9 + jsz);
			uint8_t *pkt = malloc(plen);
			pkt[0] = MSG_FRAME_FULL;
			put_u32(pkt + 1, seq);
			put_u16(pkt + 5, (uint16_t) w);
			put_u16(pkt + 7, (uint16_t) h);
			memcpy(pkt + 9, jpg, jsz);
			free(jpg);
			if (!send_framed(sock, pkt, plen)) {
				free(pkt);
				break;
			}
			free(pkt);
			memcpy(prev, cur, raw_bytes);
			have_prev = 1;
			frames_sent++;
			bytes_sent += plen;
			printf("sent_full seq=%u bytes=%u\n", seq, plen);
		} else {
			/* Find dirty 64x64 tiles */
			int max_tiles = ((w + 63) / 64) * ((h + 63) / 64);
			int *txs = malloc((size_t) max_tiles * sizeof(int));
			int *tys = malloc((size_t) max_tiles * sizeof(int));
			int dirty = 0;
			for (int ty = 0; ty < h; ty += 64) {
				int th = (ty + 64 <= h) ? 64 : (h - ty);
				for (int tx = 0; tx < w; tx += 64) {
					int tw = (tx + 64 <= w) ? 64 : (w - tx);
					int diff = 0;
					for (int ry = 0; ry < th; ry++) {
						size_t off = ((size_t) (ty + ry) * (size_t) w + (size_t) tx) * 4;
						if (memcmp(cur + off, prev + off, (size_t) tw * 4) != 0) {
							diff = 1;
							break;
						}
					}
					if (diff) {
						txs[dirty] = tx;
						tys[dirty] = ty;
						dirty++;
					}
				}
			}
			if (dirty > 0) {
				seq++;
				if (dirty * 5 > max_tiles * 2) {
					/* >40% screen changed: send full frame */
					uint8_t *jpg = NULL;
					size_t jsz = encode_jpeg_rect(cur, w, 0, 0, w, h, 65, &jpg);
					uint32_t plen = (uint32_t) (9 + jsz);
					uint8_t *pkt = malloc(plen);
					pkt[0] = MSG_FRAME_FULL;
					put_u32(pkt + 1, seq);
					put_u16(pkt + 5, (uint16_t) w);
					put_u16(pkt + 7, (uint16_t) h);
					memcpy(pkt + 9, jpg, jsz);
					free(jpg);
					if (!send_framed(sock, pkt, plen)) {
						free(pkt);
						free(txs);
						free(tys);
						break;
					}
					free(pkt);
					frames_sent++;
					bytes_sent += plen;
				} else {
					/* Batched dirty tiles */
					size_t cap = 7 + (size_t) dirty * 8192;
					uint8_t *pkt = malloc(cap);
					size_t pos = 7;
					pkt[0] = MSG_FRAME_TILES;
					put_u32(pkt + 1, seq);
					put_u16(pkt + 5, (uint16_t) dirty);
					for (int di = 0; di < dirty; di++) {
						int tx = txs[di];
						int ty = tys[di];
						int tw = (tx + 64 <= w) ? 64 : (w - tx);
						int th = (ty + 64 <= h) ? 64 : (h - ty);
						uint8_t *jpg = NULL;
						size_t jsz = encode_jpeg_rect(cur, w, tx, ty, tw, th, 65, &jpg);
						if (pos + 12 + jsz > cap) {
							cap = (pos + 12 + jsz) * 2;
							pkt = realloc(pkt, cap);
						}
						put_u16(pkt + pos, (uint16_t) tx);
						put_u16(pkt + pos + 2, (uint16_t) ty);
						put_u16(pkt + pos + 4, (uint16_t) tw);
						put_u16(pkt + pos + 6, (uint16_t) th);
						put_u32(pkt + pos + 8, (uint32_t) jsz);
						memcpy(pkt + pos + 12, jpg, jsz);
						pos += 12 + jsz;
						free(jpg);
					}
					if (!send_framed(sock, pkt, (uint32_t) pos)) {
						free(pkt);
						free(txs);
						free(tys);
						break;
					}
					free(pkt);
					frames_sent++;
					bytes_sent += pos;
					printf("sent_tiles seq=%u dirty=%d bytes=%zu\n", seq, dirty, pos);
				}
				memcpy(prev, cur, raw_bytes);
			}
			free(txs);
			free(tys);
		}
		for (int sl = 0; sl < 10 && !g_stop; sl++) {
			pump_messages();
			Sleep(15);
		}
	}

	{
		wchar_t text[128];
		memset(text, 0, sizeof(text));
		GetWindowTextW(g_edit, text, 127);
		printf("worker_summary frames=%llu bytes=%llu clicks_in=%ld keys_in=%ld ui_clicks=%d ui_text=\"%ls\" ui_return=%d\n",
			(unsigned long long) frames_sent,
			(unsigned long long) bytes_sent,
			g_remote_clicks, g_remote_keys,
			g_btn_count, text, g_ret_count);
	}
	InterlockedExchange(&g_stop, 1);
	closesocket(sock);
	if (rth != NULL) {
		WaitForSingleObject(rth, 2000);
		CloseHandle(rth);
	}
	DestroyWindow(hwnd);
	pump_messages();
	free(cur);
	free(prev);
	WSACleanup();
	printf("worker_done\n");
	return 0;
}

static HANDLE
console_system_token(DWORD target_session)
{
	HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	PROCESSENTRY32W entry;
	DWORD pid = 0;

	if (snap == INVALID_HANDLE_VALUE) return NULL;
	entry.dwSize = sizeof(entry);
	if (Process32FirstW(snap, &entry)) {
		do {
			DWORD s = 0;
			if (_wcsicmp(entry.szExeFile, L"winlogon.exe") != 0) continue;
			ProcessIdToSessionId(entry.th32ProcessID, &s);
			if (s == target_session) {
				pid = entry.th32ProcessID;
				break;
			}
		} while (Process32NextW(snap, &entry));
	}
	CloseHandle(snap);
	if (pid == 0) return NULL;
	HANDLE proc = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pid);
	if (proc == NULL) return NULL;
	HANDLE token = NULL, dup = NULL;
	if (OpenProcessToken(proc, TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY, &token)) {
		DuplicateTokenEx(token, MAXIMUM_ALLOWED, NULL, SecurityImpersonation, TokenPrimary, &dup);
		CloseHandle(token);
	}
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
	(void) argc;
	(void) argv;
	g_svc_handle = RegisterServiceCtrlHandlerW(L"ArgusShotP2", svc_ctrl);
	report_svc(SERVICE_RUNNING);
	freopen(SERVICE_LOG, "w", stdout);
	setvbuf(stdout, NULL, _IONBF, 0);
	DWORD sess = WTSGetActiveConsoleSessionId();
	printf("svc_session %lu\n", sess);
	HANDLE tok = console_system_token(sess);
	if (tok != NULL) {
		STARTUPINFOW si;
		PROCESS_INFORMATION pi;
		wchar_t cmd[512];
		snwprintf(cmd, 512, L"\"%ls\" worker", PROBE_EXE);
		memset(&si, 0, sizeof(si));
		si.cb = sizeof(si);
		si.lpDesktop = L"winsta0\\Default";
		memset(&pi, 0, sizeof(pi));
		if (!CreateProcessAsUserW(tok, NULL, cmd, NULL, NULL, FALSE,
			CREATE_NO_WINDOW, NULL, PROBE_DIR, &si, &pi)) {
			si.lpDesktop = L"winsta0\\Winlogon";
			CreateProcessAsUserW(tok, NULL, cmd, NULL, NULL, FALSE,
				CREATE_NO_WINDOW, NULL, PROBE_DIR, &si, &pi);
		}
		CloseHandle(tok);
		if (pi.hProcess != NULL) {
			DWORD code = 999;
			printf("svc_worker_pid %lu\n", pi.dwProcessId);
			WaitForSingleObject(pi.hProcess, 80000);
			GetExitCodeProcess(pi.hProcess, &code);
			printf("svc_worker_exit %lu\n", code);
			CloseHandle(pi.hThread);
			CloseHandle(pi.hProcess);
		}
	}
	report_svc(SERVICE_STOPPED);
}

int
main(int argc, char **argv)
{
	if (argc >= 2 && strcmp(argv[1], "worker") == 0) {
		return worker_main();
	}
	if (argc >= 2 && strcmp(argv[1], "service") == 0) {
		SERVICE_TABLE_ENTRYW table[2];
		table[0].lpServiceName = L"ArgusShotP2";
		table[0].lpServiceProc = svc_main;
		table[1].lpServiceName = NULL;
		table[1].lpServiceProc = NULL;
		StartServiceCtrlDispatcherW(table);
		return 0;
	}
	return 1;
}
