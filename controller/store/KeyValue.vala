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

namespace Argus.Controller.Store
{
	/**
	 * One key-value entry or expander header in {@link MachineGeneral}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var header = new Argus.Controller.Store.KeyValue() {
	 *     key = "System info",
	 *     val = "web-01",
	 *     expander = true,
	 *     indent = 0
	 * };
	 * var row = new Argus.Controller.Store.KeyValue() {
	 *     key = "Hostname",
	 *     val = "web-01",
	 *     indent = 1
	 * };
	 * }}}
	 */
	public class KeyValue : GLib.Object
	{
		/**
		 * Section heading or field label.
		 */
		public string key { get; set; default = ""; }

		/**
		 * Formatted field value or expander summary.
		 */
		public string val { get; set; default = ""; }

		/**
		 * Indentation level from the layout CSV.
		 */
		public int indent { get; set; default = 0; }

		/**
		 * True when this entry opens a collapsible group.
		 */
		public bool expander { get; set; default = false; }

		/**
		 * Initial expanded state when {@link expander} is true.
		 */
		public bool expanded { get; set; default = true; }

		/**
		 * Optional CSS class applied by the renderer (such as
		 * ''status-ok'', ''status-warn'', or ''status-bad'').
		 */
		public string css_class { get; set; default = ""; }

		/**
		 * Optional tooltip text.
		 */
		public string tooltip { get; set; default = ""; }
	}
}
