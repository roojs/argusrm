/*
 * libxlsxwriter Vala bindings for Argus (write path).
 * Upstream: https://github.com/jmcnamara/libxlsxwriter — BSD-2-Clause.
 */

[CCode (cheader_filename = "xlsxwriter_shim.h")]
namespace Lxw
{
	[CCode (cname = "LXW_DEF_COL_WIDTH")]
	public const double DEFAULT_COLUMN_WIDTH;

	[CCode (cname = "lxw_error", cprefix = "LXW_", has_type_id = false)]
	public enum Error
	{
		NO_ERROR = 0,
		ERROR_MEMORY_MALLOC_FAILED,
		ERROR_CREATING_XLSX_FILE,
		ERROR_CREATING_TMPFILE,
		ERROR_READING_TMPFILE,
		ERROR_ZIP_FILE_OPERATION,
		ERROR_ZIP_PARAMETER_ERROR,
		ERROR_ZIP_BAD_ZIP_FILE,
		ERROR_ZIP_INTERNAL_ERROR,
		ERROR_ZIP_FILE_ADD,
		ERROR_ZIP_CLOSE,
		ERROR_FEATURE_NOT_SUPPORTED,
		ERROR_NULL_PARAMETER_IGNORED,
		ERROR_PARAMETER_VALIDATION,
		ERROR_PARAMETER_IS_EMPTY,
		ERROR_SHEETNAME_LENGTH_EXCEEDED,
		ERROR_INVALID_SHEETNAME_CHARACTER,
		ERROR_SHEETNAME_START_END_APOSTROPHE,
		ERROR_SHEETNAME_ALREADY_USED,
		ERROR_32_STRING_LENGTH_EXCEEDED,
		ERROR_128_STRING_LENGTH_EXCEEDED,
		ERROR_255_STRING_LENGTH_EXCEEDED,
		ERROR_MAX_STRING_LENGTH_EXCEEDED,
		ERROR_SHARED_STRING_INDEX_NOT_FOUND,
		ERROR_WORKSHEET_INDEX_OUT_OF_RANGE,
		ERROR_WORKSHEET_MAX_URL_LENGTH_EXCEEDED,
		ERROR_WORKSHEET_MAX_NUMBER_URLS_EXCEEDED,
		ERROR_IMAGE_DIMENSIONS,
		MAX_ERRNO,
	}

	[CCode (cname = "lxw_defined_colors", cprefix = "LXW_COLOR_", has_type_id = false)]
	public enum Color
	{
		BLACK = 0x1000000,
		BLUE = 0x0000ff,
		BROWN = 0x800000,
		CYAN = 0x00ffff,
		GRAY = 0x808080,
		GREEN = 0x008000,
		LIME = 0x00ff00,
		MAGENTA = 0xff00ff,
		NAVY = 0x000080,
		ORANGE = 0xff6600,
		PINK = 0xff00ff,
		PURPLE = 0x800080,
		RED = 0xff0000,
		SILVER = 0xc0c0c0,
		WHITE = 0xffffff,
		YELLOW = 0xffff00,
	}

	[CCode (cname = "lxw_format_patterns", cprefix = "LXW_PATTERN_", has_type_id = false)]
	public enum Pattern
	{
		NONE = 0,
		SOLID,
	}

	[CCode (cname = "lxw_format_alignments", cprefix = "LXW_ALIGN_", has_type_id = false)]
	public enum Alignment
	{
		NONE = 0,
		LEFT,
		CENTER,
		RIGHT,
		FILL,
		JUSTIFY,
		CENTER_ACROSS,
		DISTRIBUTED,
		VERTICAL_TOP,
		VERTICAL_BOTTOM,
		VERTICAL_CENTER,
		VERTICAL_JUSTIFY,
		VERTICAL_DISTRIBUTED,
	}

	[CCode (cname = "lxw_strerror")]
	public string strerror (Error code);

	[CCode (
		cname = "lxw_workbook",
		has_type_id = false,
		ref_function = false,
		unref_function = "lxw_workbook_unref"
	)]
	public class Workbook
	{
		[CCode (cname = "workbook_new", constructor = true)]
		public Workbook (string filename);

		[CCode (cname = "workbook_add_worksheet")]
		public unowned Worksheet add_worksheet (string? sheet_name = null);

		[CCode (cname = "workbook_add_format")]
		public unowned Format add_format ();

		/** Closes the file and frees the workbook; the wrapper must not be used after this. */
		[CCode (cname = "workbook_close")]
		public Error close ();
	}

	[CCode (
		cname = "lxw_worksheet",
		has_type_id = false,
		ref_function = false,
		unref_function = false
	)]
	public class Worksheet
	{
		[CCode (cname = "worksheet_write_string")]
		public Error write_string (
			uint row,
			uint16 col,
			string text,
			Format? format = null
		);

		[CCode (cname = "worksheet_write_number")]
		public Error write_number (
			uint row,
			uint16 col,
			double number,
			Format? format = null
		);

		[CCode (cname = "worksheet_write_blank")]
		public Error write_blank (uint row, uint16 col, Format? format = null);

		[CCode (cname = "worksheet_freeze_panes")]
		public void freeze_panes (uint row, uint16 col);

		[CCode (cname = "worksheet_set_column")]
		public Error set_column (
			uint16 first_col,
			uint16 last_col,
			double width,
			Format? format = null
		);
	}

	[CCode (
		cname = "lxw_format",
		has_type_id = false,
		ref_function = false,
		unref_function = false
	)]
	public class Format
	{
		[CCode (cname = "format_set_bold")]
		public void set_bold ();

		[CCode (cname = "format_set_italic")]
		public void set_italic ();

		[CCode (cname = "format_set_align")]
		public void set_align (Alignment alignment);

		[CCode (cname = "format_set_text_wrap")]
		public void set_text_wrap ();

		[CCode (cname = "format_set_font_color")]
		public void set_font_color (Color color);

		[CCode (cname = "format_set_bg_color")]
		public void set_bg_color (Color color);

		[CCode (cname = "format_set_fg_color")]
		public void set_fg_color (Color color);

		[CCode (cname = "format_set_pattern")]
		public void set_pattern (Pattern pattern);

		[CCode (cname = "format_set_num_format")]
		public void set_num_format (string num_format);
	}
}