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

namespace Argus.Server.Offering
{
	public class Certificate : GLib.Object
	{
		public Application app { get; private set; }

		public string csr { get; private set; default = ""; }

		public string crt_pem { get; private set; default = ""; }

		public string fingerprint { get; private set; default = ""; }

		public string ca_pem { get; private set; default = ""; }

		public bool bad_csr { get; private set; default = false; }

		[CCode (cname = "gnutls_x509_crt_set_crq", cheader_filename = "gnutls/x509.h")]
		private static extern int gnutls_x509_crt_set_crq(
			GnuTLS.X509.Certificate crt,
			GnuTLS.X509.CertificateRequest request
		);

		public Certificate(Application app, string csr)
		{
			Object();
			this.app = app;
			this.csr = csr;
			if (GnuTLS.global_init() < 0) {
				GLib.warning("could not sign");
				return;
			}
			var csr_datum = GnuTLS.Datum() {
				data = csr,
				size = csr.length
			};
			var crq = GnuTLS.X509.CertificateRequest.create();
			if (crq.import(ref csr_datum, GnuTLS.X509.CertificateFormat.PEM) < 0) {
				GLib.warning("bad csr");
				this.bad_csr = true;
				return;
			}
			var crt = GnuTLS.X509.Certificate.create();
			if (gnutls_x509_crt_set_crq(crt, crq) < 0 || crt.set_version(3) < 0) {
				GLib.warning("bad csr");
				this.bad_csr = true;
				return;
			}
			var serial = new uint8[16];
			for (var i = 0; i < serial.length; i++) {
				serial[i] = (uint8) GLib.Random.int_range(0, 256);
			}
			var now = (time_t) (GLib.get_real_time() / 1000000);
			if (crt.set_serial(serial, serial.length) < 0
				|| crt.set_activation_time(now) < 0
				|| crt.set_expiration_time(
					now + (time_t) (3650 * 24 * 60 * 60)) < 0) {
				GLib.warning("could not sign");
				return;
			}
			var ca_key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					this.app.tls.ca_pem_path, out this.ca_pem);
				GLib.FileUtils.get_contents(
					this.app.tls.ca_key_path, out ca_key_pem);
			} catch (GLib.Error e) {
				GLib.warning("could not sign: %s", e.message);
				return;
			}
			var ca_datum = GnuTLS.Datum() {
				data = this.ca_pem,
				size = this.ca_pem.length
			};
			var key_datum = GnuTLS.Datum() {
				data = ca_key_pem,
				size = ca_key_pem.length
			};
			var ca_crt = GnuTLS.X509.Certificate.create();
			var ca_key = GnuTLS.X509.PrivateKey.create();
			if (ca_crt.import(
				ref ca_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| ca_key.import(
					ref key_datum, GnuTLS.X509.CertificateFormat.PEM) < 0
				|| crt.sign2(
					ca_crt, ca_key, GnuTLS.DigestAlgorithm.SHA256, 0) < 0) {
				GLib.warning("could not sign");
				return;
			}
			var crt_len = (size_t) 0;
			crt.export(GnuTLS.X509.CertificateFormat.PEM, null, ref crt_len);
			var crt_buf = new uint8[crt_len];
			if (crt.export(
				GnuTLS.X509.CertificateFormat.PEM, crt_buf, ref crt_len) < 0) {
				GLib.warning("could not sign");
				return;
			}
			this.crt_pem = (string) crt_buf;
			try {
				var issued = new GLib.TlsCertificate.from_pem(
					this.crt_pem, this.crt_pem.length);
				this.fingerprint = GLib.Checksum.compute_for_data(
					GLib.ChecksumType.SHA256,
					issued.certificate.data
				);
			} catch (GLib.Error e) {
				GLib.warning("could not sign: %s", e.message);
				this.crt_pem = "";
			}
		}
	}
}