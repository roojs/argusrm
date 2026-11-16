#include "android-gio-tls.h"

#include <gio/gio.h>
#include <string.h>

/* Static glib-networking OpenSSL backend. */
extern void g_io_openssl_load (gpointer module);

gboolean
argus_controller_configure_android_gio_tls_modules (void)
{
	GTlsBackend *backend;
	const char *type_name;

	g_io_openssl_load (NULL);
	backend = g_tls_backend_get_default ();
	if (backend == NULL) {
		g_warning ("GIO TLS backend unavailable after g_io_openssl_load(NULL)");
		return FALSE;
	}
	type_name = G_OBJECT_TYPE_NAME (backend);
	if (type_name == NULL || strcmp (type_name, "GDummyTlsBackend") == 0) {
		g_warning ("GIO TLS backend is dummy after g_io_openssl_load(NULL)");
		return FALSE;
	}
	return TRUE;
}
