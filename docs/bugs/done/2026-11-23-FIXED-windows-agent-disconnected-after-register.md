# Windows agent stays Disconnected after successful registration

**Status:** ✅

### User reported

- 🔷 After tray registration on **0.1.40**, machine stayed **Disconnected**; no controller tick.

### Success scenario

- Post-enroll TLS to app port; tray **Connected**; machine online in controller.

### Current behavior

- User confirmed **0.1.41** with `address_list()` host-only fix resolves connect (2026-11-23).

### Proposed fix

- ✔️ **`shared/SQT/Server.vala`** — `address_list_hosts.add(host)` not `add(text)`.

### Debugging

#### Current debug output

```text
13:41:40.574851: G_LOG_LEVEL_DEBUG : Service.vala:195: registration 0
13:41:40.591220: G_LOG_LEVEL_DEBUG : getaddrinfo failed to resolve host string 192.168.88.132:817
13:41:40.591220: G_LOG_LEVEL_WARNING : Connection.vala:211: address is invalid
```