[CCode (cprefix = "nft_", lower_case_cprefix = "nft_")]
namespace Nft
{
	[CCode (
		cheader_filename = "nftables/libnftables.h",
		cname = "struct nft_ctx",
		cprefix = "nft_ctx_",
		free_function = "nft_ctx_free"
	)]
	[Compact]
	public class Context
	{
		[CCode (cname = "nft_ctx_new")]
		public Context(uint32 flags = 0);

		public int buffer_output();
		public int unbuffer_output();
		public unowned string get_output_buffer();

		public int buffer_error();
		public int unbuffer_error();
		public unowned string get_error_buffer();

		[CCode (cname = "nft_run_cmd_from_buffer")]
		public int run_cmd_from_buffer(string buffer);
	}
}
