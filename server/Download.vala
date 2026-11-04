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

namespace Argus.Server
{
	/**
	 * HTTPS GET listener for the download socket.
	 *
	 * Binds {@link Application.download}. A download is a standard
	 * HTTP GET over TLS. The client certificate is required. This
	 * socket is not the app socket, so a transfer does not clog
	 * RPC. Not {@link Argus.Agent.Download.fetch}, and not
	 * ''Download.get''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var files = new Argus.Server.Download(app);
	 * if (files.listen()) {
	 *     // bound
	 * }
	 * }}}
	 */
	public class Download : GLib.Object
	{
		public Application app { get; private set; }

		private Soup.Server soup {
			get; set; default = new Soup.Server("server-header", null);
		}
		private bool listening = false;

		public Download(Application app)
		{
			this.app = app;
		}

		/**
		 * Bind the HTTPS socket from {@link Application.download}.
		 *
		 * Returns false when the address is empty or the port is
		 * outside 1–65535. Bind failure logs a warning and returns
		 * false. Only a GET is answered. The path is a file under
		 * ''packages'' under {@link Argus.SERVER_DATA_DIR}. The body
		 * is read off the main loop, then Soup writes it.
		 *
		 * @return true when the download socket is up
		 */
		public bool listen()
		{
			if (this.listening) {
				return true;
			}
			var socket = this.app.download;
			var colon = socket.last_index_of(":");
			var host = "";
			var port = 0;
			if (colon > 0) {
				host = socket.substring(0, colon);
				int.try_parse(socket.substring(colon + 1), out port);
			}
			if (socket == "" || colon <= 0 || host == "" || port < 1 || port > 65535) {
				return false;
			}
			var parsed = new GLib.InetSocketAddress.from_string(host, (uint16) port);
			if (parsed == null) {
				return false;
			}
			this.soup = new Soup.Server("server-header", null);
			this.soup.set_tls_certificate(this.app.tls.certificate);
			if (this.app.tls.trust != null) {
				this.soup.set_tls_database(this.app.tls.trust);
			}
			this.soup.set_tls_auth_mode(GLib.TlsAuthenticationMode.REQUIRED);
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
			try {
				this.soup.listen(parsed, Soup.ServerListenOptions.HTTPS);
			} catch (GLib.Error e) {
				GLib.warning("failed to bind download listener %s:%u: %s",
					host, (uint) port, e.message);
				return false;
			}
			this.listening = true;
			GLib.debug("download listening on %s:%u", host, (uint) port);
			return true;
		}

		/**
		 * Unbind the download socket.
		 *
		 * No-op when {@link listen} did not bind.
		 */
		public void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.soup.disconnect();
			this.soup = new Soup.Server("server-header", null);
		}
	}
}
