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
	 * Certificate registration and deregistration with Argus.
	 *
	 * {@link try_connection} and {@link try_batch} enroll a machine;
	 * {@link save} persists the outcome to SQLite. {@link remove} and
	 * {@link remove_local} drop a saved management-server row (controller
	 * deregister).
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
		 * Client SQLite for {@link save}.
		 *
		 * The agent or controller sets this before {@link save}.
		 */
		public SQ.Database? client_db = null;

		/**
		 * Device or host name for {@link try_connection} and {@link save}.
		 *
		 * Agents set this to {@link GLib.Environment.get_host_name}. When
		 * empty, that name is used at RPC time. Controllers use
		 * {@link hostname} for the management identity fields instead.
		 */
		public string host_name = "";

		/**
		 * True stores this registration as a control client.
		 *
		 * Agents leave this false. Controllers set it explicitly.
		 */
		public bool is_controller = false;

		/**
		 * True sends pin ''0000'' as a batch request.
		 *
		 * The Linux agent sets this for ''--request''. An open
		 * registration window queues that request and returns a
		 * temporary certificate.
		 */
		public bool batch = false;

		/**
		 * True when the reply was ''pending''.
		 *
		 * The certificate files are stored. This attempt does not
		 * call the registration port again. {@link try_batch}
		 * polls the normal port when this is set.
		 */
		public bool pending = false;

		/**
		 * Operating-system login name for a controller registration.
		 *
		 * Agents leave this empty.
		 */
		public string username = "";

		/**
		 * Machine name for a controller registration.
		 *
		 * Agents leave this empty.
		 */
		public string hostname = "";

		/**
		 * Reply material from the last successful {@link try_connection}.
		 * Null until a success path assigns it. Persist with
		 * {@link save} on a platform subclass instance.
		 */
		public Argus.Shared.SQT.Server? server_row { get; set; }

		public enum Phase
		{
			IDLE,
			BROWSING,
			PROBING,
			AWAITING_PIN,
			ENROLLING,
			SUCCEEDED,
			FAILED
		}

		public Phase phase { get; private set; default = Phase.IDLE; }

		/**
		 * Registration host (from browse, manual entry, or
		 * {@link hostport} setter).
		 */
		public string host { get; private set; default = ""; }

		/**
		 * Registration port.
		 */
		public uint16 port { get; private set; default = 0; }

		/**
		 * ''host:port'' view of {@link host} and {@link port}.
		 *
		 * Set parses a combined string; get returns ''host:port'' or
		 * empty when either part is missing.
		 */
		public string hostport
		{
			owned get
			{
				if (this.host == "" || this.port < 1) {
					return "";
				}
				return this.host + ":" + this.port.to_string();
			}
			set
			{
				var mark = value.last_index_of(":");
				if (mark <= 0) {
					this.host = "";
					this.port = 0;
					return;
				}
				var parsed = 0;
				if (!int.try_parse(value.substring(mark + 1), out parsed) ||
					parsed < 1 || parsed > 65535) {
					this.host = "";
					this.port = 0;
					return;
				}
				this.host = value.substring(0, mark);
				this.port = (uint16) parsed;
			}
		}

		/**
		 * Server id from the browse TXT record.
		 */
		public string server_id { get; private set; default = ""; }

		/**
		 * ''127.0.0.1'' registration port is accepting TCP.
		 */
		public bool local_registration { get; private set; default = false; }

		/**
		 * Label text for UI (status or last error).
		 */
		public string detail { get; private set; default = ""; }

		/**
		 * True when {@link connect} is polling a typed host instead of browse.
		 */
		public bool probe_by_address { get; private set; default = false; }

		/**
		 * Registration finished; {@link server_row} is set.
		 */
		public signal void enrolled();

		private Browse browse = new Browse();
		private uint browse_source = 0;
		private uint poll_source = 0;
		private int poll_token = 0;

		/**
		 * Update {@link local_registration} without starting a flow.
		 */
		public void probe_local()
		{
			GLib.SocketConnection conn;
			try {
				var client = new GLib.SocketClient() {
					timeout = 2
				};
				conn = client.connect_to_host(
					"127.0.0.1", (uint16) Argus.REGISTER_PORT, null);
			} catch (GLib.Error e) {
				this.local_registration = false;
				return;
			}
			try {
				conn.close();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
			}
			this.local_registration = true;
		}

		public void stop()
		{
			this.poll_token++;
			if (this.browse_source != 0) {
				GLib.Source.remove(this.browse_source);
				this.browse_source = 0;
			}
			if (this.poll_source != 0) {
				GLib.Source.remove(this.poll_source);
				this.poll_source = 0;
			}
			this.browse.stop();
			this.host = "";
			this.port = 0;
			this.server_id = "";
			this.probe_by_address = false;
			this.phase = Phase.IDLE;
		}

		public void start_browse()
		{
			this.stop();
			this.phase = Phase.BROWSING;
			this.detail = "Looking for a management server…";
			this.browse.start();
			this.browse_source = GLib.Timeout.add(200, this.on_mdns_poll);
		}

		public new void connect(string host, uint16 port)
		{
			this.stop();
			this.probe_by_address = true;
			this.host = host;
			this.port = port;
			this.server_id = "";
			this.phase = Phase.PROBING;
			this.detail = "Looking for a management server…";
			this.poll_source = GLib.Timeout.add_seconds(20, this.probe);
			this.probe();
		}

		/**
		 * Send the PIN on the current {@link hostport}.
		 *
		 * @param pin six-digit registration PIN
		 */
		public async void submit_pin(string pin) throws GLib.Error
		{
			if (this.phase != Phase.AWAITING_PIN) {
				throw new GLib.IOError.FAILED("registration is not waiting for a PIN");
			}
			this.phase = Phase.ENROLLING;
			this.detail = "Registering…";
			if (this.host == "" || this.port < 1) {
				this.phase = Phase.FAILED;
				this.detail = "Bad address";
				return;
			}
			var requester = this.host_name != "" ?
				this.host_name : GLib.Environment.get_host_name();
			var code = this.try_connection(this.host, this.port, pin, requester);
			if (code != 0) {
				this.phase = Phase.FAILED;
				this.detail = "Registration failed";
				return;
			}
			this.phase = Phase.SUCCEEDED;
			this.detail = "Registration succeeded";
			this.enrolled();
		}

		/**
		 * Poll mDNS while {@link phase} is ''BROWSING''.
		 */
		private bool on_mdns_poll()
		{
			if (this.phase != Phase.BROWSING) {
				return false;
			}
			var hit = this.browse.poll();
			if (hit == "") {
				return true;
			}
			if (hit == "none") {
#if ANDROID
				if (!this.probe_by_address) {
					this.detail = "No management server found";
					this.browse.start();
					return true;
				}
#endif
				this.detail = "No management server found";
				this.browse.start();
				return true;
			}
			this.browse.stop();
			this.browse_source = 0;
			var nl = hit.index_of("\n");
			if (nl <= 0 || !GLib.Uuid.string_is_valid(hit.substring(0, nl))) {
				this.phase = Phase.FAILED;
				this.detail = "No server id";
				return false;
			}
			this.server_id = hit.substring(0, nl);
			this.hostport = hit.substring(nl + 1);
			this.probe_by_address = false;
			this.phase = Phase.AWAITING_PIN;
			this.detail = "Management server found. Enter the six-digit PIN.";
			return false;
		}

		/**
		 * Start one async TCP check to the registration port on
		 * {@link host} and {@link port}. The 20 s timer calls this again until the
		 * port answers or the flow is cancelled.
		 *
		 * @return true to leave the timer running
		 */
		private bool probe()
		{
			if (this.phase != Phase.PROBING) {
				return false;
			}
			if (this.host == "" || this.port < 1) {
				this.phase = Phase.FAILED;
				this.detail = "Not active";
				return false;
			}
			var token = this.poll_token;
			var client = new GLib.SocketClient () {
				timeout = 5
			};
			client.connect_to_host_async.begin(
				this.host, this.port, null,
				(obj, res) => {
					this.on_probe_complete(token, client, res);
				}
			);
			return true;
		}

		/**
		 * Handle {@link GLib.SocketClient.connect_to_host_async} for
		 * {@link probe}.
		 *
		 * @param token {@link poll_token} when the probe started
		 * @param client socket client for this attempt
		 * @param res async result
		 */
		private void on_probe_complete(
			int token, GLib.SocketClient client, GLib.AsyncResult res)
		{
			if (token != this.poll_token) {
				return;
			}
			if (this.phase != Phase.PROBING) {
				return;
			}
			var opened = false;
			try {
				var conn = client.connect_to_host_async.end(res);
				opened = true;
				try {
					conn.close();
				} catch (GLib.Error close_error) {
					GLib.warning("%s", close_error.message);
				}
			} catch (GLib.Error e) {
				opened = false;
			}
			if (!opened) {
				this.detail = "Not active";
				return;
			}
			if (this.poll_source != 0) {
				GLib.Source.remove(this.poll_source);
				this.poll_source = 0;
			}
			this.poll_token++;
			this.phase = Phase.AWAITING_PIN;
			this.detail = "Okay";
		}

		/**
		 * Deregister could not complete.
		 */
		public signal void remove_failed(string message);

		/**
		 * {@link Registration.deregister} did not complete (timeout or transport).
		 * UI may still call {@link remove_local}.
		 */
		public signal void remove_server_unreachable(string message);

		/**
		 * The saved server row was removed from {@link client_db}.
		 */
		public signal void remove_row_deleted();

		/**
		 * Register this machine while the Argus RM window is open.
		 *
		 * Sends ''pin'', the certificate request, ''requester'',
		 * the OS family, the batch flag, and the controller identity fields.
		 * Windows sends ''windows''. Android sends ''android''. Linux asks
		 * {@link GLib.Environment.get_os_info} for ''ID'' and
		 * ''ID_LIKE''. That reads ''/etc/os-release''. Debian and
		 * Ubuntu send ''debian''.
		 * Fedora, RHEL, CentOS, and SUSE send ''rpm''. When that
		 * file does not decide, ''dpkg'' on ''PATH'' sends
		 * ''debian'' and ''rpm'' on ''PATH'' sends ''rpm''.
		 * Stores the signed certificate, the CA, the download
		 * path, and the app socket. The download address is the
		 * host this call connected to and {@link Argus.DOWNLOAD_PORT}.
		 * A stored certificate is replaced. A ''pending'' reply
		 * stores those files and sets {@link pending}.
		 * {@link try_batch} polls the normal port after that.
		 *
		 * @param host Argus Remote Manager address
		 * @param port Argus Remote Manager port
		 * @param pin number from the registration window
		 * @param requester device string stored with the machine
		 * @return zero when the files are stored, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int try_connection(string host, uint16 port, string pin, string requester = "")
		{
			this.server_row = null;
			this.pending = false;
			var device = requester;
			if (device == "") {
				device = this.host_name;
			}
			if (device == "") {
				device = GLib.Environment.get_host_name();
			}
			GLib.debug("registering %s:%u", host, (uint) port);
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
				var connection = new OLLMrpc.Transport.TlsClient(host, port) {
					accept_any = true
				};
				response = connection.call(new OLLMrpc.Request() {
					method = "Agent.request_registration",
					args = OLLMrpc.args("ssssbbss", pin, csr, device,
						family, this.is_controller, this.batch, this.username, this.hostname)
				});
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			if (response.error != null) {
				if (response.error.message == "This machine is already registered.") {
					return 1;
				}
				return response.error.code;
			}
			var packed = (string[]) response.retval;
			if (packed.length < 3) {
				return (int) OLLMrpc.RpcErrorCode.INVALID_REQUEST;
			}
			var stored_port = port.to_string();
			if (packed.length > 3) {
				var listed = packed[3];
				var listed_mark = listed.last_index_of(":");
				if (listed_mark > 0 && listed.substring(listed_mark + 1) != "") {
					stored_port = listed.substring(listed_mark + 1);
				}
			}
			var key_pem = "";
			try {
				GLib.FileUtils.get_contents(
					GLib.Path.build_filename(dir, "client-key.pem"), out key_pem);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			var listen = "";
			if (packed.length > 3) {
				listen = string.joinv("\n", packed[3:packed.length]);
			}
			this.server_row = new Argus.Shared.SQT.Server() {
				name = device,
				port = int.parse(stored_port),
				addresses = listen,
				download = host + ":" + Argus.DOWNLOAD_PORT.to_string(),
				download_path = packed[2],
				pem_private_key = key_pem.strip(),
				pem_client_certificate = packed[0].strip(),
				pem_ca_certificate = packed[1].strip()
			};
			if (response.msg == "pending") {
				this.pending = true;
			}
			return 0;
		}

		/**
		 * Register this machine without a typed number.
		 *
		 * Sends pin ''0000'' with the batch flag. A closed
		 * registration port is tried again every ten seconds for
		 * about three minutes. A pending reply is polled on the
		 * stored normal port every twenty seconds, fifteen times.
		 * Stdout is one line, rewritten in place. If none of those
		 * connects, the stored certificate is deleted.
		 *
		 * @param host Argus Remote Manager address
		 * @param port registration port
		 * @param requester device string stored with the machine
		 * @return zero when the certificate is accepted, otherwise
		 *   an {@link OLLMrpc.RpcErrorCode} value, or 1 when the
		 *   wait ends without approval
		 */
		public int try_batch(string host, uint16 port, string requester = "")
		{
			this.batch = true;
			var device = requester;
			if (device == "") {
				device = this.host_name;
			}
			if (device == "") {
				device = GLib.Environment.get_host_name();
			}
			var dir = this.data_dir;
			if (dir == "") {
				dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "argus");
			}
			var started = GLib.get_monotonic_time();
			while (true) {
				var code = this.try_connection(host, port, "0000", device);
				if (code == 0) {
					break;
				}
				if (code != (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR) {
					GLib.stderr.printf("Registration failed: %d\n", code);
					return code;
				}
				if (GLib.get_monotonic_time() - started >= 3 * 60 * 1000 * 1000) {
					GLib.stderr.printf("Registration failed: %d\n", code);
					return code;
				}
				GLib.stdout.printf("Registration is not open.\n");
				GLib.stdout.flush();
				GLib.Thread.usleep(10 * 1000 * 1000);
			}
			if (!this.pending) {
				return 0;
			}
			if (this.server_row == null || !this.server_row.has_certificate) {
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			GLib.InetSocketAddress poll;
			try {
				poll = this.server_row.socket(0);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			var poll_host = poll.get_address().to_string();
			var poll_port = poll.get_port();
			GLib.TlsCertificate tls_cert;
			try {
				tls_cert = this.server_row.tls_certificate();
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			var approved = false;
			var attempt = 0;
			var polled = GLib.get_monotonic_time();
			while (attempt < 15) {
				attempt++;
				GLib.stdout.printf(
					"\rWaiting for registration to be approved, try %d of 15",
					attempt);
				GLib.stdout.flush();
				var opened = new OLLMrpc.Transport.TlsClient(poll_host, (uint16) poll_port) {
					accept_any = true,
					tls_certificate = tls_cert
				};
				opened.timeout = 5;
				var connected = false;
				try {
					opened.open();
					connected = true;
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				OLLMrpc.Response? response = null;
				if (connected) {
					try {
						response = opened.call(new OLLMrpc.Request() {
							method = "RPC-Daemon.hello",
							args = OLLMrpc.args("iss", 1, "argus-agent", Argus.VERSION)
						});
					} catch (GLib.Error e) {
						GLib.warning("%s", e.message);
					}
				}
				if (response != null && response.error != null) {
					GLib.warning("%s", response.error.message);
				} else if (response != null) {
					var server_version = "0.0.0";
					if (response.retval.holds(typeof(string)) && response.retval.get_string() != "") {
						server_version = response.retval.get_string();
					}
					var order = GLib.strcmp(Argus.VERSION.collate_key_for_filename(), server_version.collate_key_for_filename());
					if (order > 0) {
						GLib.stdout.printf("\n");
						GLib.stderr.printf("The server is %s. This client is %s.\n", server_version, Argus.VERSION);
						this.server_row = null;
						return 1;
					}
					if (order < 0) {
						GLib.warning("This client is %s. The server is %s.", Argus.VERSION, server_version);
					}
					approved = true;
				}
				if (approved) {
					break;
				}
				if (attempt >= 15) {
					break;
				}
				var wait_until = polled + (int64) attempt * 20 * 1000 * 1000;
				var now = GLib.get_monotonic_time();
				if (now >= wait_until) {
					continue;
				}
				GLib.Thread.usleep((ulong) (wait_until - now));
			}
			GLib.stdout.printf("\n");
			GLib.stdout.flush();
			if (!approved) {
				this.server_row = null;
				GLib.stderr.printf("Registration was not approved.\n");
				return 1;
			}
			return 0;
		}

		/**
		 * Copy {@link server_row} into a platform {@link Argus.Shared.SQT.Server}
		 * subclass and {@link Argus.Shared.SQT.Server.save} to the client database.
		 *
		 * The caller constructs ''row'' (for example
		 * {@link Argus.Agent.SQT.Server} with {@link Argus.Agent.SQT.Server.data_dir}
		 * set). Column fields and PEM strings come from {@link server_row}.
		 * When ''row.name'' is still empty, ''default_name'' is used if the
		 * reply name is empty.
		 *
		 * Controllers usually persist through
		 * {@link Argus.Controller.Dialog.Bootstrap.finish_registration} (CA policy on
		 * Linux). Agents may call {@link save} directly.
		 *
		 * @param row agent or controller {@link Argus.Shared.SQT.Server} subclass
		 * @return false when there is no row, certificates are incomplete, or save failed
		 */
		public bool save(Argus.Shared.SQT.Server row) {
			var src = this.server_row;
			var db = this.client_db;
			if (db == null || row == null || src == null || !src.has_certificate) {
				return false;
			}
			if (row.name == "") {
				if (src.name != "") {
					row.name = src.name;
				} else if (this.host_name != "") {
					row.name = this.host_name;
				} else {
					row.name = GLib.Environment.get_host_name();
				}
			}
			row.port = src.port;
			row.addresses = src.addresses;
			row.download = src.download;
			row.download_path = src.download_path;
			row.pem_private_key = src.pem_private_key;
			row.pem_client_certificate = src.pem_client_certificate;
			row.pem_ca_certificate = src.pem_ca_certificate;
			try {
				row.save(db);
			} catch (GLib.Error e) {
				GLib.warning("%s", e.message);
				return false;
			}
			return true;
		}

		/**
		 * Ask the management server to drop this certificate, then remove the
		 * local {@link Argus.Shared.SQT.Server} row.
		 *
		 * Uses the TLS {@link OLLMrpc.Client} already open for this
		 * registration. Emits {@link remove_server_unreachable}, {@link remove_failed},
		 * or {@link remove_row_deleted}. {@link client_db} must be set.
		 */
		public void remove(Argus.Shared.SQT.Server row, OLLMrpc.Client rpc)
		{
			if (this.client_db == null) {
				this.remove_failed("The client database is not set.");
				return;
			}
			if (row.pem_client_certificate == "") {
				this.remove_failed("The saved server has no certificate.");
				return;
			}
			GLib.TlsCertificate cert;
			try {
				cert = new GLib.TlsCertificate.from_pem(
					row.pem_client_certificate, row.pem_client_certificate.length);
			} catch (GLib.Error e) {
				this.remove_failed(e.message);
				return;
			}
			var fingerprint = GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, cert.certificate.data);
			if (!rpc.connected) {
				this.remove_server_unreachable("The server did not answer.");
				return;
			}
			var settled = false;
			uint wait = 0;
			wait = GLib.Timeout.add_seconds(5, () => {
				if (settled) {
					return false;
				}
				settled = true;
				wait = 0;
				this.remove_server_unreachable("The server did not answer.");
				return false;
			});
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Registration.deregister",
				args = OLLMrpc.args("s", fingerprint)
			}, (call_obj, call_res) => {
				if (settled) {
					return;
				}
				settled = true;
				if (wait != 0) {
					GLib.Source.remove(wait);
					wait = 0;
				}
				var response = new OLLMrpc.Response();
				try {
					response = rpc.call.end(call_res);
				} catch (GLib.Error e) {
					this.remove_server_unreachable(e.message);
					return;
				}
				if (response.error != null) {
					this.remove_failed(response.error.message);
					return;
				}
				rpc.disconnect();
				this.remove_local(row);
			});
		}

		/**
		 * Remove the local row only (after {@link remove_server_unreachable}).
		 */
		public void remove_local(Argus.Shared.SQT.Server row)
		{
			var db = this.client_db;
			if (db == null) {
				this.remove_failed("The client database is not set.");
				return;
			}
			try {
				row.remove(db);
			} catch (GLib.Error e) {
				this.remove_failed(e.message);
				return;
			}
			this.remove_row_deleted();
		}
	}
}
