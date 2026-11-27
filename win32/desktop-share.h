/* Thin COM wrapper for Windows Desktop Sharing (IRDPSRAPISharingSession).
 * All session loop, file I/O, timeout, and process logic lives in Vala.
 */
#ifndef ARGUS_DESKTOP_SHARE_H
#define ARGUS_DESKTOP_SHARE_H

#include <stdint.h>

typedef void (*ArgusShareEventFn)(int dispid, void *user_data);

/* Open a sharing session on port with password and create one invitation.
 * Returns an opaque handle (close with argus_rdp_share_close) or NULL. */
void *argus_rdp_share_open(
	uint16_t port,
	const char *password,
	ArgusShareEventFn on_event,
	void *user_data);

/* Return the UTF-8 RACS2 ConnectionString owned by handle. */
const char *argus_rdp_share_invite(void *handle);

/* Close the sharing session and release COM resources. */
void argus_rdp_share_close(void *handle);

#endif
