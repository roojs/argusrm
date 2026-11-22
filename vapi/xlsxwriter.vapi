/*
 * libxlsxwriter Vala bindings for Argus (write path).
 * Upstream: https://github.com/jmcnamara/libxlsxwriter — BSD-2-Clause.
 *
 * OOP surface: new Lxw.Workbook (), sheet.write_string (), format.set_bold (), …
 *
 * Worksheet and Format come from the workbook; hold them as unowned Lxw.Worksheet /
 * unowned Lxw.Format — do not use var or owned references (libxlsxwriter is not
 * refcounted).
 */

[CCode (cheader_filename = "xlsxwriter_shim.h")]
namespace Lxw
{
	/* --- Constants --- */

	[CCode (cname = "LXW_DEF_COL_WIDTH")]
	public const double DEFAULT_COLUMN_WIDTH;

	[CCode (cname = "LXW_DEF_ROW_HEIGHT")]
	public const double DEFAULT_ROW_HEIGHT;

	[CCode (cname = "LXW_ROW_MAX")]
	public const uint ROW_MAX;

	[CCode (cname = "LXW_COL_MAX")]
	public const uint16 COL_MAX;

	[CCode (cname = "LXW_VERSION")]
	public const string LIBRARY_VERSION;

	[CCode (cname = "LXW_VERSION_ID")]
	public const uint16 LIBRARY_VERSION_ID;

	/* --- Enums --- */

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

	[CCode (cname = "lxw_boolean", cprefix = "LXW_", has_type_id = false)]
	public enum Boolean
	{
		FALSE,
		TRUE,
		EXPLICIT_FALSE,
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
		MEDIUM_GRAY,
		DARK_GRAY,
		LIGHT_GRAY,
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

	[CCode (cname = "lxw_format_underlines", cprefix = "LXW_UNDERLINE_", has_type_id = false)]
	public enum Underline
	{
		NONE = 0,
		SINGLE,
		DOUBLE,
		SINGLE_ACCOUNTING,
		DOUBLE_ACCOUNTING,
	}

	[CCode (cname = "lxw_format_borders", cprefix = "LXW_BORDER_", has_type_id = false)]
	public enum Border
	{
		NONE,
		THIN,
		MEDIUM,
		DASHED,
		DOTTED,
		THICK,
		DOUBLE,
		HAIR,
		MEDIUM_DASHED,
		DASH_DOT,
		MEDIUM_DASH_DOT,
		DASH_DOT_DOT,
		MEDIUM_DASH_DOT_DOT,
		SLANT_DASH_DOT,
	}

	[CCode (cname = "lxw_format_scripts", cprefix = "LXW_FONT_", has_type_id = false)]
	public enum FontScript
	{
		SUPERSCRIPT = 1,
		SUBSCRIPT,
	}

	/* --- Structs --- */

	[CCode (cname = "lxw_datetime", has_type_id = false)]
	public struct DateTime
	{
		public int year;
		public int month;
		public int day;
		public int hour;
		public int min;
		public double sec;
	}

	[CCode (cname = "lxw_workbook_options", has_type_id = false)]
	public struct WorkbookOptions
	{
		public uint8 constant_memory;
		public string? tmpdir;
		public uint8 use_zip64;
		[CCode (type = "const char**")]
		public void* output_buffer;
		[CCode (type = "size_t*")]
		public void* output_buffer_size;
	}

	[CCode (cname = "lxw_doc_properties", has_type_id = false)]
	public struct DocumentProperties
	{
		public string? title;
		public string? subject;
		public string? author;
		public string? manager;
		public string? company;
		public string? category;
		public string? keywords;
		public string? comments;
		public string? status;
		public string? hyperlink_base;
		public time_t created;
	}

	[CCode (cname = "lxw_protection", has_type_id = false)]
	public struct Protection
	{
		public uint8 no_select_locked_cells;
		public uint8 no_select_unlocked_cells;
		public uint8 format_cells;
		public uint8 format_columns;
		public uint8 format_rows;
		public uint8 insert_columns;
		public uint8 insert_rows;
		public uint8 insert_hyperlinks;
		public uint8 delete_columns;
		public uint8 delete_rows;
		public uint8 sort;
		public uint8 autofilter;
		public uint8 pivot_tables;
		public uint8 scenarios;
		public uint8 objects;
	}

	/* --- Library helpers --- */

	[CCode (cname = "lxw_strerror")]
	public unowned string strerror (Error code);

	[CCode (cname = "lxw_version")]
	public unowned string version ();

	[CCode (cname = "lxw_version_id")]
	public uint16 version_id ();

	[CCode (cname = "lxw_datetime_to_excel_datetime")]
	public double datetime_to_excel (DateTime datetime);

	[CCode (cname = "lxw_name_to_row")]
	public uint name_to_row (string row_ref);

	[CCode (cname = "lxw_name_to_col")]
	public uint16 name_to_col (string col_ref);

	[CCode (cname = "lxw_rowcol_to_cell")]
	public void rowcol_to_cell ([CCode (array_length = false)] uint8[] buffer, uint row, uint16 col);

	[CCode (cname = "lxw_rowcol_to_range")]
	public void rowcol_to_range (
		[CCode (array_length = false)] uint8[] buffer,
		uint first_row,
		uint16 first_col,
		uint last_row,
		uint16 last_col
	);

	[CCode (cname = "lxw_quote_sheetname")]
	public string quote_sheetname (string name);

	/* --- Workbook --- */

	[CCode (
		cname = "lxw_workbook",
		has_type_id = false,
		ref_function = false,
		unref_function = "lxw_workbook_unref",
		dup_function = false
	)]
	public class Workbook
	{
		[CCode (cname = "workbook_new", constructor = true)]
		public Workbook (string filename);

		[CCode (cname = "workbook_new_opt")]
		public static Workbook create_with_options (string? filename, WorkbookOptions options);

		[CCode (cname = "workbook_add_worksheet")]
		public unowned Worksheet add_worksheet (string? sheet_name = null);

		[CCode (cname = "workbook_add_format")]
		public unowned Format add_format ();

		[CCode (cname = "workbook_get_worksheet_by_name")]
		public unowned Worksheet? get_worksheet_by_name (string sheet_name);

		[CCode (cname = "workbook_get_default_url_format")]
		public unowned Format get_default_url_format ();

		[CCode (cname = "workbook_validate_sheet_name")]
		public Error validate_sheet_name (string sheet_name);

		[CCode (cname = "workbook_set_properties")]
		public Error set_properties (DocumentProperties properties);

		[CCode (cname = "workbook_define_name")]
		public Error define_name (string name, string formula);

		[CCode (cname = "workbook_set_custom_property_string")]
		public Error set_custom_property_string (string name, string value);

		[CCode (cname = "workbook_set_custom_property_number")]
		public Error set_custom_property_number (string name, double value);

		[CCode (cname = "workbook_set_custom_property_boolean")]
		public Error set_custom_property_boolean (string name, uint8 value);

		[CCode (cname = "workbook_read_only_recommended")]
		public void set_read_only_recommended ();

		/** Closes the file and frees the workbook; do not use the instance after this. */
		[CCode (cname = "workbook_close")]
		public Error close ();
	}

	/* --- Worksheet --- */

	[CCode (
		cname = "lxw_worksheet",
		has_type_id = false,
		ref_function = false,
		unref_function = false,
		dup_function = false
	)]
	public class Worksheet
	{
		[CCode (cname = "worksheet_write_string")]
		public Error write_string (uint row, uint16 col, string text, Format? format = null);

		[CCode (cname = "worksheet_write_number")]
		public Error write_number (uint row, uint16 col, double number, Format? format = null);

		[CCode (cname = "worksheet_write_boolean")]
		public Error write_boolean (uint row, uint16 col, int value, Format? format = null);

		[CCode (cname = "worksheet_write_blank")]
		public Error write_blank (uint row, uint16 col, Format? format = null);

		[CCode (cname = "worksheet_write_datetime")]
		public Error write_datetime (uint row, uint16 col, DateTime datetime, Format? format = null);

		[CCode (cname = "worksheet_write_unixtime")]
		public Error write_unixtime (uint row, uint16 col, int64 unix_time, Format? format = null);

		[CCode (cname = "worksheet_write_formula")]
		public Error write_formula (uint row, uint16 col, string formula, Format? format = null);

		[CCode (cname = "worksheet_write_url")]
		public Error write_url (uint row, uint16 col, string url, Format? format = null);

		[CCode (cname = "worksheet_merge_range")]
		public Error merge_range (
			uint first_row,
			uint16 first_col,
			uint last_row,
			uint16 last_col,
			string text,
			Format? format = null
		);

		[CCode (cname = "worksheet_autofilter")]
		public Error set_autofilter (
			uint first_row,
			uint16 first_col,
			uint last_row,
			uint16 last_col
		);

		[CCode (cname = "worksheet_freeze_panes")]
		public void freeze_panes (uint row, uint16 col);

		[CCode (cname = "worksheet_split_panes")]
		public void split_panes (double y_split, double x_split);

		[CCode (cname = "worksheet_set_column")]
		public Error set_column (
			uint16 first_col,
			uint16 last_col,
			double width,
			Format? format = null
		);

		[CCode (cname = "worksheet_set_column_pixels")]
		public Error set_column_pixels (
			uint16 first_col,
			uint16 last_col,
			uint32 width_pixels,
			Format? format = null
		);

		[CCode (cname = "worksheet_set_row")]
		public Error set_row (uint row, double height, Format? format = null);

		[CCode (cname = "worksheet_set_default_row")]
		public void set_default_row (double height, uint8 hide_unused_rows);

		[CCode (cname = "worksheet_set_landscape")]
		public void set_landscape ();

		[CCode (cname = "worksheet_set_portrait")]
		public void set_portrait ();

		[CCode (cname = "worksheet_set_zoom")]
		public void set_zoom (uint16 scale);

		[CCode (cname = "worksheet_set_tab_color")]
		public void set_tab_color (Color color);

		[CCode (cname = "worksheet_set_first_sheet")]
		public void set_first_sheet ();

		[CCode (cname = "worksheet_protect")]
		public void protect (string? password, Protection? options);
	}

	/* --- Format --- */

	[CCode (
		cname = "lxw_format",
		has_type_id = false,
		ref_function = false,
		unref_function = false,
		dup_function = false
	)]
	public class Format
	{
		[CCode (cname = "format_set_font_name")]
		public void set_font_name (string font_name);

		[CCode (cname = "format_set_font_size")]
		public void set_font_size (double size);

		[CCode (cname = "format_set_bold")]
		public void set_bold ();

		[CCode (cname = "format_set_italic")]
		public void set_italic ();

		[CCode (cname = "format_set_underline")]
		public void set_underline (Underline style);

		[CCode (cname = "format_set_font_strikeout")]
		public void set_font_strikeout ();

		[CCode (cname = "format_set_font_script")]
		public void set_font_script (FontScript style);

		[CCode (cname = "format_set_align")]
		public void set_align (Alignment alignment);

		[CCode (cname = "format_set_text_wrap")]
		public void set_text_wrap ();

		[CCode (cname = "format_set_rotation")]
		public void set_rotation (int16 angle);

		[CCode (cname = "format_set_indent")]
		public void set_indent (uint8 level);

		[CCode (cname = "format_set_shrink")]
		public void set_shrink ();

		[CCode (cname = "format_set_num_format")]
		public void set_num_format (string num_format);

		[CCode (cname = "format_set_num_format_index")]
		public void set_num_format_index (uint8 index);

		[CCode (cname = "format_set_font_color")]
		public void set_font_color (Color color);

		[CCode (cname = "format_set_bg_color")]
		public void set_bg_color (Color color);

		[CCode (cname = "format_set_fg_color")]
		public void set_fg_color (Color color);

		[CCode (cname = "format_set_pattern")]
		public void set_pattern (Pattern pattern);

		[CCode (cname = "format_set_border")]
		public void set_border (Border style);

		[CCode (cname = "format_set_top")]
		public void set_top (Border style);

		[CCode (cname = "format_set_bottom")]
		public void set_bottom (Border style);

		[CCode (cname = "format_set_left")]
		public void set_left (Border style);

		[CCode (cname = "format_set_right")]
		public void set_right (Border style);

		[CCode (cname = "format_set_border_color")]
		public void set_border_color (Color color);

		[CCode (cname = "format_set_top_color")]
		public void set_top_color (Color color);

		[CCode (cname = "format_set_bottom_color")]
		public void set_bottom_color (Color color);

		[CCode (cname = "format_set_left_color")]
		public void set_left_color (Color color);

		[CCode (cname = "format_set_right_color")]
		public void set_right_color (Color color);

		[CCode (cname = "format_set_unlocked")]
		public void set_unlocked ();

		[CCode (cname = "format_set_hidden")]
		public void set_hidden ();

		[CCode (cname = "format_set_quote_prefix")]
		public void set_quote_prefix ();

		[CCode (cname = "format_set_hyperlink")]
		public void set_hyperlink ();

		/** 24-bit RGB (0xRRGGBB), including values outside #Color. */
		[CCode (cname = "format_set_font_color")]
		public void set_font_color_rgb (uint32 rgb);

		[CCode (cname = "format_set_bg_color")]
		public void set_bg_color_rgb (uint32 rgb);
	}
}