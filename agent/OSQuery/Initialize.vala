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

namespace Argus.Agent.OSQuery
{
	/**
	 * Download and install osquery.
	 *
	 * {@link start} runs {@link run} on the caller. Windows and
	 * Linux use {@link Download} for the registration URL path
	 * when ''osqueryi'' is missing, then install that file.
	 * {@link Execute} posts the tables.
	 *
	 * == Example ==
	 *
	 * {{{
	 * new Argus.Agent.OSQuery.Initialize(application).start();
	 * }}}
	 */
	public class Initialize : GLib.Object
	{
		/**
		 * Agent that owns the server connection.
		 */
		private Application application;

		/**
		 * @param application agent whose server connection is open
		 */
		public Initialize(Application application)
		{
			this.application = application;
		}

		/**
		 * True while {@link run} is in progress.
		 *
		 * {@link start} returns without a second run when this
		 * is set.
		 */
		private static bool running = false;

		/**
		 * Install osquery when needed.
		 *
		 * Returns immediately when a run is already in progress.
		 * The result is logged from this call.
		 */
		public void start()
		{
			if (Initialize.running) {
				return;
			}
			Initialize.running = true;
			var code = this.run();
			Initialize.running = false;
			GLib.debug("osquery %d", code);
		}

		/**
		 * Download and install ''osqueryi'' when it is missing.
		 *
		 * {@link Execute.init} sets the path. An empty path
		 * fetches the registration URL and installs that file.
		 * This method does not query.
		 *
		 * @return zero when the executable is present, otherwise an
		 *   {@link OLLMrpc.RpcErrorCode} value
		 */
		public int run()
		{
			var pass = 0;
			while (pass < 2) {
				pass++;
				Execute.init();
				if (Execute.osqueryi != "") {
					break;
				}
				if (pass > 1) {
					break;
				}
				var url_path = "";
				try {
#if LINUX
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						Argus.AGENT_DATA_DIR, "download-path"),
						out url_path);
#else
					GLib.FileUtils.get_contents(GLib.Path.build_filename(
						GLib.Environment.get_user_data_dir(), "argus", "download-path"),
						out url_path);
#endif
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				var download = new Download();
				var fetched = download.fetch(url_path.strip());
				if (fetched != 0) {
					return fetched;
				}
				string[] argv = {};
#if WINDOWS
				argv = new string[] { download.path, "/S" };
				if (download.path.has_suffix(".msi")) {
					argv = new string[] { "msiexec.exe", "/i", download.path, "/qn" };
				}
#elif LINUX
				if (download.path.has_suffix(".deb")) {
					argv = new string[] { "dpkg", "-i", download.path };
				} else if (download.path.has_suffix(".rpm")) {
					argv = new string[] { "rpm", "-U", download.path };
				}
#endif
				if (argv.length == 0) {
					GLib.warning("osquery installer %s", download.path);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				GLib.Subprocess installer;
				try {
					installer = new GLib.Subprocess.newv(argv, GLib.SubprocessFlags.NONE);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				try {
					installer.wait(null);
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				if (installer.get_exit_status() != 0) {
					GLib.warning("osquery installer exited %d", installer.get_exit_status());
					return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
				}
				continue;
			}
			if (Execute.osqueryi == "") {
				GLib.warning("osqueryi is not installed");
				return (int) OLLMrpc.RpcErrorCode.INTERNAL_ERROR;
			}
			return 0;
		}
	}
}
