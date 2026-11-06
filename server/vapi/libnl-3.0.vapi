[CCode (cheader_filename = "netlink/netlink.h", cprefix = "nl_", lower_case_cprefix = "nl_")]
namespace Nl
{
	[CCode (cname = "NETLINK_ROUTE", cheader_filename = "linux/netlink.h")]
	public const int NETLINK_ROUTE;

	[CCode (cname = "nl_geterror", cheader_filename = "netlink/errno.h")]
	public static unowned string strerror(int error);

	[Compact]
	[CCode (cname = "struct nl_sock", free_function = "nl_socket_free", cheader_filename = "netlink/socket.h")]
	public class Socket
	{
		[CCode (cname = "nl_socket_alloc")]
		public Socket();

		[CCode (cname = "nl_connect", cheader_filename = "netlink/netlink.h")]
		public int connect(int protocol);
	}

	[Compact]
	[CCode (cname = "struct nl_cache", free_function = "nl_cache_put", cheader_filename = "netlink/cache.h")]
	public class Cache
	{
	}

	[Compact]
	[CCode (cname = "struct nl_addr", cprefix = "nl_addr_", free_function = "nl_addr_put", cheader_filename = "netlink/addr.h")]
	public class Address
	{
		[CCode (cname = "nl_addr_build")]
		public Address(int family, uint8[] bytes);

		public int get_family();
		public uint get_len();

		[CCode (cname = "nl_addr_get_binary_addr")]
		public void* binary();
	}

	[Compact]
	[CCode (cname = "struct rtnl_addr", cprefix = "rtnl_addr_", cheader_filename = "netlink/route/addr.h")]
	public class Addr
	{
		[CCode (cname = "rtnl_addr_alloc_cache")]
		public static int read(Socket sock, out Cache? cache);

		[CCode (cname = "nl_cache_get_first", cheader_filename = "netlink/cache.h")]
		public static unowned Addr? first(Cache cache);

		[CCode (cname = "nl_cache_get_next", cheader_filename = "netlink/cache.h")]
		public unowned Addr? next();

		public unowned Address? get_local();
	}

	[Compact]
	[CCode (cname = "struct rtnl_route", cprefix = "rtnl_route_", cheader_filename = "netlink/route/route.h")]
	public class Route
	{
		[CCode (cname = "rtnl_route_lookup")]
		public static int lookup(Socket sock, Address destination, out unowned Route? route);

		[CCode (cname = "rtnl_route_put")]
		public void unref();

		public unowned Address? get_pref_src();
	}
}
