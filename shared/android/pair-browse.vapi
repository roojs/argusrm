[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "pair-browse.h")]
namespace Argus.Shared.Android {

	[CCode (cheader_filename = "pair-browse.h")]
	public unowned string argus_android_phone_label ();

	[CCode (cheader_filename = "pair-browse.h")]
	public void argus_android_pair_browse_start ();

	[CCode (cheader_filename = "pair-browse.h")]
	public string argus_android_pair_browse_poll ();

	[CCode (cheader_filename = "pair-browse.h")]
	public void argus_android_pair_browse_stop ();
}
