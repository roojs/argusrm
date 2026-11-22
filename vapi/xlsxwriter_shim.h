/*
 * Declarations for Vala bindings not provided by upstream libxlsxwriter.
 */

#ifndef ARGUS_XLSXWRITER_SHIM_H
#define ARGUS_XLSXWRITER_SHIM_H

#include <xlsxwriter.h>

void lxw_workbook_unref (lxw_workbook *workbook);

#endif