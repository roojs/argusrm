/* Windows DNS-SD browse. Names match windns.h and winerror.h. */

[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "windns-include.h")]
namespace Argus.Shared.Windows {

	[CCode (cheader_filename = "windns-include.h")]
	public const uint16 DNS_TYPE_PTR;
	[CCode (cheader_filename = "windns-include.h")]
	public const uint32 DNS_QUERY_REQUEST_VERSION1;
	[CCode (cheader_filename = "windns-include.h")]
	public const int DNS_REQUEST_PENDING;
	[CCode (cheader_filename = "windns-include.h")]
	public const uint32 ERROR_SUCCESS;
	[CCode (cheader_filename = "windns-include.h")]
	public const uint32 ERROR_CANCELLED;

	[CCode (cprefix = "", cheader_filename = "windns-include.h", has_type_id = false)]
	public enum DNS_FREE_TYPE {
		DnsFreeFlat,
		DnsFreeRecordList,
		DnsFreeParsedMessageFields
	}

	[CCode (cheader_filename = "windns-include.h", has_type_id = false, destroy_function = "")]
	public struct DNS_PTR_DATAW {
		public uint16* pNameHost;
	}

	[CCode (cheader_filename = "windns-include.h", has_type_id = false, destroy_function = "")]
	public struct DNS_RECORDW {
		public DNS_RECORDW* pNext;
		public uint16* pName;
		public uint16 wType;
		public uint16 wDataLength;
		public uint32 Flags;
		public uint32 dwTtl;
		public uint32 dwReserved;
		[CCode (cname = "Data.PTR")]
		public DNS_PTR_DATAW DataPTR;
	}

	[CCode (cheader_filename = "windns-include.h", has_target = false)]
	public delegate void DNS_SERVICE_BROWSE_CALLBACK (uint32 status, void* context, DNS_RECORDW* record);

	[CCode (cheader_filename = "windns-include.h", has_type_id = false, destroy_function = "")]
	public struct DNS_SERVICE_BROWSE_REQUEST {
		public uint32 Version;
		public uint32 InterfaceIndex;
		public uint16* QueryName;
		[CCode (delegate_target = false)]
		public unowned DNS_SERVICE_BROWSE_CALLBACK pBrowseCallback;
		public void* pQueryContext;
	}

	[CCode (cheader_filename = "windns-include.h", has_type_id = false, destroy_function = "")]
	public struct DNS_SERVICE_CANCEL {
		public void* reserved;
	}

	[CCode (cheader_filename = "windns-include.h", has_type_id = false, destroy_function = "")]
	public struct DNS_SERVICE_INSTANCE {
		public uint16* pszInstanceName;
		public uint16* pszHostName;
		public uint32* ip4Address;
		public void* ip6Address;
		public uint16 wPort;
		public uint16 wPriority;
		public uint16 wWeight;
		public uint32 dwPropertyCount;
		public uint16** keys;
		public uint16** values;
		public uint32 dwInterfaceIndex;
	}

	[CCode (cheader_filename = "windns-include.h", has_target = false)]
	public delegate void DNS_SERVICE_RESOLVE_COMPLETE (uint32 status, void* context, DNS_SERVICE_INSTANCE* instance);

	[CCode (cheader_filename = "windns-include.h", has_type_id = false, destroy_function = "")]
	public struct DNS_SERVICE_RESOLVE_REQUEST {
		public uint32 Version;
		public uint32 InterfaceIndex;
		public uint16* QueryName;
		[CCode (delegate_target = false)]
		public unowned DNS_SERVICE_RESOLVE_COMPLETE pResolveCompletionCallback;
		public void* pQueryContext;
	}

	[CCode (cheader_filename = "windns-include.h")]
	public int DnsServiceBrowse (ref DNS_SERVICE_BROWSE_REQUEST request, ref DNS_SERVICE_CANCEL cancel);

	[CCode (cheader_filename = "windns-include.h")]
	public int DnsServiceBrowseCancel (ref DNS_SERVICE_CANCEL cancel);

	[CCode (cheader_filename = "windns-include.h")]
	public int DnsServiceResolve (ref DNS_SERVICE_RESOLVE_REQUEST request, ref DNS_SERVICE_CANCEL cancel);

	[CCode (cheader_filename = "windns-include.h")]
	public void DnsServiceFreeInstance (DNS_SERVICE_INSTANCE* instance);

	[CCode (cheader_filename = "windns-include.h")]
	public void DnsFree (void* data, DNS_FREE_TYPE free_type);
}
