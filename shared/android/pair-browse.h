#pragma once

#include <glib.h>

G_BEGIN_DECLS

const char *argus_android_phone_label (void);
void argus_android_pair_browse_start (void);
char *argus_android_pair_browse_poll (void);
void argus_android_pair_browse_stop (void);

G_END_DECLS
