# Agent download fails on CRLF headers and server logs no download activity

**Status:** ✔️

### User decisions required

None.

### User reported

- 🔷 Agent download is still not working: the agent logs `Download.vala:106: start downloading https://192.168.254.88:818/osquery/osquery.deb` followed by `px_manager_get_proxies_sync: url=https://192.168.254.88:818 online=1` and `px_manager_get_proxies_sync: Proxy[0] = direct:` and nothing after.
- 🔷 There is no debug or log on the server indicating download start or anything.
- 🔷 Put the verification probe in `tests/` rather than `build/`.

### Success scenario

- `Argus.Agent.Download.fetch` completes an mTLS HTTPS GET against `Argus.Server.Net.Download` and writes the exact binary payload (byte-for-byte SHA-256 match).
- `Argus.Agent.Download.fetch` returns non-zero on missing files (HTTP 404) and untrusted client certificates (mTLS reject).
- `Argus.Server.Net.Download` emits `GLib.debug` lines on connection start, client certificate check, request method/path, error status, and 200 byte count.
- Linux agent startup runs `OSQuery.Initialize` off the main loop via `send_inventory()` so download and `dpkg -i` / `rpm -U` never block the main context.
- Automated Meson test `download` (`tests/download.vala`) exercises live `server/Net/Download.vala` and `agent/Download.vala` end-to-end and passes.

### Current behavior

- On the remote test machine
  - The agent log showed `px_manager_get_proxies_sync: url=https://192.168.254.88:818 online=1` right after `Download.vala:106`, then stalled with no further output.
  - The server produced no log lines for the download request.
- In local two-process reproduction
  - Calling `Soup.Session.send_and_read()` from a `GLib.Timeout` callback on the default main loop (the pre-`cf385c8` Linux code path) deadlocked indefinitely after proxy resolution (`timeout 6` killed with exit 124 despite `Session.timeout = 5`), even with the server in a separate process.
  - Running the post-`cf385c8` `agent/Download.vala` Gio implementation against `Soup.Server` received HTTP 200 with `Content-Length`, failed to recognize the `\r\n` header terminator, consumed the entire binary body as header lines until EOF, and exited with `short read` after writing 0 bytes.

### Codebase observed behavior

- [`agent/Download.vala`](../../agent/Download.vala) constructs `GLib.DataInputStream` with its default `newline_type` (`GLib.DataStreamNewlineType.LF`) and checks `if (line == null || line == "")`, so HTTP/1.1 `\r\n` lines retain trailing `"\r"` and the blank separator line is `"\r"` instead of `""`.
  ```vala
  var input = new GLib.DataInputStream(tls.get_input_stream());
  ...
  while (true) {
      var line = input.read_line(null);
      if (line == null || line == "") {
          break;
      }
  ```
- [`agent/Download.vala`](../../agent/Download.vala) uses `OutputStream.write(...)` instead of `write_all(...)` for both the HTTP request and body chunks.
- [`server/Net/Download.vala`](../../server/Net/Download.vala) has no `GLib.debug()` calls inside `request_started`, `accept_certificate`, or `add_handler`, so server debug logs show nothing when an agent connects or downloads.
- [`server/Net/Download.vala`](../../server/Net/Download.vala) builds `file_path` from `Argus.SERVER_DATA_DIR` directly instead of checking `Application.opt_data_dir` like [`server/Application.vala`](../../server/Application.vala).
- [`agent/Application.vala`](../../agent/Application.vala) runs `new OSQuery.Initialize(this).start()` synchronously on the main loop on Linux instead of calling `this.send_inventory()` on a worker thread as non-Linux builds do.

### Debugging

#### Current debug output

- User report from remote Linux agent (`10:25:40`–`10:25:44`)
  ```text
  10:25:40.982023: G_LOG_LEVEL_DEBUG : px_manager_get_proxies_sync: url=none://192.168.254.88:817 online=1
  10:25:40.982046: G_LOG_LEVEL_DEBUG : px_manager_get_proxies_sync: Proxy[0] = direct://
  10:25:41.024091: G_LOG_LEVEL_DEBUG : Connection.vala:382: watching the server connection
  10:25:44.964832: G_LOG_LEVEL_DEBUG : Initialize.vala:113: osquery package /osquery/osquery.deb
  10:25:44.965631: G_LOG_LEVEL_DEBUG : Download.vala:106: start downloading https://192.168.254.88:818/osquery/osquery.deb
  10:25:44.966276: G_LOG_LEVEL_DEBUG : px_manager_get_proxies_sync: url=https://192.168.254.88:818 online=1
  10:25:44.966346: G_LOG_LEVEL_DEBUG : px_manager_get_proxies_sync: Proxy[0] = direct:
  ```
  - `url=https://192.168.254.88:818` proves the remote machine was running the pre-`cf385c8` `Soup.Session` build (`3cdc85e`, also version `0.1.64`); `GLib.SocketClient.connect_to_host` queries `none://host:port` (as seen on port 817).

- Local two-process probe (`2026-11-27`, `Soup.Server` in process A vs clients in process B)
  ```text
  === TEST 1: client-soup-main ===
  [client-soup-main] start downloading https://127.0.0.1:18818/osquery/test.bin
  [SERVER] request_started
  exit=124
  === TEST 2: client-gio-bug ===
  [client-gio-bug] status_line='HTTP/1.1 200 OK\r' (len=16)
  [client-gio-bug] header[3]='Content-Length: 131072\r'
  [client-gio-bug] header[4]='\r'
  [client-gio-bug] header[5]='\001\002\003\004\005\006\007\b\t'
  ...
  [client-gio-bug] end of headers after 528 headers (line=null)
  [client-gio-bug] status=200 content_length=131072
  [client-gio-bug] short read at written=0 remaining=131072
  === TEST 3: client-gio-fix ===
  [client-gio-fix] status_line='HTTP/1.1 200 OK' (len=15)
  [client-gio-fix] header[3]='Content-Length: 131072'
  [client-gio-fix] end of headers after 3 headers (line=empty)
  [client-gio-fix] status=200 content_length=131072
  [client-gio-fix] SUCCESS fetched 131072 bytes
  ```
  - Proves both defects: main-loop `Soup.Session` deadlocks after proxy resolution, and `cf385c8` `DataInputStream` without `CR_LF` eats the body as headers and fails with `short read`.

#### Debug code added (remove when complete)

None (the permanent `GLib.debug` lines added to `server/Net/Download.vala` are part of the fix).

### Proposed fix

### ✔️ Phase 1 — Fix CRLF header parsing and writes in `agent/Download.vala`

#### Remove (`agent/Download.vala` lines 132–221)

```vala
			var request = @"GET $(request_path) HTTP/1.1\r\nHost: $(host):$(port)\r\nConnection: close\r\n\r\n";
			try {
				tls.get_output_stream().write(request.data);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var input = new GLib.DataInputStream(tls.get_input_stream());
			var status = (uint) 0;
			int64 content_length = -1;
			try {
				var status_line = input.read_line(null);
				if (status_line == null || status_line == "") {
					GLib.warning("empty HTTP response");
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				var parts = status_line.split(" ");
				if (parts.length < 2) {
					GLib.warning("%s", status_line);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				status = uint.parse(parts[1]);
				while (true) {
					var line = input.read_line(null);
					if (line == null || line == "") {
						break;
					}
					if (line.casefold().has_prefix("content-length:")) {
						content_length = int64.parse(line.substring(15).strip());
					}
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.debug("download %u", status);
			if (status != 200) {
				GLib.warning("download %u", status);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (content_length < 1) {
				GLib.warning("missing Content-Length");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.debug("download body %s", content_length.to_string());
			GLib.FileOutputStream output;
			try {
				output = GLib.File.new_for_path(dest).replace(
					null, false, GLib.FileCreateFlags.PRIVATE);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var remaining = content_length;
			var chunk = new uint8[1048576];
			var next_mark = (size_t) 4194304;
			while (remaining > 0) {
				var want = (int) int64.min(remaining, (int64) chunk.length);
				ssize_t n;
				try {
					n = input.read(chunk[0:want]);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (n <= 0) {
					GLib.warning("short read");
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					output.write(chunk[0:n]);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				written += (size_t) n;
				remaining -= n;
				if (written >= next_mark || remaining == 0) {
					GLib.debug("download %zu %s", written, content_length.to_string());
					while (next_mark <= written) {
						next_mark += 4194304;
					}
				}
			}
			if (written == 0) {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			this.path = dest;
			GLib.debug("fetched %s %zu", dest, written);
			return 0;
```

#### Replace with (`agent/Download.vala`)

```vala
			var request = @"GET $(request_path) HTTP/1.1\r\nHost: $(host):$(port)\r\nConnection: close\r\n\r\n";
			try {
				size_t sent;
				tls.get_output_stream().write_all(request.data, out sent);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var input = new GLib.DataInputStream(tls.get_input_stream());
			input.newline_type = GLib.DataStreamNewlineType.CR_LF;
			uint status = 0;
			int64 content_length = -1;
			try {
				var status_line = input.read_line(null);
				if (status_line == null || status_line == "") {
					GLib.warning("empty HTTP response");
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				var parts = status_line.split(" ");
				if (parts.length < 2) {
					GLib.warning("%s", status_line);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				status = uint.parse(parts[1]);
				while (true) {
					var line = input.read_line(null);
					if (line == null || line == "") {
						break;
					}
					if (line.casefold().has_prefix("content-length:")) {
						content_length = int64.parse(line.substring(15).strip());
					}
				}
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.debug("download %u", status);
			if (status != 200) {
				GLib.warning("download %u", status);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (content_length < 1) {
				GLib.warning("missing Content-Length");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.debug("download body %s", content_length.to_string());
			GLib.FileOutputStream output;
			try {
				output = GLib.File.new_for_path(dest).replace(
					null, false, GLib.FileCreateFlags.PRIVATE);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var remaining = content_length;
			var chunk = new uint8[1048576];
			var next_mark = (size_t) 4194304;
			while (remaining > 0) {
				var want = (int) int64.min(remaining, (int64) chunk.length);
				ssize_t n;
				try {
					n = input.read(chunk[0:want]);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (n <= 0) {
					GLib.warning("short read");
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					size_t wrote;
					output.write_all(chunk[0:n], out wrote);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				written += (size_t) n;
				remaining -= n;
				if (written >= next_mark || remaining == 0) {
					GLib.debug("download %zu %s", written, content_length.to_string());
					while (next_mark <= written) {
						next_mark += 4194304;
					}
				}
			}
			try {
				output.close();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (written == 0) {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			this.path = dest;
			GLib.debug("fetched %s %zu", dest, written);
			return 0;
```

### ✔️ Phase 2 — Add server download debug logging and honor `opt_data_dir` in `server/Net/Download.vala`

#### Remove (`server/Net/Download.vala` lines 89–140)

```vala
			this.soup.request_started.connect((server, msg) => {
				msg.accept_certificate.connect((peer_cert, errors) => {
					if (peer_cert == null) {
						return false;
					}
					return (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
				});
			});
			this.soup.add_handler(null, (server, msg, path, query) => {
				if (msg.get_method() != "GET") {
					msg.set_status(405, null);
					return;
				}
				var peer = msg.get_tls_peer_certificate();
				var errors = msg.get_tls_peer_certificate_errors();
				if (peer == null || (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) != 0) {
					msg.set_status(403, null);
					return;
				}
				if (!path.has_prefix("/") || path.contains("..") || path.has_suffix("/")) {
					msg.set_status(404, null);
					return;
				}
				var relative = path.substring(1);
				if (relative == "") {
					msg.set_status(404, null);
					return;
				}
				var file_path = GLib.Path.build_filename(
					Argus.SERVER_DATA_DIR, "packages", relative);
				if (!GLib.FileUtils.test(file_path, GLib.FileTest.EXISTS)) {
					msg.set_status(404, null);
					return;
				}
				var file = GLib.File.new_for_path(file_path);
				msg.pause();
				file.load_contents_async.begin(null, (obj, res) => {
					var contents = new uint8[0];
					var etag = "";
					try {
						file.load_contents_async.end(res, out contents, out etag);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						msg.set_status(404, null);
						msg.unpause();
						return;
					}
					msg.set_status(200, null);
					msg.set_response("application/octet-stream", Soup.MemoryUse.COPY, contents);
					msg.unpause();
				});
			});
```

#### Replace with (`server/Net/Download.vala`)

```vala
			this.soup.request_started.connect((server, msg) => {
				var remote = msg.get_remote_host();
				GLib.debug("download request started from %s", remote != null ? remote : "");
				msg.accept_certificate.connect((peer_cert, errors) => {
					var accepted = peer_cert != null &&
						(errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) == 0;
					GLib.debug("download client cert %s errors %u accepted %s",
						peer_cert != null ? "present" : "missing", (uint) errors, accepted.to_string());
					return accepted;
				});
			});
			this.soup.add_handler(null, (server, msg, path, query) => {
				var remote = msg.get_remote_host();
				GLib.debug("download %s %s from %s",
					msg.get_method(), path, remote != null ? remote : "");
				if (msg.get_method() != "GET") {
					GLib.debug("download %s 405", path);
					msg.set_status(405, null);
					return;
				}
				var peer = msg.get_tls_peer_certificate();
				var errors = msg.get_tls_peer_certificate_errors();
				if (peer == null || (errors & ~GLib.TlsCertificateFlags.BAD_IDENTITY) != 0) {
					GLib.debug("download %s 403 errors %u", path, (uint) errors);
					msg.set_status(403, null);
					return;
				}
				if (!path.has_prefix("/") || path.contains("..") || path.has_suffix("/")) {
					GLib.debug("download %s 404 invalid path", path);
					msg.set_status(404, null);
					return;
				}
				var relative = path.substring(1);
				if (relative == "") {
					GLib.debug("download %s 404 empty path", path);
					msg.set_status(404, null);
					return;
				}
				var data_dir = Application.opt_data_dir != "" ?
					Application.opt_data_dir : Argus.SERVER_DATA_DIR;
				var file_path = GLib.Path.build_filename(data_dir, "packages", relative);
				if (!GLib.FileUtils.test(file_path, GLib.FileTest.EXISTS)) {
					GLib.debug("download %s 404 missing %s", path, file_path);
					msg.set_status(404, null);
					return;
				}
				var file = GLib.File.new_for_path(file_path);
				msg.pause();
				file.load_contents_async.begin(null, (obj, res) => {
					var contents = new uint8[0];
					var etag = "";
					try {
						file.load_contents_async.end(res, out contents, out etag);
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
						msg.set_status(404, null);
						msg.unpause();
						return;
					}
					GLib.debug("download %s 200 %d bytes", path, contents.length);
					msg.set_status(200, null);
					msg.set_response("application/octet-stream", Soup.MemoryUse.COPY, contents);
					msg.unpause();
				});
			});
```

### ✔️ Phase 3 — Run Linux `OSQuery.Initialize` off the main loop in `agent/Application.vala`

#### Remove (`agent/Application.vala` lines 306–309)

```vala
			new GLib.Thread<int>("osquery-init", () => {
				var code = new OSQuery.Initialize(this).run();
				GLib.Idle.add(() => {
```

#### Replace with (`agent/Application.vala`)

```vala
			new GLib.Thread<int>("osquery-init", () => {
				var code = new OSQuery.Initialize(this).run();
				GLib.debug("osquery %d", code);
				GLib.Idle.add(() => {
```

#### Remove (`agent/Application.vala` lines 573–596)

```vala
				if (this.connection != null && !Application.connection_down) {
					new OSQuery.Initialize(this).start();
					this.osquery.send_startup();
					this.monitor = new PackageMonitor(this);
					this.monitor.start();
					this.user_monitor = new UserMonitor(this);
					this.user_monitor.start();
				}
				if (this.connection == null || Application.connection_down) {
					GLib.debug("waiting for connection");
					GLib.Timeout.add_seconds(5, () => {
						if (this.connection == null || Application.connection_down) {
							GLib.debug("waiting for connection");
							return true;
						}
						new OSQuery.Initialize(this).start();
						this.osquery.send_startup();
						this.monitor = new PackageMonitor(this);
						this.monitor.start();
						this.user_monitor = new UserMonitor(this);
						this.user_monitor.start();
						return false;
					});
				}
```

#### Replace with (`agent/Application.vala`)

```vala
				if (this.connection != null && !Application.connection_down) {
					this.send_inventory();
				}
				if (this.connection == null || Application.connection_down) {
					GLib.debug("waiting for connection");
					GLib.Timeout.add_seconds(5, () => {
						if (this.connection == null || Application.connection_down) {
							GLib.debug("waiting for connection");
							return true;
						}
						this.send_inventory();
						return false;
					});
				}
```

### ✔️ Phase 4 — Add end-to-end download test in `tests/download.vala` and `tests/meson.build`

#### Add (`tests/download.vala` and `tests/meson.build`)

- `tests/download.vala`: boots live `Argus.Server.Net.Download` with a minimal `Argus.Server.Application` stub and generated CA/server/client certs via `OLLMrpc.Transport.Cert`, then runs live `Argus.Agent.Download.fetch` on a worker thread for:
  - 512 KiB binary payload containing `\0`, `\r`, `\n`, `\r\n`, and all byte values (verifies return 0, size, and SHA-256)
  - missing path `/osquery/missing.deb` (verifies non-zero return)
  - untrusted client certificate signed by a separate CA (verifies non-zero return)
- `tests/meson.build`: adds `argus-download` executable and `test('download', download_test, timeout: 15)` under Linux.

### LLM

- ℹ️ Related commits
  - `3cdc85e` (`08:16:20`) bumped `meson.build` to `0.1.64` with `Soup.Session`.
  - `cf385c8` (`09:50:55`, tagged `v0.1.64`) replaced `Soup.Session` with Gio `SocketClient` + `TlsClientConnection` + `DataInputStream`, leaving `meson.build` at `0.1.64`.
- ℹ️ Deployment note for the remote test machine
  - Because the remote log printed `px_manager_get_proxies_sync: url=https://192.168.254.88:818`, the installed agent on that host was still the `Soup.Session` build (`3cdc85e`), likely because `0.1.64` was not bumped again when `cf385c8` landed or the newer build was not installed there yet.
  - Upgrading the remote machine to a build including Phases 1–3 fixes both the `Soup.Session` main-loop deadlock and the `cf385c8` CRLF header bug, and adds server-side download debug logs.
- ℹ️ Source files
  - [`agent/Download.vala`](../../agent/Download.vala)
  - [`server/Net/Download.vala`](../../server/Net/Download.vala)
  - [`agent/Application.vala`](../../agent/Application.vala)
  - [`tests/download.vala`](../../tests/download.vala)
  - [`tests/meson.build`](../../tests/meson.build)
- ✔️ Verification
  - `ninja -C build tests/argus-download agent/argusrm-agent agent/argusrm-agent-gtk` succeeded.
  - Clean build verified `server/argusrm-server` links cleanly.
  - `meson test -C build download --print-errorlogs` passed (`1/1 download OK 0.22s`), confirming 512 KiB binary SHA-256 match, HTTP 404 failure, untrusted client mTLS rejection, and server `GLib.debug` output.
