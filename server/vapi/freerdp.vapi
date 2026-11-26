[CCode (cheader_filename = "freerdp/freerdp.h", lower_case_cprefix = "freerdp_")]
namespace FreeRDP
{
	[CCode (cname = "ENCRYPTION_LEVEL_CLIENT_COMPATIBLE", cheader_filename = "freerdp/settings_types.h")]
	public const uint32 ENCRYPTION_LEVEL_CLIENT_COMPATIBLE;

	[CCode (cprefix = "FreeRDP_", has_type_id = false, cheader_filename = "freerdp/settings_keys.h")]
	public enum SettingsBool
	{
		NlaSecurity,
		TlsSecurity,
		RdpSecurity,
		SupportMultitransport,
		SupportGraphicsPipeline,
		RemoteFxCodec,
		NSCodec,
		BitmapCacheEnabled,
		BitmapCacheV3Enabled,
		SurfaceCommandsEnabled,
		GfxH264,
		GfxAVC444,
		GfxAVC444v2,
		RedirectDrives,
		AudioPlayback,
		RedirectClipboard,
	}

	[CCode (cprefix = "FreeRDP_", has_type_id = false, cheader_filename = "freerdp/settings_keys.h")]
	public enum SettingsUint32
	{
		EncryptionLevel,
		ColorDepth,
		ServerPort,
		DesktopWidth,
		DesktopHeight,
		MultitransportFlags,
	}

	[CCode (cprefix = "FreeRDP_", has_type_id = false, cheader_filename = "freerdp/settings_keys.h")]
	public enum SettingsString
	{
		ServerHostname,
		Username,
		Password,
		Domain
	}

	[CCode (cprefix = "FreeRDP_", has_type_id = false, cheader_filename = "freerdp/settings_keys.h")]
	public enum SettingsPointer
	{
		RdpServerCertificate,
		RdpServerRsaKey
	}

	[Compact]
	[CCode (cname = "rdpSettings", cheader_filename = "freerdp/settings.h")]
	public class Settings
	{
		[CCode (cname = "freerdp_settings_set_bool")]
		public bool set_bool (SettingsBool key, bool value);

		[CCode (cname = "freerdp_settings_set_uint32")]
		public bool set_uint32 (SettingsUint32 key, uint32 value);

		[CCode (cname = "freerdp_settings_set_pointer")]
		public bool set_pointer (SettingsPointer key, void* value);

		[CCode (cname = "freerdp_settings_set_string")]
		public bool set_string (SettingsString key, string value);
	}

	[Compact]
	[CCode (cname = "rdpContext", cheader_filename = "freerdp/freerdp.h")]
	public class Context
	{
		public unowned Settings settings;
		public unowned Instance instance;
		public unowned Gdi? gdi;
	}

	[Compact]
	[CCode (cname = "rdpCertificate", cheader_filename = "freerdp/crypto/certificate.h")]
	public class Certificate
	{
		[CCode (cname = "freerdp_certificate_new_from_file")]
		public Certificate.from_file (string path);
	}

	[Compact]
	[CCode (cname = "rdpPrivateKey", cheader_filename = "freerdp/crypto/privatekey.h")]
	public class PrivateKey
	{
		[CCode (cname = "freerdp_key_new_from_file")]
		public PrivateKey.from_file (string path);
	}

	[CCode (has_target = false, cname = "psPeerInitialize")]
	public delegate bool PeerInitialize (Peer peer);

	[CCode (has_target = false, cname = "psPeerPostConnect")]
	public delegate bool PeerPostConnect (Peer peer);

	[CCode (has_target = false, cname = "psPeerActivate")]
	public delegate bool PeerActivate (Peer peer);

	[CCode (has_target = false, cname = "psPeerLogon")]
	public delegate bool PeerLogon (Peer peer, [CCode (type = "const SEC_WINNT_AUTH_IDENTITY*")] void* identity, bool automatic);

	[CCode (has_target = false, cname = "psPeerCheckFileDescriptor")]
	public delegate bool PeerCheckFileDescriptor (Peer peer);

	[CCode (has_target = false, cname = "psPeerDisconnect")]
	public delegate bool PeerDisconnect (Peer peer);

	[CCode (has_target = false, cname = "psPeerGetEventHandles")]
	public delegate uint32 PeerGetEventHandles (Peer peer, [CCode (array_length = false)] void*[] events, uint32 count);

	[Compact]
	[CCode (cname = "freerdp_peer", cheader_filename = "freerdp/peer.h")]
	public class Peer
	{
		public unowned Context context;
		public PeerInitialize Initialize;
		public PeerGetEventHandles GetEventHandles;
		public PeerCheckFileDescriptor CheckFileDescriptor;
		public PeerDisconnect Disconnect;
		public PeerPostConnect PostConnect;
		public PeerActivate Activate;
		public PeerLogon Logon;
		public int activated;

		[CCode (cname = "freerdp_peer_context_new")]
		public bool context_new ();

		[CCode (cname = "freerdp_peer_context_free")]
		public void context_free ();

		[CCode (cname = "freerdp_peer_free")]
		public void peer_free ();
	}

	[CCode (has_target = false, cname = "psListenerOpen")]
	public delegate bool ListenerOpen (Listener listener, string address, uint16 port);

	[CCode (has_target = false, cname = "psListenerGetEventHandles")]
	public delegate uint32 ListenerGetEventHandles (Listener listener, [CCode (array_length = false)] void*[] events, uint32 count);

	[CCode (has_target = false, cname = "psListenerCheckFileDescriptor")]
	public delegate bool ListenerCheckFileDescriptor (Listener listener);

	[CCode (has_target = false, cname = "psListenerClose")]
	public delegate void ListenerClose (Listener listener);

	[CCode (has_target = false, cname = "psPeerAccepted")]
	public delegate bool PeerAccepted (Listener listener, Peer peer);

	[Compact]
	[CCode (cname = "freerdp_listener", cheader_filename = "freerdp/listener.h", free_function = "freerdp_listener_free")]
	public class Listener
	{
		[CCode (cname = "freerdp_listener_new")]
		public Listener ();

		public ListenerOpen Open;
		public ListenerGetEventHandles GetEventHandles;
		public ListenerCheckFileDescriptor CheckFileDescriptor;
		public ListenerClose Close;
		public PeerAccepted PeerAccepted;
	}

	[CCode (cname = "PIXEL_FORMAT_BGRA32", cheader_filename = "freerdp/codec/color.h")]
	public const uint32 PIXEL_FORMAT_BGRA32;

	[Compact]
	[CCode (cname = "rdpGdi", cheader_filename = "freerdp/gdi/gdi.h")]
	public class Gdi
	{
		public int width;
		public int height;
		public uint32 stride;
		public void *primary_buffer;
	}

	[CCode (has_target = false, cname = "pPostConnect")]
	public delegate bool PostConnect (Instance instance);

	[CCode (has_target = false, cname = "pAuthenticate")]
	public delegate bool Authenticate (
		Instance instance,
		[CCode (type = "char**")] out string username,
		[CCode (type = "char**")] out string password,
		[CCode (type = "char**")] out string domain);

	[CCode (has_target = false, cname = "pVerifyCertificateEx")]
	public delegate uint32 VerifyCertificateEx (
		Instance instance,
		string host,
		uint16 port,
		string common_name,
		string subject,
		string issuer,
		string fingerprint,
		uint32 flags);

	[Compact]
	[CCode (cname = "freerdp", free_function = "freerdp_free", cheader_filename = "freerdp/freerdp.h")]
	public class Instance
	{
		[CCode (cname = "freerdp_new")]
		public Instance ();

		public unowned Context context;
		public PostConnect PostConnect;
		public Authenticate Authenticate;
		public VerifyCertificateEx VerifyCertificateEx;

		[CCode (cname = "freerdp_context_new")]
		public bool context_new ();

		[CCode (cname = "freerdp_context_free")]
		public void context_free ();

		[CCode (cname = "freerdp_connect")]
		public bool connect ();

		[CCode (cname = "freerdp_disconnect")]
		public bool disconnect ();

		[CCode (cname = "freerdp_shall_disconnect")]
		public bool shall_disconnect ();
	}

	[CCode (cname = "freerdp_get_event_handles")]
	public uint32 get_event_handles (Context context, [CCode (array_length = false)] void*[] events, uint32 count);

	[CCode (cname = "freerdp_check_event_handles")]
	public bool check_event_handles (Context context);

	[CCode (cname = "freerdp_get_last_error")]
	public uint32 get_last_error (Context context);

	[CCode (cname = "freerdp_get_last_error_name")]
	public unowned string get_last_error_name (uint32 error);

	[CCode (cname = "gdi_init", cheader_filename = "freerdp/gdi/gdi.h")]
	public bool gdi_init (Instance instance, uint32 format);

	[CCode (cname = "gdi_free", cheader_filename = "freerdp/gdi/gdi.h")]
	public void gdi_free (Instance instance);
}

[CCode (cheader_filename = "winpr/thread.h", cprefix = "", lower_case_cprefix = "")]
namespace WinPr
{
	[CCode (has_target = false)]
	public delegate uint32 ThreadStart (void* parameter);

	[CCode (cname = "CreateThread")]
	public void* create_thread (void* attributes, size_t stack, ThreadStart start, void* parameter, uint32 flags, void* thread_id);

	[CCode (cname = "CloseHandle", cheader_filename = "winpr/handle.h")]
	public bool close_handle (void* handle);

	[CCode (cname = "WaitForMultipleObjects", cheader_filename = "winpr/synch.h")]
	public uint32 wait (uint32 count, [CCode (array_length = false)] void*[] handles, bool wait_all, uint32 milliseconds);

	[CCode (cname = "INFINITE", cheader_filename = "winpr/synch.h")]
	public const uint32 INFINITE;

	[CCode (cname = "WAIT_TIMEOUT", cheader_filename = "winpr/synch.h")]
	public const uint32 WAIT_TIMEOUT;

	[CCode (cname = "WAIT_FAILED", cheader_filename = "winpr/synch.h")]
	public const uint32 WAIT_FAILED;
}
