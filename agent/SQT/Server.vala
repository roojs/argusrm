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

namespace Argus.Agent.SQT
{
	/**
	 * Agent management-server row with PEM files under {@link data_dir}.
	 */
	public class Server : Argus.Shared.SQT.Server
	{
		public static SQ.Query<Server> query(SQ.Database db)
		{
			return new SQ.Query<Server>(db, "server");
		}

		/**
		 * Directory with ''client.pem'', ''client-key.pem'', and
		 * ''ollmrpc-ca.pem''.
		 */
		public string data_dir { get; set; default = ""; }

		/**
		 * Read PEM files from {@link data_dir}.
		 */
		public override void load_certificates() throws GLib.Error
		{
			this.pem_private_key = "";
			this.pem_client_certificate = "";
			this.pem_ca_certificate = "";
			if (this.data_dir == "") {
				throw new GLib.IOError.FAILED("data_dir is not set");
			}
			var key_path = GLib.Path.build_filename(this.data_dir, "client-key.pem");
			var cert_path = GLib.Path.build_filename(this.data_dir, "client.pem");
			var ca_path = GLib.Path.build_filename(this.data_dir, "ollmrpc-ca.pem");
			if (!GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)
				|| !GLib.FileUtils.test(cert_path, GLib.FileTest.EXISTS)
				|| !GLib.FileUtils.test(ca_path, GLib.FileTest.EXISTS)) {
				return;
			}
			var key_pem = "";
			var cert_pem = "";
			var ca_pem = "";
			GLib.FileUtils.get_contents(key_path, out key_pem);
			GLib.FileUtils.get_contents(cert_path, out cert_pem);
			GLib.FileUtils.get_contents(ca_path, out ca_pem);
			this.pem_private_key = key_pem.strip();
			this.pem_client_certificate = cert_pem.strip();
			this.pem_ca_certificate = ca_pem.strip();
		}

		/**
		 * Write {@link pem_*} under {@link data_dir}.
		 */
		public override void store_certificates() throws GLib.Error
		{
			if (this.data_dir == "") {
				throw new GLib.IOError.FAILED("data_dir is not set");
			}
			if (GLib.DirUtils.create_with_parents(this.data_dir, 0700) != 0) {
				throw new GLib.FileError.FAILED("Could not create the data directory");
			}
			var key_path = GLib.Path.build_filename(this.data_dir, "client-key.pem");
			var cert_path = GLib.Path.build_filename(this.data_dir, "client.pem");
			var ca_path = GLib.Path.build_filename(this.data_dir, "ollmrpc-ca.pem");
			GLib.FileUtils.set_contents(key_path, this.pem_private_key);
			GLib.FileUtils.set_contents(cert_path, this.pem_client_certificate);
			GLib.FileUtils.set_contents(ca_path, this.pem_ca_certificate);
			if (this.download != "") {
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(this.data_dir, "download"),
					this.download);
			}
			if (this.download_path != "") {
				GLib.FileUtils.set_contents(
					GLib.Path.build_filename(this.data_dir, "download-path"),
					this.download_path);
			}
#if !G_OS_WIN32
			GLib.FileUtils.chmod(key_path, 0600);
			GLib.FileUtils.chmod(cert_path, 0600);
			GLib.FileUtils.chmod(ca_path, 0600);
#else
			var tls_files = new OLLMrpc.Transport.Cert() {
				dir = this.data_dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "argus-agent",
			};
			tls_files.ensure();
#endif
		}

		/**
		 * Remove agent registration PEM files.
		 */
		public override void clear_registration() throws GLib.Error
		{
			if (this.data_dir != "") {
				GLib.FileUtils.remove(GLib.Path.build_filename(this.data_dir, "ollmrpc-ca.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(this.data_dir, "client.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(this.data_dir, "client-key.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(this.data_dir, "client.csr"));
			}
			this.pem_private_key = "";
			this.pem_client_certificate = "";
			this.pem_ca_certificate = "";
		}
	}
}