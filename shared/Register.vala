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

namespace Argus.Shared
{
	/**
	 * Certificate registration with Argus.
	 *
	 * Adapts the registration half of ''FilesdClient.try_connection'':
	 * a TLS connection, ''ClientCert.request_registration'', then
	 * {@link OLLMrpc.Transport.Cert} files under the user data
	 * directory ''argus''. The call includes the OS family so the
	 * server can choose the download. The reply string array is
	 * the client certificate, the CA, the download socket, the
	 * download URL path, then listen addresses. The app socket is
	 * the host and port this call used, written as ''server'' next
	 * to those files.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var registration = new Argus.Shared.Register();
	 * var code = registration.try_connection(host, port, pin, "desktop");
	 * }}}
	 */
	public class Register : GLib.Object
	{
		/**
		 * Certificate storage directory.
		 *
		 * Empty uses the current user's ''argus'' data directory.
		 * A privileged caller may set a system agent directory.
		 */
		public string data_dir = "";

		/**
		 * Download socket from the registration reply, ''host:port''.
		 *
		 * Empty until a reply stores it. Also written as ''download''
		 * next to the certificate files.
		 */
		public string download = "";

		/**
		 * Download URL path from the registration reply.
		 *
		 * Empty until a reply stores it. Also written as
		 * ''download-path'' next to the certificate files. The
		 * path includes the extension for the OS family this call
		 * sent. The server chooses it.
		 */
		public string download_path = "";

		/**
		 * Listen addresses from the registration reply, one per line.
		 *
		 * Empty when the reply has none after the download URL path.
		 */
		public string addresses = "";

		/**
		 * Register this machine while the Argus window is open.
		 *
		 * Sends ''pin'', the certificate request, ''requester'',
		 * and the OS family. Windows sends ''windows''. Android
		 * sends ''android''. Linux asks
		 * {@link GLib.Environment.get_os_info} for ''ID'' and
		 * ''ID_LIKE''. That reads ''/etc/os-release''. Debian and
		 * Ubuntu send ''debian''.
		 * Fedora, RHEL, CentOS, and SUSE send ''rpm''. When that
		 * file does not decide, ''dpkg'' on ''PATH'' sends
		 * ''debian'' and ''rpm'' on ''PATH'' sends ''rpm''.
		 * Stores the signed certificate, the CA, the download
		 * socket, the download URL path, and the app socket. A
		 * stored certificate is replaced.
		 *
		 * @param host Argus address
		 * @param port Argus port
		 * @param pin number from the registration window
		 * @param requester device string stored with the machine
		 * @return zero when registration succeeds, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int try_connection(string host, uint16 port, string pin, string requester)
		{
			OLLMrpc.rpc_register();
			var dir = this.data_dir;
			if (dir == "") {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argus");
			}
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
			var csr = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "client.csr"), out csr);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var family = "linux";
#if G_OS_WIN32
			family = "windows";
#elif ANDROID
			family = "android";
#else
			var os_id = "";
			var id_value = GLib.Environment.get_os_info(GLib.OsInfoKey.ID);
			if (id_value != null) {
				os_id = id_value;
			}
			var os_like = "";
			var like_value = GLib.Environment.get_os_info("ID_LIKE");
			if (like_value != null) {
				os_like = like_value;
			}
			var os_text = os_id + " " + os_like;
			if (os_text.contains("debian") || os_text.contains("ubuntu")) {
				family = "debian";
			}
			if (family == "linux" &&
				(os_text.contains("fedora") || os_text.contains("rhel") ||
				os_text.contains("centos") || os_text.contains("suse") ||
				os_text.contains("sles"))) {
				family = "rpm";
			}
			var dpkg = GLib.Environment.find_program_in_path("dpkg");
			if (family == "linux" && dpkg != null) {
				family = "debian";
			}
			var rpm = GLib.Environment.find_program_in_path("rpm");
			if (family == "linux" && rpm != null) {
				family = "rpm";
			}
#endif
			if (family == "linux") {
				GLib.warning("os-release did not name debian or rpm");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			OLLMrpc.Response response;
			try {
				var link = new OLLMrpc.Transport.TlsClient(host, port) {
					accept_any = true
				};
				response = link.call(new OLLMrpc.Request() {
					method = "ClientCert.request_registration",
					args = OLLMrpc.args("ssss", pin, csr, requester, family)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				return response.error.code;
			}
			var packed = (string[]) response.retval;
			if (packed.length < 4) {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "client.pem"), packed[0]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"), packed[1]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download"), packed[2]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "download-path"), packed[3]);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			try {
				GLib.FileUtils.set_contents(GLib.Path.build_filename(dir, "server"),
					host + ":" + port.to_string());
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			tls_files.ensure();
			this.download = packed[2];
			this.download_path = packed[3];
			if (packed.length > 4) {
				this.addresses = string.joinv("\n", packed[4:packed.length]);
			}
			return 0;
		}
	}
}
