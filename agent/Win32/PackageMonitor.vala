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
	 * Watch Windows installs and send the ''programs'' difference.
	 *
	 * The constructor subscribes to the Application log, source
	 * ''MsiInstaller''. Install events are ''1033'' and ''11707''.
	 * Removal events are ''1034'' and ''11724''. The event is only
	 * the signal. {@link send} posts the ''programs'' difference.
	 * Startup does not construct this.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var monitor = new Argus.Agent.PackageMonitor(application);
	 * }}}
	 */
	public class PackageMonitor : GLib.Object
	{
		/**
		 * The monitor the log callback resumes.
		 *
		 * The subscription callback has no instance, and it is not
		 * on the main loop. One process runs one monitor.
		 */
		private static PackageMonitor current;

		/**
		 * Log callback. Kept for the life of the process.
		 */
		private static Win32.EVT_SUBSCRIBE_CALLBACK logged = (action, context, event) => {
			if (action != 1) {
				return 0;
			}
			GLib.Idle.add(() => {
				if (PackageMonitor.current.later != 0) {
					return false;
				}
				PackageMonitor.current.later = GLib.Timeout.add_seconds(1, () => {
					PackageMonitor.current.application.osquery.send_packages();
					PackageMonitor.current.later = 0;
					return false;
				});
				return false;
			});
			return 0;
		};

		/**
		 * Agent that owns the server connection and the kept fetch.
		 */
		private Application application;

		/**
		 * Deferred rescan. Zero when none is waiting.
		 */
		private uint later = 0;

		/**
		 * Application log subscription.
		 */
		private void* subscription;

		/**
		 * Subscribe to ''MsiInstaller'' on the Application log.
		 *
		 * @param application agent whose startup fetch is kept
		 */
		public PackageMonitor(Application application)
		{
			this.application = application;
			PackageMonitor.current = this;
			var query = ("*[System[Provider[@Name='MsiInstaller'] and " +
				"(EventID=1033 or EventID=11707 or " +
				"EventID=1034 or EventID=11724)]]").to_utf16();
			this.subscription = Win32.EvtSubscribe(null, null,
				"Application".to_utf16(), query, null, null,
				PackageMonitor.logged, Win32.EvtSubscribeToFutureEvents);
			if (this.subscription == null) {
				GLib.warning("application log %u", Win32.GetLastError());
			}
		}

	}
}
