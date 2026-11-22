/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Agent.Linux
{
	private enum LocalEnrollStep
	{
		ENROLL,
		SUCCEEDED,
		CONFLICT,
		FAILED
	}

	/**
	 * Gtk **Connect locally**: co-located certificate issue, save, service restart.
	 */
	internal class LocalRegistration : GLib.Object
	{
		public unowned Application app { get; construct; }

		public LocalRegistration(Application application)
		{
			Object(app: application);
		}

		private LocalEnrollStep step;
		private ServiceManager? service;
		private Argus.Shared.Register? reg;
		private bool replace_server_registration;
		private string detail = "";

		public void start(
			ServiceManager service,
			Argus.Shared.Register reg,
			bool replace_server_registration = false)
		{
			this.service = service;
			this.reg = reg;
			this.replace_server_registration = replace_server_registration;
			this.detail = "";
			this.step = LocalEnrollStep.ENROLL;
			this.continue_flow();
		}

		private void continue_flow()
		{
			switch (this.step) {
				case LocalEnrollStep.ENROLL:
					this.do_enroll();
					break;

				case LocalEnrollStep.SUCCEEDED:
					this.notice_done(
						"Registration succeeded",
						"The Argus agent service was restarted. " +
						"It will connect to the management server shortly.");
					break;

				case LocalEnrollStep.CONFLICT:
					this.do_conflict();
					break;

				case LocalEnrollStep.FAILED:
					GLib.warning("Connect locally failed: %s", this.detail);
					this.notice_done(
						"Could not register locally",
						this.detail);
					break;
			}
		}

		private void do_enroll()
		{
			var title = "Argus Remote Management Agent " + Argus.VERSION;
			var busy = new Argus.Shared.Notice(
				this.replace_server_registration ?
					"Removing server registration" :
					"Registering with the local management server",
				"");
			busy.title = title;
			busy.present(null);
			this.enroll_certificate.begin(
				this.service,
				this.reg,
				this.replace_server_registration,
				(obj, res) => {
				busy.close();
				try {
					this.enroll_certificate.end(res);
					this.step = LocalEnrollStep.SUCCEEDED;
				} catch (Argus.Shared.RegistrationError.ALREADY_REGISTERED e) {
					this.step = LocalEnrollStep.CONFLICT;
					this.detail = e.message;
				} catch (GLib.Error e) {
					this.step = LocalEnrollStep.FAILED;
					this.detail = e.message;
				}
				this.continue_flow();
			});
		}

		private void do_conflict()
		{
			var title = "Argus Remote Management Agent " + Argus.VERSION;
			var body =
				this.detail + "\n\nThe server still lists this machine. " +
				"Delete it from the agent list in Remote Manager, or clear " +
				"the registration on this server.";
			var err = new Argus.Shared.Notice("Could not register locally", body);
			err.title = title;
			var continued = false;
			err.add_response("deregister", "Remove on server");
			err.add_response("retry", "Retry");
			err.responded.connect((response) => {
				continued = true;
				err.close();
				if (response == "deregister") {
					this.replace_server_registration = true;
					this.step = LocalEnrollStep.ENROLL;
					this.continue_flow();
					return;
				}
				if (response == "retry") {
					this.replace_server_registration = false;
					this.step = LocalEnrollStep.ENROLL;
					this.continue_flow();
				}
			});
			err.closed.connect(() => {
				if (!continued) {
					this.app.quit();
				}
			});
			err.present(null);
		}

		private void notice_done(string heading, string body)
		{
			var notice = new Argus.Shared.Notice(heading, body);
			notice.title = "Argus Remote Management Agent " + Argus.VERSION;
			notice.add_response("ok", "OK");
			notice.closed.connect(() => {
				this.app.quit();
			});
			notice.present(null);
		}

		private async void enroll_certificate(
			ServiceManager service,
			Argus.Shared.Register reg,
			bool replace_server_registration) throws GLib.Error
		{
			if (Posix.geteuid() != 0) {
				throw new GLib.IOError.FAILED(
					"Connect locally requires administrator privileges.");
			}
			if (replace_server_registration) {
				var sock = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "argus.sock");
				if (!GLib.FileUtils.test(sock, GLib.FileTest.EXISTS)) {
					throw new GLib.IOError.FAILED(
						"The management server is not running on this machine.");
				}
				var rpc = new OLLMrpc.Client("", "", sock) {
					live_handles = true,
					call_timeout_seconds = 15
				};
				var hello = yield rpc.connect(new OLLMrpc.Request() {
					method = "RPC-Daemon.hello",
					args = OLLMrpc.args("iss", 1, "argusrm-agent-gtk", Argus.VERSION)
				});
				if (!hello) {
					throw new GLib.IOError.FAILED(rpc.connect_error);
				}
				OLLMrpc.Response remove;
				try {
					remove = yield rpc.call(new OLLMrpc.Request() {
						method = "Registration.deregister",
						args = OLLMrpc.args("s", "agent")
					});
				} catch (GLib.Error e) {
					throw new GLib.IOError.FAILED(e.message);
				}
				if (remove.error != null) {
					throw new GLib.IOError.FAILED(remove.error.message);
				}
			}
			var executable = Argus.SERVER_EXECUTABLE;
			if (!GLib.FileUtils.test(executable, GLib.FileTest.IS_EXECUTABLE)) {
				throw new GLib.IOError.FAILED("argusrm-server is missing");
			}
			var launcher = new GLib.SubprocessLauncher(
				GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
			GLib.Subprocess proc;
			try {
				proc = launcher.spawnv({
					executable,
					"--give-me-a-certificate", "agent"
				});
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED(e.message);
			}
			string? stdout_text = null;
			string? stderr_text = null;
			yield proc.communicate_utf8_async(null, null, out stdout_text, out stderr_text);
			var output = stdout_text != null ? stdout_text.strip() : "";
			var stderr_out = stderr_text != null ? stderr_text.strip() : "";
			if (output == "") {
				throw new GLib.IOError.FAILED(
					stderr_out != "" ? stderr_out : "Registration failed");
			}
			Argus.Shared.SQT.Server? data = null;
			try {
				data = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), output)
					as Argus.Shared.SQT.Server;
			} catch (GLib.Error e) {
				throw new GLib.IOError.FAILED(e.message);
			}
			if (data == null) {
				throw new GLib.IOError.FAILED("Registration failed");
			}
			if (data.error != "" || !data.has_certificate) {
				if (data.error == "This machine is already registered.") {
					throw new Argus.Shared.RegistrationError.ALREADY_REGISTERED(
						data.error);
				}
				throw new GLib.IOError.FAILED(
					data.error != "" ? data.error : "Registration failed");
			}
			reg.server_row = data;
			var row = new Argus.Agent.SQT.Server() { data_dir = this.app.data_dir };
			if (!reg.save(row)) {
				throw new GLib.IOError.FAILED("Could not save the server row");
			}
			service.restart(false);
			GLib.debug("Connect locally: registration saved");
		}
	}
}