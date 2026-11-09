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
	internal class ServiceManager : GLib.Object
	{
		private string systemctl = "";
		private GLib.SubprocessFlags flags {
			get; set; default = GLib.SubprocessFlags.STDOUT_SILENCE |
				GLib.SubprocessFlags.STDERR_SILENCE;
		}

		public ServiceManager()
		{
			Object();
			var found = GLib.Environment.find_program_in_path("systemctl");
			if (found != null &&
				GLib.FileUtils.test("/run/systemd/system", GLib.FileTest.IS_DIR)) {
				this.systemctl = found;
			}
		}

		public bool running() throws GLib.Error
		{
			string[] command = {};
			if (this.systemctl != "") {
				command = {
					this.systemctl, "is-active", "--quiet", "argusrm-agent.service"
				};
			}
			if (this.systemctl == "") {
				if (!GLib.FileUtils.test(Argus.AGENT_SYSVINIT, GLib.FileTest.EXISTS)) {
					throw new GLib.IOError.NOT_FOUND(
						"Argus Remote Manager agent init script was not found");
				}
				command = {Argus.AGENT_SYSVINIT, "status"};
			}
			var process = new GLib.Subprocess.newv(command, this.flags);
			process.wait();
			return process.get_successful();
		}

		public ServiceStatus status() throws GLib.Error
		{
			if (!this.running()) {
				return ServiceStatus.STOPPED;
			}
			var connection = GLib.Bus.get_sync(GLib.BusType.SYSTEM);
			var proxy = connection.get_proxy_sync<ServiceManagerInterface>(
				"org.roojs.ArgusAgent", "/org/roojs/ArgusAgent",
				GLib.DBusProxyFlags.NONE, null);
			return proxy.status();
		}

		public void setup() throws GLib.Error
		{
			if (this.systemctl != "") {
				var enable = new GLib.Subprocess.newv(
					{this.systemctl, "enable", "argusrm-agent.service"},
					this.flags);
				enable.wait();
				if (!enable.get_successful()) {
					throw new GLib.IOError.FAILED(
						"Could not enable the Argus Remote Manager agent service");
				}
				if (this.running()) {
					return;
				}
				var start = new GLib.Subprocess.newv(
					{this.systemctl, "start", "argusrm-agent.service"},
					this.flags);
				start.wait();
				if (!start.get_successful()) {
					throw new GLib.IOError.FAILED(
						"Could not start the Argus Remote Manager agent service");
				}
				return;
			}
			if (!GLib.FileUtils.test(Argus.AGENT_SYSVINIT, GLib.FileTest.EXISTS)) {
				throw new GLib.IOError.NOT_FOUND(
					"Argus Remote Manager agent init script was not found");
			}
			var update_rc = GLib.Environment.find_program_in_path("update-rc.d");
			string[] enable_command = {};
			if (update_rc != null) {
				enable_command = {update_rc, "argusrm-agent", "defaults"};
			}
			if (update_rc == null) {
				var chkconfig = GLib.Environment.find_program_in_path("chkconfig");
				if (chkconfig == null) {
					throw new GLib.IOError.NOT_FOUND(
						"update-rc.d and chkconfig were not found");
				}
				enable_command = {chkconfig, "argusrm-agent", "on"};
			}
			var enable = new GLib.Subprocess.newv(enable_command, this.flags);
			enable.wait();
			if (!enable.get_successful()) {
				throw new GLib.IOError.FAILED(
					"Could not enable the Argus Remote Manager agent service");
			}
			if (this.running()) {
				return;
			}
			var start = new GLib.Subprocess.newv(
				{Argus.AGENT_SYSVINIT, "start"},
				this.flags);
			start.wait();
			if (!start.get_successful()) {
				throw new GLib.IOError.FAILED(
					"Could not start the Argus Remote Manager agent service");
			}
		}

		public void restart() throws GLib.Error
		{
			string[] command = {};
			if (this.systemctl != "") {
				command = {this.systemctl, "restart", "argusrm-agent.service"};
			}
			if (this.systemctl == "") {
				if (!GLib.FileUtils.test(Argus.AGENT_SYSVINIT, GLib.FileTest.EXISTS)) {
					throw new GLib.IOError.NOT_FOUND(
						"Argus Remote Manager agent init script was not found");
				}
				command = {Argus.AGENT_SYSVINIT, "restart"};
			}
			var process = new GLib.Subprocess.newv(command, this.flags);
			process.wait();
			if (!process.get_successful()) {
				throw new GLib.IOError.FAILED(
					"Could not restart the Argus Remote Manager agent service");
			}
			var status = ServiceStatus.STOPPED;
			for (var attempt = 0; attempt < 40; attempt++) {
				try {
					status = this.status();
				} catch (GLib.Error e) {
					GLib.debug("agent status unavailable: %s", e.message);
					try {
						status = this.running() ?
							ServiceStatus.RUNNING :
							ServiceStatus.STOPPED;
					} catch (GLib.Error status_error) {
						GLib.debug("agent service status unavailable: %s",
							status_error.message);
						status = ServiceStatus.STOPPED;
					}
				}
				if (status == ServiceStatus.CONNECTED) {
					return;
				}
				GLib.Thread.usleep(250000);
			}
			if (status == ServiceStatus.STOPPED) {
				throw new GLib.IOError.TIMED_OUT(
					"Argus Remote Manager agent service did not start");
			}
			throw new GLib.IOError.TIMED_OUT(
				"Argus Remote Manager agent service did not connect to the management server");
		}
	}
}
