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
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_data_dir(), "argus");
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
			GLib.debug("fetching %s", request_path);
			var blob = new GLib.Bytes(new uint8[0]);
			var status = (uint) 0;
			try {
				var session = new Soup.Session();
				var message = new Soup.Message("GET", url);
				message.set_tls_client_certificate(tls_files.certificate);
				message.request_certificate.connect((tls_connection) => {
					tls_connection.set_certificate(tls_files.certificate);
					return true;
				});
				message.accept_certificate.connect((peer_cert, errors) => {
					return true;
				});
				blob = session.send_and_read(message, null);
				status = message.status_code;
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (status != 200) {
				GLib.warning("download %u", status);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (blob.get_size() == 0) {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			var dest = GLib.Path.build_filename(GLib.Environment.get_tmp_dir(), file_name);
			try {
				GLib.FileUtils.set_data(dest, blob.get_data());
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			this.path = dest;
			return 0;
		}
	}
}
