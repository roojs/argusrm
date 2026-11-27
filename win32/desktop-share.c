/* Thin COM FFI wrapper for IRDPSRAPISharingSession (RdpEncom.dll).
 * No program logic: only COM initialization, vtable sink, Open, and Close.
 */
#define COBJMACROS
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif

#include "desktop-share.h"

#include <windows.h>
#include <objbase.h>
#include <olectl.h>
#include <oleauto.h>
#include <initguid.h>
#include <rdpencomapi.h>
#include <stdlib.h>

typedef struct {
	IDispatchVtbl *lpVtbl;
	LONG ref_count;
	ArgusShareEventFn on_event;
	void *user_data;
} ArgusShareSink;

typedef struct {
	IRDPSRAPISharingSession *session;
	IConnectionPointContainer *cpc;
	IConnectionPoint *cp;
	IRDPSRAPIInvitationManager *inv_mgr;
	IRDPSRAPIInvitation *inv;
	ArgusShareSink *sink;
	DWORD cookie;
	char *invite;
} ArgusShareHandle;

static HRESULT STDMETHODCALLTYPE sink_qi(IDispatch *self, REFIID riid, void **ppv)
{
	if (IsEqualIID(riid, &IID_IUnknown) ||
		IsEqualIID(riid, &IID_IDispatch) ||
		IsEqualIID(riid, &DIID__IRDPSessionEvents)) {
		*ppv = self;
		IDispatch_AddRef(self);
		return S_OK;
	}
	*ppv = NULL;
	return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE sink_addref(IDispatch *self)
{
	return (ULONG) InterlockedIncrement(&((ArgusShareSink *) self)->ref_count);
}

static ULONG STDMETHODCALLTYPE sink_release(IDispatch *self)
{
	ArgusShareSink *sink = (ArgusShareSink *) self;
	LONG refs = InterlockedDecrement(&sink->ref_count);
	if (refs == 0) {
		free(sink);
	}
	return (ULONG) refs;
}

static HRESULT STDMETHODCALLTYPE sink_tic(IDispatch *self, UINT *n)
{
	(void) self;
	*n = 0;
	return S_OK;
}

static HRESULT STDMETHODCALLTYPE sink_ti(IDispatch *self, UINT i, LCID l, ITypeInfo **t)
{
	(void) self; (void) i; (void) l;
	*t = NULL;
	return E_NOTIMPL;
}

static HRESULT STDMETHODCALLTYPE sink_ids(IDispatch *self, REFIID r, LPOLESTR *n, UINT c, LCID l, DISPID *d)
{
	(void) self; (void) r; (void) n; (void) c; (void) l; (void) d;
	return E_NOTIMPL;
}

static void grant_interactive(VARIANT *arg)
{
	IDispatch *disp = NULL;
	if (arg->vt == VT_DISPATCH) {
		disp = arg->pdispVal;
	} else if (arg->vt == (VT_DISPATCH | VT_BYREF) && arg->ppdispVal) {
		disp = *arg->ppdispVal;
	}
	if (!disp) {
		return;
	}
	IRDPSRAPIAttendee *att = NULL;
	if (SUCCEEDED(IDispatch_QueryInterface(disp, &IID_IRDPSRAPIAttendee, (void **) &att)) && att) {
		IRDPSRAPIAttendee_put_ControlLevel(att, CTRL_LEVEL_INTERACTIVE);
		IRDPSRAPIAttendee_Release(att);
	}
}

static HRESULT STDMETHODCALLTYPE sink_invoke(
	IDispatch *self, DISPID dispid, REFIID riid, LCID lcid, WORD flags,
	DISPPARAMS *params, VARIANT *res, EXCEPINFO *ex, UINT *err)
{
	(void) riid; (void) lcid; (void) flags; (void) res; (void) ex; (void) err;
	ArgusShareSink *sink = (ArgusShareSink *) self;
	if (dispid == DISPID_RDPSRAPI_EVENT_ON_ATTENDEE_CONNECTED && params && params->cArgs >= 1) {
		grant_interactive(&params->rgvarg[0]);
	}
	if (dispid == DISPID_RDPSRAPI_EVENT_ON_CTRLLEVEL_CHANGE_REQUEST && params && params->cArgs >= 2) {
		grant_interactive(&params->rgvarg[1]);
	}
	if (sink->on_event) {
		sink->on_event((int) dispid, sink->user_data);
	}
	return S_OK;
}

static IDispatchVtbl sink_vtbl = {
	sink_qi, sink_addref, sink_release, sink_tic, sink_ti, sink_ids, sink_invoke
};

static void set_i4_prop(IRDPSRAPISessionProperties *props, const wchar_t *name, LONG value)
{
	BSTR key = SysAllocString(name);
	if (!key) {
		return;
	}
	VARIANT val;
	VariantInit(&val);
	val.vt = VT_I4;
	val.lVal = value;
	IRDPSRAPISessionProperties_put_Property(props, key, val);
	SysFreeString(key);
}

void *argus_rdp_share_open(
	uint16_t port,
	const char *password,
	ArgusShareEventFn on_event,
	void *user_data)
{
	if (!password || FAILED(CoInitializeEx(NULL, COINIT_APARTMENTTHREADED))) {
		return NULL;
	}
	ArgusShareHandle *h = (ArgusShareHandle *) calloc(1, sizeof(ArgusShareHandle));
	if (!h) {
		CoUninitialize();
		return NULL;
	}
	if (FAILED(CoCreateInstance(&CLSID_RDPSession, NULL, CLSCTX_INPROC_SERVER,
		&IID_IRDPSRAPISharingSession, (void **) &h->session)) || !h->session) {
		argus_rdp_share_close(h);
		return NULL;
	}
	IRDPSRAPISessionProperties *props = NULL;
	if (SUCCEEDED(IRDPSRAPISharingSession_get_Properties(h->session, &props)) && props) {
		if (port > 0) {
			set_i4_prop(props, L"PortId", (LONG) port);
		}
		set_i4_prop(props, L"PortProtocol", 2);
		set_i4_prop(props, L"EnabledTransports", 1);
		set_i4_prop(props, L"DefaultAttendeeControlLevel", CTRL_LEVEL_VIEW);
		IRDPSRAPISessionProperties_Release(props);
	}
	h->sink = (ArgusShareSink *) calloc(1, sizeof(ArgusShareSink));
	if (!h->sink) {
		argus_rdp_share_close(h);
		return NULL;
	}
	h->sink->lpVtbl = &sink_vtbl;
	h->sink->ref_count = 1;
	h->sink->on_event = on_event;
	h->sink->user_data = user_data;
	if (SUCCEEDED(IRDPSRAPISharingSession_QueryInterface(
		h->session, &IID_IConnectionPointContainer, (void **) &h->cpc)) && h->cpc) {
		if (SUCCEEDED(IConnectionPointContainer_FindConnectionPoint(
			h->cpc, &DIID__IRDPSessionEvents, &h->cp)) && h->cp) {
			IConnectionPoint_Advise(h->cp, (IUnknown *) h->sink, &h->cookie);
		}
	}
	if (FAILED(IRDPSRAPISharingSession_Open(h->session))) {
		argus_rdp_share_close(h);
		return NULL;
	}
	if (FAILED(IRDPSRAPISharingSession_get_Invitations(h->session, &h->inv_mgr)) || !h->inv_mgr) {
		argus_rdp_share_close(h);
		return NULL;
	}
	int wlen = MultiByteToWideChar(CP_UTF8, 0, password, -1, NULL, 0);
	wchar_t *wpass = wlen > 0 ? (wchar_t *) calloc((size_t) wlen, sizeof(wchar_t)) : NULL;
	if (wpass) {
		MultiByteToWideChar(CP_UTF8, 0, password, -1, wpass, wlen);
	}
	BSTR b_auth = SysAllocString(L"Argus");
	BSTR b_group = SysAllocString(L"ArgusGroup");
	BSTR b_pass = SysAllocString(wpass ? wpass : L"");
	free(wpass);
	HRESULT hr = IRDPSRAPIInvitationManager_CreateInvitation(
		h->inv_mgr, b_auth, b_group, b_pass, 1, &h->inv);
	SysFreeString(b_auth);
	SysFreeString(b_group);
	SysFreeString(b_pass);
	if (FAILED(hr) || !h->inv) {
		argus_rdp_share_close(h);
		return NULL;
	}
	BSTR b_conn = NULL;
	if (FAILED(IRDPSRAPIInvitation_get_ConnectionString(h->inv, &b_conn)) || !b_conn) {
		argus_rdp_share_close(h);
		return NULL;
	}
	int ulen = WideCharToMultiByte(CP_UTF8, 0, b_conn, -1, NULL, 0, NULL, NULL);
	h->invite = ulen > 0 ? (char *) calloc((size_t) ulen, 1) : NULL;
	if (h->invite) {
		WideCharToMultiByte(CP_UTF8, 0, b_conn, -1, h->invite, ulen, NULL, NULL);
	}
	SysFreeString(b_conn);
	if (!h->invite) {
		argus_rdp_share_close(h);
		return NULL;
	}
	return h;
}

const char *argus_rdp_share_invite(void *handle)
{
	return handle ? ((ArgusShareHandle *) handle)->invite : "";
}

void argus_rdp_share_close(void *handle)
{
	if (!handle) {
		return;
	}
	ArgusShareHandle *h = (ArgusShareHandle *) handle;
	if (h->session) {
		IRDPSRAPISharingSession_Close(h->session);
	}
	if (h->inv) {
		IRDPSRAPIInvitation_Release(h->inv);
	}
	if (h->inv_mgr) {
		IRDPSRAPIInvitationManager_Release(h->inv_mgr);
	}
	if (h->cp && h->cookie) {
		IConnectionPoint_Unadvise(h->cp, h->cookie);
	}
	if (h->cp) {
		IConnectionPoint_Release(h->cp);
	}
	if (h->cpc) {
		IConnectionPointContainer_Release(h->cpc);
	}
	if (h->sink) {
		IDispatch_Release((IDispatch *) h->sink);
	}
	if (h->session) {
		IRDPSRAPISharingSession_Release(h->session);
	}
	free(h->invite);
	free(h);
	CoUninitialize();
}
