/*
 * Vala scope cleanup for Lxw.Workbook — libxlsxwriter has no refcount.
 * Always call Workbook.close() (workbook_close) to write and free; this stub
 * satisfies Vala's end-of-scope unref only.
 */

#include <xlsxwriter.h>

void
lxw_workbook_unref (lxw_workbook *workbook)
{
	(void) workbook;
}