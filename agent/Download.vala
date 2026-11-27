/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Agent
{
	/**
	 * One file from the download socket.
	 *
	 * The address is the ''download'' file from registration,
	 * ''host:port''. {@link fetch} sends an HTTPS GET for the URL
	 * path, with the client certificate. The server allows or
	 * refuses that certificate. The body is written under the temp
	 * directory. {@link path} is that file. The app socket is not
	 * used.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var download = new Argus.Agent.Download();
	 * var code = download.fetch("/osquery/osquery.deb");
	 * }}}
	 */
	public class Download : GLib.Object
	{
		/**
		 * File written by the last successful {@link fetch}.
		 *
		 * Empty until then. The basename is the last segment of
		 * the URL path.
		 */
		public string path = "";

		/**
		 * Download ''url_path'' from the download socket.
		 *
		 * Sends a standard HTTPS GET with the client certificate.
		 * The server enforces access. A response other than 200
		 * is a failure. The saved basename is the last segment
		 * of ''url_path''. A stored file is replaced. The server
		 * certificate is accepted.
		 *
		 * @param url_path path from registration, such as
		 *   ''/osquery/osquery.deb''
		 * @return zero when the file is written, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int fetch(string url_path)
		{
			OLLMrpc.rpc_register();
#if LINUX
			var dir = Argus.AGENT_DATA_DIR;
#else
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
#endif
			var text = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "download"), out text);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			text = text.strip();
			var mark = text.last_index_of(":");
			if (text == "" || mark < 1) {
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var host = text.substring(0, mark);
			var port = int.parse(text.substring(mark + 1));
			if (port <= 0 || port > 65535) {
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var request_path = url_path.strip();
			if (request_path == "") {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			var file_name = GLib.Path.get_basename(request_path);
			if (file_name == "" || file_name == "." || file_name == "..") {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			if (!request_path.has_prefix("/")) {
				request_path = "/" + request_path;
			}
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
			var url = "https://" + host + ":" + port.to_string() + request_path;
			GLib.debug("start downloading %s", url);
			var dest = GLib.Path.build_filename(GLib.Environment.get_tmp_dir(), file_name);
			var written = (size_t) 0;
			GLib.SocketConnection conn;
			try {
				var client = new GLib.SocketClient();
				client.timeout = 15;
				conn = client.connect_to_host(host, (uint16) port, null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			conn.socket.timeout = 120;
			GLib.TlsClientConnection tls;
			try {
				tls = GLib.TlsClientConnection.@new(conn, null);
				tls.set_certificate(tls_files.certificate);
				tls.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				tls.handshake(null);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			GLib.debug("download connected");
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
		}
	}
}