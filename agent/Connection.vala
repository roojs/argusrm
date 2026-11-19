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
	 * Long-lived TLS session to the management server.
	 *
	 * ''docs/plans/2.6.1-management-client-link-spec.md''
	 */
	internal class Connection : GLib.Object
	{
		internal enum State
		{
			DISCONNECTED_WILL_RETRY,
			CHECKING_CONFIG,
			CONNECTING,
			CONNECTION_CHECK,
			CONNECTED,
			DISCONNECTED_DEAD
		}

		private unowned Application app;

		private uint attempt_generation = 0;
		private uint scheduler_source_id = 0;
		private OLLMrpc.Transport.TlsClient? tls_client;
		private OLLMrpc.Transport.TlsClient? pending_tls_client;
		private string attempt_host = "";
		private uint16 attempt_port = 0;

		internal State state { get; private set; default = State.DISCONNECTED_WILL_RETRY; }

		internal string failure_detail { get; private set; default = ""; }

		internal int64 reconnect_at { get; private set; }

		internal int64 connect_attempt_until { get; private set; }

		public Connection(Application application)
		{
			Object();
			this.app = application;
			this.scheduler_source_id = GLib.Timeout.add_seconds(1, () => {
				if (this.state == State.CONNECTED && this.client() != null) {
					return true;
				}
				if (this.state == State.DISCONNECTED_DEAD) {
					return true;
				}
				if (this.state == State.CONNECTING || this.state == State.CONNECTION_CHECK) {
					if (this.connect_attempt_until != 0 &&
						GLib.get_monotonic_time() >= this.connect_attempt_until) {
						this.attempt_generation++;
						this.pending_tls_client = null;
						this.tls_client = null;
						this.schedule_retry(false);
					}
					return true;
				}
				if (this.state != State.DISCONNECTED_WILL_RETRY) {
					return true;
				}
				if (this.reconnect_at != 0 &&
					GLib.get_monotonic_time() < this.reconnect_at) {
					return true;
				}
				this.enter_state(State.CHECKING_CONFIG);
				return true;
			});
			if (!GLib.FileUtils.test(
				GLib.Path.build_filename(this.app.data_dir, "client.pem"),
				GLib.FileTest.EXISTS)) {
				return;
			}
			this.reconnect_at = GLib.get_monotonic_time();
			this.enter_state(State.DISCONNECTED_WILL_RETRY);
			this.enter_state(State.CHECKING_CONFIG);
		}

		internal unowned OLLMrpc.Transport.TlsClient? client()
		{
			if (this.state != State.CONNECTED) {
				return null;
			}
			return this.tls_client;
		}
 

		private void enter_state(State next)
		{
			this.state = next;
			switch (this.state) {
				case State.DISCONNECTED_WILL_RETRY:
					this.on_disconnected_will_retry();
					break;

				case State.CHECKING_CONFIG:
					this.on_checking_config();
					break;

				case State.CONNECTING:
					this.on_connecting();
					break;

				case State.CONNECTION_CHECK:
					this.on_connection_check();
					break;

				case State.CONNECTED:
					this.on_connected();
					break;

				case State.DISCONNECTED_DEAD:
					this.on_disconnected_dead();
					break;
			}
		}

		private void on_disconnected_will_retry()
		{
			this.pending_tls_client = null;
			this.tls_client = null;
			Application.connection_down = true;
			if (this.reconnect_at == 0) {
				this.reconnect_at = GLib.get_monotonic_time();
			}
			this.connect_attempt_until = 0;
			this.failure_detail = "";
		}

		private void on_checking_config()
		{
			var dir = this.app.data_dir;
			string host = "";
			uint16 port = 0;
			var text = "";
			try {
				GLib.FileUtils.get_contents(GLib.Path.build_filename(dir, "server"), out text);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				this.schedule_retry(false);
				return;
			}
			text = text.strip();
			var mark = text.last_index_of(":");
			if (text == "" || mark < 1) {
				this.schedule_retry(false);
				return;
			}
			host = text.substring(0, mark);
			var parsed = int.parse(text.substring(mark + 1));
			if (parsed < 1 || parsed > 65535) {
				this.schedule_retry(false);
				return;
			}
			port = (uint16) parsed;
			var ca = GLib.Path.build_filename(dir, "ollmrpc-ca.pem");
			var cert = GLib.Path.build_filename(dir, "client.pem");
			var key = GLib.Path.build_filename(dir, "client-key.pem");
			if (!GLib.FileUtils.test(ca, GLib.FileTest.EXISTS) ||
				!GLib.FileUtils.test(cert, GLib.FileTest.EXISTS) ||
				!GLib.FileUtils.test(key, GLib.FileTest.EXISTS)) {
				this.enter_dead("No certificate for the management server.", false);
				return;
			}
			this.attempt_host = host;
			this.attempt_port = port;
			this.enter_state(State.CONNECTING);
		}

		private void on_connecting()
		{
			this.connect_attempt_until = GLib.get_monotonic_time() + (int64) 8 * 1000 * 1000;
			this.attempt_generation++;
			var generation = this.attempt_generation;
			var host = this.attempt_host;
			var port = this.attempt_port;
			var dir = this.app.data_dir;
			new GLib.Thread<int>("mgmt-connect", () => {
				var tls_files = new OLLMrpc.Transport.Cert() {
					dir = dir,
					cert_pem = "client.pem",
					key_pem = "client-key.pem",
					cn = "argus-agent",
				};
				tls_files.ensure();
				var socket = new OLLMrpc.Transport.TlsClient(host, port) {
					accept_any = true,
					tls_certificate = tls_files.certificate,
					timeout = 3
				};
				OLLMrpc.Transport.TlsClient? dialled = null;
				try {
					socket.open();
					dialled = socket;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				GLib.Idle.add(() => {
					if (generation != this.attempt_generation) {
						return false;
					}
					if (this.state != State.CONNECTING) {
						return false;
					}
					if (dialled == null) {
						this.schedule_retry(false);
						return false;
					}
					this.pending_tls_client = dialled;
					this.enter_state(State.CONNECTION_CHECK);
					return false;
				});
				return 0;
			});
		}

		private void on_connection_check()
		{
			var opened = this.pending_tls_client;
			if (opened == null) {
				this.schedule_retry(false);
				return;
			}
			var generation = this.attempt_generation;
			new GLib.Thread<int>("mgmt-hello", () => {
				bool accepted = false;
				bool retry = true;
				bool registration_rejected = false;
				string notice = "";
				OLLMrpc.Response? response = null;
				try {
					response = opened.call(new OLLMrpc.Request() {
						method = "RPC-Daemon.hello",
						args = OLLMrpc.args("iss", 1, "argus-agent", Argus.VERSION)
					});
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				if (response != null &&
					response.error != null &&
					response.error.code == (int) OLLMrpc.RpcErrorCode.CERT_NOT_REGISTERED) {
					registration_rejected = true;
					retry = false;
					notice = "Not registered with the management server.";
				} else if (response != null && response.error != null) {
					retry = false;
					notice = response.error.message;
				} else if (response != null) {
					var server_version = "0.0.0";
					if (response.retval.holds(typeof(string)) &&
						response.retval.get_string() != "") {
						server_version = response.retval.get_string();
					}
					var order = GLib.strcmp(
						Argus.VERSION.collate_key_for_filename(),
						server_version.collate_key_for_filename());
					if (order > 0) {
						retry = false;
						notice = "The server is " + server_version +
							". This client is " + Argus.VERSION + ".";
					} else {
						if (order < 0) {
							GLib.warning("This client is %s. The server is %s.",
								Argus.VERSION, server_version);
						}
						accepted = true;
						retry = false;
					}
				}
				GLib.Idle.add(() => {
					if (generation != this.attempt_generation) {
						return false;
					}
					if (this.state != State.CONNECTION_CHECK) {
						return false;
					}
					this.connect_attempt_until = 0;
					if (registration_rejected) {
						this.pending_tls_client = null;
						this.enter_dead(notice, true);
						return false;
					}
					if (accepted) {
						this.enter_connected(opened, true);
						return false;
					}
					this.pending_tls_client = null;
					if (notice != "") {
						this.failure_detail = notice;
					}
					if (retry) {
						this.schedule_retry(false);
					} else {
						this.enter_dead(notice != "" ? notice : this.failure_detail, false);
					}
					return false;
				});
				return 0;
			});
		}

		private void on_connected()
		{
			Application.connection_down = false;
			this.failure_detail = "";
			this.reconnect_at = 0;
			this.connect_attempt_until = 0;
		}

		private void on_disconnected_dead()
		{
			this.pending_tls_client = null;
			this.tls_client = null;
			Application.connection_down = true;
			this.reconnect_at = 0;
			this.connect_attempt_until = 0;
			this.app.status_notice = this.failure_detail;
		}

		private void enter_connected(OLLMrpc.Transport.TlsClient opened, bool watch)
		{
			this.pending_tls_client = null;
			this.tls_client = opened;
			if (watch) {
				opened.closed.connect(() => {
					this.tls_client = null;
					this.schedule_retry(true);
				});
				opened.notification.connect(this.app.notification);
				opened.watch();
				GLib.debug("watching the server connection");
#if !LINUX
				this.app.start_inventory_once();
#endif
			}
			this.enter_state(State.CONNECTED);
		}

		private void schedule_retry(bool immediate)
		{
			this.pending_tls_client = null;
			this.tls_client = null;
			if (immediate) {
				this.reconnect_at = GLib.get_monotonic_time();
			} else {
				this.reconnect_at = GLib.get_monotonic_time() + (int64) 5 * 1000 * 1000;
			}
			this.connect_attempt_until = 0;
			this.enter_state(State.DISCONNECTED_WILL_RETRY);
		}

		private void enter_dead(string detail, bool wipe_registration)
		{
			if (wipe_registration) {
				var dir = this.app.data_dir;
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "ollmrpc-ca.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client-key.pem"));
				GLib.FileUtils.remove(GLib.Path.build_filename(dir, "client.csr"));
				GLib.debug("registration cleared");
			}
			this.failure_detail = detail;
			this.enter_state(State.DISCONNECTED_DEAD);
		}
	}
}