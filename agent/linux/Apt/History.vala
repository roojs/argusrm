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

namespace Argus.Agent.Apt
{
	/**
	 * Explicit package names from apt history.
	 *
	 * {@link send} reads ''history.log'' and posts names that
	 * were installed after the watermark. An empty watermark
	 * reads the rotated logs once. The server stores the first
	 * ''Start-Date'' and does not drop older rows.
	 *
	 * {@link Argus.Agent.OSQuery.Execute.send_startup} calls {@link send}
	 * for an APT host. {@link Argus.Agent.PackageMonitor.apt} calls
	 * {@link send} again after a dpkg change, once the locks are free.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var code = new Argus.Agent.Apt.History().send(application);
	 * }}}
	 */
	public class History : GLib.Object
	{
		/**
		 * Watermark already read in this process.
		 * ''-1'' means the file has not been read yet.
		 */
		static int cached = -1;

		/**
		 * Unix time already accepted. Stanzas at or before this
		 * are not sent.
		 */
		internal int watermark = 0;

		/**
		 * Latest complete ''End-Date'' in this pass.
		 */
		internal int consumed = 0;

		/**
		 * Package name to the first ''Start-Date'' in this pass.
		 */
		internal Gee.HashMap<string, int> names { get; set; default = new Gee.HashMap<string, int>(); }

		/**
		 * Send explicit installs newer than the stored watermark.
		 *
		 * Uses {@link cached} when this process has already read the
		 * watermark file. An empty watermark reads the rotated logs,
		 * then ''history.log''. A stored watermark returns when
		 * ''history.log'' is not newer than that time, and otherwise
		 * reads only that file. A failed send leaves the watermark
		 * file alone.
		 *
		 * @param application agent that holds the server connection
		 * @return zero, or an {@link OLLMrpc.RpcErrorCode} value
		 */
		public int send(Application application)
		{
			var mark_path = GLib.Path.build_filename(
				Argus.AGENT_DATA_DIR, "apt-explicit-through");
			if (History.cached < 0) {
				History.cached = 0;
				if (GLib.FileUtils.test(mark_path, GLib.FileTest.EXISTS)) {
					var contents = "";
					try {
						GLib.FileUtils.get_contents(mark_path, out contents);
					} catch (GLib.Error e) {
						History.cached = -1;
						GLib.warning("%s", e.message);
						return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
					}
					var text = contents.strip();
					if (text != "") {
						History.cached = int.parse(text);
					}
				}
			}
			this.watermark = History.cached;
			this.consumed = this.watermark;
			this.names = new Gee.HashMap<string, int>();
			if (this.watermark == 0) {
				try {
					this.archive();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
			}
			if (this.watermark > 0) {
				var history = GLib.File.new_for_path("/var/log/apt/history.log");
				try {
					var info = history.query_info(GLib.FileAttribute.TIME_MODIFIED,
						GLib.FileQueryInfoFlags.NONE, null);
					if (info.get_modification_date_time().to_unix() <= this.watermark) {
						return 0;
					}
				} catch (GLib.Error e) {
					if (e is GLib.IOError.NOT_FOUND) {
						return 0;
					}
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
			}
			try {
				var raw = GLib.File.new_for_path("/var/log/apt/history.log").read(null);
				this.read(new GLib.DataInputStream(raw));
			} catch (GLib.Error e) {
				if (!(e is GLib.IOError.NOT_FOUND)) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
			}
			if (this.names.size > 0) {
				var rows = new Gee.ArrayList<Argus.Shared.OSQuery.AgentInfo>();
				foreach (var name in this.names.keys) {
					rows.add(new Argus.Shared.OSQuery.AptExplicitInstall() {
						name = name,
						installed_dt = this.names.get(name)
					});
				}
				var connection = application.connection;
				if (connection == null) {
					GLib.warning("server connection is not open");
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					var response = connection.call(new OLLMrpc.Request() {
						method = "OSQuery.sync",
						args = OLLMrpc.args("so", "AptExplicitInstall", rows)
					});
					if (response.error != null) {
						GLib.debug("apt explicit send failed %s", response.error.message);
						return response.error.code;
					}
				} catch (GLib.Error e) {
					Application.connection_down = true;
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
			}
			if (this.consumed > this.watermark) {
				try {
					GLib.FileUtils.set_contents(mark_path, this.consumed.to_string());
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				History.cached = this.consumed;
				this.watermark = this.consumed;
			}
			return 0;
		}

		/**
		 * Read rotated ''history.log.*.gz'' files, oldest first.
		 */
		internal void archive() throws GLib.Error
		{
			var dir = GLib.Dir.open("/var/log/apt");
			var files = new Gee.ArrayList<string>();
			while (true) {
				var name = dir.read_name();
				if (name == null) {
					break;
				}
				if (!name.has_prefix("history.log.") || !name.has_suffix(".gz")) {
					continue;
				}
				files.add("/var/log/apt/" + name);
			}
			files.sort((a, b) => {
				var a_num = int.parse(GLib.Path.get_basename(a).replace(
					"history.log.", "").replace(".gz", ""));
				var b_num = int.parse(GLib.Path.get_basename(b).replace(
					"history.log.", "").replace(".gz", ""));
				return b_num - a_num;
			});
			foreach (var path in files) {
				var raw = GLib.File.new_for_path(path).read(null);
				this.read(new GLib.DataInputStream(new GLib.ConverterInputStream(raw,
					new GLib.ZlibDecompressor(GLib.ZlibCompressorFormat.GZIP))));
			}
		}

		/**
		 * Read one apt history stream into this pass.
		 *
		 * A stanza at or before {@link watermark} adds no names.
		 * A stanza with no ''End-Date'' adds no names and does not
		 * move {@link consumed}.
		 *
		 * @param input apt history text, gzip already decoded
		 */
		internal void read(GLib.DataInputStream input) throws GLib.Error
		{
			var pending = new Gee.HashSet<string>();
			var start_unix = 0;
			var stanza_open = false;
			while (true) {
				var line = input.read_line(null);
				if (line == null) {
					break;
				}
				var text = line.strip();
				if (text == "") {
					continue;
				}
				if (text.has_prefix("Start-Date:") || text.has_prefix("End-Date:")) {
					var prefix = "Start-Date:";
					if (text.has_prefix("End-Date:")) {
						prefix = "End-Date:";
					}
					var body = text.substring(prefix.length).strip().replace("  ", " ");
					var space = body.index_of(" ");
					if (space < 1) {
						GLib.warning("apt history date %s", body);
						pending.clear();
						stanza_open = false;
						continue;
					}
					var ymd = body.substring(0, space).split("-");
					var hms = body.substring(space + 1).split(":");
					if (ymd.length != 3 || hms.length != 3) {
						GLib.warning("apt history date %s", body);
						pending.clear();
						stanza_open = false;
						continue;
					}
					var when = new GLib.DateTime.local(
						int.parse(ymd[0]), int.parse(ymd[1]), int.parse(ymd[2]),
						int.parse(hms[0]), int.parse(hms[1]), double.parse(hms[2]));
					var stamp = (int) when.to_unix();
					if (text.has_prefix("Start-Date:")) {
						pending.clear();
						start_unix = stamp;
						stanza_open = true;
						continue;
					}
					if (stanza_open && start_unix > this.watermark) {
						foreach (var token in pending) {
							if (!this.names.has_key(token)) {
								this.names.set(token, start_unix);
							}
						}
					}
					if (stanza_open && stamp > this.consumed) {
						this.consumed = stamp;
					}
					pending.clear();
					stanza_open = false;
					continue;
				}
				if (!text.has_prefix("Commandline:") || !stanza_open || start_unix <= this.watermark) {
					continue;
				}
				var tokens = text.split(" ");
				var in_install = false;
				foreach (var token in tokens) {
					var clean = token.strip();
					if (clean == "install") {
						in_install = true;
						continue;
					}
					if (!in_install || clean == "" || clean.has_prefix("-")) {
						continue;
					}
					if (clean.contains("=")) {
						break;
					}
					pending.add(clean);
				}
			}
		}
	}
}
