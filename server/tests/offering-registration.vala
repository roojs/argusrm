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

/**
 * Registration desk in user space: controller on the unix socket,
 * agents on the registration TLS port.
 *
 * Uses {@link OfferingRegistrationTestServer} and the test
 * {@link Application} stub (''tests/offering-test-application.vala'').
 * No nftables and no root — firewalls are not enabled. Loopback ports
 * and a temp data directory only.
 *
 * Run: ''meson test -C build offering-registration --print-errorlogs''
 */
namespace Argus.Server
{
	class OfferingRegistrationTest
	{
		static int failures = 0;

		static void note(bool ok, string message)
		{
			if (ok) {
				GLib.print("ok %s\n", message);
				return;
			}
			failures++;
			GLib.printerr("fail %s\n", message);
		}

		static uint16 ephemeral_port()
		{
			var probe = new GLib.SocketListener();
			GLib.SocketAddress? bound = null;
			try {
				probe.add_address(
					new GLib.InetSocketAddress(
						new GLib.InetAddress.loopback(GLib.SocketFamily.IPV4), 0),
					GLib.SocketType.STREAM,
					GLib.SocketProtocol.TCP,
					null,
					out bound);
			} catch (GLib.Error e) {
				GLib.printerr("fail ephemeral port: %s\n", e.message);
				return 0;
			}
			var port = ((GLib.InetSocketAddress) bound).get_port();
			probe.close();
			return port;
		}

		static string make_csr(string tls_dir, string label)
		{
			var dir = GLib.Path.build_filename(tls_dir, label);
			GLib.DirUtils.create_with_parents(dir, 0700);
			var material = new OLLMrpc.Transport.Cert() {
				dir = dir,
				cert_pem = "client.pem",
				key_pem = "client-key.pem",
				cn = "offering-test-" + label,
			};
			material.ensure();
			var csr = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client.csr"), out csr);
			} catch (GLib.Error e) {
				GLib.printerr("fail csr %s: %s\n", label, e.message);
				return "";
			}
			return csr;
		}

		/**
		 * Blocking ''TlsClient.call'' on a worker thread so the default
		 * main context can run registration ''SslListen'' handshakes.
		 */
		private class RegistrationTlsJob : GLib.Object
		{
			public bool done { get; private set; default = false; }
			public OLLMrpc.Response? response { get; private set; }
			public GLib.Error? error { get; private set; }
			public GLib.TlsCertificate? client_cert { get; set; }

			public void run(uint16 reg_port, OLLMrpc.Request request)
			{
				try {
					var connection = new OLLMrpc.Transport.TlsClient(
						"127.0.0.1", reg_port) {
						accept_any = true,
						tls_certificate = this.client_cert
					};
					this.response = connection.call(request);
				} catch (GLib.Error e) {
					this.error = e;
				}
				this.done = true;
			}
		}

		static OLLMrpc.Response? registration_tls_call(
			uint16 reg_port,
			OLLMrpc.Request request,
			GLib.TlsCertificate? client_cert = null
		) throws GLib.Error
		{
			var job = new RegistrationTlsJob() {
				client_cert = client_cert
			};
			var thread = new GLib.Thread<void>("reg-tls", () => {
				job.run(reg_port, request);
			});
			var ctx = GLib.MainContext.default();
			while (!job.done) {
				while (ctx.iteration(false)) {
				}
				GLib.Thread.usleep(20000);
			}
			thread.join();
			if (job.error != null) {
				throw job.error;
			}
			return job.response;
		}

		static OLLMrpc.Response? enroll_tls(
			uint16 reg_port,
			string pin,
			string csr,
			string requester,
			bool batch)
		{
			try {
				return registration_tls_call(reg_port,
					new OLLMrpc.Request() {
						method = "Offering.enroll",
						args = OLLMrpc.args(
							"ssssbbss",
							pin, csr, requester, "debian",
							false, batch, "", "")
					});
			} catch (GLib.Error e) {
				GLib.warning("enroll tls: %s", e.message);
				return null;
			}
		}

		static bool registration_tls_handshake(uint16 reg_port)
		{
			try {
				var response = registration_tls_call(reg_port,
					new OLLMrpc.Request() {
						method = "Offering.status"
					});
				return response != null;
			} catch (GLib.Error e) {
				return false;
			}
		}

		static OLLMrpc.Response? status_tls(
			uint16 reg_port,
			GLib.TlsCertificate? client_cert = null)
		{
			try {
				return registration_tls_call(reg_port,
					new OLLMrpc.Request() {
						method = "Offering.status"
					},
					client_cert);
			} catch (GLib.Error e) {
				return null;
			}
		}

		static GLib.TlsCertificate? provisional_cert(
			string tls_dir,
			string label,
			string signed_pem)
		{
			if (signed_pem == "") {
				return null;
			}
			var cert_path = GLib.Path.build_filename(
				tls_dir, label, "signed-client.pem");
			var key_path = GLib.Path.build_filename(
				tls_dir, label, "client-key.pem");
			try {
				GLib.FileUtils.set_contents(cert_path, signed_pem);
				return new GLib.TlsCertificate.from_files(
					cert_path, key_path);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return null;
			}
		}

		static async bool connect_unix(
			OLLMrpc.Client client) throws GLib.Error
		{
			return yield client.connect(new OLLMrpc.Request() {
				method = "RPC-Daemon.hello",
				args = OLLMrpc.args("iss", 1, "offering-test", Argus.VERSION)
			});
		}

		static async string open_pin(
			OLLMrpc.Client client,
			bool pending) throws GLib.Error
		{
			var response = yield client.call(new OLLMrpc.Request() {
				method = "Offering.open",
				args = OLLMrpc.args("b", pending)
			});
			if (response.error != null) {
				throw new GLib.IOError.FAILED(response.error.message);
			}
			if (pending) {
				note(response.msg == "ok", "bulk open msg ok");
				return "";
			}
			var packed = (string[]) response.retval;
			if (packed.length < 1 || packed[0].length != 6) {
				throw new GLib.IOError.FAILED("open did not return a pin");
			}
			return packed[0];
		}

		static Gee.ArrayList<Argus.Shared.AgentPending> pending_rows(
			SQ.Database db)
		{
			var rows = new Gee.ArrayList<Argus.Shared.AgentPending>();
			Argus.Shared.AgentPending.query(db).select("", rows);
			return rows;
		}

		static async int run() throws GLib.Error
		{
			var data_dir = "";
			try {
				data_dir = GLib.DirUtils.make_tmp("argus-offering-reg-XXXXXX");
			} catch (GLib.Error e) {
				GLib.printerr("fail temp data dir: %s\n", e.message);
				return 1;
			}
			var app_port = ephemeral_port();
			var reg_port = ephemeral_port();
			if (app_port < 1 || reg_port < 1 || app_port == reg_port) {
				GLib.printerr("fail could not allocate ports\n");
				return 1;
			}
			var server = new OfferingRegistrationTestServer();
			if (!server.start(
				data_dir,
				"127.0.0.1:" + app_port.to_string(),
				"127.0.0.1:" + reg_port.to_string())) {
				GLib.printerr("fail test server start\n");
				return 1;
			}
			var sock = server.unix_socket_path;
			var client = new OLLMrpc.Client("", "", sock) {
				live_handles = true,
				call_timeout_seconds = 30
			};
			if (!yield connect_unix(client)) {
				GLib.printerr("fail unix hello: %s\n", client.connect_error);
				server.stop();
				return 1;
			}
			note(yield connect_unix(client), "controller unix connected");

			var tls_dir = GLib.Path.build_filename(data_dir, "agent-tls");
			GLib.DirUtils.create_with_parents(tls_dir, 0700);
			var csr_pin = make_csr(tls_dir, "pin");
			var csr_bulk_a = make_csr(tls_dir, "bulk-a");
			var csr_bulk_b = make_csr(tls_dir, "bulk-b");
			note(csr_pin.length > 0 &&
				csr_pin.index_of("REQUEST") >= 0, "pin CSR");

			note(!registration_tls_handshake(reg_port),
				"registration TLS down before open");

			string pin = "";
			try {
				pin = yield open_pin(client, false);
			} catch (GLib.Error e) {
				note(false, "Offering.open pin (" + e.message + ")");
				server.stop();
				return 1;
			}
			note(pin.length == 6, "Offering.open returns six-digit pin");

			var wrong = enroll_tls(reg_port, "000001", csr_pin,
				"wrong-pin", false);
			note(wrong != null && wrong.error != null,
				"wrong pin is rejected");
			note(wrong != null && wrong.error != null &&
				wrong.error.message == "number rejected",
				"wrong pin error message");

			var bad = enroll_tls(reg_port, pin, "not a csr", "bad-csr",
				false);
			note(bad != null && bad.error != null, "bad csr is rejected");
			note(bad != null && bad.error != null &&
				bad.error.message == "bad csr",
				"bad csr error message");

			var instant = enroll_tls(reg_port, pin, csr_pin,
				"instant-agent", false);
			note(instant != null && instant.error == null,
				"matching pin enrolls");
			note(instant != null && instant.msg == "ok",
				"instant enroll msg ok");
			var packed = instant != null ? (string[]) instant.retval : null;
			note(packed != null && packed.length >= 3,
				"instant enroll returns cert bundle");

			var agents = new Gee.ArrayList<Argus.Shared.Agent>();
			Argus.Shared.Agent.query(server.app.db).select("", agents);
			note(agents.size == 1, "one agent row after instant enroll");

			var late = enroll_tls(reg_port, pin, csr_pin, "late", false);
			note(late != null && late.error != null,
				"pin cleared after instant success");
			note(late != null && late.error.message == "number rejected",
				"late instant enroll error message");

			yield client.call(new OLLMrpc.Request() {
				method = "Offering.close",
				args = OLLMrpc.args("b", false)
			});
			note(!registration_tls_handshake(reg_port),
				"registration TLS down after pin close");

			yield open_pin(client, true);
			note(server.app.offering.polling == false, "bulk open not polling yet");

			var prov_a = enroll_tls(reg_port, "0000", csr_bulk_a,
				"provisional-a", true);
			note(prov_a != null && prov_a.msg == "pending",
				"provisional enroll pending");
			note(prov_a != null && prov_a.error == null,
				"provisional enroll no error");

			var prov_b = enroll_tls(reg_port, "0000", csr_bulk_b,
				"provisional-b", true);
			note(prov_b != null && prov_b.msg == "pending",
				"second provisional pending");

			var pending = pending_rows(server.app.db);
			note(pending.size == 2, "two agent_pending rows");

			if (pending.size < 2) {
				server.stop();
				return failures == 0 ? 0 : 1;
			}
			var accept_id = (int) pending.get(0).id;
			var reject_id = (int) pending.get(1).id;
			var accept_ids = new int[] { accept_id };

			var accept = yield client.call(new OLLMrpc.Request() {
				method = "Offering.accept",
				args = OLLMrpc.args("ai", accept_ids, accept_ids.length)
			});
			note(accept.error == null, "Offering.accept");
			agents.clear();
			Argus.Shared.Agent.query(server.app.db).select("", agents);
			note(agents.size == 2, "accept promotes row to agent");

			pending = pending_rows(server.app.db);
			var pending_before_reject = pending.size;

			var reject_ids = new int[] { reject_id };
			var reject = yield client.call(new OLLMrpc.Request() {
				method = "Offering.reject",
				args = OLLMrpc.args("ai", reject_ids, reject_ids.length)
			});
			note(reject.error == null, "Offering.reject");
			pending = pending_rows(server.app.db);
			note(pending.size == pending_before_reject - 1,
				"reject drops one pending row");

			var empty_reject_error = "";
			try {
				var empty_reject = yield client.call(
					new OLLMrpc.Request() {
						method = "Offering.reject",
						args = OLLMrpc.args("ai", new int[] { }, 0)
					});
				if (empty_reject.error != null) {
					empty_reject_error = empty_reject.error.message;
				}
			} catch (GLib.Error e) {
				empty_reject_error = e.message;
			}
			note(empty_reject_error == "nothing selected",
				"reject empty list");

			yield client.call(new OLLMrpc.Request() {
				method = "Offering.close",
				args = OLLMrpc.args("b", true)
			});
			note(server.app.offering.polling, "bulk close enters polling");
			pending = pending_rows(server.app.db);
			note(pending.size == pending_before_reject - 1,
				"bulk close keeps remaining pending rows");

			note(registration_tls_handshake(reg_port),
				"registration TLS up in polling");

			var packed_a = prov_a != null ? (string[]) prov_a.retval : null;
			var signed_a = packed_a != null && packed_a.length > 0 ?
				packed_a[0] : "";
			var cert_a = provisional_cert(tls_dir, "bulk-a", signed_a);
			var status_accepted = status_tls(reg_port, cert_a);
			note(status_accepted != null && status_accepted.error == null &&
				status_accepted.msg == "accepted",
				"Offering.status accepted after accept");

			var packed_b = prov_b != null ? (string[]) prov_b.retval : null;
			var signed_b = packed_b != null && packed_b.length > 0 ?
				packed_b[0] : "";
			var cert_b = provisional_cert(tls_dir, "bulk-b", signed_b);
			var status_rejected = status_tls(reg_port, cert_b);
			note(status_rejected != null && status_rejected.error == null &&
				status_rejected.msg == "rejected",
				"Offering.status rejected after reject");

			var late_bulk = enroll_tls(reg_port, "0000", csr_bulk_b,
				"late-bulk", true);
			note(late_bulk == null || late_bulk.msg != "pending",
				"no provisional enroll while polling");

			server.stop();
			return failures == 0 ? 0 : 1;
		}

		static int main()
		{
			int code = 0;
			var loop = new GLib.MainLoop();
			run.begin((obj, res) => {
				try {
					code = run.end(res);
				} catch (GLib.Error e) {
					GLib.printerr("fail: %s\n", e.message);
					code = 1;
				}
				loop.quit();
			});
			loop.run();
			return code;
		}
	}
}