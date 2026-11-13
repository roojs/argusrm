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

namespace Argus.Controller
{
	/**
	 * About button widget that shows an {@link Adw.AboutDialog} when
	 * clicked.
	 *
	 * Self-contained button showing ''help-about-symbolic'' that opens
	 * the application about dialog over the enclosing window.
	 *
	 * == Example ==
	 *
	 * {{{
	 * toolbar.append(new Argus.Controller.About());
	 * }}}
	 */
	public class About : Gtk.Button
	{
		/**
		 * Create a new About button.
		 */
		public About()
		{
			this.icon_name = "help-about-symbolic";
			this.tooltip_text = "About";
			this.clicked.connect(() => {
				var about = new Adw.AboutDialog() {
					application_name = "Argus Remote Manager",
					application_icon = "org.roojs.ArgusController",
					version = Argus.VERSION,
					developer_name = "Alan Knowles",
					website = "https://github.com/roojs/argusrm",
					issue_url = "https://github.com/roojs/argusrm/issues",
					license_type = Gtk.License.LGPL_3_0,
					copyright = "Copyright © 2026 Alan Knowles",
					comments = """<b>Argus Remote Manager</b> is a work-in-progress remote
management suite for coordinating Linux and Windows machines from a
central server and desktop controller.

<b>Key Features:</b>
• Plug-and-play enrollment with short-lived PINs and TLS certificates
• Cross-platform agents for Linux and Windows with osquery reporting
• Machine inventory, installed packages, and software tracking
• Script repositories and remote task execution
• Server connection management with keyring credential storage"""
				};
				about.present(this);
			});
		}
	}
}
