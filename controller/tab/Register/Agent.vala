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

namespace Argus.Controller.Tab.Register
{
	/**
	 * Agent / Controller registration page.
	 *
	 * {@link Current} lists registered agents and controllers.
	 * Its bar is Agent, Controller, and Bulk registration.
	 * Bulk registration is for agents. {@link Pending} is the
	 * provisional queue and the place that stops bulk
	 * registration. The {@link Adw.ViewSwitcher} switches
	 * between them. Pending stays hidden until the queue has
	 * a row or bulk registration is open, and it is selected
	 * when bulk registration starts or a new row arrives.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Register.Agent(window);
	 * pages.add_named(page, "registration");
	 * }}}
	 */
	public class Agent : Gtk.Box
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;
		/**
		 * Registered machines.
		 */
		public Current current { get; private set; }
		/**
		 * Waiting for accept or reject.
		 */
		public Pending pending { get; private set; }
		private Adw.ViewStack pages;
		private Adw.ViewStackPage pending_stack_page;
		private uint queue_size = 0;
		/**
		 * True while provisional agent registration is open.
		 *
		 * The Bulk registration button hides, and the Pending
		 * tab is shown so it can be stopped.
		 */
		public bool bulk_on { get; set; default = false; }

		/**
		 * The pending queue went from empty to non-empty.
		 */
		public signal void pending_opened();

		/**
		 * Build Current and Pending under one switcher.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Agent(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.pages = new Adw.ViewStack() {
				hexpand = true,
				vexpand = true
			};
			this.current = new Current(window);
			this.pending = new Pending(window);
			this.pages.add_titled_with_icon(
				this.current,
				"current",
				"Current",
				"computer-symbolic"
			);
			this.pages.add_titled_with_icon(
				this.pending,
				"pending",
				"Pending",
				"hourglass-symbolic"
			);
			this.pending_stack_page = this.pages.get_page(this.pending);
			this.pending_stack_page.visible = false;
			this.sync_pending(false);
			this.pending.queue.store.items_changed.connect(() => {
				this.sync_pending(true);
			});
			this.append(new Adw.ViewSwitcher() {
				stack = this.pages,
				policy = Adw.ViewSwitcherPolicy.WIDE,
				hexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_top = 6,
				margin_bottom = 4
			});
			this.append(this.pages);
			this.notify["bulk-on"].connect(() => {
				this.current.bulk_registration.visible = !this.bulk_on;
				this.current.agent_registration.sensitive = !this.bulk_on;
				this.current.controller_registration.sensitive = !this.bulk_on;
				this.pending.stop_bulk.visible = this.bulk_on;
				if (!this.bulk_on) {
					var count = this.pending.queue.store.get_n_items();
					this.pending_stack_page.visible = count > 0;
					if (count < 1 && this.pages.visible_child_name == "pending") {
						this.pages.visible_child_name = "current";
					}
					return;
				}
				this.pending_stack_page.visible = true;
				this.pages.visible_child_name = "pending";
			});
		}

		/**
		 * Show the Pending subtab.
		 */
		public void focus_pending()
		{
			if (this.pending.queue.store.get_n_items() < 1) {
				return;
			}
			this.pages.visible_child_name = "pending";
		}

		/**
		 * Hide or show the Pending subtab and select it when new rows arrive.
		 *
		 * @param select_pending true after a queue change, not on first build
		 */
		private void sync_pending(bool select_pending)
		{
			var count = this.pending.queue.store.get_n_items();
			if (count == this.queue_size) {
				return;
			}
			var was = this.queue_size;
			this.queue_size = count;
			var on_pending = this.pages.visible_child_name == "pending";
			this.pending_stack_page.visible = count > 0 || this.bulk_on;
			this.pending_stack_page.needs_attention = count > 0;
			if (count < 1 && on_pending && !this.bulk_on) {
				this.pages.visible_child_name = "current";
			}
			if (count < 1) {
				return;
			}
			if (was < 1) {
				this.pending_opened();
			}
			if (select_pending || was < 1) {
				this.pages.visible_child_name = "pending";
			}
		}
	}
}