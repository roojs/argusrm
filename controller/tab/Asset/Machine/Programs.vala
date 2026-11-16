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

namespace Argus.Controller.Tab.Asset.Machine
{
	/**
	 * Per-machine Windows program grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''programs_machine.csv''. {@link Argus.Controller.Store.Programs}
	 * loads ''Programs.list'' for the selected ''agent_id''.
	 * An empty grid shows a spinner over it while that call is in
	 * flight. {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.Programs(window);
	 * tab.load(1);
	 * }}}
	 */
	public class Programs : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Programs store;

		/**
		 * Build the per-machine Windows program grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			base("programs_machine", "name");
			this.store = new Argus.Controller.Store.Programs(window.app);
			this.column_grid(this.store);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.content.append(this.overlay);
		}

		/**
		 * Load installed Windows programs for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
			this.store.load(agent_id);
		}
	}
}
