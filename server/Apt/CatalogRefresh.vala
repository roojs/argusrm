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

namespace Argus.Server.Apt
{
	/**
	 * Periodic {@link CatalogImport.run_update} on the main context.
	 */
	public class CatalogRefresh : GLib.Object
	{
		public Application app { get; private set; }

		private uint source_id = 0;

		public CatalogRefresh(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Refresh once, then every twenty-four hours.
		 */
		public void start()
		{
			if (this.source_id != 0) {
				return;
			}
			CatalogImport.run_update(this.app.db);
			this.source_id = GLib.Timeout.add_seconds(24 * 60 * 60, () => {
				CatalogImport.run_update(this.app.db);
				return true;
			});
		}

		public void stop()
		{
			if (this.source_id != 0) {
				GLib.Source.remove(this.source_id);
				this.source_id = 0;
			}
		}
	}
}